//
//  SetupCheck.swift
//  CinematicCoreMacOS
//
//  Bounded single-camera setup check (PREFLIGHT card). While capture runs on
//  the selected source and route, it waits out a warm-up, then collects the
//  next few diagnostics windows (~5 s each) and evaluates them with
//  CapabilityReport. It only observes: it never changes the show standard,
//  the capture format or the route, and it adds no frame-path work — it reads
//  the windows ProgramOutputManager already closes.
//
//  Owned by CameraManager so it survives the inspector drawer closing.
//

import Combine
import QuartzCore
import Foundation

final class SetupCheck: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Waiting for the pipeline to settle; windows are discarded.
        case warmingUp
        /// Collecting measurement windows.
        case sampling(collected: Int, needed: Int)
        case finished(CapabilityReport)
        case cancelled(reason: String)

        var isRunning: Bool {
            switch self {
            case .warmingUp, .sampling: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    let warmUpSeconds: TimeInterval
    let sampleWindows: Int
    let thresholds: CapabilityThresholds

    /// Roughly how long a run takes: warm-up plus the windows, plus up to one
    /// window already in progress when the check starts.
    var approximateDuration: TimeInterval { warmUpSeconds + Double(sampleWindows + 1) * 5 }

    private var startedAt: TimeInterval = 0
    private var samples: [CapabilitySample] = []
    private var subscription: AnyCancellable?
    private weak var output: ProgramOutputManager?

    init(warmUpSeconds: TimeInterval = 5, sampleWindows: Int = 4,
         thresholds: CapabilityThresholds = .provisional) {
        self.warmUpSeconds = warmUpSeconds
        self.sampleWindows = sampleWindows
        self.thresholds = thresholds
    }

    /// Start a check against the running pipeline. Refused (cancelled with a
    /// reason) if capture is not running.
    func start(output: ProgramOutputManager, isCaptureRunning: Bool) {
        subscription = nil
        guard isCaptureRunning else {
            phase = .cancelled(reason: "Start capture on the source and route you will use, then run the check.")
            return
        }
        self.output = output
        begin(now: CACurrentMediaTime())
        output.noteDiagnostics("setup check start")
        // Each closed window republishes `lastPipelineWindow` (~every 5 s);
        // skip the value current at subscription time.
        subscription = output.$lastPipelineWindow
            .dropFirst()
            .sink { [weak self] window in
                self?.ingest(window, thermal: ThermalLevel(ProcessInfo.processInfo.thermalState),
                             now: CACurrentMediaTime())
            }
    }

    func cancel(reason: String = "Cancelled by the operator.") {
        guard phase.isRunning else { return }
        finish(.cancelled(reason: reason))
    }

    // MARK: - Core (driven by tests without a live pipeline)

    func begin(now: TimeInterval) {
        startedAt = now
        samples = []
        phase = .warmingUp
    }

    /// Feed one closed window. `now` is when it closed.
    func ingest(_ window: DiagnosticsWindow?, thermal: ThermalLevel, now: TimeInterval,
                context: CapabilityContext? = nil) {
        guard phase.isRunning else { return }
        // Stop flushes a partial window, and a new capture resets the window
        // to nil: either way the source the check was measuring is gone.
        guard let window, window.kind != .partial else {
            finish(.cancelled(reason: "Capture stopped during the check."))
            return
        }
        // Only windows that began after the warm-up count.
        let windowStart = now - window.windowSeconds
        guard windowStart >= startedAt + warmUpSeconds - 0.25 else { return }

        samples.append(CapabilitySample(window: window, thermal: thermal))
        if samples.count >= sampleWindows {
            let report = CapabilityReport.evaluate(
                samples: samples,
                context: context ?? currentContext(),
                thresholds: thresholds)
            finish(.finished(report))
        } else {
            phase = .sampling(collected: samples.count, needed: sampleWindows)
        }
    }

    private func finish(_ result: Phase) {
        subscription = nil
        phase = result
        switch result {
        case .finished(let report):
            output?.noteDiagnostics("setup check \(report.verdict.rawValue)")
        case .cancelled:
            output?.noteDiagnostics("setup check cancelled")
        default:
            break
        }
    }

    private func currentContext() -> CapabilityContext {
        guard let identity = output?.currentSessionIdentity() else {
            return CapabilityContext(captureFPS: nil, showStandard: "unknown", showFPS: 0,
                                     belowShowRate: false, source: "unknown", route: nil)
        }
        let source = identity.source
        let described = [source.deviceName, source.captureProfile].compactMap { $0 }.joined(separator: " · ")
        return CapabilityContext(
            captureFPS: source.configuredCaptureFPS,
            showStandard: identity.output.showStandard,
            showFPS: identity.output.showFPS,
            belowShowRate: source.belowShowRate,
            source: described.isEmpty ? source.inputKind : described,
            route: identity.output.route)
    }
}
