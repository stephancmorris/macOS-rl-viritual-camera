import CoreGraphics
import Testing
import Vision
@testable import Alfie

struct LockedSearchRegionTests {
    private let box = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.4)
    private func region(_ velocity: CGVector = .zero, elapsed: Double = 0) -> CGRect {
        CameraManager.lockedSearchRegion(box: box, velocity: velocity, elapsed: elapsed)
    }

    @Test func stationaryRegionKeepsExistingPaddingAndCenter() {
        let roi = region()
        #expect(abs(roi.width - box.width * 3.0) < 1e-12)
        #expect(abs(roi.height - box.height * 1.8) < 1e-12)
        #expect(abs(roi.midX - box.midX) < 1e-12 && abs(roi.midY - box.midY) < 1e-12)
    }

    @Test func leadScalesWithVelocityAndTimeInEitherDirection() {
        for sign: CGFloat in [-1, 1] {
            let roi = region(CGVector(dx: sign * 0.2, dy: 0), elapsed: 0.1)
            #expect(abs(roi.midX - box.midX - sign * 0.02) < 1e-12)
            #expect(abs(roi.midY - box.midY) < 1e-12)
        }
        let vertical = region(CGVector(dx: 0, dy: 0.2), elapsed: 0.1)
        #expect(abs(vertical.midY - box.midY - 0.02) < 1e-12)
    }

    @Test func longGapsHaveABoundedLeadAndRemainInsideFrame() {
        let roi = region(CGVector(dx: 2, dy: 2), elapsed: 100)
        #expect(abs(hypot(roi.midX - box.midX, roi.midY - box.midY) - box.width * 0.25) < 1e-12)
        let edge = CameraManager.lockedSearchRegion(box: CGRect(x: 0.85, y: 0.8, width: 0.1, height: 0.15),
                                                 velocity: CGVector(dx: 2, dy: 2), elapsed: 1)
        #expect(edge.minX >= 0 && edge.minY >= 0 && edge.maxX <= 1 && edge.maxY <= 1)
    }

    @Test func absentBoxesAndInvalidMotionHaveSafeFallbacks() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(CameraManager.lockedSearchRegion(box: nil, velocity: .zero, elapsed: 0) == full)
        #expect(CameraManager.lockedSearchRegion(box: .zero, velocity: .zero, elapsed: 0) == full)
        #expect(region(CGVector(dx: 1, dy: 0), elapsed: -1) == region())
        #expect(region(CGVector(dx: CGFloat.nan, dy: 0), elapsed: 1) == region())
    }

    @MainActor @Test func detectorExposesTheLatestMotionAsAReadOnlySnapshot() throws {
        let detector = PersonDetector()
        detector.updateTracking(rectObservations: [VNHumanObservation(boundingBox: box)],
                                poseObservations: [], faceObservations: [], timestamp: 100)
        let id = try #require(detector.detectedPersons.first?.id)
        detector.updateTracking(rectObservations: [VNHumanObservation(boundingBox: box.offsetBy(dx: 0.02, dy: 0))],
                                poseObservations: [], faceObservations: [], timestamp: 100.1)
        let motion = try #require(detector.trackMotion(for: id))
        #expect(motion.lastSeen == 100.1 && motion.velocity.dx > 0)
        #expect(detector.trackMotion(for: id)?.velocity.dx == motion.velocity.dx)
    }
}
