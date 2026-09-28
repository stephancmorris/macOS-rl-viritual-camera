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
}
