//
//  FramingRegressionTests.swift
//  CinematicCoreMacOSTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

/// Regression coverage for operator-visible framing semantics and validation
/// clip timing. These tests deliberately use geometry rather than labels from
/// the legacy `ShotFraming` setting: the stage/webcam presets are what the
/// operator selects and what the program crop represents.
@MainActor
struct FramingRegressionTests {
    private func person(height: CGFloat = 0.70) -> PersonDetector.DetectedPerson {
        PersonDetector.DetectedPerson(
            id: UUID(),
            boundingBox: CGRect(x: 0.40, y: 0.10, width: 0.20, height: height),
            confidence: 0.95,
            timestamp: 0,
            poseKeypoints: nil,
            faceBoundingBox: nil,
            faceLandmarkRatios: nil
        )
    }

    private func cropHeight(
        preset: ShotComposer.Config.ShotPreset,
        profile: ShotComposer.Config.FrameProfile,
        subject: PersonDetector.DetectedPerson
    ) throws -> CGFloat {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.frameProfile = profile
        composer.config.shotPreset = preset
        return try #require(composer.compose(person: subject)?.size.height)
    }

    @Test func stagePresetNamesDescribeTheActiveFormat() {
        var config = ShotComposer.Config()
        config.cinematicFormat = .stage
        config.shotPreset = .waistUp
        #expect(config.activeFramingTitle == "Waist Up")

        config.cinematicFormat = .webcam
        config.webcamPreset = .tight
        #expect(config.activeFramingTitle == "Tight")
    }

    @Test func tallStageSubjectNeverReversesPresetOrderAcrossProfiles() throws {
        // A close/tall subject exercises the maximum-crop caps where the
        // previous regression made Full Body wider than Wide. Equality is
        // permitted when a physical crop cap is reached; inversion is not.
        let subject = person()
        for profile in ShotComposer.Config.FrameProfile.allCases {
            let wide = try cropHeight(preset: .wide, profile: profile, subject: subject)
            let fullBody = try cropHeight(preset: .fullBody, profile: profile, subject: subject)
            let waistUp = try cropHeight(preset: .waistUp, profile: profile, subject: subject)

            #expect(wide + 0.0001 >= fullBody,
                    "Wide must not crop tighter than Full Body for \(profile)")
            #expect(fullBody + 0.0001 >= waistUp,
                    "Full Body must not crop tighter than Waist Up for \(profile)")
        }
    }

    @Test func steadyFollowBandScalesToTheVisibleProgramCrop() throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let subject = person(height: 0.40)

        // The first observation applies the initial framing; the next twelve
        // distinct observations settle the Steady Follow state and establish
        // the displayed band. The band is an operator-facing amount
        // of movement inside the *program* view, so it must shrink with a
        // tighter crop instead of remaining a fixed fraction of the source.
        var crop: CropEngine.CropRect?
        for frame in 0..<14 {
            crop = composer.compose(
                person: subject,
                isFresh: true,
                observationTimestamp: Double(frame) / 50.0
            )
        }

        let settledCrop = try #require(crop)
        let band = try #require(composer.steadyBand)
        let maximumViewportRelativeWidth = settledCrop.size.width * composer.config.steadyBandWidth
        #expect(
            band.width <= maximumViewportRelativeWidth + 0.0001,
            "the source-space band must not consume more than its configured share of the program crop"
        )
    }

    @Test(arguments: [25.0, 50.0, 60.0])
    func steadyFollowSettlesByCaptureTimeAtEverySupportedRate(fps: Double) throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let subject = person(height: 0.40)

        // The first observation applies the initial crop. Measure from the
        // first actual settle observation so rates can differ only by their
        // sampling granularity, not by the number of compositor invocations.
        _ = composer.compose(person: subject, isFresh: true, observationTimestamp: 0)
        let firstSettleObservation = 1.0 / fps
        var settledAt: Double?
        for frame in 1...Int(fps) {
            let timestamp = Double(frame) / fps
            _ = composer.compose(
                person: subject,
                isFresh: true,
                observationTimestamp: timestamp
            )
            if composer.steadyBand != nil {
                settledAt = timestamp
                break
            }
        }

        let time = try #require(settledAt)
        let elapsed = time - firstSettleObservation
        // The intended settle period is 12/50 s. A sampled detector may cross
        // it up to one observation later, but must not become a rate-dependent
        // 12-frame wait (0.48 s at 25 fps or 0.20 s at 60 fps).
        #expect(elapsed >= 0.24 - 0.0001)
        #expect(elapsed <= 0.24 + (1.0 / fps) + 0.0001)
    }

    @Test(arguments: [25.0, 50.0, 60.0])
    func bandExitRequiresFreshElapsedEvidence(fps: Double) throws {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        let still = person(height: 0.40)
        for frame in 0...Int(fps) {
            _ = composer.compose(person: still, observationTimestamp: Double(frame) / fps)
        }
        #expect(composer.steadyBand != nil)
        let moving = PersonDetector.DetectedPerson(
            id: still.id, boundingBox: still.boundingBox.offsetBy(dx: 0.10, dy: 0),
            confidence: still.confidence, timestamp: still.timestamp, poseKeypoints: nil,
            faceBoundingBox: nil, faceLandmarkRatios: nil)
        let start = 1.0 + 1.0 / fps
        _ = composer.compose(person: moving, observationTimestamp: start)
        // Re-displaying one observation must never confirm an exit.
        for _ in 0..<10 {
            _ = composer.compose(person: moving, isFresh: false, observationTimestamp: start)
        }
        #expect(composer.steadyBand != nil)
        var releasedAt: Double?
        for frame in 1...Int(fps) {
            let time = start + Double(frame) / fps
            _ = composer.compose(person: moving, observationTimestamp: time)
            if composer.steadyBand == nil { releasedAt = time; break }
        }
        let elapsed = try #require(releasedAt) - start
        #expect(elapsed >= 0.04 - 0.0001)
        #expect(elapsed <= 0.04 + 1.0 / fps + 0.0001)
    }

    @Test func validationPlaybackUsesAbsolutePresentationTime() {
        let start = 100.0
        #expect(CameraManager.playbackDelay(
            sourceTimestamp: 42.0, firstTimestamp: 42.0, playbackStart: start, now: start
        ) == 0)

        // 400 ms of source time must be scheduled from the original playback
        // epoch. Accounting for 100 ms spent processing prior frames leaves
        // exactly 300 ms, rather than a new 400 ms delay from "now".
        #expect(abs(CameraManager.playbackDelay(
            sourceTimestamp: 42.4, firstTimestamp: 42.0, playbackStart: start, now: 100.1
        ) - 0.3) < 0.000_001)

        // Slow processing never adds a compensating sleep, and malformed
        // non-monotonic timestamps cannot schedule a frame before playback.
        #expect(CameraManager.playbackDelay(
            sourceTimestamp: 42.4, firstTimestamp: 42.0, playbackStart: start, now: 100.8
        ) == 0)
        #expect(CameraManager.playbackDelay(
            sourceTimestamp: 41.9, firstTimestamp: 42.0, playbackStart: start, now: start
        ) == 0)
    }
}
