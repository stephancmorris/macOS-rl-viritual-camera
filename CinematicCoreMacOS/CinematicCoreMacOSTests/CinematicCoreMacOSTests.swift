//
//  CinematicCoreMacOSTests.swift
//  CinematicCoreMacOSTests
//
//  Created by Stephan Morris on 2/2/2026.
//

import Testing
import Foundation
import CoreGraphics
@testable import Alfie

struct CinematicCoreMacOSTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
}

/// Regression tests for the detection cadence gate
/// (`CameraManager.detectionSlotIsDue`). The intermediate bug this locks out:
/// testing `(counter + 1) % interval == 0` while only advancing the counter on
/// already-due frames dead-locked scheduled detection at interval > 1 and froze
/// tracking on the single tap-time detection.
struct DetectionCadenceTests {

    @Test func intervalTwoRunsEverySecondEligibleFrame() {
        // Eligible frames are counted 1, 2, 3, … (every captured frame with no
        // detection in flight). At interval 2 slots must land on 2, 4, 6 —
        // including the crucial property that frame 1 (count 1) does NOT run,
        // yet frame 3 (count 3) still reaches count-3 → next slot at 4.
        let expected = [false, true, false, true, false, true, false, true]
        for (index, want) in expected.enumerated() {
            let count = UInt64(index + 1)
            #expect(
                CameraManager.detectionSlotIsDue(eligibleFrameCount: count, interval: 2) == want,
                "eligible frame \(count) at interval 2 should be \(want ? "DUE" : "skipped")"
            )
        }
    }

    @Test func intervalThreeSkipsThenRunsOnMultiples() {
        let expected = [false, false, true, false, false, true]
        for (index, want) in expected.enumerated() {
            let count = UInt64(index + 1)
            #expect(
                CameraManager.detectionSlotIsDue(eligibleFrameCount: count, interval: 3) == want,
                "eligible frame \(count) at interval 3 should be \(want ? "DUE" : "skipped")"
            )
        }
    }

    @Test func intervalOneRunsEveryEligibleFrame() {
        for count: UInt64 in 1...8 {
            #expect(CameraManager.detectionSlotIsDue(eligibleFrameCount: count, interval: 1))
        }
    }

    @Test func degenerateIntervalStillRuns() {
        // Interval clamps to ≥ 1, so even a nonsense configured value can
        // never starve detection.
        for count: UInt64 in 1...5 {
            #expect(CameraManager.detectionSlotIsDue(eligibleFrameCount: count, interval: 0))
        }
    }
}

/// Crop-size stability: the program-crop rectangle must not change SHAPE when
/// the tracked subject is still (Vision bbox height jitters a few percent even
/// for a motionless speaker), while position keeps following and real
/// approach/retreat still reframes. Also locks the operator-set hold duration
/// and the Wide preset's capped-crop semantics.
@MainActor
struct CropStabilityTests {

    private func person(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> PersonDetector.DetectedPerson {
        PersonDetector.DetectedPerson(
            id: UUID(),
            boundingBox: CGRect(x: x, y: y, width: w, height: h),
            confidence: 0.9,
            timestamp: 0,
            poseKeypoints: nil,
            faceBoundingBox: nil,
            faceLandmarkRatios: nil
        )
    }

    @Test func stationarySubjectKeepsStableCropSize() {
        let composer = ShotComposer()
        composer.config.shotPreset = .waistUp

        // First sighting establishes the emitted size (waistUp fraction 1.15).
        let first = composer.compose(person: person(x: 0.40, y: 0.30, w: 0.20, h: 0.40))
        let firstSize = try! #require(first?.size)
        #expect(abs(firstSize.height - 0.46) < 0.001)

        // Same subject, Vision noise wobbles bbox height by ~2.4% (<5%
        // hysteresis): the crop SIZE must not change…
        let jittered = composer.compose(person: person(x: 0.40, y: 0.295, w: 0.20, h: 0.41))
        let jitteredSize = try! #require(jittered?.size)
        #expect(jitteredSize.height == firstSize.height,
                "sub-hysteresis bbox jitter must not reshape the crop")

        // …but the crop POSITION must still track the subject.
        #expect(jittered!.origin.x > first!.origin.x - 0.001)  // same center → same clamp
    }

