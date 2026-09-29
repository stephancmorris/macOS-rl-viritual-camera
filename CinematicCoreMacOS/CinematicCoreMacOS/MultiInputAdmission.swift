//
//  MultiInputAdmission.swift
//  CinematicCoreMacOS
//
//  Admission for a second input (ADMISSION card; docs/ALFIE_MULTICAMERA_SPEC.md
//  "Scheduler, admission, and degraded operation"). Below the UI and
//  independent of Take: it decides, from measurements on this exact
//  configuration, whether B may run alongside A at the show standard.
//
//  - A configuration is fingerprinted (machine, OS, show standard, route,
//    each input's device / delivered format / rate / profile / mode, policy
//    version). Any change makes it unknown again.
//  - unknown until measured; provisional after a passing measured sample;
//    unsupported when a concrete measurement fails (and says which);
//    certified only when MULTI-QA records it for this fingerprint.
//  - Unknown ≠ supported: an unknown pair may only run as a labelled trial.
//  - Admission never changes the show standard or lowers the output rate.
//

import Combine
import Foundation
import QuartzCore

nonisolated enum AdmissionPolicy {
    /// Bump when thresholds or evaluation change; older records become unknown.
    static let version = 1
}

// MARK: - Fingerprint

nonisolated struct AdmissionFingerprint: Codable, Hashable, Sendable {
    struct Input: Codable, Hashable, Sendable {
        var channel: String
        var deviceModelID: String?
        var deliveredWidth: Int?
        var deliveredHeight: Int?
        var captureFPS: Double?
        var captureProfile: String?
        /// "wide", "track", "manual", "pan": Track+Track costs more than Track+Pan.
        var mode: String
    }

    var policyVersion: Int = AdmissionPolicy.version
    var machineModel: String
    var osVersion: String
    var showStandard: String
    var route: String?
    var inputs: [Input]

    /// Stable key for the record store.
    var key: String {
        let parts = [String(policyVersion), machineModel, osVersion, showStandard, route ?? "none"]
            + inputs.sorted { $0.channel < $1.channel }.map {
                "\($0.channel):\($0.deviceModelID ?? "?"):\($0.deliveredWidth ?? 0)x\($0.deliveredHeight ?? 0)@\($0.captureFPS ?? 0):\($0.captureProfile ?? "?"):\($0.mode)"
            }
        return parts.joined(separator: "|")
    }
}

// MARK: - Status and reasons

nonisolated enum AdmissionBottleneck: String, Codable, Sendable {
    case capture, render, perception, cpu, memory, heat, evidence
}

nonisolated struct AdmissionReason: Codable, Equatable, Sendable, Identifiable {
    var code: String
    var bottleneck: AdmissionBottleneck
    var message: String
    var id: String { code }
}

nonisolated enum AdmissionStatus: Codable, Equatable, Sendable {
    case unknown
    /// Measured now on this configuration; not certified.
    case provisional
    /// Recorded by MULTI-QA (60-minute two-input soak) for this fingerprint.
    case certified
    /// A concrete measurement failed.
    case unsupported([AdmissionReason])

    var title: String {
        switch self {
        case .unknown: return "Unknown on this Mac"
        case .provisional: return "Provisional · measured, not certified"
        case .certified: return "Certified for this setup"
        case .unsupported: return "Unsupported alongside Program"
        }
    }
}

/// What the show may do with a second input under a fingerprint.
nonisolated enum AdmissionDecision: Equatable, Sendable {
    case allowed(certified: Bool)
    /// No evidence yet: may run only as an explicitly labelled trial.
    case trialOnly
    case refused([AdmissionReason])

    static func decide(_ status: AdmissionStatus) -> AdmissionDecision {
        switch status {
        case .unknown: return .trialOnly
        case .provisional: return .allowed(certified: false)
        case .certified: return .allowed(certified: true)
        case .unsupported(let reasons): return .refused(reasons)
        }
    }
}

// MARK: - Evaluation

/// Preview channel sample for one diagnostics window.
nonisolated struct PreviewAdmissionSample: Equatable, Sendable {
    var windowSeconds: Double
    /// New renders (repeats excluded) the Preview channel produced.
    var renderedFrames: Int
}

nonisolated struct PairAdmissionContext: Equatable, Sendable {
    var program: CapabilityContext
    /// Preview's configured capture rate.
    var previewCaptureFPS: Double?
}

