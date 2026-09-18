import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import Testing
import Vision
@testable import Alfie

@MainActor
struct LockedTrackIntegrationRegressionTests {
    private func observation(_ box: CGRect) -> VNHumanObservation {
        VNHumanObservation(boundingBox: box)
    }

    private func assertLockedTrackDoesNotEscapeThroughOrdinaryMatching(
        reference: CGRect,
        rejectedCandidate: CGRect
    ) {
        let detector = PersonDetector()
        detector.updateTracking(
            rectObservations: [observation(reference)],
            poseObservations: [],
            faceObservations: [],
            timestamp: 10
        )
        let lockedID = detector.detectedPersons[0].id
        detector.lockedTargetID = lockedID

        detector.updateTracking(
            rectObservations: [observation(rejectedCandidate)],
            poseObservations: [],
            faceObservations: [],
            timestamp: 10.02
        )

        #expect(detector.detectedPersons.count == 1)
        #expect(
            detector.detectedPersons[0].id != lockedID,
            "A candidate rejected by the locked policy must not inherit the locked UUID in ordinary matching"
        )
    }

    @Test func probationCandidateCannotBypassLockedPolicy() {
        let reference = CGRect(x: 0.47, y: 0.30, width: 0.06, height: 0.50)
        let candidate = reference.offsetBy(dx: 0.10, dy: 0)
        let resolution = PersonDetector.resolveLockedAssignment(
            detections: [candidate], referenceBox: reference,
            lockVelocityMagnitude: 0, timeSinceLockSeen: 0.02,
            otherTrackBoxes: [], probation: nil
        )
        #expect(resolution.assignedIndex == nil)
        #expect(resolution.probation != nil)
        assertLockedTrackDoesNotEscapeThroughOrdinaryMatching(
            reference: reference, rejectedCandidate: candidate)
    }

    @Test func outOfRadiusCandidateCannotBypassLockedPolicy() {
        let reference = CGRect(x: 0.47, y: 0.30, width: 0.06, height: 0.50)
        let candidate = reference.offsetBy(dx: 0.13, dy: 0)
        #expect(PersonDetector.lockedMatchScore(
            detection: candidate, reference: reference,
            allowedDistance: PersonDetector.lockedBaseJumpRadius
        ) == 0)
        assertLockedTrackDoesNotEscapeThroughOrdinaryMatching(
            reference: reference, rejectedCandidate: candidate)
    }

    @Test func incompatibleBodySizeCannotBypassLockedPolicy() {
        let reference = CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.50)
        let candidate = CGRect(x: 0.44, y: 0.425, width: 0.12, height: 0.25)
        #expect(PersonDetector.iou(reference, candidate) > 0.2)
        #expect(PersonDetector.lockedMatchScore(
            detection: candidate, reference: reference,
            allowedDistance: PersonDetector.lockedBaseJumpRadius
        ) == 0)
        assertLockedTrackDoesNotEscapeThroughOrdinaryMatching(
            reference: reference, rejectedCandidate: candidate)
    }
}

@MainActor
struct ReacquisitionEvidenceRegressionTests {
    private let target = UUID()
    private let other = UUID()

    private func strongTargetBatch() -> [ShotComposer.ReacquisitionScore] {
        [
            .init(id: target, printDistance: 0.10, landmarkDistance: 0.01),
            .init(id: other, printDistance: 0.40, landmarkDistance: 0.02)
        ]
    }

    @Test func threeDistinctCompleteObservationBatchesAreRequired() {
        var evidence = ShotComposer.ReacquisitionEvidence()
        #expect(evidence.consider(observationID: 1, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 1, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 2, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 3, scores: strongTargetBatch()) == target)
    }

    @Test func lateOlderObservationCannotAdvanceEvidence() {
        var evidence = ShotComposer.ReacquisitionEvidence()
        #expect(evidence.consider(observationID: 10, scores: strongTargetBatch()) == nil)
        #expect(evidence.count == 1)
        #expect(evidence.consider(observationID: 9, scores: strongTargetBatch()) == nil)
        #expect(evidence.count == 1)
        #expect(evidence.consider(observationID: 11, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 12, scores: strongTargetBatch()) == target)
    }

