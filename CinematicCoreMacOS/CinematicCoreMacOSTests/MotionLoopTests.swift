//
//  MotionLoopTests.swift
//  CinematicCoreMacOSTests
//
//  D-02 path 2: each camera's per-frame loop (step, render, store) runs on
//  its capture queue and never waits for the main thread. These tests run the
//  loop with a fake frame source: a serial queue that delivers small buffers.
//  No camera, no capture session.
//

import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Counts what the loop asks the main thread for. Safe from any queue.
nonisolated final class HopCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [MotionMainHop: Int] = [:]
    func note(_ hop: MotionMainHop) { lock.lock(); counts[hop, default: 0] += 1; lock.unlock() }
    func count(_ hop: MotionMainHop) -> Int { lock.lock(); defer { lock.unlock() }; return counts[hop] ?? 0 }
}

/// A value the fake renderer and the test share across queues.
nonisolated final class LoopProbe<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    func mutate(_ change: (inout Value) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}

nonisolated struct FakeRenderFailure: Error {}

/// Records what a Program camera hands to its port.
final class RecordingPort: ChannelOutputPort {
    struct Submission { let buffer: CVPixelBuffer; let timestamp: Double; let isRepeat: Bool; let routeGeneration: UInt64 }
    var submissions: [Submission] = []
    var hopLags: [TimeInterval] = []
    var droppedReasons: [String] = []

    var diagnosticsFileName: String? { "recording port" }
    func submitFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool, routeGeneration: UInt64) {
        submissions.append(.init(buffer: pixelBuffer, timestamp: timestamp, isRepeat: isRepeat, routeGeneration: routeGeneration))
    }
    func start() {}
    func stop() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool) {}
    func beginDiagnosticsSessionIfNeeded(note: String) {}
    func noteDetectionStartIfNeeded() {}
    func noteDiagnostics(_ text: String) {}
    func recordSourceIdentity(_ source: DiagnosticsSessionIdentity.Source) {}
    func recordDeliveredDimensions(width: Int, height: Int) {}
    func recordInputFrame(timestamp: Double) {}
    func recordMainActorHop(_ seconds: TimeInterval) { hopLags.append(seconds) }
    func recordDetectionTiming(queueWait: TimeInterval, visionWall: TimeInterval) {}
    func recordObservationAge(_ age: TimeInterval) {}
    func recordLatency(stage: ProgramOutputManager.LatencyStage, duration: TimeInterval, timestamp: TimeInterval) {}
    func recordDroppedFrame(timestamp: Double, reason: String, stage: ProgramOutputManager.DropStage) { droppedReasons.append(reason) }
    func recordGateDropTotal(_ total: UInt64) {}
    func recordFramePathCounts(detectedPersons: Int) {}
    func recordPictureQuality(sourceHeight: Int, cropHeightFraction: Double, outputHeight: Int) {}
}

@MainActor
struct MotionLoopTests {
    /// The fake frame source: one serial queue, as a camera's capture queue is.
    private let source = DispatchQueue(label: "test.fake-frame-source")

