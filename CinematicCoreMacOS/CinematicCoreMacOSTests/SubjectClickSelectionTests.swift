import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct SubjectClickSelectionTests {
    private func person(_ box: CGRect = CGRect(x: 0.4, y: 0.2, width: 0.1, height: 0.6)) -> PersonDetector.DetectedPerson {
        .init(id: UUID(), boundingBox: box, confidence: 0.95, timestamp: 0,
              poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
    }

    @Test func bodyHitsAndModestNearBodyClicksStillSelect() {
        let person = person()
        for point in [CGPoint(x: 0.45, y: 0.5), CGPoint(x: 0.4, y: 0.2), CGPoint(x: 0.51, y: 0.5)] {
            #expect(CameraManager.personNearest(to: point, in: [person])?.id == person.id)
        }
    }

    @Test func fallbackBoundaryScalesWithEachCandidatesWidthAndHeight() {
        for width: CGFloat in [0.05, 0.1, 0.3] {
            let candidate = person(CGRect(x: 0.3, y: 0.2, width: width, height: 0.6))
            let box = candidate.boundingBox
            #expect(CameraManager.personNearest(to: CGPoint(x: box.midX + width * 0.74, y: box.midY), in: [candidate])?.id == candidate.id)
            #expect(CameraManager.personNearest(to: CGPoint(x: box.midX + width * 0.76, y: box.midY), in: [candidate]) == nil)
        }
    }

    @Test func emptyStageAndInvalidClicksSelectNobody() {
        #expect(CameraManager.personNearest(to: CGPoint(x: 0.9, y: 0.5), in: [person()]) == nil)
        #expect(CameraManager.personNearest(to: CGPoint(x: 0.5, y: 0.5), in: []) == nil)
        #expect(CameraManager.personNearest(to: CGPoint(x: CGFloat.nan, y: 0.5), in: [person()]) == nil)
    }

    @Test func ordinaryMissRearmsDetectRatherThanLockingABystander() {
        let manager = TestHardware.makeCamera()
        manager.beginDetection()
        manager.selectSubject(at: CGPoint(x: 0.9, y: 0.5))
        manager.resolvePendingSubjectTap(in: [person()], now: 100)
        #expect(manager.manualLockedTargetID == nil)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .awaitingTap)
    }

    @Test func holdRetargetMissKeepsTheCurrentLock() {
        let manager = TestHardware.makeCamera()
        let old = UUID()
        manager.lockTarget(personID: old)
        manager.retargetSubject(at: CGPoint(x: 0.9, y: 0.5))
        manager.resolvePendingSubjectTap(in: [person()], now: 100)
        #expect(manager.manualLockedTargetID == old)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .acquiring)
    }

    @Test func aSuccessfulClickStillStartsNormalAcquisition() {
        let manager = TestHardware.makeCamera()
        let candidate = person()
        manager.beginDetection()
        manager.selectSubject(at: CGPoint(x: 0.45, y: 0.5))
        manager.resolvePendingSubjectTap(in: [candidate], now: 100)
        #expect(manager.manualLockedTargetID == candidate.id)
        #expect(manager.currentDetectionPlan(detectionRunsThisFrame: true).mode == .acquiring)
    }
}