    @Test func oneCrowdBatchCountsAsOneSighting() {
        let third = UUID()
        var evidence = ShotComposer.ReacquisitionEvidence()
        let crowd = [
            ShotComposer.ReacquisitionScore(id: target, printDistance: 0.10, landmarkDistance: 0.01),
            ShotComposer.ReacquisitionScore(id: other, printDistance: 0.40, landmarkDistance: 0.02),
            ShotComposer.ReacquisitionScore(id: third, printDistance: 0.50, landmarkDistance: 0.03)
        ]
        #expect(evidence.consider(observationID: 10, scores: crowd) == nil)
        #expect(evidence.count == 1)
        #expect(evidence.candidate == target)
    }

    @Test func missingObservationBreaksConsecutiveEvidence() {
        var evidence = ShotComposer.ReacquisitionEvidence()
        #expect(evidence.consider(observationID: 1, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 2, scores: []) == nil)
        #expect(evidence.count == 0)
        #expect(evidence.consider(observationID: 3, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 4, scores: strongTargetBatch()) == nil)
        #expect(evidence.consider(observationID: 5, scores: strongTargetBatch()) == target)
    }

    @Test func ambiguousBatchBreaksConsecutiveEvidence() {
        var evidence = ShotComposer.ReacquisitionEvidence()
        #expect(evidence.consider(observationID: 1, scores: strongTargetBatch()) == nil)
        let ambiguous = [
            ShotComposer.ReacquisitionScore(id: target, printDistance: 0.10, landmarkDistance: 0.01),
            ShotComposer.ReacquisitionScore(id: other, printDistance: 0.11, landmarkDistance: 0.01)
        ]
        #expect(evidence.consider(observationID: 2, scores: ambiguous) == nil)
        #expect(evidence.count == 0)
        #expect(evidence.candidate == nil)
    }

    @Test func landmarkVetoedBystanderDoesNotRelaxSoloThreshold() {
        var evidence = ShotComposer.ReacquisitionEvidence()
        let effectivelySolo = [
            // This candidate clears the multi-person threshold (0.62) but not
            // the stricter solo threshold (0.55).
            ShotComposer.ReacquisitionScore(id: target, printDistance: 0.58, landmarkDistance: 0.01),
            // A landmark veto proves this bystander is ineligible; their mere
            // presence must not make the target candidate easier to accept.
            ShotComposer.ReacquisitionScore(id: other, printDistance: 0.20, landmarkDistance: 0.50)
        ]
        #expect(evidence.consider(observationID: 1, scores: effectivelySolo) == nil)
        #expect(evidence.count == 0)
        #expect(evidence.candidate == nil)
    }
}

@MainActor
struct DetectionFrameFreshnessRegressionTests {
    private func pixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
            nil, &buffer
        )
        #expect(status == kCVReturnSuccess)
        return buffer!
    }

    private func frame(id: UInt64, capturedAt: TimeInterval) -> DetectionFrame {
        DetectionFrame(
            observationID: id,
            capturedAt: capturedAt,
            sourceTimestamp: capturedAt,
            pixelBuffer: pixelBuffer(),
            persons: [],
            queueWait: 0,
            detectionDuration: 0
        )
    }

    @Test func observationIsFreshExactlyOnceAndExpiresWithItsPixels() {
        let store = DetectionFrameStore()
        let generation = store.generation
        #expect(store.publish(frame(id: 1, capturedAt: 10), generation: generation))

        let first = store.consume(at: 10.1)
        #expect(first.frame?.observationID == 1)
        #expect(first.isFresh)

        let repeated = store.consume(at: 10.2)
        #expect(repeated.frame?.observationID == 1)
        #expect(!repeated.isFresh)

        let expired = store.consume(at: 10 + DetectionFrameStore.maximumAge + 0.001)
        #expect(expired.frame == nil)
        #expect(!expired.isFresh)
        #expect(store.latest == nil)
    }

    @Test func originalPixelsStayPairedAndLateResultsCannotReplaceExpiredNewerOnes() throws {
        let store = DetectionFrameStore()
        let original = frame(id: 2, capturedAt: 10)
        #expect(store.publish(original, generation: store.generation))
        let consumed = try #require(store.consume(at: 10.1).frame)
        #expect(consumed.pixelBuffer === original.pixelBuffer)
        _ = store.consume(at: 11)
        #expect(!store.publish(frame(id: 1, capturedAt: 10.9), generation: store.generation))
        #expect(store.latest == nil)
    }

    @Test func invalidationRejectsResultsFromThePreviousGeneration() {
        let store = DetectionFrameStore()
        let staleGeneration = store.generation
        store.invalidate()
        #expect(!store.publish(frame(id: 1, capturedAt: 10), generation: staleGeneration))
        #expect(store.latest == nil)
    }
}