nonisolated struct PairAdmissionResult: Equatable, Sendable {
    var status: AdmissionStatus
    var reasons: [AdmissionReason]
    var programReport: CapabilityReport
    var previewFPS: Double
}

nonisolated enum PairAdmission {
    /// Provisional limits (calibrate against MULTI-QA).
    static let previewCadenceFloor = 0.9
    static let mainActorBudgetFraction = 0.5
    static let observationAgeCeilingMS = 150.0

    static func evaluate(
        program: [CapabilitySample],
        preview: [PreviewAdmissionSample],
        context: PairAdmissionContext,
        thresholds: CapabilityThresholds = .provisional
    ) -> PairAdmissionResult {
        let report = CapabilityReport.evaluate(samples: program, context: context.program, thresholds: thresholds)
        var reasons = report.reasons.compactMap(Self.map)

        let previewSeconds = preview.reduce(0) { $0 + $1.windowSeconds }
        let previewFrames = preview.reduce(0) { $0 + $1.renderedFrames }
        let previewFPS = previewSeconds > 0 ? Double(previewFrames) / previewSeconds : 0
        if preview.isEmpty || previewSeconds <= 0 {
            reasons.append(.init(code: "preview.noEvidence", bottleneck: .evidence,
                message: "The second input produced no measurement windows."))
        } else if let target = context.previewCaptureFPS, target > 0,
                  previewFPS < target * previewCadenceFloor {
            reasons.append(.init(code: "preview.render", bottleneck: .render,
                message: String(format: "The second input rendered %.1f fps; it needs about %@ fps to stay ready for Take.",
                                previewFPS, CapabilityReport.rate(target))))
        }

        let m = report.measured
        if let fps = context.program.captureFPS, fps > 0, m.counts.admitted > 0 {
            let mainMean = program.isEmpty ? 0
                : program.reduce(0) { $0 + $1.window.mainMeanMS * Double($1.window.window.admitted) } / Double(max(1, m.counts.admitted))
            let budget = 1000 / fps * mainActorBudgetFraction
            if mainMean > budget {
                reasons.append(.init(code: "program.mainActor", bottleneck: .cpu,
                    message: String(format: "Main-thread work took %.1f ms per Program frame with both inputs (limit %.1f ms).", mainMean, budget)))
            }
        }
        if m.detections > 0, m.observationAgeMeanMS > observationAgeCeilingMS {
            reasons.append(.init(code: "program.perception", bottleneck: .perception,
                message: String(format: "Detections were %.0f ms old on average with both inputs (limit %.0f ms).",
                                m.observationAgeMeanMS, observationAgeCeilingMS)))
        }

        let status: AdmissionStatus
        if reasons.contains(where: { $0.bottleneck == .evidence }) || report.verdict == .unverified {
            status = .unknown
        } else if !reasons.isEmpty {
            status = .unsupported(reasons)
        } else {
            status = .provisional
        }
        return PairAdmissionResult(status: status, reasons: reasons, programReport: report, previewFPS: previewFPS)
    }

    /// Map a single-channel capability reason to a pair bottleneck; notes are
    /// context, not failures.
    static func map(_ reason: CapabilityReason) -> AdmissionReason? {
        let bottleneck: AdmissionBottleneck
        switch reason.kind {
        case .note: return nil
        case .unknown: bottleneck = .evidence
        case .limit:
            switch reason.code {
            case "capture.cadence", "capture.dropped": bottleneck = .capture
            case "pipeline.gateSkips", "pipeline.frameTime", "render.failed", "output.refused", "output.noRoute":
                bottleneck = .render
            case "system.memoryGrowth": bottleneck = .memory
            case "system.thermal": bottleneck = .heat
            default: bottleneck = .render
            }
        }
        return AdmissionReason(code: "program." + reason.code, bottleneck: bottleneck, message: reason.message)
    }
}

// MARK: - Records

/// Admission results by fingerprint, persisted so a measured setup is not
/// re-measured every launch. Records from another policy version are ignored.
final class AdmissionRecordStore {
    struct Record: Codable, Equatable, Sendable {
        var status: AdmissionStatus
        var measuredAt: Date
        var policyVersion: Int
    }

