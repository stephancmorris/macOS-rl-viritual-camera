import Foundation
import Testing
@testable import Alfie

/// Authored evidence sequence only; no camera, operator or production threshold.
struct DirectorStyleSettleEvidenceReviewTests {
    @Test func styleSpecificSettlingDoesNotInheritTimeAboveStyleMotionLimit() throws {
        let target = UUID()
        func sample(_ time: Double, speed: Double) -> ChannelEvidenceSample {
            ChannelEvidenceSample(channel: .b, sampledAt: time, lockPhase: .tracking,
                trackingOwnsControl: true, galleryReady: true, lockedTargetID: target,
                observationAge: 0.05, subjectSpeed: speed, holdingSteady: true,
                cropConverged: true, operatorGestureInProgress: false, observedPersonCount: 1)
        }
        var adapter = DirectorEvidenceAdapter(parameters: .init(maximumObservationAge: 2,
                                                               debounce: 0, stillSpeed: 0.05))
        adapter.ingest(sample(0, speed: 0.01))
        adapter.ingest(sample(1, speed: 0.01))
        adapter.ingest(sample(2, speed: 0.01))
        adapter.ingest(sample(2.1, speed: 0))
        let style = DirectorStyle(minimumShotDuration: 8, preferredShotDuration: 20,
            softMaximumShotDuration: 40, wideCadence: 75, repetitionWindow: 40,
            maximumMovement: 0.005, settleTime: 1, onAirMoveRate: 0.35, cutOnMotionAllowed: false)
        let study = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 0.03,
            cutOnMotionAllowed: true, minimumCutSettledTime: 0.25, maximumCutMotion: 0.02)
        let effective = study.tightened(by: style)
        #expect(effective.minimumCutSettledTime == 1)
        #expect(effective.maximumCutMotion == 0.005)
        let take = TakeAvailability(program: .a, preview: .b, standard: .p50,
                                    reason: nil, takePending: false, editLive: false)
        let input = try #require(adapter.readinessInputs(for: .b, take: take, now: 2.1))
        #expect(input.identity == .confirmed && input.motion == 0 && input.cropConverged)
        #expect(input.framingSettledFor >= 2)
        let ready = DirectorReadiness.evaluate(input, parameters: effective, bar: .cut)
        // Only this sample is below the style limit; the preceding two seconds
        // were above it. The style's one-second settling interval has not elapsed.
        #expect(ready.reasons == [.framingUnsettled])
    }
}
