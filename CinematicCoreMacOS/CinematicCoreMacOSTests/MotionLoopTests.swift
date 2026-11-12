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
    struct Drop { let timestamp: Double; let reason: String; let stage: ProgramOutputManager.DropStage }
    var submissions: [Submission] = []
    var hopLags: [TimeInterval] = []
    var inputs: [Double] = []
    var drops: [Drop] = []
    var droppedReasons: [String] { drops.map(\.reason) }

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
    func recordInputFrame(timestamp: Double) { inputs.append(timestamp) }
    func recordMainActorHop(_ seconds: TimeInterval) { hopLags.append(seconds) }
    func recordDetectionTiming(queueWait: TimeInterval, visionWall: TimeInterval) {}
    func recordObservationAge(_ age: TimeInterval) {}
    func recordLatency(stage: ProgramOutputManager.LatencyStage, duration: TimeInterval, timestamp: TimeInterval) {}
    func recordDroppedFrame(timestamp: Double, reason: String, stage: ProgramOutputManager.DropStage) {
        drops.append(.init(timestamp: timestamp, reason: reason, stage: stage))
    }
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

    /// `width` × `height` is the frame size the controller has already
    /// applied; the loop renders nothing from frames of another size.
    private func makeRig(isProgram: Bool, width: Int = 64, height: Int = 36,
                         render: @escaping ChannelMotionUnit.Renderer) -> Rig {
        let frames = ChannelFrameMailbox()
        frames.update { $0.isRunning = true; $0.formatWidth = width; $0.formatHeight = height }
        let targets = MotionTargetMailbox()
        let hops = HopCounter()
        let route = LoopProbe(FrameRoute(generation: 0, isProgram: isProgram))
        let now = LoopProbe<TimeInterval>(100)
        let unit = ChannelMotionUnit(channelID: isProgram ? .a : .b, core: CropMotionCore(), targets: targets,
                                     frames: frames, pan: AutoPanState(),
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

    /// A running camera whose controller has applied the fake source's frame
    /// size. The first frame of a size is not rendered: it waits for the
    /// controller's turn, which `processFrameForTesting` waits for.
    private func runningCamera(port: RecordingPort, width: Int = 64, height: Int = 36) async throws -> CameraManager {
        let camera = TestHardware.makeCamera(outputPort: port)
        camera.setRunningForTesting(true)
        await camera.processFrameForTesting(try Self.buffer(width: width, height: height), timestampSeconds: -1)
        return camera
    }

    /// A loop on a real camera's mailboxes and motion core, with a renderer
    /// the test controls. The camera's own controller is not wired to it.
    private func loop(on camera: CameraManager, isProgram: Bool = false,
                      render: @escaping ChannelMotionUnit.Renderer) throws -> ChannelMotionUnit {
        let engine = try #require(camera.cropEngine)
        camera.frameMailbox.update { $0.formatWidth = 64; $0.formatHeight = 36 }
        return ChannelMotionUnit(channelID: camera.channelID, core: engine.motion, targets: camera.motionTargets,
                                 frames: camera.frameMailbox, pan: camera.autoPan,
                                 route: { FrameRoute(generation: 0, isProgram: isProgram) }, render: render)
    }

    /// Start one frame and return once its render has begun; the render then
    /// waits for `proceed`. Lets a test act on the main thread mid-render.
    private func beginFrame(on unit: ChannelMotionUnit, entered: DispatchSemaphore) throws {
        let box = SendablePixelBufferBox(try Self.buffer())
        source.async { unit.process(box.pixelBuffer, timestamp: 1) }
        entered.wait()
    }

    // MARK: Frames keep rendering while the main thread is busy

    @Test func framesKeepRenderingWhileTheMainThreadIsBusy() async throws {
        // The real camera object, its real crop engine and renderer. Program,
        // so every frame also has a hand-off waiting for the main thread.
        let port = RecordingPort()
        let camera = try await runningCamera(port: port)
        let unit = try #require(camera.motionUnit)

        // This test function is the main thread, and from here it does not
        // suspend while the frames are delivered: the main thread is busy.
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
        let camera = try await runningCamera(port: port)
        let unit = try #require(camera.motionUnit)

        try deliver(25, to: unit)
        // The main thread comes back: one hand-off, carrying the newest frame.
        await settle { !port.submissions.isEmpty }
        for _ in 0..<10 { await Task.yield() }
        #expect(port.submissions.count == 1)
        #expect(port.submissions.first?.timestamp == 24.0 / 50)
        #expect(port.submissions.first?.buffer === camera.latestRenderedFrame?.pixelBuffer)
        #expect(port.hopLags.count == 1)

        // Every frame the loop finished is an input frame. The 24 that the
        // newest one replaced are drops with their own stage and reason, so
        // a stalled main thread is not read as a camera that delivered less.
        #expect(port.inputs == (0..<25).map { Double($0) / 50 })
        #expect(port.drops.count == 24)
        #expect(port.drops.allSatisfy { $0.stage == .handoffSuperseded && $0.reason == CameraManager.supersededHandOffReason })
        #expect(port.drops.map(\.timestamp) == (0..<24).map { Double($0) / 50 })

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
        #expect(pending.superseded == (0..<9).map { Double($0) / 50 })
        // Taken once: the next hand-off starts a new count.
        try deliver(1, to: rig.unit, now: rig.now)
        #expect(try #require(rig.unit.takeHandOff()).superseded.isEmpty)
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
        // Not stored, not handed off. The retiring also cleared the earlier
        // frame, in the same locked step as the new generation.
        #expect(rig.frames.renderedFrameCount == 1)
        #expect(rig.frames.latestRendered == nil)
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
        frames.update { $0.isRunning = true; $0.formatWidth = 64; $0.formatHeight = 36 }
        let unit = ChannelMotionUnit(channelID: .a, core: CropMotionCore(), targets: MotionTargetMailbox(),
                                     frames: frames, pan: AutoPanState(),
                                     route: routeOfA, clock: { 100 }) { _, _, _, _ in
            roles.value?()
            return try Self.buffer()
        }
        // The roles change while the frame renders (the router's state is
        // written under its own lock; the router itself stays on the main thread).
        let state = router.routeState
        roles.value = { state.setProgram(.b) }
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
        #expect(rig.frames.isHolding)
        // The held frame is still handed to the router, marked as a repeat.
        #expect(try #require(rig.unit.takeHandOff()).frame.isRepeat)
        // The controller hears of both failures and of hold starting, in one message.
        let events = rig.unit.takeEvents()
        #expect(events.failedRenders == [1.0 / 50, 1.0 / 50 + 0.02].map { $0 - 1.0 / 50 })
        #expect(events.lastFailureDescription != nil)
        #expect(events.holdChanged)
        #expect(rig.hops.count(.event) == 1)

        fail.value = false
        try deliver(1, to: rig.unit, now: rig.now)
        let recovered = try #require(rig.frames.latestRendered)
        #expect(!recovered.isRepeat)
        #expect(recovered.pixelBuffer !== good.pixelBuffer)
        #expect(!rig.frames.isHolding)
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
        let camera = try await runningCamera(port: port)
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
        #expect(port.drops.count == 1)
        #expect(port.drops.first?.stage == .renderFailed)
    }

    // MARK: The loop steps what the directive says
    //
    // These use 1080-line fake frames: the quality floor follows the delivered
    // height, and a 36-line frame would floor every crop at the full picture.

    @Test func theLoopAppliesATrackingTargetOncePerSerialAndStepsTheSpring() throws {
        let rig = makeRig(isProgram: false, width: 1920, height: 1080) { _, _, _, _ in try Self.buffer() }
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
        let rig = makeRig(isProgram: false, width: 1920, height: 1080) { _, _, _, _ in try Self.buffer() }
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
        let rig = makeRig(isProgram: false, width: 1920, height: 1080) { _, _, _, _ in try Self.buffer() }
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

    // MARK: Review fixes (PR #141)

    // 3. The capture queue never waits on a main-thread transaction.

    @Test func aMainThreadTransactionNeverDelaysAFrameAndLandsAsOneStep() throws {
        let rig = makeRig(isProgram: false, width: 1920, height: 1080) { _, _, _, _ in try Self.buffer() }
        let tight = CropEngine.CropRect(center: CGPoint(x: 0.3, y: 0.5), size: CGSize(width: 0.5, height: 0.5))
        let other = CropEngine.CropRect(center: CGPoint(x: 0.7, y: 0.5), size: CGSize(width: 0.4, height: 0.4))
        var directive = MotionDirective()
        directive.smoothing = 0.10
        directive.mode = .wide(target: tight)
        rig.targets.write(directive)
        rig.unit.core.setTargetCrop(tight)
        rig.unit.core.jumpToTarget()
        try deliver(3, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        #expect(try #require(rig.frames.latestRendered).crop == tight)

        // A command on the main thread: it writes the core and will publish a
        // new directive. Then it is slow (a lock-machine tick, the composer),
        // and stays open while the camera delivers ten frames.
        let core = rig.unit.core
        core.beginTransaction()
        core.setTargetCrop(other)
        core.jumpToTarget()
        #expect(core.currentCrop == other)          // the main thread reads its own writes
        try deliver(10, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        // All ten rendered (had the capture queue waited, this test would
        // never get here), and none of them saw any part of the command.
        #expect(rig.frames.renderedFrameCount == 13)
        #expect(try #require(rig.frames.latestRendered).crop == tight)

        // The commit: the core's new state and the directive, together.
        directive.mode = .wide(target: other)
        let targets = rig.targets
        core.endTransaction { targets.write(directive) }
        try deliver(1, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        #expect(try #require(rig.frames.latestRendered).crop == other)
        #expect(!core.isInTransaction)
    }

    @Test func aTargetAppliedDuringATransactionIsAppliedAgainAfterIt() throws {
        // The capture queue applies a composed target to the live state while
        // a transaction is open; the commit replaces that state. The target
        // must not be lost.
        let rig = makeRig(isProgram: false, width: 1920, height: 1080) { _, _, _, _ in try Self.buffer() }
        let target = CropEngine.CropRect(center: CGPoint(x: 0.6, y: 0.5), size: CGSize(width: 0.5, height: 0.5))
        var directive = MotionDirective()
        directive.mode = .tracking
        directive.smoothing = 0.10
        directive.trackingTarget = target
        directive.trackingSerial = 1
        rig.unit.core.beginTransaction()
        rig.targets.write(directive)
        try deliver(2, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        rig.unit.core.endTransaction()
        #expect(rig.unit.core.targetCrop == .fullFrame)
        try deliver(1, to: rig.unit, now: rig.now, width: 1920, height: 1080)
        #expect(rig.unit.core.targetCrop == target)
    }

    @Test func aSlowCommandHandlerDoesNotDelayFrames() async throws {
        // The real camera: frames arrive while a command is being handled on
        // the main thread. 720-line frames, so the quality floor allows a
        // crop tighter than the whole picture.
        let port = RecordingPort()
        let camera = try await runningCamera(port: port, width: 1280, height: 720)
        let unit = try #require(camera.motionUnit)
        let engine = try #require(camera.cropEngine)
        engine.setTargetCrop(.init(center: CGPoint(x: 0.4, y: 0.5), size: CGSize(width: 0.5, height: 0.5)))
        engine.jumpToTarget()
        try deliver(2, to: unit, width: 1280, height: 720)
        let before = camera.renderedFrameCount
        #expect(before == 2)
        #expect(camera.latestRenderedFrame?.crop != .fullFrame)

        // The epoch observer runs inside the command handler. Deliver frames
        // from there: the handler is busy for as long as they take.
        var renderedDuring: [UInt64] = []
        var cropsDuring: [CropEngine.CropRect] = []
        let original = camera.commands.epochObserver
        camera.commands.epochObserver = { epoch in
            original?(epoch)
            try? self.deliver(3, to: unit, width: 1280, height: 720)
            renderedDuring.append(camera.renderedFrameCount)
            if let crop = camera.latestRenderedFrame?.crop { cropsDuring.append(crop) }
        }
        let result = camera.dispatch(camera.makeCommand(.returnToWide))
        camera.commands.epochObserver = original
        guard case .accepted = result else {
            Issue.record("Return to Wide was not accepted")
            return
        }
        // Frames kept rendering while the handler ran, and none of them
        // showed the command's snap to wide before it was complete.
        #expect((renderedDuring.last ?? 0) >= before + 3)
        #expect(!cropsDuring.isEmpty && cropsDuring.allSatisfy { $0 != .fullFrame })
        // The next frame shows the whole command.
        try deliver(1, to: unit, width: 1280, height: 720)
        #expect(camera.latestRenderedFrame?.crop == .fullFrame)
    }

    // 2. The old hold and retire rules, asserted on the live loop.

    @Test func liveLoopAFailedRenderKeepsThePriorProgramAndNeverInventsAFirstFrame() throws {
        let camera = TestHardware.makeCamera()
        camera.setRunningForTesting(true)
        let fail = LoopProbe(true)
        let good = LoopProbe<CVPixelBuffer?>(nil)
        let unit = try loop(on: camera) { _, _, _, _ in
            if fail.value { throw FakeRenderFailure() }
            let buffer = try Self.buffer()
            good.value = buffer
            return buffer
        }
        try deliver(1, to: unit)
        #expect(camera.latestRenderedFrame == nil)
        #expect(camera.croppedFrameBuffer == nil)

        fail.value = false
        try deliver(1, to: unit)
        let rendered = try #require(good.value)
        #expect(camera.latestRenderedFrame?.pixelBuffer === rendered)

        fail.value = true
        for _ in 0..<5 {
            try deliver(1, to: unit)
            #expect(camera.latestRenderedFrame?.pixelBuffer === rendered)
            #expect(camera.latestRenderedFrame?.isRepeat == true)
        }
        #expect(camera.frameMailbox.isHolding)
        #expect(camera.repeatedFrameCount == 5)

        camera.stopCapture()
        #expect(camera.selectProgramBuffer(rendered: nil) == nil)
        camera.setRunningForTesting(true)
        try deliver(1, to: unit)
        #expect(camera.latestRenderedFrame == nil)
    }

    @Test func liveLoopARetiredFailedRenderCannotCancelANewZoom() throws {
        let camera = TestHardware.makeCamera()
        camera.setRunningForTesting(true)
        let engine = try #require(camera.cropEngine)
        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let unit = try loop(on: camera) { _, _, _, _ in
            entered.signal()
            proceed.wait()
            throw FakeRenderFailure()
        }
        try beginFrame(on: unit, entered: entered)
        camera.cancelOperatorMotion() // a newer operator epoch while rendering
        engine.beginZoom(.pushIn, to: 0.25)
        proceed.signal()
        source.sync {}

        // The frame is retired: its failure is not reported, so nothing on
        // the main thread cancels the zoom, and it does not start a hold.
        #expect(unit.takeEvents().isEmpty)
        #expect(engine.zoomDirection == .pushIn)
        #expect(!camera.frameMailbox.isHolding)
        #expect(!camera.isProgramHolding)
        #expect(camera.latestRenderedFrame == nil)
    }

    @Test func liveLoopARetiredCompletionOnBIsRejectedAndAIsUntouched() throws {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []))
        let a = show.channelA
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        let aRevisions = a.revisions
        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let unit = try loop(on: b) { _, _, _, _ in
            entered.signal()
            proceed.wait()
            return try Self.buffer()
        }
        // B's source is stopped while its render is in flight: the completion
        // belongs to a retired generation and must not become B's program.
        try beginFrame(on: unit, entered: entered)
        b.stopCapture()
        proceed.signal()
        source.sync {}

        #expect(b.latestRenderedFrame == nil)
        #expect(b.croppedFrameBuffer == nil)
        #expect(unit.takeHandOff() == nil)
        #expect(a.revisions == aRevisions)
        #expect(a.latestRenderedFrame == nil)
    }

    // 4. A retired frame cannot refill the hold after a reset.

    @Test func aRetiredFrameCannotRefillTheHoldAfterAReset() throws {
        let frames = LoopProbe<ChannelFrameMailbox?>(nil)
        let mode = LoopProbe("good")
        let rig = makeRig(isProgram: true) { _, _, _, _ in
            switch mode.value {
            case "fail": throw FakeRenderFailure()
            case "retire":
                // A reconnect on the main thread, mid-render: the generation
                // retires, and with it the held frame.
                frames.value?.update { $0.sourceGeneration &+= 1 }
                return try Self.buffer()
            default: return try Self.buffer()
            }
        }
        frames.value = rig.frames
        try deliver(1, to: rig.unit, now: rig.now)
        #expect(rig.frames.lastGoodCrop != nil)

        mode.value = "retire"
        try deliver(1, to: rig.unit, now: rig.now)
        // The retired render was not held, and the old held frame is gone.
        #expect(rig.frames.lastGoodCrop == nil)
        #expect(rig.frames.latestRendered == nil)

        // The new generation's first render fails: there is nothing to
        // repeat, least of all a frame from the old generation.
        mode.value = "fail"
        _ = rig.unit.takeHandOff()
        try deliver(2, to: rig.unit, now: rig.now)
        #expect(rig.frames.latestRendered == nil)
        #expect(rig.unit.takeHandOff() == nil)
        #expect(rig.frames.renderedFrameCount == 1)

        // In the mailbox itself: a selection for a retired generation is
        // refused and changes nothing.
        let generation = rig.frames.admission.sourceGeneration
        #expect(rig.frames.selectProgram(rendered: try Self.buffer(), crop: .fullFrame, sourceGeneration: generation &- 1) == nil)
        #expect(rig.frames.lastGoodCrop == nil)
        #expect(rig.frames.selectProgram(rendered: try Self.buffer(), crop: .fullFrame, sourceGeneration: generation)?.buffer != nil)
    }

    // 5. A role change is one write.

    @Test func noReaderSeesTheNewProgramUnderTheOldRouteGeneration() {
        // Program alternates A, B, A, …: B is Program exactly when the
        // generation is odd. A reader that ever sees otherwise read half of
        // a role change.
        let state = ProgramRouteState(program: .a)
        let stop = LoopProbe(false)
        let violations = LoopProbe(0)
        let reads = LoopProbe(0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var seen = 0
            var bad = 0
            while !stop.value {
                let route = state.route(for: .b)
                seen += 1
                if route.isProgram != (route.generation % 2 == 1) { bad += 1 }
            }
            reads.value = seen
            violations.value = bad
            finished.signal()
        }
        for index in 0..<200_000 { state.setProgram(index % 2 == 0 ? .b : .a) }
        stop.value = true
        finished.wait()
        #expect(violations.value == 0)
        #expect(reads.value > 0)
        #expect(state.routeGeneration == 200_000)
        #expect(state.programChannel == .a)
    }

    // 6. No frame of a size the controller has not applied is rendered.

    @Test func framesOfANewSizeWaitForTheController() throws {
        let rig = makeRig(isProgram: true) { _, _, _, _ in try Self.buffer() }
        try deliver(2, to: rig.unit, now: rig.now)
        #expect(rig.frames.renderedFrameCount == 2)
        // The controller takes its messages until the slot is empty.
        while rig.unit.takeControl().hasWork {}
        _ = rig.unit.takeHandOff()
        let hopsBefore = rig.hops.count(.control)

        // The driver starts delivering another size (a different aspect).
        try deliver(3, to: rig.unit, now: rig.now, width: 48, height: 48)
        #expect(rig.frames.renderedFrameCount == 2)
        #expect(rig.unit.takeHandOff() == nil)
        // The controller was asked, with the new size, and the wide pane has
        // the raw frame.
        #expect(rig.hops.count(.control) == hopsBefore + 1)
        let tick = try #require(rig.unit.takeControl().tick)
        #expect(tick.width == 48 && tick.height == 48)
        #expect(rig.frames.sourceBuffer.map(CVPixelBufferGetWidth) == 48)

        // The controller applies it and publishes; frames render again.
        rig.frames.update { $0.formatWidth = 48; $0.formatHeight = 48 }
        try deliver(1, to: rig.unit, now: rig.now, width: 48, height: 48)
        #expect(rig.frames.renderedFrameCount == 3)
        #expect(rig.unit.takeHandOff() != nil)
    }

    @Test func theFirstFrameOfANewAspectIsNotHandedToProgramAndTheNextUsesTheNewWideTarget() async throws {
        let port = RecordingPort()
        let camera = try await runningCamera(port: port)          // 64 × 36, 16:9
        let engine = try #require(camera.cropEngine)
        await camera.processFrameForTesting(try Self.buffer(), timestampSeconds: 0)
        #expect(port.submissions.count == 1)
        #expect(engine.targetCrop == .fullFrame)

        // A square source: the wide view is now a 16:9 band of it.
        let square = try Self.buffer(width: 48, height: 48)
        await camera.processFrameForTesting(square, timestampSeconds: 1)
        #expect(port.submissions.count == 1)                       // not rendered, not handed on
        #expect(camera.renderedFrameCount == 1)
        #expect(camera.sourcePixelWidth == 48 && camera.sourcePixelHeight == 48)

        await camera.processFrameForTesting(square, timestampSeconds: 2)
        #expect(port.submissions.count == 2)
        let band = CropEngine.CropRect.widest(aspect: camera.shotComposer.normalizedAspect)
        #expect(band != .fullFrame)
        #expect(engine.targetCrop == band)
    }

    // 7. The test seam is frame by frame.

    @Test func theTestSeamReturnsAfterThatFramesControlTurnAndHandOff() async throws {
        let port = RecordingPort()
        let camera = TestHardware.makeCamera(outputPort: port)
        camera.setRunningForTesting(true)
        #expect(camera.sourcePixelHeight == 0)
        await camera.processFrameForTesting(try Self.buffer(), timestampSeconds: 0)
        // The control turn for that frame has run: the controller knows the size.
        #expect(camera.sourcePixelWidth == 64 && camera.sourcePixelHeight == 36)
        #expect(camera.frameMailbox.admission.formatHeight == 36)
        for index in 1...5 {
            await camera.processFrameForTesting(try Self.buffer(), timestampSeconds: Double(index))
            // No waiting loop: the hand-off for this frame has been taken.
            #expect(port.submissions.count == index)
            #expect(port.submissions.last?.timestamp == Double(index))
        }
        #expect(port.drops.isEmpty)
    }

    // 8. Loop events are bounded.

    @Test func failuresDuringALongStallAreCountedNotQueued() throws {
        let fail = LoopProbe(false)
        let rig = makeRig(isProgram: false) { _, _, _, _ in
            if fail.value { throw FakeRenderFailure() }
            return try Self.buffer()
        }
        try deliver(1, to: rig.unit, now: rig.now)
        fail.value = true
        // Twenty seconds of failed renders at 50 fps, and nobody listening.
        try deliver(1000, to: rig.unit, now: rig.now)
        #expect(rig.hops.count(.event) == 1)
        let batch = rig.unit.takeEvents()
        // How many failed is exact; the timestamps kept are capped.
        #expect(batch.failedRenders.count == 1000)
        #expect(Set(batch.failedRenders).count <= CaptureDropCoalescer.maxPendingTimestamps)
        #expect(batch.failedRenders.last == 999.0 / 50)
        #expect(batch.holdChanged)
        #expect(rig.unit.takeEvents().isEmpty)
    }

    // Decided by the owner (11 Nov 2026): a framing command reaches the
    // picture one frame later than it did. This pins it at exactly one.

    @Test func aFramingCommandThatLandsInAControlTurnIsUsedByTheNextRenderedFrame() async throws {
        // The real camera, tracking a subject. 1080-line frames, so the
        // quality floor leaves room between the two presets.
        let port = RecordingPort()
        let camera = try await runningCamera(port: port, width: 1920, height: 1080)
        let unit = try #require(camera.motionUnit)
        let engine = try #require(camera.cropEngine)
        camera.shotComposer.config.cinematicFormat = .stage
        camera.shotComposer.config.shotPreset = .waistUp
        let subject = PersonDetector.DetectedPerson(
            id: UUID(), boundingBox: CGRect(x: 0.44, y: 0.15, width: 0.12, height: 0.5),
            confidence: 0.95, timestamp: 0, poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        camera.shotComposer.lockTarget(subject.id)
        camera.shotComposer.forceTrackingForTesting()
        camera.commands.setTrackingOwnership(true)
        camera.setOperationMode(.autoTracking)
        #expect(camera.activeMode == .autoTracking)

        // From here the test does not suspend, so the camera's own control
        // turns (which would run Vision on the fake frames) never run. The
        // test runs the same control step by hand, with the subject above.
        func frame() throws { try deliver(1, to: unit, width: 1920, height: 1080) }
        for index in 0..<4 {
            try frame()
            camera.runControlStepForTesting(persons: [subject], isFresh: index % 2 == 0)
        }
        try frame()
        let waistUp = engine.targetCrop
        #expect(waistUp != .fullFrame)

        // The command lands between two frames.
        guard case .accepted = camera.dispatch(camera.makeCommand(.selectPreset(.stage(.fullBody)))) else {
            Issue.record("the preset command was not accepted")
            return
        }
        // The frames that arrive before the control turn still aim at the
        // old framing, however many there are.
        for _ in 0..<3 {
            try frame()
            #expect(engine.targetCrop == waistUp)
        }
        // The control turn composes the new framing and publishes it…
        camera.runControlStepForTesting(persons: [subject], isFresh: false)
        #expect(engine.targetCrop == waistUp)
        // …and the very next rendered frame is stepped toward it.
        try frame()
        let fullBody = engine.targetCrop
        #expect(fullBody != waistUp)
        #expect(fullBody.size.height > waistUp.size.height)
        // One frame, not two: the frame after changes nothing more.
        try frame()
        #expect(engine.targetCrop == fullBody)
    }
}
