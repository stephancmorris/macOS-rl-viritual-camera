import Foundation
import Testing
@testable import Alfie

/// A-07: sequences of evidence samples → debounced identity, settled time,
/// readiness inputs and authority events.
struct DirectorEvidenceAdapterTests {
    private static let pastor = UUID(), visitor = UUID()
    /// Test fixture values only.
    private let parameters = DirectorEvidenceAdapter.Parameters(maximumObservationAge: 0.5, debounce: 0.5, stillSpeed: 0.05)

    private func sample(_ t: TimeInterval, channel: ChannelID = .b, phase: RecoveryState.Phase = .tracking,
                        target: UUID? = pastor, age: TimeInterval? = 0.05, speed: Double = 0,
                        steady: Bool = true, converged: Bool = true, gesture: Bool = false,
                        people: Int = 1, owns: Bool = true) -> ChannelEvidenceSample {
        ChannelEvidenceSample(channel: channel, sampledAt: t, lockPhase: phase, trackingOwnsControl: owns,
            galleryReady: phase != .acquiring, lockedTargetID: target, observationAge: age,
            subjectSpeed: speed, holdingSteady: steady, cropConverged: converged,
            operatorGestureInProgress: gesture, observedPersonCount: people)
    }

    /// Confirms channel B at t = 0…0.6 and returns the adapter.
    private func confirmed() -> DirectorEvidenceAdapter {
        var adapter = DirectorEvidenceAdapter(parameters: parameters)
        adapter.ingest(sample(0)); adapter.ingest(sample(0.6))
        return adapter
    }

    @Test func confirmationIsDebouncedThenPublished() {
        var adapter = DirectorEvidenceAdapter(parameters: parameters)
        #expect(adapter.ingest(sample(0)).isEmpty)
        #expect(adapter.state(for: .b)?.identity == .unavailable)
        #expect(adapter.ingest(sample(0.6)) == [.evidenceAvailable(.b, true)])
        #expect(adapter.state(for: .b)?.identity == .confirmed)
    }

