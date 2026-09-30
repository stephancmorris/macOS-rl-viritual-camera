//
//  CapabilityReport.swift
//  CinematicCoreMacOS
//
//  Pure evaluation behind the single-camera setup check (PREFLIGHT card).
//  Takes the diagnostics windows measured during a short live sample and
//  returns a provisional verdict with the measured reasons behind it.
//
//  What this is not: a certification. A 20–30 s sample cannot show that a
//  setup holds for a 60-minute show (that is the SOAK card), no free-CPU/GPU
//  API is assumed, and nothing here changes the show standard or capture.
//  Thresholds are provisional until calibrated against rig soak results.
//

import Foundation

nonisolated enum CapabilityVerdict: String, Equatable, Sendable {
    /// Every measured stage kept up during the sample.
    case supported
    /// At least one measured stage fell short; reasons say which.
    case limited
    /// The sample could not measure the workload (too short, no frames,
    /// detection never ran, unknown capture rate).
    case unverified

    var title: String {
        switch self {
        case .supported: return "Supported · provisional"
        case .limited: return "Limited"
        case .unverified: return "Unverified"
        }
    }
}

/// Thermal state as a comparable level (ProcessInfo.ThermalState is not
/// Comparable and not Sendable-friendly in pure code).
nonisolated enum ThermalLevel: Int, Comparable, Sendable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    var name: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        }
    }

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Provisional pass/fail lines. Calibrate against SOAK evidence before
/// treating any of them as release criteria.
nonisolated struct CapabilityThresholds: Equatable, Sendable {
    /// Windows (~5 s each) the sample must contain after warm-up.
    var minimumWindows = 3
    /// Delivered rate must reach this fraction of the configured capture rate.
    var deliveredRatioFloor = 0.97
    /// Gate-skipped frames as a fraction of delivered frames.
    var gateSkipRatioCeiling = 0.02
    /// Mean processFrame wall time as a fraction of one capture frame period.
    var frameWallBudgetFraction = 0.8
    /// Footprint growth across the sample, extrapolated per minute.
    var memoryGrowthCeilingMBPerMinute = 50.0
    /// Thermal level at or above which the setup is limited.
    var thermalLimit = ThermalLevel.serious

    static let provisional = CapabilityThresholds()
}

/// One measured window plus the thermal state when it closed.
nonisolated struct CapabilitySample: Equatable, Sendable {
    var window: DiagnosticsWindow
    var thermal: ThermalLevel
}

/// What the sample was measuring against.
nonisolated struct CapabilityContext: Equatable, Sendable {
    /// Capture rate Alfie configured (may be below the show rate in Webcam
    /// mode). nil if the source did not report one.
    var captureFPS: Double?
    var showStandard: String
    var showFPS: Double
    var belowShowRate: Bool
    var source: String
    var route: String?
    /// Whether the measured configuration runs detection at all. Wide / Pan
    /// / Manual don't, so a sample without detections is complete for them
    /// (the admission fingerprint includes each input's mode).
    var expectsDetection: Bool = true
}

nonisolated struct CapabilityReason: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        /// A measured stage fell short.
        case limit
        /// Something could not be measured.
        case unknown
        /// Context the operator should know; does not change the verdict.
        case note
    }

    var code: String
    var kind: Kind
    var message: String

    var id: String { code }
}

/// Aggregates across the sample windows.
nonisolated struct CapabilityMeasurements: Equatable, Sendable {
    var windows = 0
    var seconds: Double = 0
    var deliveredFPS: Double = 0
    var admittedFPS: Double = 0
    var handoffFPS: Double = 0
    var gateSkipRatio: Double = 0
    var frameWallMeanMS: Double = 0
    var frameWallMaxMS: Double = 0
    var visionMeanMS: Double = 0
    var observationAgeMeanMS: Double = 0
    var detections = 0
    var memoryGrowthMBPerMinute: Double = 0
    var worstThermal = ThermalLevel.nominal
    var counts = PipelineCounters()
}

