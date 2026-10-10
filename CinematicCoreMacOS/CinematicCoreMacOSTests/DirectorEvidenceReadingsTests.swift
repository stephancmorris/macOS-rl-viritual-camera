import Testing
@testable import Alfie

/// S3 B-01: read-only evidence accessors. Reading them never changes the
/// channel; each one reports what the channel already knows.
@MainActor struct DirectorEvidenceReadingsTests {
    private func manager() -> CameraManager {
        CameraManager(channelID: .b, programOutput: ProgramOutputManager(sinks: []), routed: false)
    }

    @Test func freshChannelReportsNothingKnown() {
        let camera = manager()
        let readings = camera.evidenceReadings(now: 100)
        #expect(readings.channel == .b)
        #expect(readings.sampledAt == 100)
        #expect(!readings.isRunning)
        #expect(readings.mode == .wide)
        #expect(readings.lockPhase == .inactive)
        #expect(!readings.galleryReady)
        #expect(!readings.trackingOwnsControl)
        #expect(readings.lockedTargetID == nil)
        #expect(readings.subjectSpeed == 0)
        #expect(!readings.holdingSteady)
        #expect(readings.observationAge == nil)
        #expect(readings.observedPersonCount == 0)
        #expect(!readings.operatorGestureInProgress)
    }

    @Test func observationAgeUsesTheHostClock() {
        let camera = manager()
        camera.recordObservationForTesting(capturedAt: 10, personCount: 2)
        #expect(camera.observationAge(now: 10.25) == 0.25)
        let readings = camera.evidenceReadings(now: 12)
        #expect(readings.observationAge == 2)
        #expect(readings.observedPersonCount == 2)
    }

    @Test func armedDetectIsAnOperatorGestureInProgress() {
        let camera = manager()
        camera.setRunningForTesting(true)
        #expect(camera.dispatch(camera.makeCommand(.detect)) == .accepted)
        #expect(camera.operatorGestureInProgress)
        #expect(camera.evidenceReadings().operatorGestureInProgress)
        #expect(camera.dispatch(camera.makeCommand(.cancelDetect)) == .accepted)
        #expect(!camera.operatorGestureInProgress)
    }

    @Test func readingDoesNotChangeTheChannel() {
        let camera = manager()
        camera.setRunningForTesting(true)
        let before = camera.revisions
        let mode = camera.activeMode
        for _ in 0..<5 { _ = camera.evidenceReadings() }
        #expect(camera.revisions == before)
        #expect(camera.activeMode == mode)
    }

    @Test func readingsCrossIsolationBoundaries() async {
        let readings = manager().evidenceReadings(now: 1)
        let echoed = await Task.detached { readings }.value
        #expect(echoed == readings)
    }
}
