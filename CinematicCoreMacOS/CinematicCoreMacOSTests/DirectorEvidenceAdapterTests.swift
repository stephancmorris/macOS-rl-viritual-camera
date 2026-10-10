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
                        people: Int = 1) -> ChannelEvidenceSample {
        ChannelEvidenceSample(channel: channel, sampledAt: t, lockPhase: phase, trackingOwnsControl: true,
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

    @Test func staleObservationIsAGapNotALoss() {
        var adapter = confirmed()
        adapter.ingest(sample(1.0, age: 2))
        let events = adapter.ingest(sample(1.6, age: 2))
        #expect(events == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .unavailable)
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

    @Test func outOfOrderAndInvalidTimesAreIgnored() {
        var adapter = confirmed()
        #expect(adapter.ingest(sample(0.2, phase: .wideWaiting, target: nil)).isEmpty)
        #expect(adapter.ingest(sample(.nan, phase: .wideWaiting, target: nil)).isEmpty)
        #expect(adapter.state(for: .b)?.identity == .confirmed)
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
