//
//  WorldModelCensusTests.swift
//  CinematicCoreMacOSTests
//
//  C-01 path 2: the census. A full-frame box scan answers "the leftmost
//  person on camera 3" without touching the lock, never scans Program, and
//  never runs in the background unless a rate is passed in.
//

import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
struct WorldModelCensusTests {
    private let now: TimeInterval = 1000
    private let maximumAge: TimeInterval = 0.5

    private func box(x: CGFloat) -> CGRect { CGRect(x: x - 0.05, y: 0.2, width: 0.10, height: 0.5) }
    private func censusBox(x: CGFloat, confidence: Float = 0.9) -> PersonDetector.CensusBox {
        .init(box: box(x: x), confidence: confidence)
    }
    private func buffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }
    private func settle() async { for _ in 0..<10 { await Task.yield() } }

    /// Camera 3 with a lock: only the lock's padded box is scanned.
    private func lockedCamera3(lock: UUID) -> WorldModel.Reading {
        .init(channel: .c, sourceGeneration: 7, isRunning: true, sourceMissing: false, lockPhase: .tracking,
              lockedTrack: lock, crop: CGRect(x: 0, y: 0, width: 1, height: 1), minimumCropHeight: 0.25,
              observation: .init(sourceGeneration: 7, coverage: .region(CGRect(x: 0.42, y: 0, width: 0.26, height: 0.9)),
                                 observedAt: now - 0.03, sightings: [.init(track: lock, box: box(x: 0.55), confidence: 0.9)]))
    }

    // MARK: The table

    @Test func oneCensusAnswersTheLeftmostPersonOnCamera3() throws {
        let lock = UUID()
        var world = WorldModel()
        world.record(lockedCamera3(lock: lock), role: .other)
        let camera3 = try #require(ChannelID(cameraNumber: 3))
        guard case .unknown(.partialView) = world.leftmost(on: camera3, now: now, maximumAge: maximumAge) else {
            Issue.record("a locked camera should only know its region"); return
        }
        let ownRowsBefore = world.camera(.c)?.people

        let stored = world.recordCensus([censusBox(x: 0.55), censusBox(x: 0.80), censusBox(x: 0.20)],
                                        on: .c, sourceGeneration: 7, observedAt: now - 0.02)
        #expect(stored)
        guard case .person(let channel, let person) = world.leftmost(on: camera3, now: now, maximumAge: maximumAge) else {
            Issue.record("expected a person after the census"); return
        }
        #expect(channel == .c)
        #expect(abs(person.box.midX - 0.20) < 1e-9)
        #expect(!person.isLockSubject)
        // The box over the lock subject is recognised as the lock subject.
        let census = try #require(world.camera(.c)?.census)
        #expect(census.people.count == 3)
        #expect(census.people.first { $0.isLockSubject }?.track == lock)
        // The camera's own rows and coverage are exactly as they were.
        #expect(world.camera(.c)?.people == ownRowsBefore)
        #expect(world.camera(.c)?.coverage == .region(CGRect(x: 0.42, y: 0, width: 0.26, height: 0.9)))
    }

    @Test func aCensusIsNotCutToFivePeople() {
        var world = WorldModel()
        world.record(lockedCamera3(lock: UUID()), role: .other)
        world.recordCensus((0..<7).map { censusBox(x: 0.1 + 0.12 * CGFloat($0)) }, on: .c, sourceGeneration: 7, observedAt: now)
        #expect(world.camera(.c)?.census?.people.count == 7)
    }

    @Test func aCensusSurvivesTheNextSampleThenGoesStaleAndDiesWithItsSource() {
        let lock = UUID()
        var world = WorldModel()
        world.record(lockedCamera3(lock: lock), role: .other)
        world.recordCensus([censusBox(x: 0.2), censusBox(x: 0.55)], on: .c, sourceGeneration: 7, observedAt: now)
        // The console's next 15 Hz sample keeps it, and keeps the same people.
        let firstIDs = world.camera(.c)?.census?.people.map(\.track)
        world.record(lockedCamera3(lock: lock), role: .other)
        #expect(world.camera(.c)?.census?.people.map(\.track) == firstIDs)
        // A second census matches the same people by overlap and keeps first-seen.
        world.recordCensus([censusBox(x: 0.21), censusBox(x: 0.55)], on: .c, sourceGeneration: 7, observedAt: now + 0.4)
        #expect(Set(world.camera(.c)?.census?.people.map(\.track) ?? []) == Set(firstIDs ?? []))
        #expect(world.camera(.c)?.census?.people.allSatisfy { $0.firstSeen <= now } == true)
        // Too old to act on.
        guard case .unknown(.stale) = world.leftmost(on: .c, now: now + 2, maximumAge: maximumAge) else {
            Issue.record("expected stale"); return
        }
        // Wrong source generation is refused; a new generation drops the census.
        let wrongGeneration = world.recordCensus([censusBox(x: 0.2)], on: .c, sourceGeneration: 6, observedAt: now)
        #expect(!wrongGeneration)
        var next = lockedCamera3(lock: lock)
        next = .init(channel: .c, sourceGeneration: 8, isRunning: true, sourceMissing: false, lockPhase: .inactive, lockedTrack: nil,
                     crop: next.crop, minimumCropHeight: next.minimumCropHeight, observation: nil)
        world.record(next, role: .other)
        #expect(world.camera(.c)?.census == nil)
        let noRow = world.recordCensus([censusBox(x: 0.2)], on: .d, sourceGeneration: 1, observedAt: now)
        #expect(!noRow)
    }

    // MARK: The scheduler

    @Test func aCensusAndATrackingRequestFromOneCameraDoNotCancelEachOther() async {
        let scheduler = FrameWorkScheduler()
        let running = await scheduler.acquire(.perception, for: .a)!
        let census = Task { await scheduler.acquire(.perception, for: .b, kind: .census) }
        await settle()
        let tracking = Task { await scheduler.acquire(.perception, for: .b) }
        await settle()
        #expect(scheduler.isWaiting(.perception, for: .b, kind: .census))
        #expect(scheduler.isWaiting(.perception, for: .b, kind: .tracking))
        #expect(scheduler.stats[.b]?.superseded ?? 0 == 0)
        // Tracking is served first, then the census.
        scheduler.release(running)
        let first = await tracking.value
        #expect(first?.kind == .tracking)
        #expect(scheduler.isWaiting(.perception, for: .b, kind: .census))
        scheduler.release(first!)
        let second = await census.value
        #expect(second?.kind == .census && second?.channel == .b)
        scheduler.release(second!)
        #expect(scheduler.runningPermit(.perception) == nil)
    }

    @Test func sameKindRequestsStillSupersedeAndCancelsAreByKind() async {
        let scheduler = FrameWorkScheduler()
        let running = await scheduler.acquire(.perception, for: .a)!
        let older = Task { await scheduler.acquire(.perception, for: .b, kind: .census) }
        await settle()
        let newer = Task { await scheduler.acquire(.perception, for: .b, kind: .census) }
        await settle()
        #expect(await older.value == nil)
        #expect(scheduler.stats[.b]?.superseded == 1)
        // Cancelling the camera's tracking waiter (what discovery does) leaves the census.
        let tracking = Task { await scheduler.acquire(.perception, for: .b) }
        await settle()
        scheduler.cancelWaiting(.perception, for: .b)
        #expect(await tracking.value == nil)
        #expect(scheduler.isWaiting(.perception, for: .b, kind: .census))
        // Stopping the camera drops every kind.
        scheduler.cancelWaiting(for: .b)
        #expect(await newer.value == nil)
        #expect(scheduler.waitingChannels(.perception).isEmpty)
        scheduler.release(running)
    }

    // MARK: The detector

    @Test func aCensusLeavesTheLocksTrackerUnchanged() async throws {
        let detector = PersonDetector()
        let lockBox = box(x: 0.55)
        detector.trackForTesting([lockBox], timestamp: 1.00)
        let subject = try #require(detector.detectedPersons.first)
        detector.lockedTargetID = subject.id
        detector.trackForTesting([lockBox], timestamp: 1.04)
        let before = detector.detectedPersons.map { [$0.id.uuidString, "\($0.boundingBox)"] }
        let statsBefore = detector.stats.totalFramesProcessed

        // Seven people in the frame, one of them standing on the lock subject.
        let scene = (0..<6).map { censusBox(x: 0.08 + 0.07 * CGFloat($0)) } + [censusBox(x: 0.55)]
        detector.censusVisionForTesting = { scene }
        let boxes = await detector.census(try buffer())

        #expect(boxes.count == 7)                       // not cut to five
        #expect(detector.detectedPersons.map { [$0.id.uuidString, "\($0.boundingBox)"] } == before)
        #expect(detector.lockedTargetID == subject.id)
        #expect(detector.stats.totalFramesProcessed == statsBefore)
        // The next tracking run still binds the same subject.
        detector.trackForTesting([lockBox], timestamp: 1.08)
        #expect(detector.detectedPersons.map(\.id) == [subject.id])
    }

    // MARK: The show

    private func showWithRunningB(scene: [PersonDetector.CensusBox]) throws -> (ShowCoordinator, CameraManager) {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []))
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        b.censusFrameForTesting = try buffer()
        b.personDetector.censusVisionForTesting = { scene }
        return (show, b)
    }

    @Test func aLookupRequestsOneCensusAndTheNextLookupAnswers() async throws {
        let (show, _) = try showWithRunningB(scene: [censusBox(x: 0.7), censusBox(x: 0.2)])
        #expect(show.lookup(.left, on: .b, now: 100, maximumAge: maximumAge, mayRequestCensus: true) == .unknown(.notObserved))
        let task = try #require(show.censusInFlight[.b])
        // Asking again while it runs does not start a second one.
        _ = show.lookup(.left, on: .b, now: 100.01, maximumAge: maximumAge, mayRequestCensus: true)
        #expect(await task.value)
        #expect(show.censusInFlight[.b] == nil)
        #expect(show.censusStats.started == 1 && show.censusStats.recorded == 1)
        guard case .person(let channel, let person) = show.lookup(.left, on: .b, now: 100.1, maximumAge: maximumAge, mayRequestCensus: false) else {
            Issue.record("expected a person after the census"); return
        }
        #expect(channel == .b)
        #expect(abs(person.box.midX - 0.2) < 1e-9)
        #expect(show.workScheduler.runningPermit(.perception) == nil)
    }

    @Test func aLookupWithoutPermissionNeverScans() throws {
        let (show, _) = try showWithRunningB(scene: [censusBox(x: 0.2)])
        #expect(show.lookup(.left, on: .b, now: 100, maximumAge: maximumAge, mayRequestCensus: false) == .unknown(.notObserved))
        #expect(show.censusInFlight.isEmpty)
        #expect(show.censusStats.requested == 0)
    }

    @Test func programIsNeverScanned() throws {
        let (show, _) = try showWithRunningB(scene: [censusBox(x: 0.2)])
        let a = show.channelA
        a.setRunningForTesting(true)
        a.censusFrameForTesting = try buffer()
        a.personDetector.censusVisionForTesting = { [] }
        #expect(show.programChannel == .a)
        _ = show.lookup(.left, on: .a, now: 100, maximumAge: maximumAge, mayRequestCensus: true)
        guard case .refused(.program) = show.requestCensus(of: .a, now: 100) else {
            Issue.record("Program must be refused"); return
        }
        #expect(show.runBackgroundCensus(rate: 10, now: 100) == [.b])
        #expect(show.censusInFlight[.a] == nil)
        guard case .refused(.notAssigned) = show.requestCensus(of: .c, now: 100) else {
            Issue.record("an unassigned slot must be refused"); return
        }
    }

    @Test func noBackgroundScanRunsUnlessARateIsPassed() async throws {
        let (show, b) = try showWithRunningB(scene: [censusBox(x: 0.2)])
        // The console's refresh, many times over: nothing is scanned.
        for _ in 0..<60 { show.refreshWorldModel() }
        #expect(show.censusStats.requested == 0)
        #expect(show.runBackgroundCensus(rate: 0, now: 100).isEmpty)
        #expect(show.runBackgroundCensus(rate: .nan, now: 100).isEmpty)
        #expect(show.censusStats.requested == 0)

        // With a rate: two scans a second means one every half second.
        #expect(show.runBackgroundCensus(rate: 2, now: 100) == [.b])
        #expect(await show.censusInFlight[.b]?.value == true)
        #expect(show.runBackgroundCensus(rate: 2, now: 100.2).isEmpty)
        #expect(show.runBackgroundCensus(rate: 2, now: 100.6) == [.b])
        #expect(await show.censusInFlight[.b]?.value == true)

        // A locked camera is not scanned in the background.
        b.shotComposer.lockTarget(UUID())
        #expect(b.recoveryState.phase != .inactive)
        #expect(show.runBackgroundCensus(rate: 2, now: 102).isEmpty)
        // It can still be scanned on request; the lock is not involved.
        guard case .started(let task) = show.requestCensus(of: .b, now: 102) else {
            Issue.record("a locked camera can be scanned on request"); return
        }
        #expect(await task.value)
    }

    @Test func aWaitingCensusIsDroppedWhenItsCameraStops() async throws {
        let (show, b) = try showWithRunningB(scene: [censusBox(x: 0.2)])
        let held = try #require(await show.workScheduler.acquire(.perception, for: .a))
        guard case .started(let task) = show.requestCensus(of: .b, now: 100) else {
            Issue.record("expected the census to start waiting"); return
        }
        await settle()
        #expect(show.workScheduler.isWaiting(.perception, for: .b, kind: .census))
        guard case .refused(.alreadyInFlight) = show.requestCensus(of: .b, now: 100) else {
            Issue.record("one census per camera at a time"); return
        }
        b.setRunningForTesting(false)
        show.workScheduler.release(held)
        #expect(await task.value == false)
        #expect(show.censusStats.started == 0)
        #expect(show.censusInFlight[.b] == nil)
        #expect(show.workScheduler.runningPermit(.perception) == nil)
    }
}
