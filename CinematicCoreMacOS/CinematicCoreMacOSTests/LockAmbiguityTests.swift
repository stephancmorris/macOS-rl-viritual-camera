//
//  LockAmbiguityTests.swift
//  CinematicCoreMacOSTests
//
//  The detector's lock-ambiguity window: which events open it, that it
//  closes after a quiet second, and that ordinary tracking never opens it.
//

import Testing
import Foundation
import CoreGraphics
@preconcurrency import Vision
@testable import Alfie

@MainActor
struct LockAmbiguityTests {
    @MainActor private final class Rig {
        let detector = PersonDetector()
        var time = 1000.0
        func box(_ x: Double, width: Double = 0.07) -> CGRect {
            CGRect(x: x - width / 2, y: 0.25, width: width, height: 0.30)
        }
        func scan(_ boxes: [CGRect]) {
            time += 0.04
            detector.updateTracking(rectObservations: boxes.map { VNHumanObservation(boundingBox: $0) },
                poseObservations: [], faceObservations: [], timestamp: time)
        }
        /// Locks the first detected person after one shared scan.
        func lock(_ boxes: [CGRect]) throws -> UUID {
            scan(boxes)
            let id = try #require(detector.detectedPersons.first?.id)
            detector.lockedTargetID = id
            return id
        }
        var reasons: PersonDetector.LockAmbiguity { detector.lockAmbiguity(at: time).reasons }
    }

    @Test func continuousTrackingNeverOpens() throws {
        let rig = Rig()
        _ = try rig.lock([rig.box(0.30), rig.box(0.60)])
        for frame in 0..<60 {
            let jitter = frame.isMultiple(of: 2) ? 0.001 : -0.001
            rig.scan([rig.box(0.30 + jitter), rig.box(0.60)])
            #expect(!rig.detector.lockAmbiguityOpen)
        }
    }

    @Test func overlapOpensAndQuietCloses() throws {
        let rig = Rig()
        _ = try rig.lock([rig.box(0.30), rig.box(0.60)])
        rig.scan([rig.box(0.30), rig.box(0.60)])
        #expect(!rig.detector.lockAmbiguityOpen)
        // IoU about 0.17 with the lock's box.
        rig.scan([rig.box(0.30), rig.box(0.35)])
        #expect(rig.detector.lockAmbiguityOpen)
        #expect(rig.reasons.contains(.overlap))
        let opened = rig.time
        while rig.time - opened < PersonDetector.lockAmbiguityQuietDuration - 0.05 {
            rig.scan([rig.box(0.30), rig.box(0.60)])
            #expect(rig.detector.lockAmbiguityOpen)
        }
        rig.scan([rig.box(0.30), rig.box(0.60)])
        rig.scan([rig.box(0.30), rig.box(0.60)])
        #expect(!rig.detector.lockAmbiguityOpen)
    }

    @Test func coastRebindOpensOnlyWithSomeoneNearby() throws {
        let alone = Rig()
        _ = try alone.lock([alone.box(0.30)])
        alone.scan([alone.box(0.30)])
        alone.scan([])
        alone.scan([alone.box(0.30)])
        #expect(!alone.detector.lockAmbiguityOpen)

        let crowded = Rig()
        _ = try crowded.lock([crowded.box(0.30), crowded.box(0.50)])
        crowded.scan([crowded.box(0.30), crowded.box(0.50)])
        crowded.scan([crowded.box(0.50)])
        #expect(!crowded.detector.lockAmbiguityOpen)
        crowded.scan([crowded.box(0.30), crowded.box(0.50)])
        #expect(crowded.detector.lockAmbiguityOpen)
        #expect(crowded.reasons == .coastRebind)
    }

    @Test func probationAcceptOpens() throws {
        let rig = Rig()
        let lock = try rig.lock([rig.box(0.30)])
        rig.scan([rig.box(0.30)])
        // A 0.04 shift leaves IoU about 0.27: not the same object at once.
        for _ in 0..<6 {
            rig.scan([rig.box(0.34)])
            if rig.detector.detectedPersons.first?.id == lock, rig.detector.lockAmbiguityOpen { break }
        }
        #expect(rig.detector.detectedPersons.first?.id == lock)
        #expect(rig.reasons.contains(.probationAccept))
    }

    @Test func unionBoxOpensAsMerge() throws {
        let rig = Rig()
        let lock = try rig.lock([rig.box(0.30), rig.box(0.38)])
        rig.scan([rig.box(0.30), rig.box(0.38)])
        rig.detector.lockedTargetID = lock
        // One box covering both people: about 2.1x the lock's area.
        rig.scan([CGRect(x: 0.265, y: 0.25, width: 0.15, height: 0.30)])
        #expect(rig.detector.detectedPersons.first?.id == lock)
        #expect(rig.reasons.contains(.merge))
    }

    @Test func newLockResetsTheWindow() throws {
        let rig = Rig()
        _ = try rig.lock([rig.box(0.30), rig.box(0.60)])
        rig.scan([rig.box(0.30), rig.box(0.35)])
        #expect(rig.detector.lockAmbiguityOpen)
        rig.detector.lockedTargetID = UUID()
        #expect(!rig.detector.lockAmbiguityOpen)
    }
}