@MainActor
struct AcquisitionDeadlineRegressionTests {
    private func person(id: UUID, timestamp: TimeInterval) -> PersonDetector.DetectedPerson {
        PersonDetector.DetectedPerson(
            id: id,
            boundingBox: CGRect(x: 0.4, y: 0.2, width: 0.15, height: 0.5),
            confidence: 1,
            timestamp: timestamp,
            poseKeypoints: nil,
            faceBoundingBox: nil,
            faceLandmarkRatios: nil
        )
    }

    @Test func visibleBodyWithoutFaceCannotAcquireForever() {
        let composer = ShotComposer()
        let id = UUID()
        composer.lockTarget(id)
        let started = CACurrentMediaTime()
        _ = composer.tick(
            detections: [person(id: id, timestamp: started)],
            timestamp: started + ShotComposer.acquisitionTimeout + 0.01,
            pixelBuffer: nil,
            isFresh: true,
            observationID: 1,
            observationTimestamp: started
        )
        #expect(!composer.isAcquiring)
        #expect(composer.acquisitionFeedback != nil)
    }

    @Test func missingGraceUsesTheLastFreshSighting() {
        let composer = ShotComposer()
        let id = UUID()
        composer.lockTarget(id)
        let started = CACurrentMediaTime()
        let lastSeen = started + 0.25
        _ = composer.tick(
            detections: [person(id: id, timestamp: lastSeen)],
            timestamp: lastSeen,
            pixelBuffer: nil,
            isFresh: true,
            observationID: 1,
            observationTimestamp: lastSeen
        )
        _ = composer.tick(
            detections: [],
            timestamp: lastSeen + ShotComposer.acquireGrace - 0.01,
            pixelBuffer: nil,
            isFresh: true,
            observationID: 2
        )
        #expect(composer.isAcquiring)

        _ = composer.tick(
            detections: [],
            timestamp: lastSeen + ShotComposer.acquireGrace + 0.01,
            pixelBuffer: nil,
            isFresh: true,
            observationID: 3
        )
        #expect(!composer.isAcquiring)
        #expect(composer.acquisitionFeedback != nil)
    }

    @Test func missingGraceStartsAtObservationCaptureTime() {
        let composer = ShotComposer()
        let id = UUID()
        composer.lockTarget(id)
        let started = CACurrentMediaTime()

        // The observation was captured at `started` but delivered after 0.4 s.
        // Last-seen time must describe the sighting, not the delivery tick.
        _ = composer.tick(
            detections: [person(id: id, timestamp: started)],
            timestamp: started + 0.4,
            pixelBuffer: nil,
            isFresh: true,
            observationID: 1,
            observationTimestamp: started
        )
        _ = composer.tick(
            detections: [],
            timestamp: started + ShotComposer.acquireGrace + 0.01,
            pixelBuffer: nil,
            isFresh: true,
            observationID: 2
        )

        #expect(!composer.isAcquiring)
        #expect(composer.acquisitionFeedback != nil)
    }
}
