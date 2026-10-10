import Foundation
import Testing
@testable import Alfie

/// A-02: discrete identity evidence (plan §5.2) and the two readiness bars (P1).
struct IdentityEvidenceTests {
    private static let subject = UUID()

    private static func sample(phase: RecoveryState.Phase = .tracking, owns: Bool = true,
                               galleryReady: Bool = true, target: UUID? = subject,
                               age: TimeInterval? = 0.05, people: Int = 1,
                               gesture: Bool = false) -> ChannelEvidenceSample {
        ChannelEvidenceSample(channel: .b, sampledAt: 10, lockPhase: phase,
            trackingOwnsControl: owns, galleryReady: galleryReady, lockedTargetID: target,
            observationAge: age, subjectSpeed: 0, holdingSteady: true, cropConverged: true,
            operatorGestureInProgress: gesture, observedPersonCount: people)
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let sample: ChannelEvidenceSample
        let expected: IdentityEvidence
        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(name: "tracking, owned, gallery ready, fresh", sample: sample(), expected: .confirmed),
        Row(name: "acquiring (learning face)", sample: sample(phase: .acquiring, galleryReady: false), expected: .acquiring),
        Row(name: "tracking before gallery ready", sample: sample(galleryReady: false), expected: .acquiring),
        Row(name: "hold (recovering)", sample: sample(phase: .hold), expected: .holding),
        Row(name: "wideWaiting (subject gone)", sample: sample(phase: .wideWaiting, target: nil), expected: .lost),
        Row(name: "two people in the subject ROI", sample: sample(people: 2), expected: .ambiguous),
        Row(name: "no lock", sample: sample(phase: .inactive, target: nil), expected: .unavailable),
        Row(name: "operator framing manually", sample: sample(owns: false), expected: .unavailable),
        Row(name: "stale observation", sample: sample(age: 2), expected: .unavailable),
        Row(name: "no observation yet", sample: sample(age: nil), expected: .unavailable),
        Row(name: "operator gesture does not change identity", sample: sample(gesture: true), expected: .confirmed),
    ]

    @Test(arguments: rows)
    func classifiesEveryEvidenceRow(row: Row) {
        #expect(IdentityEvidence.classify(row.sample, maximumObservationAge: 0.5) == row.expected)
    }

    @Test func invalidAgesFailClosed() {
        for limit in [Double.nan, -1, .infinity] {
            #expect(IdentityEvidence.classify(Self.sample(), maximumObservationAge: limit) == .unavailable)
        }
        for age in [Double.nan, -0.1, .infinity] {
            #expect(IdentityEvidence.classify(Self.sample(age: age), maximumObservationAge: 0.5) == .unavailable)
        }
    }

    // MARK: Two readiness bars

    private let take = TakeAvailability(program: .a, preview: .b, standard: .p50,
        reason: nil, takePending: false, editLive: false)
    private let study = DirectorReadiness.Parameters(minimumSettledTime: 0.2, maximumMotion: 0.3,
        cutOnMotionAllowed: false, minimumCutSettledTime: 1, maximumCutMotion: 0.05)

    private func inputs(identity: IdentityEvidence = .confirmed, settled: TimeInterval = 2,
                        motion: Double = 0, converged: Bool = true) -> DirectorReadiness.Inputs {
        .init(take: take, identity: identity, framingSettledFor: settled, motion: motion, cropConverged: converged)
    }

    @Test func settledConfirmedSubjectIsReadyOnBothBars() {
        #expect(DirectorReadiness.evaluate(inputs(), parameters: study).isReady)
        #expect(DirectorReadiness.evaluate(inputs(), parameters: study, bar: .cut).isReady)
    }

    @Test func cutBarIsStricterThanPrepare() {
        let justSettled = inputs(settled: 0.5, motion: 0.1, converged: false)
        #expect(DirectorReadiness.evaluate(justSettled, parameters: study).isReady)
        let cut = DirectorReadiness.evaluate(justSettled, parameters: study, bar: .cut)
        #expect(Set(cut.reasons) == [.framingUnsettled, .moving, .cropMoving])
    }

    @Test func cutBarIgnoresCutOnMotionAllowance() {
        let allowing = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 0.3,
            cutOnMotionAllowed: true, minimumCutSettledTime: 0, maximumCutMotion: 0.05)
        let moving = inputs(motion: 0.2)
        #expect(DirectorReadiness.evaluate(moving, parameters: allowing).isReady)
        #expect(DirectorReadiness.evaluate(moving, parameters: allowing, bar: .cut).reasons == [.moving])
    }

    @Test(arguments: [IdentityEvidence.acquiring, .holding, .lost, .ambiguous, .unavailable])
    func anythingButConfirmedIsNotReady(identity: IdentityEvidence) {
        #expect(DirectorReadiness.evaluate(inputs(identity: identity), parameters: study).reasons == [.identityUncertain])
        #expect(DirectorReadiness.evaluate(inputs(identity: identity), parameters: study, bar: .cut).reasons == [.identityUncertain])
    }

    @Test func cutParametersLooserThanPrepareAreInvalid() {
        let looserSettle = DirectorReadiness.Parameters(minimumSettledTime: 1, maximumMotion: 0.3,
            cutOnMotionAllowed: false, minimumCutSettledTime: 0.5, maximumCutMotion: 0.05)
        let looserMotion = DirectorReadiness.Parameters(minimumSettledTime: 0.2, maximumMotion: 0.1,
            cutOnMotionAllowed: false, minimumCutSettledTime: 1, maximumCutMotion: 0.2)
        #expect(!looserSettle.isValid && !looserMotion.isValid)
        #expect(DirectorReadiness.evaluate(inputs(), parameters: looserMotion, bar: .cut).reasons == [.invalidParameters])
    }

    @Test func readinessNeverOverridesTakeEligibility() {
        let refused = TakeAvailability(program: .a, preview: .b, standard: .p50,
            reason: .sourceMissing, takePending: false, editLive: false)
        let input = DirectorReadiness.Inputs(take: refused, identity: .confirmed,
            framingSettledFor: 2, motion: 0, cropConverged: true)
        #expect(DirectorReadiness.evaluate(input, parameters: study).reasons == [.takeUnavailable])
    }
}
