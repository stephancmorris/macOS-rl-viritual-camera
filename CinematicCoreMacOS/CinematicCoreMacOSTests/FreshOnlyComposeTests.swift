//
//  FreshOnlyComposeTests.swift
//  CinematicCoreMacOSTests
//
//  D-02 path 2 gate. Today the frame path calls the composer on every frame:
//  on a fresh detection, and again on each repeat frame with `isFresh: false`.
//  Path 2 calls it only when a detection arrives. These tests drive the same
//  subject motion both ways through the real composer and the real spring and
//  compare the crop on every frame. The picture must be the same.
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

nonisolated enum FreshOnlyMotion: String, CaseIterable, Sendable {
    case still, jitter, walk, sway, stopAndGo, leavesFrame

    /// Subject box centre x at time `t`; nil when the detector finds nobody.
    func centreX(at t: Double) -> CGFloat? {
        switch self {
        case .still: return 0.5
        case .jitter: return 0.5 + 0.004 * CGFloat(sin(40 * t))
        case .walk: return 0.2 + 0.1 * CGFloat(t)
        case .sway: return 0.5 + 0.3 * CGFloat(sin(2 * Double.pi * t / 3))
        case .stopAndGo: return t < 2 ? 0.3 : (t < 4 ? 0.3 + 0.15 * CGFloat(t - 2) : 0.6)
        case .leavesFrame: return t < 3 ? 0.4 + 0.05 * CGFloat(t) : nil
        }
    }
}

@MainActor
struct FreshOnlyComposeTests {
    /// The crop on every frame of a six-second take.
    private func picture(freshOnly: Bool, preset: ShotComposer.Config.ShotPreset, motion: FreshOnlyMotion,
                         fps: Double, detectionInterval: Int,
                         changePresetAtFrame: Int? = nil, composeOnCommand: Bool = false) throws -> [CropEngine.CropRect] {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = preset
        let engine = try #require(CropEngine())
        let floor = CropEngine.QualityFloor.forSource(height: 2160)
        engine.qualityFloor = floor
        composer.qualityFloorHeightFraction = floor.minCropHeightFraction
        let id = UUID()
        composer.lockTarget(id)

        var latest: PersonDetector.DetectedPerson?
        var latestTime = 0.0
        var lastTrackingCrop: CropEngine.CropRect?
        var crops: [CropEngine.CropRect] = []
        for frame in 0..<Int(fps * 6) {
            let now = 100 + Double(frame) / fps
            let fresh = frame % detectionInterval == 0
            // Path 2 as specified composes on fresh detections only. The variant
            // also composes on the frame a framing command lands.
            let composes = fresh || !freshOnly || (composeOnCommand && frame == changePresetAtFrame)
            if frame == changePresetAtFrame {
                // An operator preset change, as the command path applies it.
                composer.config.shotPreset = preset == .waistUp ? .fullBody : .waistUp
                composer.reapplyFraming()
            }
            if fresh {
                latestTime = now
                latest = motion.centreX(at: now - 100).map {
                    PersonDetector.DetectedPerson(id: id, boundingBox: CGRect(x: $0 - 0.06, y: 0.15, width: 0.12, height: 0.5),
                                                  confidence: 0.95, timestamp: now, poseKeypoints: nil,
                                                  faceBoundingBox: nil, faceLandmarkRatios: nil)
                }
            }
            // The tracking branch of CameraManager.processFrame.
            engine.applyFrameSmoothing(composer.config.smoothingFactor, operatorSetting: composer.config.smoothingFactor)
            if let latest {
                if composes,
                   let crop = composer.compose(person: latest, isFresh: fresh, observationTimestamp: latestTime) {
                    lastTrackingCrop = crop
                    engine.setTargetCrop(crop)
                }
            } else if composes, let lastTrackingCrop {
                engine.setTargetCrop(lastTrackingCrop)
            }
            crops.append(engine.tickInterpolation(now: now).crop)
        }
        return crops
    }

