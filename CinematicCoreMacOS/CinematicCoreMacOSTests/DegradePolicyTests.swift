import Testing
@testable import Alfie

struct DegradePolicyTests {
    @Test func sustainedOverloadClimbsOnlyTheOptionalWorkLadder() {
        var policy = DegradePolicy()
        var window = DegradePolicy.Window()
        window.cpuFraction = 0.95
        let levels: [DegradePolicy.Level] = [.optionalUI, .optionalPoseFace, .previewPerception, .previewRender]
        for expected in levels {
            for _ in 0..<2 { #expect(policy.update(window).level < expected) }
            let decision = policy.update(window)
            #expect(decision.level == expected)
            #expect(decision.transition?.to == expected)
            #expect(!decision.requiresExplicitSingleChannelAction)
        }
        #expect(policy.transitions.count == 4)
    }

    @Test func recoveryNeedsSixHealthyWindowsPerRung() {
        var policy = DegradePolicy()
        var hot = DegradePolicy.Window()
        hot.thermalSerious = true
        for _ in 0..<6 { _ = policy.update(hot) }
        #expect(policy.level == .optionalPoseFace)
        for _ in 0..<5 { #expect(policy.update(.init()).level == .optionalPoseFace) }
        #expect(policy.update(.init()).level == .optionalUI)
        for _ in 0..<6 { _ = policy.update(.init()) }
        #expect(policy.level == .normal)
    }

    @Test func alternatingPressureCannotFlap() {
        var policy = DegradePolicy()
        var hot = DegradePolicy.Window()
        hot.cpuFraction = 0.98
        for _ in 0..<20 {
            _ = policy.update(hot)
            _ = policy.update(.init())
        }
        #expect(policy.level == .normal)
        #expect(policy.transitions.isEmpty)
    }

    @Test func failedMinimumBudgetRequiresExplicitSingleChannelAction() {
        var policy = DegradePolicy()
        var failed = DegradePolicy.Window()
        failed.sourceIngestSustainable = false
        let decision = policy.update(failed)
        #expect(decision.level == .unsupported)
        #expect(decision.requiresExplicitSingleChannelAction)
        #expect(decision.takeBlockedByPolicy)
        #expect(decision.reasons.contains(.sourceIngestFailed))
        for _ in 0..<12 {
            let latched = policy.update(.init())
            #expect(latched.level == .unsupported)
            #expect(latched.reasons.contains(.sourceIngestFailed))
            #expect(!latched.reasons.contains(.programBudgetFailed))
        }
        var single = DegradePolicy.Window()
        single.twoInputsActive = false
        #expect(policy.update(single).level == .normal)
    }

    @Test func staleCandidateAlwaysBlocksTakeEvenAtNormalWorkload() {
        var policy = DegradePolicy()
        var stale = DegradePolicy.Window()
        stale.candidateAgeSeconds = 0.5
        let decision = policy.update(stale)
        #expect(decision.level == .normal)
        #expect(decision.takeBlockedByPolicy)
        #expect(decision.reasons.contains(.candidateStale))
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, -1.0])
    func invalidCandidateAgeBlocksTake(age: Double) {
        var policy = DegradePolicy()
        var window = DegradePolicy.Window()
        window.candidateAgeSeconds = age
        let decision = policy.update(window)
        #expect(decision.takeBlockedByPolicy)
        #expect(decision.reasons.contains(.candidateStale))
    }

    @Test func freshnessBoundaryAndMissingCandidate() {
        var policy = DegradePolicy()
        var window = DegradePolicy.Window()
        window.candidateAgeSeconds = policy.thresholds.candidateFreshnessSeconds
        #expect(!policy.update(window).takeBlockedByPolicy)
        window.candidateAgeSeconds = nil
        #expect(policy.update(window).takeBlockedByPolicy)
    }

    @Test func invalidThresholdsAreRejectedInsteadOfSilentlyNormalized() {
        let fields: [WritableKeyPath<DegradePolicy.Thresholds, Double>] = [
            \.cpuFraction, \.programDeadlineMissFraction, \.previewRenderAgeSeconds, \.candidateFreshnessSeconds]
        for field in fields {
            for value in [Double.nan, .infinity, -.infinity, -1, 0] {
                var thresholds = DegradePolicy.Thresholds()
                thresholds[keyPath: field] = value
                #expect(DegradePolicy(thresholds: thresholds) == nil)
            }
        }
        for field in [\DegradePolicy.Thresholds.cpuFraction, \.programDeadlineMissFraction] {
            var thresholds = DegradePolicy.Thresholds()
            thresholds[keyPath: field] = 1.1
            #expect(DegradePolicy(thresholds: thresholds) == nil)
        }
        for count in [-1, 0] {
            var thresholds = DegradePolicy.Thresholds()
            thresholds.enterWindows = count
            #expect(DegradePolicy(thresholds: thresholds) == nil)
            thresholds = .init()
            thresholds.exitWindows = count
            #expect(DegradePolicy(thresholds: thresholds) == nil)
        }
        #expect(DegradePolicy(thresholds: .init()) != nil)
    }

    @Test func invalidMeasurementsBlockTakeAndCannotRecoverWorkload() {
        let fields: [WritableKeyPath<DegradePolicy.Window, Double>] = [
            \.cpuFraction, \.programDeadlineMissFraction, \.previewRenderAgeSeconds]
        for field in fields {
            for value in [Double.nan, .infinity, -.infinity, -1] {
                var policy = DegradePolicy()
                var window = DegradePolicy.Window()
                window[keyPath: field] = value
                for _ in 0..<12 {
                    let decision = policy.update(window)
                    #expect(decision.takeBlockedByPolicy)
                    #expect(decision.reasons.contains(.invalidMeasurement))
                }
                #expect(policy.level == .previewRender)
                window.twoInputsActive = false
                #expect(policy.update(window).takeBlockedByPolicy)
            }
        }
        for field in [\DegradePolicy.Window.cpuFraction, \.programDeadlineMissFraction] {
            var policy = DegradePolicy()
            var window = DegradePolicy.Window()
            window[keyPath: field] = 1.1
            #expect(policy.update(window).takeBlockedByPolicy)
        }
    }

}
