//
//  WorldModelTests.swift
//  CinematicCoreMacOSTests
//
//  C-01 path 1: the world-model table and its lookups. The table is filled
//  by hand here; the lookups must answer a person, nobody, or unknown with a
//  reason, and must never guess from a partial or old view.
//

import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
struct WorldModelTests {
    private let now: TimeInterval = 1000
    private let maximumAge: TimeInterval = 0.5
    private let lockRegion = CGRect(x: 0.42, y: 0, width: 0.26, height: 0.9)

    private func sighting(_ id: UUID = UUID(), x: CGFloat) -> WorldModel.Sighting {
        .init(track: id, box: CGRect(x: x - 0.05, y: 0.2, width: 0.10, height: 0.5), confidence: 0.9)
    }

    private func reading(_ channel: ChannelID, generation: UInt64 = 7, running: Bool = true, missing: Bool = false,
                         coverage: WorldModel.Coverage? = nil, age: TimeInterval = 0.04,
                         observationGeneration: UInt64? = nil,
                         sightings: [WorldModel.Sighting] = [], locked: UUID? = nil) -> WorldModel.Reading {
        .init(channel: channel, sourceGeneration: generation, isRunning: running, sourceMissing: missing,
              lockPhase: locked == nil ? .inactive : .tracking, lockedTrack: locked,
              crop: CGRect(x: 0, y: 0, width: 1, height: 1), minimumCropHeight: 0.25,
              observation: coverage.map {
                  .init(sourceGeneration: observationGeneration ?? generation, coverage: $0,
                        observedAt: now - age, sightings: sightings)
              })
    }

    private func table(_ readings: WorldModel.Reading...) -> WorldModel {
        var world = WorldModel()
        for reading in readings { world.record(reading, role: reading.channel == .a ? .program : .other) }
        return world
    }

    private func camera3() throws -> ChannelID { try #require(ChannelID(cameraNumber: 3)) }

    // MARK: The ten lookup cases

    @Test func cameraNumbersMapToSlots() {
        #expect(ChannelID(cameraNumber: 1) == .a)
        #expect(ChannelID(cameraNumber: 3) == .c)
        #expect(ChannelID(cameraNumber: 4) == .d)
        #expect(ChannelID(cameraNumber: 0) == nil)
        #expect(ChannelID(cameraNumber: 5) == nil)
    }

    @Test func lockedCameraOnlyKnowsItsRegion() throws {
        let lock = UUID()
        let world = table(reading(.c, coverage: .region(lockRegion), sightings: [sighting(lock, x: 0.55)], locked: lock))
        #expect(world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) == .unknown(.partialView(lockRegion)))
    }

    @Test func passiveCameraIsNotObserved() throws {
        let world = table(reading(.c))
        #expect(world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) == .unknown(.notObserved))
    }

    @Test func fullFrameScanAnswersTheLeftmostPersonOnCamera3() throws {
        let left = UUID(), lock = UUID()
        let world = table(reading(.c, coverage: .fullFrame,
                                  sightings: [sighting(lock, x: 0.55), sighting(x: 0.80), sighting(left, x: 0.20)], locked: lock))
        guard case .person(let channel, let person) = world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) else {
            Issue.record("expected a person"); return
        }
        #expect(channel == .c)
        #expect(person.track == left)
        #expect(!person.isLockSubject)
        #expect(world.camera(.c)?.people.first { $0.track == lock }?.isLockSubject == true)
    }

    @Test func rightmostUsesTheSameRules() throws {
        let right = UUID()
        let world = table(reading(.c, coverage: .fullFrame, sightings: [sighting(x: 0.20), sighting(right, x: 0.80)]))
        guard case .person(_, let person) = world.rightmost(on: try camera3(), now: now, maximumAge: maximumAge) else {
            Issue.record("expected a person"); return
        }
        #expect(person.track == right)
    }