    @Test func briefLockFlickerDoesNotChurnEvidence() {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(1.0, phase: .hold)).isEmpty)
        #expect(adapter.ingest(sample(1.2, phase: .hold)).isEmpty)
        #expect(adapter.ingest(sample(1.3)).isEmpty)
        #expect(adapter.state(for: .b)?.identity == .confirmed)
    }

    @Test func sustainedHoldOpensAGapWithoutRevoking() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, phase: .hold))
        let events = adapter.ingest(sample(1.6, phase: .hold))
        #expect(events == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .holding)
        #expect(!events.contains(.identityLost(.b)))
    }

    @Test func wideWaitingIsALossImmediatelyAndOnce() {
        var adapter = confirmed()
        let first = adapter.ingest(sample(1.0, phase: .wideWaiting, target: nil))
        #expect(first == [.identityLost(.b), .evidenceAvailable(.b, false)])
        #expect(adapter.ingest(sample(1.1, phase: .wideWaiting, target: nil)).isEmpty)
        #expect(adapter.state(for: .b)?.identity == .lost)
    }

    @Test func operatorGestureInhibitsOnly() {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(1.0, gesture: true)) == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .confirmed)
        #expect(adapter.ingest(sample(1.1)) == [.evidenceAvailable(.b, true)])
    }

    @Test func staleObservationImmediatelyOpensAGapWithoutRevoking() {
        var adapter = confirmed()
        let events = adapter.ingest(sample(1.0, age: 2))
        #expect(events == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .unavailable)
        #expect(adapter.state(for: .b)?.lockedTargetID == Self.pastor)
        #expect(adapter.settledFor(.b, now: 1.0) == 0)
        #expect(adapter.ingest(sample(1.6, age: 2)).isEmpty)
    }

    @Test(arguments: [0.0, 0.5.nextDown, 0.5])
    func observationAgeThroughInclusiveLimitRemainsFresh(age: TimeInterval) {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(1.0, age: age)).isEmpty)
        #expect(adapter.state(for: .b)?.evidenceAvailable == true)
        #expect(adapter.settledFor(.b, now: 1.0) > 0)
    }

    @Test func firstRepresentableAgePastLimitImmediatelyInhibits() {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(1.0, age: parameters.maximumObservationAge.nextUp)) == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .unavailable)
        #expect(adapter.state(for: .b)?.settledSince == nil)
    }

    struct InvalidAge: Sendable, CustomTestStringConvertible {
        let label: String
        let value: TimeInterval?
        var testDescription: String { label }
    }

    static let invalidAges = [
        InvalidAge(label: "missing observation", value: nil),
        InvalidAge(label: "future observation", value: -0.01),
        InvalidAge(label: "NaN observation age", value: .nan),
        InvalidAge(label: "infinite observation age", value: .infinity),
        InvalidAge(label: "negative infinite observation age", value: -.infinity),
        InvalidAge(label: "stale observation", value: 2)
    ]

    @Test(arguments: invalidAges)
    func invalidObservationCannotRetainConfirmationOrSettlement(age: InvalidAge) {
        for phase in [RecoveryState.Phase.tracking, .hold, .acquiring] {
            var adapter = confirmed()
            let events = adapter.ingest(sample(1.0, phase: phase, age: age.value))
            #expect(events == [.evidenceAvailable(.b, false)])
            #expect(adapter.state(for: .b)?.evidenceAvailable == false)
            let expectedIdentity: IdentityEvidence = phase == .hold ? .holding : phase == .acquiring ? .acquiring : .unavailable
            #expect(adapter.state(for: .b)?.identity == expectedIdentity)
            #expect(adapter.state(for: .b)?.pendingIdentity == nil)
            #expect(adapter.state(for: .b)?.settledSince == nil)
            #expect(adapter.settledFor(.b, now: 1.0) == 0)
        }
    }

    @Test func freshRecoveryMustConfirmAgainAndStartANewSettlement() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, age: 2))
        #expect(adapter.ingest(sample(1.1)).isEmpty)
        #expect(adapter.state(for: .b)?.evidenceAvailable == false)
        #expect(adapter.state(for: .b)?.settledSince == nil)
        #expect(adapter.ingest(sample(1.59)).isEmpty)
        #expect(adapter.ingest(sample(1.6)) == [.evidenceAvailable(.b, true)])
        #expect(adapter.state(for: .b)?.settledSince == 1.6)
        #expect(adapter.settledFor(.b, now: 1.6) == 0)
    }

    @Test func aGapPreventsBothReadinessBarsEvenWithNoSettlingThreshold() throws {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, age: 2))
        let take = TakeAvailability(program: .a, preview: .b, standard: .p50, reason: nil, takePending: false, editLive: false)
        let input = try #require(adapter.readinessInputs(for: .b, take: take, now: 1.0))
        let bars = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 1,
            cutOnMotionAllowed: false, minimumCutSettledTime: 0, maximumCutMotion: 1)
        #expect(DirectorReadiness.evaluate(input, parameters: bars).reasons == [.identityUncertain])
        #expect(DirectorReadiness.evaluate(input, parameters: bars, bar: .cut).reasons == [.identityUncertain])
        #expect(input.take.isEligible)
    }

    @Test func invalidObservationCancelsAPendingConfirmation() {
        var adapter = DirectorEvidenceAdapter(parameters: parameters)
        adapter.ingest(sample(0))
        #expect(adapter.state(for: .b)?.pendingIdentity == .confirmed)
        adapter.ingest(sample(0.4, age: 2))
        #expect(adapter.state(for: .b)?.pendingIdentity == nil)
        adapter.ingest(sample(0.6))
        #expect(adapter.ingest(sample(1.0)).isEmpty)
        #expect(adapter.ingest(sample(1.1)) == [.evidenceAvailable(.b, true)])
    }

    @Test func unavailableControlAndLockChangesDoNotWaitForDebounce() {
        var manual = confirmed()
        #expect(manual.ingest(sample(1.0, owns: false)) == [.evidenceAvailable(.b, false)])
        #expect(manual.state(for: .b)?.identity == .unavailable)
        #expect(manual.state(for: .b)?.settledSince == nil)

        var inactive = confirmed()
        #expect(inactive.ingest(sample(1.0, phase: .inactive)) == [.evidenceAvailable(.b, false)])
        #expect(inactive.state(for: .b)?.identity == .unavailable)
        #expect(inactive.state(for: .b)?.settledSince == nil)
    }

    @Test func declaredLossStillRevokesWithInvalidObservationAge() {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(1.0, phase: .wideWaiting, target: nil, age: .nan)) ==
            [.identityLost(.b), .evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .lost)
    }

    @Test func crossingPersonBecomesAmbiguousAfterDebounce() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, people: 2))
        #expect(adapter.ingest(sample(1.6, people: 2)) == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .ambiguous)
    }

    @Test func nominationChangeIsImmediateAndResetsSettling() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0)); adapter.ingest(sample(3.0))
        #expect(adapter.settledFor(.b, now: 3) > 0)
        let events = adapter.ingest(sample(3.1, target: Self.visitor))
        #expect(events.first == .nominationChanged(.b))
        #expect(adapter.settledFor(.b, now: 3.1) == 0)
        let cleared = adapter.ingest(sample(3.2, phase: .inactive, target: nil))
        #expect(cleared.first == .nominationChanged(.b))
    }

    @Test func settledTimeAccumulatesAndResetsOnMovement() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0))
        #expect(adapter.settledFor(.b, now: 3) == 2.4)
        adapter.ingest(sample(3.0, speed: 0.4))
        #expect(adapter.settledFor(.b, now: 3) == 0)
        adapter.ingest(sample(3.5)); adapter.ingest(sample(4.0, converged: false))
        #expect(adapter.settledFor(.b, now: 4) == 0)
    }

    @Test func readinessInputsReflectTheAdapter() throws {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, speed: 0.01))
        let take = TakeAvailability(program: .a, preview: .b, standard: .p50, reason: nil, takePending: false, editLive: false)
        let inputs = try #require(adapter.readinessInputs(for: .b, take: take, now: 2))
        #expect(inputs.identity == .confirmed && inputs.cropConverged && inputs.motion == 0.01)
        #expect(abs(inputs.framingSettledFor - 1.4) < 1e-9)
        #expect(adapter.readinessInputs(for: .a, take: take, now: 2) == nil)
    }

    @Test func historicalSamplesAreDiscardedWithoutRewindingCurrentEvidence() {
        var adapter = confirmed()
        let before = adapter.state(for: .b)
        #expect(adapter.ingest(sample(0.2, phase: .wideWaiting, target: Self.visitor, age: 2, gesture: true)).isEmpty)
        #expect(adapter.state(for: .b) == before)
        #expect(adapter.ingest(sample(0.7)).isEmpty)
        #expect(adapter.state(for: .b)?.evidenceAvailable == true)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func invalidSampleClocksInhibitWithoutAcceptingPayloadOrRewindingWatermark(clock: TimeInterval) {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(clock, phase: .wideWaiting, target: Self.visitor)) == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .unavailable)
        #expect(adapter.state(for: .b)?.lastSampleAt == 0.6)
        #expect(adapter.state(for: .b)?.lockedTargetID == Self.pastor)
        #expect(adapter.state(for: .b)?.settledSince == nil)
        #expect(adapter.state(for: .b)?.pendingIdentity == nil)
        #expect(adapter.ingest(sample(clock)).isEmpty)
        #expect(adapter.ingest(sample(0.5)).isEmpty)
        #expect(adapter.state(for: .b)?.lastSampleAt == 0.6)
        #expect(adapter.ingest(sample(0.7)).isEmpty)
        #expect(adapter.ingest(sample(1.2)) == [.evidenceAvailable(.b, true)])
        #expect(adapter.state(for: .b)?.settledSince == 1.2)
    }

    @Test func invalidFirstSampleDoesNotCreateAChannelOrRevokeALoss() {
        var adapter = DirectorEvidenceAdapter(parameters: parameters)
        #expect(adapter.ingest(sample(-1)).isEmpty)
        #expect(adapter.state(for: .b) == nil)
        adapter.ingest(sample(0, phase: .wideWaiting, target: nil))
        #expect(adapter.ingest(sample(.nan)).isEmpty)
        #expect(adapter.state(for: .b)?.identity == .lost)
        #expect(adapter.state(for: .b)?.lastSampleAt == 0)
    }

    @Test func equalSampleClockCanOpenAGapWithoutAdvancingTheClock() {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(0.6, age: 2)) == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.lastSampleAt == 0.6)
        #expect(adapter.ingest(sample(0.6)).isEmpty)
        #expect(adapter.state(for: .b)?.pendingSince == 0.6)
        #expect(adapter.ingest(sample(1.1)) == [.evidenceAvailable(.b, true)])
    }

    @Test func invalidParametersFailClosed() {
        var adapter = DirectorEvidenceAdapter(parameters: .init(maximumObservationAge: .nan, debounce: 0, stillSpeed: 0))
        adapter.ingest(sample(0)); adapter.ingest(sample(5))
        #expect(adapter.state(for: .b)?.identity == .unavailable)
        #expect(adapter.state(for: .b)?.evidenceAvailable == false)
    }

    @Test func channelsAreIndependent() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, channel: .a, phase: .wideWaiting, target: nil))
        #expect(adapter.state(for: .a)?.identity == .lost)
        #expect(adapter.state(for: .b)?.identity == .confirmed)
    }
}
