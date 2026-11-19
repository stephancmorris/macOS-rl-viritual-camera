//
//  CaptureFramePathTests.swift
//  CinematicCoreMacOSTests
//
//  Review fixes on the capture → crop path: a cancelled render turn skips the
//  frame (CR-031), per-frame smoothing does not publish (CR-030), and system
//  drops are coalesced into one main-actor hop per burst (CR-033).
//

import Combine
import CoreVideo
import Testing
@testable import Alfie

@MainActor struct CaptureFramePathTests {
    private struct Rendered: Error {}

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private func buffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer)
        return try #require(buffer)
    }

    @Test func withoutASchedulerTheRenderRunsDirectly() async throws {
        let frame = try buffer()
        let result = try await CameraManager.renderInTurn(scheduler: nil, channel: .a) { frame }
        #expect(result === frame)
    }

    @Test func aCancelledTurnSkipsTheRender() async throws {
        let scheduler = FrameWorkScheduler()
        // A camera waits only behind its own render.
        let held = try #require(await scheduler.acquire(.render, for: .b))
        var rendered = false
        let turn = Task { @MainActor in
            _ = try await CameraManager.renderInTurn(scheduler: scheduler, channel: .b) {
                rendered = true
                throw Rendered()
            }
        }
        await settle()
        scheduler.cancelWaiting(for: .b)
        await #expect(throws: CancellationError.self) { try await turn.value }
        #expect(!rendered)
        scheduler.release(held)
        #expect(scheduler.runningPermit(.render) == nil)
    }

    @Test func twoCamerasRenderAtTheSameTimeOnTheirOwnQueueAndFilter() async throws {
        func source() throws -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 3840, 2160, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
            return try #require(buffer)
        }
        let engines = [try #require(CropEngine()), try #require(CropEngine())]
        let sources = [try source(), try source()]
        let size = CGSize(width: 1920, height: 1080)
        // The full 4K frame down to 1080p takes the Lanczos path. Both cameras
        // are in flight together: each render suspends the main actor.
        let tasks = (0..<2).map { index in
            Task { @MainActor in
                var rendered = 0
                for _ in 0..<12 {
                    let output = try await engines[index].renderCrop(sources[index], crop: .fullFrame, outputSize: size)
                    if CVPixelBufferGetWidth(output) == 1920, CVPixelBufferGetHeight(output) == 1080 { rendered += 1 }
                }
                return rendered
            }
        }
        for task in tasks { #expect(try await task.value == 12) }
    }

    @Test func aSkippedTurnDiscardsTheFrameWithoutHolding() async throws {
        let manager = TestHardware.makeCamera(channelID: .b, programOutput: ProgramOutputManager(sinks: []), routed: false)
        let result = await manager.renderProgramFrame(crop: .fullFrame, timestamp: 1) { throw CancellationError() }
        #expect(result == nil)
        #expect(!manager.isProgramHolding)
    }

    @Test func perFrameSmoothingDoesNotPublish() throws {
        let engine = try #require(CropEngine())
        var changes = 0
        let watch = engine.objectWillChange.sink { changes += 1 }
        defer { watch.cancel() }
        engine.applyFrameSmoothing(0.10, operatorSetting: engine.config.transitionSmoothing)
        engine.applyFrameSmoothing(0.25, operatorSetting: engine.config.transitionSmoothing)
        engine.applyFrameSmoothing(0.05, operatorSetting: engine.config.transitionSmoothing)
        #expect(changes == 0)
        #expect(engine.tickInterpolation(now: 1).smoothingFactor == 0.05)
        // Only an operator change reaches the published config.
        engine.applyFrameSmoothing(0.05, operatorSetting: 0.2)
        #expect(changes == 1)
        #expect(engine.config.transitionSmoothing == 0.2)
    }

    @Test func dropsInABurstScheduleOneFlush() {
        let coalescer = CaptureDropCoalescer()
        #expect(coalescer.note(timestamp: 1))
        #expect(!coalescer.note(timestamp: 2))
        #expect(!coalescer.note(timestamp: 3))
        #expect(coalescer.drain().all == [1, 2, 3])
        #expect(coalescer.drain().all.isEmpty)
        #expect(coalescer.note(timestamp: 4))
    }

    @Test func pendingDropsAreBoundedButStillCounted() {
        let coalescer = CaptureDropCoalescer()
        let total = CaptureDropCoalescer.maxPendingTimestamps + 10
        for i in 0..<total { _ = coalescer.note(timestamp: Double(i)) }
        let drained = coalescer.drain()
        #expect(drained.timestamps.count == CaptureDropCoalescer.maxPendingTimestamps)
        #expect(drained.all.count == total)
        #expect(drained.all.last == Double(total - 1))
    }
}