    @Test func positionStillTracksWhileSizeIsFrozen() {
        let composer = ShotComposer()
        composer.config.shotPreset = .waistUp

        _ = composer.compose(person: person(x: 0.40, y: 0.30, w: 0.20, h: 0.40))
        let moved = composer.compose(person: person(x: 0.47, y: 0.30, w: 0.20, h: 0.41))

        let movedCenterX = moved!.origin.x + moved!.size.width / 2
        #expect(abs(movedCenterX - 0.57) < 0.02,
                "crop center follows the subject even while size is hysteresis-frozen")
    }

    @Test func realApproachReframesPastHysteresisBand() {
        let composer = ShotComposer()
        composer.config.shotPreset = .waistUp

        let firstSize = try! #require(composer.compose(person: person(x: 0.40, y: 0.30, w: 0.20, h: 0.40))?.size)
        // Subject walks toward the camera: +25% bbox height — far outside the
        // 5% band, so the crop must reframe.
        let grown = composer.compose(person: person(x: 0.38, y: 0.22, w: 0.24, h: 0.50))
        let grownSize = try! #require(grown?.size)
        #expect(grownSize.height > firstSize.height + 0.05,
                "a genuine approach must enlarge the crop despite hysteresis")
    }

    @Test func widePresetIsACappedCropNotTheFullPicture() {
        let composer = ShotComposer()
        composer.config.shotPreset = .wide

        // A small/distant subject would frame-fit to the full frame without
        // the cap; the Wide preset must stop at 85%.
        let crop = try! #require(composer.compose(person: person(x: 0.45, y: 0.10, w: 0.10, h: 0.30)))
        #expect(crop.size.height <= 0.8501,
                "Wide stays a visible crop; Return to Wide is the uncropped view")
        #expect(crop.size.height >= 0.70 - 0.001, "…and still respects its floor")
    }

    @Test func holdDurationIsOperatorSetTenSeconds() {
        #expect(ShotComposer.holdDuration == 10.0)
    }

    // MARK: Close-range presets keep travel to follow

    @Test func closeRangeWaistUpStaysCappedAndFollowable() {
        let composer = ShotComposer()
        composer.config.shotPreset = .waistUp

        // 5 ft from the camera: bbox ~70% of frame. Subject-relative framing
        // wants 0.7 × 1.15 ≈ 0.805+; the cap must stop it at 0.80 so the crop
        // keeps horizontal travel and can still FOLLOW.
        let crop = try! #require(composer.compose(person: person(x: 0.35, y: 0.10, w: 0.30, h: 0.70)))
        #expect(crop.size.height <= 0.8001, "Waist Up caps at 0.80 even when the subject fills the sensor")
        #expect(crop.size.width < 1.0, "travel must remain — a full-width crop cannot follow")
    }

    @Test func closeRangeFullBodyStaysCappedAndFollowable() {
        let composer = ShotComposer()
        composer.config.shotPreset = .fullBody

        // bbox 50% × 3.0 → wants 1.5 → frame-fit would give the FULL frame;
        // cap at 0.95 so some travel survives.
        let crop = try! #require(composer.compose(person: person(x: 0.30, y: 0.05, w: 0.25, h: 0.50)))
        #expect(crop.size.height <= 0.9501)
        #expect(crop.size.width < 1.0)
    }

    // MARK: Vertical head-bob damping (tight shots)

    @Test func tightShotDampsVerticalHeadBob() {
        let composer = ShotComposer()
        composer.config.shotPreset = .waistUp

        let first = try! #require(composer.compose(person: person(x: 0.40, y: 0.20, w: 0.20, h: 0.40)))
        // Head bobs up by 3% of frame (a natural speaking motion).
        let bobbedRawY = first.origin.y - 0.03 * 1.15  // anchor moves with desired height
        _ = bobbedRawY
        let second = try! #require(composer.compose(person: person(x: 0.40, y: 0.17, w: 0.20, h: 0.40)))

        // The emitted anchor must move PART of the raw delta (damped), not
        // none (still responsive) and not all (jumpy).
        let rawDelta = abs((first.origin.y) - (second.origin.y))
        #expect(rawDelta > 0.001, "anchor must still move toward the subject")
        #expect(rawDelta < 0.03 * 1.15, "…but by less than the full bob (low-pass engaged)")
    }
}

/// Contract for the throttled gallery refresh (ShotComposer E-change):
/// `shouldRunGalleryRefreshScan()` must grant at most one face-including
/// detection plan per capture-spacing window, only while a lock is in
/// `.tracking`, and never while a signature capture is in flight. This is what
/// keeps the post-lock gallery fresh without turning the dropped per-frame
/// face request back into a per-frame inference.
@MainActor
struct GalleryRefreshCadenceTests {

    @Test func grantsOnceThenThrottlesWithinSpacingWindow() {
        let composer = ShotComposer()

        // Inactive: no lock, no refresh scans.
        #expect(composer.shouldRunGalleryRefreshScan() == false)

        // Operator selects a subject → .acquiring: still no refresh scans
        // (acquisition already runs the face request via its own plan).
        composer.lockTarget(UUID())
        #expect(composer.shouldRunGalleryRefreshScan() == false)

        // Promote to .tracking the same way tick() does when the gallery
        // reaches readyThreshold.
        composer.forceTrackingForTesting()
        #expect(composer.shouldRunGalleryRefreshScan() == true,
                "first tracking frame should upgrade the plan so the gallery can refresh")

        // Immediately after granting, the throttle must shut the door — even
        // though no capture has landed yet (face not visible). Without this,
        // a turned-away subject would get a face inference every frame.
        #expect(composer.shouldRunGalleryRefreshScan() == false)
    }

    @Test func stopsGrantingAfterLockReleased() {
        let composer = ShotComposer()
        composer.lockTarget(UUID())
        composer.forceTrackingForTesting()
        #expect(composer.shouldRunGalleryRefreshScan() == true)

        // Lock released (Return to Wide / unlock): no more refresh scans.
        composer.clearManualLock()
        #expect(composer.shouldRunGalleryRefreshScan() == false)
    }
}