    private nonisolated static func buffer(width: Int = 64, height: Int = 36) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }

    /// A motion unit with a fake renderer and its own mailboxes, running.
    private struct Rig {
        let unit: ChannelMotionUnit
        let frames: ChannelFrameMailbox
        let targets: MotionTargetMailbox
        let hops: HopCounter
        let route: LoopProbe<FrameRoute>
        /// Host time the unit's clock reports; tests advance it per frame.
        let now: LoopProbe<TimeInterval>
    }

    private func makeRig(isProgram: Bool, render: @escaping ChannelMotionUnit.Renderer) -> Rig {
        let frames = ChannelFrameMailbox()
        frames.update { $0.isRunning = true }
        let targets = MotionTargetMailbox()
        let hops = HopCounter()
        let route = LoopProbe(FrameRoute(generation: 0, isProgram: isProgram))
        let now = LoopProbe<TimeInterval>(100)
        let unit = ChannelMotionUnit(channelID: isProgram ? .a : .b, core: CropMotionCore(), targets: targets,
                                     frames: frames, hold: ProgramHoldState(), pan: AutoPanState(),
                                     route: { route.value }, clock: { now.value }, render: render)
        unit.setMainHop { hops.note($0) }
        return Rig(unit: unit, frames: frames, targets: targets, hops: hops, route: route, now: now)
    }

    /// Deliver `count` frames from the fake source and wait for the last one.
    /// The wait blocks the calling thread, so from a test it keeps the main
    /// thread busy for as long as the frames take.
    private func deliver(_ count: Int, to unit: ChannelMotionUnit, now: LoopProbe<TimeInterval>? = nil,
                         width: Int = 64, height: Int = 36) throws {
        let frame = try Self.buffer(width: width, height: height)
        let box = SendablePixelBufferBox(frame)
        source.sync {
            for index in 0..<count {
                now?.mutate { $0 += 0.02 }
                unit.process(box.pixelBuffer, timestamp: Double(index) / 50)
            }
        }
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<400 where !done() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    // MARK: Frames keep rendering while the main thread is busy

    @Test func framesKeepRenderingWhileTheMainThreadIsBusy() throws {
        // The real camera object, its real crop engine and renderer. Program,
        // so every frame also has a hand-off waiting for the main thread.
        let port = RecordingPort()
        let camera = TestHardware.makeCamera(outputPort: port)
        camera.setRunningForTesting(true)
        let unit = try #require(camera.motionUnit)

        // This test function is the main thread, and it does not suspend
        // while the frames are delivered: the main thread is busy throughout.
        try deliver(25, to: unit)

        #expect(camera.renderedFrameCount == 25)
        let newest = try #require(camera.latestRenderedFrame)
        #expect(newest.sourceTimestamp == 24.0 / 50)
        #expect(newest.matches(camera.revisions))
        #expect(camera.croppedFrameBuffer === newest.pixelBuffer)
        #expect(camera.currentFrameBuffer != nil)
        // Nothing reached the port: its hand-off needs the main thread.
        #expect(port.submissions.isEmpty)
    }

    @Test func theProgramHandOffIsOneSlotAndDeliversTheNewestFrame() async throws {
        let port = RecordingPort()
        let camera = TestHardware.makeCamera(outputPort: port)
        camera.setRunningForTesting(true)
        let unit = try #require(camera.motionUnit)

        try deliver(25, to: unit)
        // The main thread comes back: one hand-off, carrying the newest frame.
        await settle { !port.submissions.isEmpty }
        for _ in 0..<10 { await Task.yield() }
        #expect(port.submissions.count == 1)
        #expect(port.submissions.first?.timestamp == 24.0 / 50)
        #expect(port.submissions.first?.buffer === camera.latestRenderedFrame?.pixelBuffer)
        #expect(port.hopLags.count == 1)

        // Frame by frame, each one is handed on.
        for index in 0..<3 {
            try deliver(1, to: unit)
            await settle { port.submissions.count == index + 2 }
        }
        #expect(port.submissions.count == 4)
    }

    // MARK: A non-Program camera makes no per-frame main-thread hop

    @Test func aNonProgramCameraAsksNothingOfTheMainThreadPerFrame() throws {
        let rig = makeRig(isProgram: false) { _, _, _, _ in try Self.buffer() }
        try deliver(50, to: rig.unit, now: rig.now)

        #expect(rig.frames.renderedFrameCount == 50)
        #expect(rig.hops.count(.handOff) == 0)
        #expect(rig.unit.takeHandOff() == nil)
        #expect(rig.hops.count(.event) == 0)
        // One control message for the first frame of the source (its size is
        // news to the controller); none for the 49 frames after it.
        #expect(rig.hops.count(.control) == 1)
    }

    @Test func theSameCameraAsProgramHandsOffOncePerFrame() throws {
        let rig = makeRig(isProgram: true) { _, _, _, _ in try Self.buffer() }
        for frame in 1...5 {
            try deliver(1, to: rig.unit, now: rig.now)
            #expect(rig.hops.count(.handOff) == frame)
            #expect(rig.unit.takeHandOff() != nil)
        }
        // Unanswered, the requests do not pile up: one pending, newest frame.
        try deliver(10, to: rig.unit, now: rig.now)
        #expect(rig.hops.count(.handOff) == 6)
        let pending = try #require(rig.unit.takeHandOff())
        #expect(pending.frame.sourceTimestamp == 9.0 / 50)
        #expect(pending.superseded == 9)
    }

    @Test func aCameraWithControlWorkPostsOneCoalescedControlMessage() throws {
        let rig = makeRig(isProgram: false) { _, _, _, _ in try Self.buffer() }
        rig.frames.update { $0.controlWanted = true }
        try deliver(10, to: rig.unit, now: rig.now)
        // Ten frames wanted the controller; it was asked once, and the slot
        // holds only the newest frame.
        #expect(rig.hops.count(.control) == 1)
        let work = rig.unit.takeControl()
        #expect(work.hasWork)
        #expect(work.tick?.timestamp == 9.0 / 50)
        #expect(!rig.unit.takeControl().hasWork)
        // Emptied, the next frame asks again.
        try deliver(1, to: rig.unit, now: rig.now)
        #expect(rig.hops.count(.control) == 2)
        #expect(rig.hops.count(.handOff) == 0)
    }

    // MARK: A retired generation's frame is rejected

    @Test func aFrameWhoseSourceGenerationRetiredDuringTheRenderIsRejected() throws {
        let frames = LoopProbe<ChannelFrameMailbox?>(nil)
        let retire = LoopProbe(false)
        let rig = makeRig(isProgram: true) { _, _, _, _ in
            // A stop or a rebind lands on the main thread mid-render.
            if retire.value { frames.value?.update { $0.sourceGeneration &+= 1 } }
            return try Self.buffer()
        }
        frames.value = rig.frames

        try deliver(1, to: rig.unit, now: rig.now)
        let kept = try #require(rig.frames.latestRendered)
        _ = rig.unit.takeHandOff()

        retire.value = true
        try deliver(1, to: rig.unit, now: rig.now)
        // Not stored, not handed off; the earlier frame is untouched.
        #expect(rig.frames.renderedFrameCount == 1)
        #expect(rig.frames.latestRendered?.pixelBuffer === kept.pixelBuffer)
        #expect(rig.unit.takeHandOff() == nil)
        // And it no longer matches the camera's current revisions.
        #expect(!kept.matches(rig.frames.admission.revisions))
    }

    @Test func theMailboxRefusesAFrameFromARetiredGeneration() throws {
        let frames = ChannelFrameMailbox()
        frames.update { $0.isRunning = true; $0.sourceGeneration = 7 }
        func frame(generation: UInt64) throws -> RenderedChannelFrame {
            RenderedChannelFrame(channelID: .a,
                revisions: .init(sourceGeneration: generation, controlEpoch: 0, shotRevision: 0),
                sourceTimestamp: 1, processingStartedAt: 1, renderedAt: 1, crop: .fullFrame,
                outputSize: CGSize(width: 64, height: 36), isRepeat: false, pixelBuffer: try Self.buffer())
        }
        #expect(!frames.store(try frame(generation: 6)))
        #expect(frames.latestRendered == nil)
        #expect(frames.store(try frame(generation: 7)))
        // A stopped session and a missing source refuse too.
        frames.update { $0.sourceMissing = true }
        #expect(!frames.store(try frame(generation: 7)))
        frames.update { $0.sourceMissing = false; $0.isRunning = false }
        #expect(!frames.store(try frame(generation: 7)))
        #expect(!frames.storeSource(try Self.buffer(), sourceGeneration: 7))
    }

    @Test func aCommandDuringTheRenderRetiresThatFrame() throws {
        let frames = LoopProbe<ChannelFrameMailbox?>(nil)
        let rig = makeRig(isProgram: true) { _, _, _, _ in
            frames.value?.update { $0.controlEpoch &+= 1 }
            return try Self.buffer()
        }
        frames.value = rig.frames
        try deliver(3, to: rig.unit, now: rig.now)
        #expect(rig.frames.renderedFrameCount == 0)
        #expect(rig.frames.latestRendered == nil)
        #expect(rig.hops.count(.handOff) == 0)
    }

    @Test func aFrameCarriesTheRouteGenerationItStartedUnderAndTheRouterRefusesIt() throws {
        // A real router; the camera on channel B is not Program at first.
        let output = ProgramOutputManager(sinks: [])
        let router = ProgramRouter(output: output, programChannel: .a)
        let port = router.port(for: .a)
        let routeOfA = port.frameRoute
        #expect(routeOfA() == FrameRoute(generation: 0, isProgram: true))
        #expect(router.port(for: .b).frameRoute() == FrameRoute(generation: 0, isProgram: false))

        let roles = LoopProbe<(@Sendable () -> Void)?>(nil)
        let frames = ChannelFrameMailbox()
        frames.update { $0.isRunning = true }
        let unit = ChannelMotionUnit(channelID: .a, core: CropMotionCore(), targets: MotionTargetMailbox(),
                                     frames: frames, hold: ProgramHoldState(), pan: AutoPanState(),
                                     route: routeOfA, clock: { 100 }) { _, _, _, _ in
            roles.value?()
            return try Self.buffer()
        }
        // The roles change while the frame renders (the router's state is
        // written under its own lock; the router itself stays on the main thread).
        let state = router.routeState
        roles.value = { state.programChannel = .b; state.routeGeneration = 1 }
        try deliver(1, to: unit)

        let handOff = try #require(unit.takeHandOff())
        #expect(handOff.routeGeneration == 0)
        #expect(router.routeGeneration == 1)
        let refusedBefore = router.framesNotRouted
        port.submitFrame(handOff.frame.pixelBuffer, timestamp: 1, isRepeat: false,
                         routeGeneration: handOff.routeGeneration)
        #expect(router.framesNotRouted == refusedBefore + 1)
        // The camera is no longer Program: its next frame is not handed off.
        roles.value = nil
        try deliver(1, to: unit)
        #expect(unit.takeHandOff() == nil)
    }

    // MARK: A held frame is still chosen after a failed render

    @Test func aFailedRenderRepeatsTheLastGoodFrame() throws {
        let fail = LoopProbe(false)
        let rig = makeRig(isProgram: true) { _, _, _, _ in
            if fail.value { throw FakeRenderFailure() }
            return try Self.buffer()
        }
        try deliver(1, to: rig.unit, now: rig.now)
        let good = try #require(rig.frames.latestRendered)
        #expect(!good.isRepeat)
        #expect(rig.unit.takeEvents().isEmpty)

        fail.value = true
        try deliver(2, to: rig.unit, now: rig.now)
        let held = try #require(rig.frames.latestRendered)
        #expect(held.pixelBuffer === good.pixelBuffer)
        #expect(held.isRepeat)
        #expect(held.crop == good.crop)
        #expect(held.sourceTimestamp == 1.0 / 50)
        #expect(rig.frames.renderedFrameCount == 3)
        #expect(rig.frames.repeatedFrameCount == 2)
        #expect(rig.unit.hold.isHolding)
        // The held frame is still handed to the router, marked as a repeat.
        #expect(try #require(rig.unit.takeHandOff()).frame.isRepeat)
        // The controller hears of both failures and of hold starting, once.
        let events = rig.unit.takeEvents()
        #expect(events.count == 3)
        #expect(rig.hops.count(.event) == 1)

        fail.value = false
        try deliver(1, to: rig.unit, now: rig.now)
        let recovered = try #require(rig.frames.latestRendered)
        #expect(!recovered.isRepeat)
        #expect(recovered.pixelBuffer !== good.pixelBuffer)
        #expect(!rig.unit.hold.isHolding)
    }

    @Test func aFailedFirstRenderHasNothingToHold() throws {
        let rig = makeRig(isProgram: true) { _, _, _, _ in throw FakeRenderFailure() }
        try deliver(2, to: rig.unit, now: rig.now)
        #expect(rig.frames.latestRendered == nil)
        #expect(rig.frames.renderedFrameCount == 0)
        #expect(rig.unit.takeHandOff() == nil)
    }

    @Test func theCameraMirrorsHoldAndRecordsTheFailedRenderOnTheMainThread() async throws {
        let port = RecordingPort()
        let camera = TestHardware.makeCamera(outputPort: port)
        camera.setRunningForTesting(true)
        let unit = try #require(camera.motionUnit)
        try deliver(1, to: unit)
        await settle { port.submissions.count == 1 }
        #expect(!camera.isProgramHolding)

        // Make the real renderer fail: it cannot make a zero-sized output.
        let engine = try #require(camera.cropEngine)
        engine.config.outputSize = .zero
        try deliver(1, to: unit)
        await settle { camera.isProgramHolding && port.submissions.count == 2 }
        #expect(camera.isProgramHolding)
        #expect(port.submissions.last?.isRepeat == true)
        #expect(port.submissions.last?.buffer === port.submissions.first?.buffer)
        #expect(port.droppedReasons.count == 1)
    }

    // MARK: The loop steps what the directive says
    //
    // These use 1080-line fake frames: the quality floor follows the delivered
    // height, and a 36-line frame would floor every crop at the full picture.

    @Test func theLoopAppliesATrackingTargetOncePerSerialAndStepsTheSpring() throws {
        let rig = makeRig(isProgram: false) { _, _, _, _ in try Self.buffer() }
        let target = CropEngine.CropRect(center: CGPoint(x: 0.6, y: 0.5), size: CGSize(width: 0.5, height: 0.5))
        var directive = MotionDirective()
        directive.mode = .tracking
        directive.smoothing = 0.10
        directive.trackingTarget = target
        directive.trackingSerial = 1
        rig.targets.write(directive)

        try deliver(1, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        #expect(rig.unit.core.targetCrop == target)
        // A command writes the core directly; the unchanged serial must not
        // pull the target back.
        rig.unit.core.setTargetCrop(.fullFrame)
        rig.unit.core.jumpToTarget()
        try deliver(5, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        #expect(rig.unit.core.targetCrop == .fullFrame)

        directive.trackingSerial = 2
        rig.targets.write(directive)
        try deliver(150, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        let settled = try #require(rig.frames.latestRendered).crop
        #expect(abs(settled.center.x - 0.6) < 0.002)
        #expect(abs(settled.size.height - 0.5) < 0.002)
    }

    @Test func theLoopGivesTheSameCropsAsSteppingTheEngineOnTheMainThread() throws {
        // The spring stepped by the loop, against the engine stepped the way
        // the frame path stepped it before: same target, same times.
        let rig = makeRig(isProgram: false) { _, _, _, _ in try Self.buffer() }
        let reference = try #require(CropEngine())
        let target = CropEngine.CropRect(center: CGPoint(x: 0.35, y: 0.55), size: CGSize(width: 0.4, height: 0.4))
        var directive = MotionDirective()
        directive.mode = .wide(target: target)
        directive.smoothing = 0.10
        directive.boost = .init(smoothing: 0.25, until: 100.5)
        rig.targets.write(directive)

        var worst: CGFloat = 0
        for _ in 0..<120 {
            try deliver(1, to: rig.unit, now: rig.now, width: 1920, height: 1080)
            let now = rig.now.value
            reference.applyFrameSmoothing(now < 100.5 ? 0.25 : 0.10, operatorSetting: 0.10)
            reference.setTargetCrop(target)
            let expected = reference.tickInterpolation(now: now).crop
            let got = try #require(rig.frames.latestRendered).crop
            worst = max(worst, abs(got.origin.x - expected.origin.x), abs(got.origin.y - expected.origin.y),
                        abs(got.size.width - expected.size.width), abs(got.size.height - expected.size.height))
        }
        #expect(worst < 1e-12)
        #expect(try #require(rig.frames.latestRendered).crop != .fullFrame)
    }

    @Test func manualAndAutoPanDirectivesMoveTheCrop() throws {
        let rig = makeRig(isProgram: false) { _, _, _, _ in try Self.buffer() }
        var directive = MotionDirective()
        directive.aspect = 1
        directive.fixedHeight = 0.5
        directive.smoothing = 0.10
        directive.mode = .manual(center: CGPoint(x: 0.9, y: 0.5))
        rig.targets.write(directive)
        try deliver(1, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        // Clamped to the canvas, as the frame path's manual rectangle was.
        #expect(rig.unit.core.targetCrop == CropEngine.CropRect(origin: CGPoint(x: 0.5, y: 0.25),
                                                                size: CGSize(width: 0.5, height: 0.5)))

        directive.smoothing = nil
        directive.mode = .autoPan(speed: 0.1, height: 0.5, eased: false)
        rig.targets.write(directive)
        try deliver(1, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        let first = try #require(rig.frames.latestRendered).crop
        try deliver(10, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        let later = try #require(rig.frames.latestRendered).crop
        #expect(later.center.x > first.center.x)
        #expect(later.size == first.size)
        #expect(abs(later.center.y - 0.5) < 1e-9)
    }
}