    private let defaults: UserDefaults
    private let key = "admissionRecords.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func status(for fingerprint: AdmissionFingerprint) -> AdmissionStatus {
        guard let record = load()[fingerprint.key], record.policyVersion == AdmissionPolicy.version else {
            return .unknown
        }
        return record.status
    }

    func record(_ status: AdmissionStatus, for fingerprint: AdmissionFingerprint, at date: Date = Date()) {
        var all = load()
        // A certified record is only replaced by MULTI-QA, never by a short sample.
        if case .certified = all[fingerprint.key]?.status, status != .certified { return }
        all[fingerprint.key] = Record(status: status, measuredAt: date, policyVersion: AdmissionPolicy.version)
        save(all)
    }

    /// MULTI-QA entry point: the 60-minute two-input soak passed on this setup.
    func markCertified(_ fingerprint: AdmissionFingerprint) {
        var all = load()
        all[fingerprint.key] = Record(status: .certified, measuredAt: Date(), policyVersion: AdmissionPolicy.version)
        save(all)
    }

    /// Every stored record by fingerprint key (show setup matches these
    /// against the chosen cameras before Start).
    func allRecords() -> [String: Record] { load() }

    private func load() -> [String: Record] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([String: Record].self, from: data) else { return [:] }
        return records
    }

    private func save(_ records: [String: Record]) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Live check

/// Measures the running pair: Program's closed diagnostics windows plus the
/// Preview channel's render count over the same windows. Observes only; it
/// never starts, stops or reconfigures anything.
final class MultiInputCheck: ObservableObject {
    enum Phase: Equatable {
        case idle, warmingUp
        case sampling(collected: Int, needed: Int)
        case finished(PairAdmissionResult)
        case cancelled(String)

        var isRunning: Bool {
            switch self { case .warmingUp, .sampling: return true; default: return false }
        }
    }

    @Published private(set) var phase: Phase = .idle
    let warmUpSeconds: TimeInterval
    let sampleWindows: Int

    private var startedAt: TimeInterval = 0
    private var program: [CapabilitySample] = []
    private var preview: [PreviewAdmissionSample] = []
    private var lastPreviewCount: UInt64 = 0
    private var subscription: AnyCancellable?

    init(warmUpSeconds: TimeInterval = 5, sampleWindows: Int = 4) {
        self.warmUpSeconds = warmUpSeconds
        self.sampleWindows = sampleWindows
    }

    /// Core: feed one closed Program window and the Preview channel's
    /// cumulative new-render count at the same moment.
    func begin(now: TimeInterval, previewCount: UInt64) {
        startedAt = now
        program = []
        preview = []
        lastPreviewCount = previewCount
        phase = .warmingUp
    }

    func ingest(_ window: DiagnosticsWindow?, previewCount: UInt64, thermal: ThermalLevel,
                now: TimeInterval, context: PairAdmissionContext) {
        guard phase.isRunning else { return }
        guard let window, window.kind != .partial else {
            finish(.cancelled("Capture stopped during the check."))
            return
        }
        let frames = Int(previewCount &- lastPreviewCount)
        lastPreviewCount = previewCount
        guard now - window.windowSeconds >= startedAt + warmUpSeconds - 0.25 else { return }
        program.append(CapabilitySample(window: window, thermal: thermal))
        preview.append(PreviewAdmissionSample(windowSeconds: window.windowSeconds, renderedFrames: frames))
        if program.count >= sampleWindows {
            finish(.finished(PairAdmission.evaluate(program: program, preview: preview, context: context)))
        } else {
            phase = .sampling(collected: program.count, needed: sampleWindows)
        }
    }

    /// Live wiring: sample on every closed Program window.
    func start(show: ShowCoordinator, preview previewID: ChannelID, onResult: @escaping (PairAdmissionResult) -> Void) {
        guard let previewChannel = show.channel(previewID) else {
            phase = .cancelled("Add the second input first.")
            return
        }
        begin(now: CACurrentMediaTime(), previewCount: previewChannel.renderedFrameCount &- previewChannel.repeatedFrameCount)
        subscription = show.programOutput.$lastPipelineWindow.dropFirst().sink { [weak self, weak show] window in
            guard let self, let show, let previewChannel = show.channel(previewID) else { return }
            self.ingest(window,
                        previewCount: previewChannel.renderedFrameCount &- previewChannel.repeatedFrameCount,
                        thermal: ThermalLevel(ProcessInfo.processInfo.thermalState),
                        now: CACurrentMediaTime(),
                        context: show.pairAdmissionContext(preview: previewID))
            if case .finished(let result) = self.phase { onResult(result) }
        }
    }

    func cancel() {
        guard phase.isRunning else { return }
        finish(.cancelled("Cancelled by the operator."))
    }

    private func finish(_ result: Phase) {
        subscription = nil
        phase = result
    }
}
