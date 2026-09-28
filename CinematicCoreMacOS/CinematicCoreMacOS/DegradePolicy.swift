// Pure R2 policy. ShowCoordinator should feed one measured window at a time,
// apply only the returned optional-work hints, and combine takeBlockedByPolicy
// with its existing legal crop, identity, shot-revision and freshness gates.
// An unsupported pair requires an explicit single-channel operator action.
// Thresholds are provisional until MULTI-QA freezes measured budgets.

import Foundation

nonisolated struct DegradePolicy: Sendable {
    enum Level: Int, CaseIterable, Comparable, Sendable {
        case normal, optionalUI, optionalPoseFace, previewPerception, previewRender, unsupported
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Reason: String, Sendable {
        case thermalPressure, cpuPressure, previewStale, programDeadlineMiss
        case sourceIngestFailed, programBudgetFailed, candidateStale, recovering
    }

    struct Window: Sendable {
        var twoInputsActive = true
        var cpuFraction = 0.0
        var thermalSerious = false
        var programDeadlineMissFraction = 0.0
        var previewRenderAgeSeconds = 0.0
        var sourceIngestSustainable = true
        var programBudgetSustainable = true
        var candidateAgeSeconds: Double? = 0
    }

    struct Thresholds: Sendable {
        var enterWindows = 3
        var exitWindows = 6
        var cpuFraction = 0.90
        var programDeadlineMissFraction = 0.02
        var previewRenderAgeSeconds = 0.20
        var candidateFreshnessSeconds = 0.20
    }

    struct Transition: Sendable {
        let window: Int
        let from: Level
        let to: Level
        let reasons: [Reason]
    }

    struct Decision: Sendable {
        let level: Level
        let reasons: [Reason]
        let reduceOptionalUIAndDiagnostics: Bool
        let reduceOptionalPoseAndFace: Bool
        let reducePreviewPerception: Bool
        let reducePreviewRender: Bool
        /// Additional refusal only; normal Take validation stays authoritative.
        let takeBlockedByPolicy: Bool
        let requiresExplicitSingleChannelAction: Bool
        let transition: Transition?
    }

    let thresholds: Thresholds
    private(set) var level: Level = .normal
    private(set) var transitions: [Transition] = []
    private var overloadedWindows = 0
    private var healthyWindows = 0
    private var windowIndex = 0
    private var unsupportedReasons: [Reason] = []

    init(thresholds: Thresholds = .init()) { self.thresholds = thresholds }

    mutating func update(_ window: Window) -> Decision {
        windowIndex += 1
        let candidateStale = window.candidateAgeSeconds.map {
            !$0.isFinite || $0 > thresholds.candidateFreshnessSeconds
        } ?? true
        if !window.twoInputsActive {
            let transition = change(to: .normal, reasons: [.recovering])
            overloadedWindows = 0
            healthyWindows = 0
            unsupportedReasons = []
            return decision(reasons: [], candidateStale: candidateStale, transition: transition)
        }
        // Unsupported is latched until the operator chooses a single input.
        // A later healthy sample cannot silently re-admit the pair.
        if level == .unsupported {
            return decision(reasons: unsupportedReasons, candidateStale: candidateStale, transition: nil)
        }

        var reasons: [Reason] = []
        if window.thermalSerious { reasons.append(.thermalPressure) }
        if !window.cpuFraction.isFinite || window.cpuFraction >= thresholds.cpuFraction {
            reasons.append(.cpuPressure)
        }
        if !window.programDeadlineMissFraction.isFinite ||
            window.programDeadlineMissFraction >= thresholds.programDeadlineMissFraction {
            reasons.append(.programDeadlineMiss)
        }
        if !window.previewRenderAgeSeconds.isFinite ||
            window.previewRenderAgeSeconds >= thresholds.previewRenderAgeSeconds {
            reasons.append(.previewStale)
        }
        if !window.sourceIngestSustainable { reasons.append(.sourceIngestFailed) }
        if !window.programBudgetSustainable { reasons.append(.programBudgetFailed) }
        if candidateStale { reasons.append(.candidateStale) }

        // A concrete minimum safe-budget failure is categorical. The policy
        // cannot change the Program route or output standard to conceal it.
        if !window.sourceIngestSustainable || !window.programBudgetSustainable {
            overloadedWindows = 0
            healthyWindows = 0
            unsupportedReasons = reasons
            let transition = change(to: .unsupported, reasons: reasons)
            return decision(reasons: reasons, candidateStale: candidateStale, transition: transition)
        }

        let overloaded = reasons.contains { $0 != .candidateStale }
        var transition: Transition?
        if overloaded {
            overloadedWindows += 1
            healthyWindows = 0
            if overloadedWindows >= max(1, thresholds.enterWindows), level < .previewRender {
                overloadedWindows = 0
                transition = change(to: Level(rawValue: level.rawValue + 1)!, reasons: reasons)
            }
        } else {
            healthyWindows += 1
            overloadedWindows = 0
            if healthyWindows >= max(1, thresholds.exitWindows), level > .normal {
                healthyWindows = 0
                transition = change(to: Level(rawValue: level.rawValue - 1)!, reasons: [.recovering])
            }
        }
        return decision(reasons: reasons, candidateStale: candidateStale, transition: transition)
    }

    private mutating func change(to next: Level, reasons: [Reason]) -> Transition? {
        guard next != level else { return nil }
        let transition = Transition(window: windowIndex, from: level, to: next, reasons: reasons)
        level = next
        transitions.append(transition)
        if transitions.count > 128 { transitions.removeFirst() }
        return transition
    }

    private func decision(reasons: [Reason], candidateStale: Bool, transition: Transition?) -> Decision {
        Decision(level: level, reasons: reasons,
                 reduceOptionalUIAndDiagnostics: level >= .optionalUI,
                 reduceOptionalPoseAndFace: level >= .optionalPoseFace,
                 reducePreviewPerception: level >= .previewPerception,
                 reducePreviewRender: level >= .previewRender,
                 takeBlockedByPolicy: candidateStale || level == .unsupported,
                 requiresExplicitSingleChannelAction: level == .unsupported,
                 transition: transition)
    }
}
