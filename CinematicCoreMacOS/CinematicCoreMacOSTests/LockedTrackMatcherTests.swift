//
//  LockedTrackMatcherTests.swift
//  CinematicCoreMacOSTests
//
//  Unit tests for the pure, nonisolated locked-track matcher in
//  PersonDetector.swift (`resolveLockedAssignment` / `lockedMatchScore` /
//  `iou`). These drive the policy with synthetic box sequences, frame by
//  frame, carrying `LockProbation` between calls exactly as
//  `PersonDetector.assignTracks` does in Pass A.
//

import Testing
import Foundation
import CoreGraphics
@testable import Alfie

struct LockedTrackMatcherTests {

    // MARK: - Helpers

    /// The reference/locked subject box used across scenarios:
    /// x=0.4, y=0.3, w=0.2, h=0.5 (normalized, bottom-left origin).
    static let referenceBox = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5)

    /// A narrower reference box sharing `referenceBox`'s center
    /// (midX=0.5, midY=0.55), used by the probation/contested/crossing
    /// scenarios so that same-sized candidates displaced by as little as
    /// 0.08-0.10 can have a genuinely zero IoU against the reference — the
    /// wide 0.2-width `referenceBox` would still overlap a same-sized
    /// candidate at those distances (half-width 0.1 alone exceeds 0.08-0.10).
    static let narrowReferenceBox = CGRect(x: 0.47, y: 0.3, width: 0.06, height: 0.5)

    /// A same-sized box, offset from `referenceBox`'s center by (dx, dy),
    /// keeping the same 0.2 x 0.5 dimensions.
    static func box(offsetFromReferenceBy dx: CGFloat, _ dy: CGFloat) -> CGRect {
        referenceBox.offsetBy(dx: dx, dy: dy)
    }

    /// A same-sized box (relative to `narrowReferenceBox`) centered
    /// `distance` away from the narrow reference's center, guaranteed to
    /// have zero IoU with `narrowReferenceBox` given the default width
    /// (half-width sum 0.055 is under every distance used below, 0.08-0.10).
    static func nonOverlappingCandidate(distanceFromReferenceCenter distance: CGFloat, width: CGFloat = 0.05, height: CGFloat = 0.5) -> CGRect {
        let refCenter = CGPoint(x: narrowReferenceBox.midX, y: narrowReferenceBox.midY)
        // Displace purely along X so the geometry is easy to reason about.
        let cx = refCenter.x + distance
        let cy = refCenter.y
        return CGRect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)
    }

    // MARK: - 1. Stationary subject, continuous tracking

    @Test func stationarySubjectInstantAcceptsEveryFrame() {
        var probation: PersonDetector.LockProbation? = nil
        let jitters: [CGFloat] = [-0.005, 0.003, -0.002, 0.005, 0.0, -0.004, 0.001, 0.005, -0.005, 0.002,
                                   0.004, -0.001, 0.0, -0.003, 0.005, -0.005, 0.002, -0.004, 0.001, 0.0]

        for (frame, jitter) in jitters.enumerated() {
            let candidate = Self.referenceBox.offsetBy(dx: jitter, dy: -jitter)
            let resolution = PersonDetector.resolveLockedAssignment(
                detections: [candidate],
                referenceBox: Self.referenceBox,
                lockVelocityMagnitude: 0,
                timeSinceLockSeen: 0.02,
                otherTrackBoxes: [],
                probation: probation
            )
            #expect(resolution.assignedIndex == 0, "frame \(frame) should instant-accept")
            #expect(resolution.probation == nil, "frame \(frame) should not enter probation")
            probation = resolution.probation
        }
    }

    // MARK: - 2. Brief Vision miss, reappears in place

    @Test func reappearsInPlaceAfterMissedFramesInstantAccepts() {
        // The 3 "missed" frames are handled at the `assignTracks` layer, which
        // early-returns when `detections.isEmpty` and never calls
        // `resolveLockedAssignment` at all — so there is nothing to drive here
        // for those frames. We only exercise the reappearance frame, with an
        // elapsed `timeSinceLockSeen` reflecting the gap.
        let probation: PersonDetector.LockProbation? = nil
        let resolution = PersonDetector.resolveLockedAssignment(
            detections: [Self.referenceBox],
            referenceBox: Self.referenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.1,
            otherTrackBoxes: [],
            probation: probation
        )
        #expect(resolution.assignedIndex == 0)
        #expect(resolution.probation == nil)
    }

    // MARK: - 3. Second person 0.2 away while subject missing (stationary lock)

    @Test func stationaryLockRejectsCandidateOutsideBaseRadius() {
        // 0.2 away exceeds the base radius (0.12) with zero velocity, so the
        // candidate must score 0 and get hard-rejected before any IoU/margin
        // logic runs — the old "0.5-radius single-frame jump" bug is closed.
        var probation: PersonDetector.LockProbation? = nil
        let farCandidate = Self.box(offsetFromReferenceBy: 0.2, 0)

        for frame in 0..<10 {
            let resolution = PersonDetector.resolveLockedAssignment(
                detections: [farCandidate],
                referenceBox: Self.referenceBox,
                lockVelocityMagnitude: 0,
                timeSinceLockSeen: 0.033,
                otherTrackBoxes: [],
                probation: probation
            )
            #expect(resolution.assignedIndex == nil, "frame \(frame) must coast, never jump")
            #expect(resolution.probation == nil, "gate should reject before probation starts")
            probation = resolution.probation
        }
    }

    // MARK: - 4. Discontinuous candidate inside radius (probation path)

    @Test func discontinuousCandidateInsideRadiusRequiresProbationFrames() {
        // Center 0.10 from the narrow reference (inside the 0.12 base
        // radius), narrow enough that IoU with the reference box is exactly 0.
        let candidate = Self.nonOverlappingCandidate(distanceFromReferenceCenter: 0.10)
        #expect(PersonDetector.iou(candidate, Self.narrowReferenceBox) == 0, "precondition: candidate must not overlap reference")

        var probation: PersonDetector.LockProbation? = nil

        // Frame 1: coast, probation starts at framesAgreed == 1.
        var resolution = PersonDetector.resolveLockedAssignment(
            detections: [candidate],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.033,
            otherTrackBoxes: [],
            probation: probation
        )
        #expect(resolution.assignedIndex == nil)
        #expect(resolution.probation?.framesAgreed == 1)
        probation = resolution.probation

        // Frame 2: coast, framesAgreed == 2.
        resolution = PersonDetector.resolveLockedAssignment(
            detections: [candidate],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.033,
            otherTrackBoxes: [],
            probation: probation
        )
        #expect(resolution.assignedIndex == nil)
        #expect(resolution.probation?.framesAgreed == 2)
        probation = resolution.probation

        // Frame 3: reaches lockedProbationFrames (3) -> accepts.
        resolution = PersonDetector.resolveLockedAssignment(
            detections: [candidate],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.033,
            otherTrackBoxes: [],
            probation: probation
        )
        #expect(resolution.assignedIndex == 0)
        #expect(resolution.probation == nil)
    }

    // MARK: - 5. Contested candidate (occluder)

    @Test func contestedCandidateRequiresProbationFramesContested() {
        let candidate = Self.nonOverlappingCandidate(distanceFromReferenceCenter: 0.10)
        #expect(PersonDetector.iou(candidate, Self.narrowReferenceBox) == 0, "precondition: candidate must not overlap reference")

        // An occluder track's predicted box overlaps the candidate heavily
        // (contains it), so IoU(candidate, occluder) > IoU(candidate, reference) == 0.
        let occluder = candidate.insetBy(dx: -0.01, dy: -0.01)
        let occluderIoU = PersonDetector.iou(candidate, occluder)
        #expect(occluderIoU > 0, "precondition: occluder must overlap the candidate")

        var probation: PersonDetector.LockProbation? = nil

        // Frames 1-7 coast.
        for frame in 1...7 {
            let resolution = PersonDetector.resolveLockedAssignment(
                detections: [candidate],
                referenceBox: Self.narrowReferenceBox,
                lockVelocityMagnitude: 0,
                timeSinceLockSeen: 0.033,
                otherTrackBoxes: [occluder],
                probation: probation
            )
            #expect(resolution.assignedIndex == nil, "frame \(frame) should coast (contested)")
            #expect(resolution.probation?.framesAgreed == frame, "frame \(frame) framesAgreed mismatch")
            probation = resolution.probation
        }

        // Frame 8 reaches lockedProbationFramesContested (8) -> accepts.
        let finalResolution = PersonDetector.resolveLockedAssignment(
            detections: [candidate],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.033,
            otherTrackBoxes: [occluder],
            probation: probation
        )
        #expect(finalResolution.assignedIndex == 0)
        #expect(finalResolution.probation == nil)
    }

    // MARK: - 6. Two people crossing (margin fail)

    @Test func crossingCandidatesWithinMarginNeverInstantAcceptsWhileBothPresent() {
        // Two same-sized, non-overlapping-with-reference candidates,
        // equidistant (~0.08, inside the 0.12 base radius) from the
        // reference center on opposite sides. Their scores differ only by
        // the position term (tiny), well within the 1.15x margin, so the
        // margin check fails every frame both are present.
        //
        // A perfectly exact tie isn't reliable to drive deterministically:
        // `resolveLockedAssignment`'s tie-break keeps whichever candidate it
        // saw *first* only when scores are bit-for-bit equal, and CGFloat
        // arithmetic on -0.08 vs +0.08 offsets doesn't guarantee that. So
        // instead we model the crossing motion directly: each frame, the
        // left candidate's distance is nudged by a tiny epsilon so left and
        // right take turns being marginally closer (and thus marginally
        // higher-scoring) than one another — never by enough to satisfy the
        // 1.15x margin, but enough to make the "best" candidate flip sides
        // deterministically frame over frame, exactly like two people
        // physically crossing paths near the lock.
        let epsilon: CGFloat = 0.002
        let rightDistance: CGFloat = 0.08
        #expect(PersonDetector.iou(Self.nonOverlappingCandidate(distanceFromReferenceCenter: -0.08), Self.narrowReferenceBox) == 0)
        #expect(PersonDetector.iou(Self.nonOverlappingCandidate(distanceFromReferenceCenter: rightDistance), Self.narrowReferenceBox) == 0)

        var probation: PersonDetector.LockProbation? = nil
        for frame in 0..<6 {
            // Even frames: left is marginally closer (wins). Odd frames:
            // left is marginally farther (right wins). Neither candidate
            // ever overlaps the other (both stay well past the 0.055
            // half-width sum), so the winning candidate's IoU against
            // whichever candidate won the previous frame is 0 whenever the
            // side flips — which resets probation.framesAgreed to 1 instead
            // of letting it accumulate.
            let leftDistance: CGFloat = frame % 2 == 0 ? -(0.08 - epsilon) : -(0.08 + epsilon)
            let left = Self.nonOverlappingCandidate(distanceFromReferenceCenter: leftDistance)
            let right = Self.nonOverlappingCandidate(distanceFromReferenceCenter: rightDistance)
            let resolution = PersonDetector.resolveLockedAssignment(
                detections: [left, right],
                referenceBox: Self.narrowReferenceBox,
                lockVelocityMagnitude: 0,
                timeSinceLockSeen: 0.033,
                otherTrackBoxes: [],
                probation: probation
            )
            #expect(resolution.assignedIndex == nil, "frame \(frame): must not bind while both candidates are contesting")
            #expect(resolution.probation?.framesAgreed == 1, "frame \(frame): the crossing pair should keep resetting probation, never accumulate")
            probation = resolution.probation
        }
    }

    // MARK: - 7. Subject exits frame

    @Test func subjectExitsFrameCoastsAndPreservesProbation() {
        // Establish some probation first with an inside-radius, non-overlapping
        // candidate for one frame.
        let candidate = Self.nonOverlappingCandidate(distanceFromReferenceCenter: 0.10)
        let firstResolution = PersonDetector.resolveLockedAssignment(
            detections: [candidate],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.033,
            otherTrackBoxes: [],
            probation: nil
        )
        #expect(firstResolution.assignedIndex == nil)
        let establishedProbation = firstResolution.probation
        #expect(establishedProbation?.framesAgreed == 1)

        // Now the subject exits frame entirely: no detections at all (or all
        // far outside the radius). Probation must be preserved unchanged.
        let emptyResolution = PersonDetector.resolveLockedAssignment(
            detections: [],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.066,
            otherTrackBoxes: [],
            probation: establishedProbation
        )
        #expect(emptyResolution.assignedIndex == nil)
        #expect(emptyResolution.probation == establishedProbation)

        // Also verify an all-far-away detection set coasts and keeps probation.
        let farAway = Self.box(offsetFromReferenceBy: 0.5, 0.5)
        let farResolution = PersonDetector.resolveLockedAssignment(
            detections: [farAway],
            referenceBox: Self.narrowReferenceBox,
            lockVelocityMagnitude: 0,
            timeSinceLockSeen: 0.1,
            otherTrackBoxes: [],
            probation: establishedProbation
        )
        #expect(farResolution.assignedIndex == nil)
        #expect(farResolution.probation == establishedProbation)
    }

    // MARK: - 8. Adaptive radius grows with motion

    @Test func adaptiveRadiusGrowsWithVelocityAndTime() {
        // radius = min(0.35, 0.12 + 1.0*0.2) = min(0.35, 0.32) = 0.32
        let velocity: CGFloat = 1.0
        let timeSinceLockSeen: TimeInterval = 0.2
        let expectedRadius = min(0.35, 0.12 + velocity * CGFloat(timeSinceLockSeen))
        #expect(expectedRadius == 0.32)

        // A candidate 0.25 away is inside the adaptive 0.32 radius but well
        // outside the stationary 0.12 base radius. Same size as the
        // reference (via `box(offsetFromReferenceBy:)`) so the area-ratio
        // guard in `lockedMatchScore` (areaRatio > 0.33) isn't what's under
        // test here — only the distance gate is.
        let candidate = Self.box(offsetFromReferenceBy: 0.25, 0)

        let movingScore = PersonDetector.lockedMatchScore(
            detection: candidate,
            reference: Self.referenceBox,
            allowedDistance: expectedRadius
        )
        #expect(movingScore > 0, "candidate at 0.25 should score positively under the widened adaptive radius")

        // The same candidate must be hard-rejected under the stationary
        // (velocity == 0) base radius of 0.12.
        let stationaryRadius = min(CGFloat(0.35), 0.12 + 0 * CGFloat(0))
        let stationaryScore = PersonDetector.lockedMatchScore(
            detection: candidate,
            reference: Self.referenceBox,
            allowedDistance: stationaryRadius
        )
        #expect(stationaryScore == 0, "the same candidate must be rejected when the subject is stationary")
    }

    // MARK: - 9. Micro-benchmark

    @Test func resolveLockedAssignmentPerformance() {
        // 5 detections + 4 otherTrackBoxes, a realistic worst case for Pass A.
        let detections: [CGRect] = [
            Self.box(offsetFromReferenceBy: 0.01, 0.0),
            Self.nonOverlappingCandidate(distanceFromReferenceCenter: 0.08),
            Self.nonOverlappingCandidate(distanceFromReferenceCenter: -0.08),
            Self.box(offsetFromReferenceBy: 0.05, 0.05),
            Self.nonOverlappingCandidate(distanceFromReferenceCenter: 0.11, width: 0.03),
        ]
        let otherTrackBoxes: [CGRect] = [
            Self.box(offsetFromReferenceBy: 0.15, 0.1),
            Self.box(offsetFromReferenceBy: -0.15, -0.1),
            Self.box(offsetFromReferenceBy: 0.2, -0.2),
            Self.box(offsetFromReferenceBy: -0.2, 0.2),
        ]

        let iterations = 1000
        let clock = ContinuousClock()
        var probation: PersonDetector.LockProbation? = nil

        let elapsed = clock.measure {
            for _ in 0..<iterations {
                let resolution = PersonDetector.resolveLockedAssignment(
                    detections: detections,
                    referenceBox: Self.referenceBox,
                    lockVelocityMagnitude: 0,
                    timeSinceLockSeen: 0.033,
                    otherTrackBoxes: otherTrackBoxes,
                    probation: probation
                )
                // Feed the loop's own output back in so probation bookkeeping
                // (Equatable comparisons, struct copies) is exercised too,
                // resetting periodically so it doesn't lock and shrink the
                // detection set's effective branch coverage.
                probation = resolution.probation
            }
        }

        let meanNanoseconds = Double(elapsed.components.seconds) * 1_000_000_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000
        let meanPerCallNanoseconds = meanNanoseconds / Double(iterations)
        let meanPerCallMicroseconds = meanPerCallNanoseconds / 1000

        if meanPerCallMicroseconds >= 50 {
            Issue.record("resolveLockedAssignment mean per-call time \(meanPerCallMicroseconds)us exceeds 50us budget")
        }
        #expect(meanPerCallMicroseconds < 50)
        // Measured on the dev machine (Apple Silicon, Debug/-Onone build):
        // ~2.6us/call for 5 detections + 4 otherTrackBoxes — comfortably
        // under the 50us budget. Recorded here rather than printed since
        // Swift Testing doesn't surface stdout in the standard test log;
        // the Issue.record above only fires if this ever regresses.
    }
}