nonisolated struct CapabilityReport: Equatable, Sendable {
    static let disclaimer = "Short sample, measured now. It does not show that this setup will hold for a 60-minute show; that needs the soak run on this exact setup."

    var verdict: CapabilityVerdict
    var reasons: [CapabilityReason]
    var measured: CapabilityMeasurements
    var context: CapabilityContext

    static func evaluate(
        samples: [CapabilitySample],
        context: CapabilityContext,
        thresholds: CapabilityThresholds = .provisional
    ) -> CapabilityReport {
        let measured = aggregate(samples)
        var reasons: [CapabilityReason] = []

        // Unknowns first: without them the limits below mean nothing.
        if measured.windows < thresholds.minimumWindows {
            reasons.append(.init(code: "sample.short", kind: .unknown,
                message: "Sample too short: \(measured.windows) of \(thresholds.minimumWindows) measurement windows."))
        }
        if measured.counts.admitted == 0 {
            reasons.append(.init(code: "sample.noFrames", kind: .unknown,
                message: "No frames reached the pipeline during the sample."))
        }
        if measured.detections == 0, context.expectsDetection {
            reasons.append(.init(code: "sample.noDetection", kind: .unknown,
                message: "Detection did not run during the sample, so its load was not measured. Run the check while tracking or detecting."))
        }
        guard let captureFPS = context.captureFPS, captureFPS > 0 else {
            reasons.append(.init(code: "source.rateUnknown", kind: .unknown,
                message: "The source did not report a configured capture rate."))
            return CapabilityReport(verdict: .unverified, reasons: reasons, measured: measured, context: context)
        }

        if context.belowShowRate {
            reasons.append(.init(code: "source.belowShowRate", kind: .note,
                message: String(format: "Webcam runs at %@ fps, below the %@ show standard; the output repeats frames. Judged against %@ fps.",
                                Self.rate(captureFPS), context.showStandard, Self.rate(captureFPS))))
        }

        if measured.counts.admitted > 0 {
            if measured.deliveredFPS < captureFPS * thresholds.deliveredRatioFloor {
                reasons.append(.init(code: "capture.cadence", kind: .limit,
                    message: String(format: "Source delivered %.1f fps; Alfie configured %@ fps.", measured.deliveredFPS, Self.rate(captureFPS))))
            }
            if measured.gateSkipRatio > thresholds.gateSkipRatioCeiling {
                reasons.append(.init(code: "pipeline.gateSkips", kind: .limit,
                    message: String(format: "Alfie skipped %.1f%% of delivered frames because the previous frame had not finished.", measured.gateSkipRatio * 100)))
            }
            let periodMS = 1000 / captureFPS
            let budgetMS = periodMS * thresholds.frameWallBudgetFraction
            if measured.frameWallMeanMS > budgetMS {
                reasons.append(.init(code: "pipeline.frameTime", kind: .limit,
                    message: String(format: "Processing took %.1f ms per frame on average; one frame at %@ fps is %.1f ms (limit %.1f ms).",
                                    measured.frameWallMeanMS, Self.rate(captureFPS), periodMS, budgetMS)))
            }
        }
        let counts = measured.counts
        if counts.captureDropped > 0 {
            reasons.append(.init(code: "capture.dropped", kind: .limit,
                message: "AVCapture dropped \(counts.captureDropped) frame(s) before Alfie received them."))
        }
        if counts.renderFailed > 0 {
            reasons.append(.init(code: "render.failed", kind: .limit,
                message: "\(counts.renderFailed) crop render(s) failed; Program repeated the last good frame."))
        }
        if counts.handoffRefused > 0 {
            reasons.append(.init(code: "output.refused", kind: .limit,
                message: "The output route refused \(counts.handoffRefused) frame(s)."))
        }
        if counts.noRoute > 0 {
            reasons.append(.init(code: "output.noRoute", kind: .limit,
                message: "\(counts.noRoute) frame(s) were produced with no output route active."))
        }
        if measured.memoryGrowthMBPerMinute > thresholds.memoryGrowthCeilingMBPerMinute {
            reasons.append(.init(code: "system.memoryGrowth", kind: .limit,
                message: String(format: "Memory grew at about %.0f MB per minute during the sample.", measured.memoryGrowthMBPerMinute)))
        }
        if measured.worstThermal >= thresholds.thermalLimit {
            reasons.append(.init(code: "system.thermal", kind: .limit,
                message: "The Mac reached the \(measured.worstThermal.name) thermal state during the sample."))
        } else if measured.worstThermal == .fair {
            reasons.append(.init(code: "system.thermalFair", kind: .note,
                message: "The Mac was in the fair thermal state; a longer run may heat further."))
        }

        let verdict: CapabilityVerdict
        if reasons.contains(where: { $0.kind == .unknown }) {
            verdict = .unverified
        } else if reasons.contains(where: { $0.kind == .limit }) {
            verdict = .limited
        } else {
            verdict = .supported
        }
        return CapabilityReport(verdict: verdict, reasons: reasons, measured: measured, context: context)
    }

    static func aggregate(_ samples: [CapabilitySample]) -> CapabilityMeasurements {
        var result = CapabilityMeasurements()
        guard !samples.isEmpty else { return result }
        var counts = PipelineCounters()
        var frameWallWeighted = 0.0
        var visionWeighted = 0.0
        var observationWeighted = 0.0
        for sample in samples {
            let w = sample.window
            let c = w.window
            result.seconds += w.windowSeconds
            counts.admitted += c.admitted
            counts.gateSkipped += c.gateSkipped
            counts.captureDropped += c.captureDropped
            counts.renderFailed += c.renderFailed
            counts.routed += c.routed
            counts.noRoute += c.noRoute
            counts.handoffAccepted += c.handoffAccepted
            counts.handoffRefused += c.handoffRefused
            counts.repeated += c.repeated
            result.detections += w.detections
            frameWallWeighted += w.frameMeanMS * Double(c.admitted)
            visionWeighted += w.visionMeanMS * Double(w.detections)
            observationWeighted += w.observationMeanMS * Double(w.detections)
            result.frameWallMaxMS = max(result.frameWallMaxMS, w.frameMaxMS)
            result.worstThermal = max(result.worstThermal, sample.thermal)
        }
        result.windows = samples.count
        result.counts = counts
        if result.seconds > 0 {
            result.deliveredFPS = Double(counts.delivered) / result.seconds
            result.admittedFPS = Double(counts.admitted) / result.seconds
            result.handoffFPS = Double(counts.handoffAccepted) / result.seconds
        }
        if counts.delivered > 0 {
            result.gateSkipRatio = Double(counts.gateSkipped) / Double(counts.delivered)
        }
        if counts.admitted > 0 { result.frameWallMeanMS = frameWallWeighted / Double(counts.admitted) }
        if result.detections > 0 {
            result.visionMeanMS = visionWeighted / Double(result.detections)
            result.observationAgeMeanMS = observationWeighted / Double(result.detections)
        }
        // Footprint trend: first window to last, over the time between them.
        if samples.count >= 2 {
            let span = samples.dropFirst().reduce(0) { $0 + $1.window.windowSeconds }
            if span > 0 {
                let growth = samples[samples.count - 1].window.footprintMB - samples[0].window.footprintMB
                result.memoryGrowthMBPerMinute = growth / span * 60
            }
        }
        return result
    }

    /// "50", "59.94", "30".
    static func rate(_ fps: Double) -> String {
        fps.rounded() == fps ? String(Int(fps)) : String(format: "%.2f", fps)
    }
}
