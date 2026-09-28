//
//  ProgramRouterTests.swift
//  CinematicCoreMacOSTests
//
//  ROUTER card: one output fed only by Program under the current route
//  generation; a monotonic output clock independent of source time; source
//  loss holds the last good frame (labelled) then sends standby, never
//  switching channels; B failing leaves A; the destination is frozen per show.
//

import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
private final class RouterFakeSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route
    var available = true { didSet { onStateChange?() } }
    private(set) var sent: [(buffer: CVPixelBuffer, timestamp: Double)] = []
    var isAvailable: Bool { available }
    var summary: String { "fake" }
    var detail: String { "fake" }
    var lastErrorDescription: String? { nil }
    var onStateChange: (() -> Void)?

    init(route: ProgramOutputManager.Route) { self.route = route }

    func connect() {}
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        sent.append((pixelBuffer, timestamp))
        return true
    }
}

@MainActor
struct ProgramRouterTests {
    private final class Clock { var now: TimeInterval = 1000 }

    private func buffer(_ width: Int = 64, _ height: Int = 36) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }

    /// Router over a manager with one display sink, output started by A.
    private func routedRouter() -> (ProgramRouter, RouterFakeSink, Clock) {
        let sink = RouterFakeSink(route: .display)
        let output = ProgramOutputManager(sinks: [sink])
        let router = ProgramRouter(output: output)
        let clock = Clock()
        router.clock = { clock.now }
        router.port(for: .a).start()
        router.port(for: .a).updateCaptureStatus(isRunning: true)
        return (router, sink, clock)
    }

    @Test func onlyProgramReachesTheOutput() throws {
        let (router, sink, _) = routedRouter()
        router.port(for: .b).sendFrame(try buffer(), timestamp: 1)
        #expect(sink.sent.isEmpty)
        #expect(router.framesNotRouted == 1)
        router.port(for: .a).sendFrame(try buffer(), timestamp: 1)
        #expect(sink.sent.count == 1)
        #expect(router.state == .routed)
    }

    @Test func outputClockIsMonotonicAndIgnoresSourceTime() throws {
        let (router, sink, clock) = routedRouter()
        let a = router.port(for: .a)
        // Source timestamps jump backwards (e.g. a camera restart); host time stalls.
        a.sendFrame(try buffer(), timestamp: 500)
        a.sendFrame(try buffer(), timestamp: 10)
        clock.now -= 5
        a.sendFrame(try buffer(), timestamp: 20)
        let stamps = sink.sent.map(\.timestamp)
        #expect(stamps.count == 3)
        #expect(zip(stamps, stamps.dropFirst()).allSatisfy { $0 < $1 })
        #expect(!stamps.contains(500) && !stamps.contains(10))
    }

    @Test func frameStampedBeforeARoleChangeIsRefused() throws {
        let (router, sink, _) = routedRouter()
        let stamped = router.port(for: .a).routeGeneration
        #expect(router.setProgram(.a, expectedRouteGeneration: stamped))   // any role change bumps the generation
        router.port(for: .a).submitFrame(try buffer(), timestamp: 1, isRepeat: false, routeGeneration: stamped)
        #expect(sink.sent.isEmpty)
        #expect(router.framesNotRouted == 1)
    }

    @Test func staleRoleChangeRequestIsRefused() {
        let (router, _, _) = routedRouter()
        let generation = router.routeGeneration
        #expect(router.setProgram(.b, expectedRouteGeneration: generation))
        #expect(!router.setProgram(.a, expectedRouteGeneration: generation))
        #expect(router.programChannel == .b)
    }

    @Test func sourceLossHoldsThenStandsByAndNeverSwitches() throws {
        let (router, sink, clock) = routedRouter()
        let last = try buffer()
        router.port(for: .a).sendFrame(last, timestamp: 1)

        clock.now += ProgramRouter.sourceLossAfter + 0.1
        router.checkSourceHealth()
        guard case .holding = router.state else { Issue.record("expected hold, got \(router.state)"); return }
        #expect(router.programStatus == .holding(standbyIn: 2))
        router.faultTick()
        #expect(sink.sent.last?.buffer === last)          // repeats the last good frame

        clock.now += ProgramRouter.holdDuration + 0.1
        router.faultTick()
        #expect(router.state == .standby)
        #expect(router.programStatus == .standby)
        let standby = try #require(sink.sent.last?.buffer)
        #expect(standby !== last)                          // generated black frame
        #expect(CVPixelBufferGetWidth(standby) == 64 && CVPixelBufferGetHeight(standby) == 36)

        // Preview frames never fill the gap.
        router.port(for: .b).sendFrame(try buffer(), timestamp: 2)
        #expect(sink.sent.last?.buffer === standby)
        #expect(router.programChannel == .a)
    }

    @Test func freshProgramFramesAfterRestartResumeTheSameRoute() throws {
        let (router, sink, clock) = routedRouter()
        router.port(for: .a).sendFrame(try buffer(), timestamp: 1)
        clock.now += 5
        router.faultTick()                       // → hold
        clock.now += ProgramRouter.holdDuration + 0.1
        router.faultTick()                       // → standby
        #expect(router.state == .standby)
        let fresh = try buffer()
        router.port(for: .a).sendFrame(fresh, timestamp: 0.1)
        #expect(router.state == .routed)
        #expect(sink.sent.last?.buffer === fresh)
        #expect(router.programChannel == .a)
    }

    @Test func standbyFrameIsOpaqueBlack() throws {
        let frame = try #require(ProgramRouter.makeBlackFrame(width: 4, height: 2))
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let pixel = try #require(CVPixelBufferGetBaseAddress(frame)).assumingMemoryBound(to: UInt8.self)
        #expect([pixel[0], pixel[1], pixel[2], pixel[3]] == [0, 0, 0, 255])
    }

    @Test func previewStoppingLeavesProgramRunning() throws {
        let (router, sink, _) = routedRouter()
        router.port(for: .b).start()
        router.port(for: .b).stop()
        router.port(for: .a).sendFrame(try buffer(), timestamp: 1)
        #expect(sink.sent.count == 1)
        #expect(router.output.activeRoute == .display)
    }

    @Test func previewTelemetryNeverReachesShowDiagnostics() {
        let (router, _, _) = routedRouter()
        let b = router.port(for: .b)
        b.recordDroppedFrame(timestamp: 1, reason: "B", stage: .renderFailed)
        b.recordInputFrame(timestamp: 1)
        #expect(router.output.droppedFrames == 0)
        #expect(b.diagnosticsFileName?.contains("not Program") == true)
    }

    // MARK: Destination frozen per show

    @Test func missingDestinationMidShowPausesInsteadOfFallingBack() {
        let display = RouterFakeSink(route: .display)
        let virtual = RouterFakeSink(route: .virtualCamera)
        let output = ProgramOutputManager(sinks: [virtual, display])
        output.preferredRoute = .display
        output.start()
        output.updateCaptureStatus(isRunning: true)
        #expect(output.activeRoute == .display)

        display.available = false
        #expect(output.activeRoute == nil)             // not the virtual camera
        display.available = true
        #expect(output.activeRoute == .display)        // same endpoint resumes
        output.stop()
    }

    @Test func destinationChangeAppliesToTheNextShow() {
        let display = RouterFakeSink(route: .display)
        let virtual = RouterFakeSink(route: .virtualCamera)
        let output = ProgramOutputManager(sinks: [virtual, display])
        output.preferredRoute = .display
        output.start()
        output.updateCaptureStatus(isRunning: true)
        output.preferredRoute = .virtualCamera
        #expect(output.activeRoute == .display)
        output.stop()
        output.start()
        output.updateCaptureStatus(isRunning: true)
        #expect(output.activeRoute == .virtualCamera)
        output.stop()
    }
}