    private func largestDifference(_ a: [CropEngine.CropRect], _ b: [CropEngine.CropRect]) -> (value: CGFloat, frame: Int) {
        var worst: (CGFloat, Int) = (0, -1)
        for (index, pair) in zip(a, b).enumerated() {
            let d = max(abs(pair.0.origin.x - pair.1.origin.x), abs(pair.0.origin.y - pair.1.origin.y),
                        abs(pair.0.size.width - pair.1.size.width), abs(pair.0.size.height - pair.1.size.height))
            if d > worst.0 { worst = (d, index) }
        }
        return worst
    }

    @Test(arguments: [ShotComposer.Config.ShotPreset.fullBody, .waistUp], FreshOnlyMotion.allCases)
    func composingOnFreshDetectionsOnlyGivesTheSamePictureAt50(preset: ShotComposer.Config.ShotPreset, motion: FreshOnlyMotion) throws {
        let today = try picture(freshOnly: false, preset: preset, motion: motion, fps: 50, detectionInterval: 2)
        let freshOnly = try picture(freshOnly: true, preset: preset, motion: motion, fps: 50, detectionInterval: 2)
        #expect(today.count == freshOnly.count)
        let worst = largestDifference(today, freshOnly)
        #expect(worst.value < 1e-9, "largest crop difference \(worst.value) at frame \(worst.frame)")
        // Guard against a vacuous pass: the camera must actually move for moving subjects.
        if motion == .walk || motion == .sway {
            #expect(abs(today[0].origin.x - today[today.count - 1].origin.x) > 0.01 || motion == .sway)
        }
    }

    @Test(arguments: [25.0, 60.0], [1, 2, 3])
    func theSameHoldsAtOtherRatesAndDetectionIntervals(fps: Double, interval: Int) throws {
        for motion in [FreshOnlyMotion.walk, .stopAndGo, .jitter] {
            let today = try picture(freshOnly: false, preset: .waistUp, motion: motion, fps: fps, detectionInterval: interval)
            let freshOnly = try picture(freshOnly: true, preset: .waistUp, motion: motion, fps: fps, detectionInterval: interval)
            let worst = largestDifference(today, freshOnly)
            #expect(worst.value < 1e-9, "\(motion.rawValue): largest crop difference \(worst.value) at frame \(worst.frame)")
        }
    }

    /// A preset change is the one event that is not a detection. It lands on a
    /// repeat frame (151) here. Today the composer runs on that same frame;
    /// composing on fresh detections only applies it at the next detection.
    /// This records how far apart the two pictures get, and for how long.
    @Test func aPresetChangeOnARepeatFrameIsAppliedAtTheNextDetection() throws {
        let today = try picture(freshOnly: false, preset: .waistUp, motion: .still, fps: 50, detectionInterval: 2, changePresetAtFrame: 151)
        let freshOnly = try picture(freshOnly: true, preset: .waistUp, motion: .still, fps: 50, detectionInterval: 2, changePresetAtFrame: 151)
        let differing = zip(today, freshOnly).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        let worst = largestDifference(today, freshOnly)
        print("FRESH-ONLY-GATE preset change: differing frames=\(differing.count) first=\(differing.first ?? -1) last=\(differing.last ?? -1) largest=\(worst.value) at=\(worst.frame)")
        // The difference is real, starts on the frame after the command, and is small.
        #expect(differing.first == 152)
        #expect(worst.value > 0 && worst.value < 0.03)
        // Both land on the same shot.
        let end = largestDifference([today[today.count - 1]], [freshOnly[freshOnly.count - 1]])
        #expect(end.value < 1e-6)
        // The preset change must have moved the picture at all.
        #expect(today[150] != today[today.count - 1])
    }

    /// Composing on the command frame as well as on fresh detections removes
    /// that difference without touching the composer.
    @Test func composingOnTheCommandFrameAsWellGivesTheSamePicture() throws {
        let today = try picture(freshOnly: false, preset: .waistUp, motion: .still, fps: 50, detectionInterval: 2, changePresetAtFrame: 151)
        let variant = try picture(freshOnly: true, preset: .waistUp, motion: .still, fps: 50, detectionInterval: 2,
                                  changePresetAtFrame: 151, composeOnCommand: true)
        let worst = largestDifference(today, variant)
        #expect(worst.value < 1e-9, "largest crop difference \(worst.value) at frame \(worst.frame)")
    }
}