    @Test func oldScanIsStale() throws {
        let world = table(reading(.c, coverage: .fullFrame, age: 0.9, sightings: [sighting(x: 0.2)]))
        guard case .unknown(.stale(let age)) = world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) else {
            Issue.record("expected stale"); return
        }
        #expect(abs(age - 0.9) < 0.001)
    }

    @Test func twoPeopleInsideTheTieMarginAreAmbiguous() throws {
        let first = UUID(), second = UUID()
        let world = table(reading(.c, coverage: .fullFrame, sightings: [sighting(second, x: 0.212), sighting(first, x: 0.200)]))
        #expect(world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) == .unknown(.ambiguous([first, second])))
    }

    @Test func emptyStageIsNobody() throws {
        let world = table(reading(.c, coverage: .fullFrame))
        #expect(world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) == .nobody)
    }

    @Test func unpluggedSourceSaysSo() throws {
        let world = table(reading(.c, missing: true, coverage: .fullFrame, sightings: [sighting(x: 0.2)]))
        #expect(world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) == .unknown(.sourceMissing))
        #expect(world.camera(.c)?.people.isEmpty == true)
    }

    @Test func unassignedSlotIsNotAssigned() throws {
        let world = table(reading(.a, coverage: .fullFrame, sightings: [sighting(x: 0.2)]))
        #expect(world.leftmost(on: try #require(ChannelID(cameraNumber: 4)), now: now, maximumAge: maximumAge) == .unknown(.notAssigned))
    }

    @Test func anotherCamerasFullViewDoesNotAnswerForCamera3() throws {
        let world = table(reading(.a, coverage: .fullFrame, sightings: [sighting(x: 0.2)]), reading(.c))
        #expect(world.leftmost(on: try camera3(), now: now, maximumAge: maximumAge) == .unknown(.notObserved))
    }

    // MARK: Writing

    @Test func aPersonKeepsFirstSeenAcrossScansOfTheSameSource() {
        let id = UUID()
        var world = table(reading(.b, coverage: .fullFrame, age: 2.0, sightings: [sighting(id, x: 0.3)]))
        world.record(reading(.b, coverage: .fullFrame, age: 0.1, sightings: [sighting(id, x: 0.4), sighting(x: 0.7)]), role: .preview)
        let people = world.camera(.b)?.people ?? []
        #expect(people.count == 2)
        #expect(people.first { $0.track == id }?.firstSeen == now - 2.0)
        #expect(people.first { $0.track == id }?.lastSeen == now - 0.1)
        #expect(people.first { $0.track != id }?.firstSeen == now - 0.1)
        #expect(world.camera(.b)?.role == .preview)
    }

    @Test func aNewSourceGenerationStartsAgain() {
        let id = UUID()
        var world = table(reading(.b, generation: 7, coverage: .fullFrame, age: 2.0, sightings: [sighting(id, x: 0.3)]))
        world.record(reading(.b, generation: 8, coverage: .fullFrame, age: 0.1, sightings: [sighting(id, x: 0.3)]), role: .preview)
        #expect(world.camera(.b)?.people.first?.firstSeen == now - 0.1)
        // A scan left over from the old source is never shown under the new one.
        world.record(reading(.b, generation: 9, coverage: .fullFrame, observationGeneration: 8, sightings: [sighting(id, x: 0.3)]), role: .preview)
        #expect(world.camera(.b)?.coverage == WorldModel.Coverage.none)
        #expect(world.camera(.b)?.people.isEmpty == true)
    }

    @Test func aStoppedCameraIsNotObservedAndRemovingASlotUnassignsIt() {
        var world = table(reading(.b, running: false, coverage: .fullFrame, sightings: [sighting(x: 0.3)]))
        #expect(world.leftmost(on: .b, now: now, maximumAge: maximumAge) == .unknown(.notObserved))
        world.remove(.b)
        #expect(world.leftmost(on: .b, now: now, maximumAge: maximumAge) == .unknown(.notAssigned))
    }

    @Test func zoomHeadroomFollowsTheQualityFloor() {
        let world = table(reading(.a))
        #expect(world.camera(.a)?.zoomHeadroom == 4)
        var unconstrained = WorldModel()
        unconstrained.record(.init(channel: .a, sourceGeneration: 1, isRunning: true, sourceMissing: false, lockPhase: .inactive,
                                   lockedTrack: nil, crop: CGRect(x: 0, y: 0, width: 1, height: 1), minimumCropHeight: 0,
                                   observation: nil), role: .program)
        #expect(unconstrained.camera(.a)?.zoomHeadroom == nil)
    }

    @Test func coverageFollowsTheDetectionPlan() {
        let roi = CGRect(x: 0.4, y: 0.1, width: 0.3, height: 0.6)
        #expect(WorldModel.Coverage.scanned(mode: .off, roi: nil) == WorldModel.Coverage.none)
        #expect(WorldModel.Coverage.scanned(mode: .awaitingTap, roi: roi) == WorldModel.Coverage.none)
        #expect(WorldModel.Coverage.scanned(mode: .lockedROI, roi: roi) == .region(roi))
        #expect(WorldModel.Coverage.scanned(mode: .acquiring, roi: roi) == .region(roi))
        #expect(WorldModel.Coverage.scanned(mode: .acquiring, roi: nil) == .fullFrame)
        #expect(WorldModel.Coverage.scanned(mode: .reacquiring, roi: roi) == .fullFrame)
        guard case .region(let clipped) = WorldModel.Coverage.scanned(mode: .lockedROI, roi: CGRect(x: 0.8, y: 0, width: 0.5, height: 1)) else {
            Issue.record("expected a region"); return
        }
        #expect(abs(clipped.minX - 0.8) < 1e-9 && abs(clipped.maxX - 1) < 1e-9 && clipped.height == 1)
    }

    // MARK: Writers

    @Test func aDetectionFrameBecomesNumbersOnly() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let id = UUID()
        let box = CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.5)
        let person = PersonDetector.DetectedPerson(id: id, boundingBox: box, confidence: 0.8, timestamp: 5,
                                                   poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        let frame = DetectionFrame(observationID: 1, capturedAt: 12, sourceTimestamp: 3, pixelBuffer: try #require(buffer),
                                   persons: [person], queueWait: 0, detectionDuration: 0, coverage: .region(box))
        let observation = CameraManager.worldObservation(from: frame, sourceGeneration: 4)
        #expect(observation == .init(sourceGeneration: 4, coverage: .region(box), observedAt: 12,
                                     sightings: [.init(track: id, box: box, confidence: 0.8)]))
    }

    @Test func theShowSamplesEverySlotAndLeavesCAndDUnassigned() {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []))
        show.refreshWorldModel()
        #expect(show.worldModel.camera(.a)?.role == .program)
        #expect(show.worldModel.leftmost(on: .a, now: now, maximumAge: maximumAge) == .unknown(.notObserved))
        #expect(show.worldModel.leftmost(on: .c, now: now, maximumAge: maximumAge) == .unknown(.notAssigned))
        #expect(show.worldModel.leftmost(on: .d, now: now, maximumAge: maximumAge) == .unknown(.notAssigned))

        show.addChannel(.b)
        show.refreshWorldModel()
        #expect(show.worldModel.camera(.b)?.role == .preview)
        show.removeChannel(.b)
        show.refreshWorldModel()
        #expect(show.worldModel.camera(.b) == nil)
    }
}
