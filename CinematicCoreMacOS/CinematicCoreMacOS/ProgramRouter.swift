//
//  ProgramRouter.swift
//  CinematicCoreMacOS
//
//  The only component that decides which channel feeds the show output
//  (ROUTER card; docs/ALFIE_MULTICAMERA_SPEC.md "Message and time model",
//  "Lifecycle and routing state machine").
//
//  - Exactly one ProgramOutputManager, owned by the show. Channels reach it
//    only through a `RouterChannelPort`, which asks the router at call time
//    whether its channel is Program; nothing is re-wired on a role change.
//  - One monotonic output clock, independent of source timestamps: every
//    frame sent downstream (including repeats and standby) gets a strictly
//    increasing host-clock timestamp, so a Take can never move time backward.
//  - A route generation gates sends. A frame submitted under an older
//    generation (before a role change) is dropped, never shown late.
//  - Program source loss: after `sourceLossAfter` without a Program frame the
//    router repeats the last good rendered frame for `holdDuration` (labelled
//    hold), then sends a generated black standby frame at the show rate. It
//    never switches to another channel on its own and never sends raw pixels.
//    Fresh frames from the same Program channel (after an explicit restart)
//    resume the route.
//  - Render faults inside a channel are still that channel's HOLD (it
//    re-sends its own last good render, flagged as a repeat).
//

import CoreVideo
import Foundation
import QuartzCore

final class ProgramRouter {

    enum State: Equatable {
        /// Output not started, or started and waiting for the first frame.
        case idle
        case routed
        /// Repeating the last good frame since `since` (host time).
        case holding(since: TimeInterval)
        /// Sending the generated black standby frame.
        case standby
    }

    static let sourceLossAfter: TimeInterval = 0.5
    static let holdDuration: TimeInterval = 2.0

    let output: ProgramOutputManager
    private(set) var programChannel: ChannelID
    /// Increments on every role change; sends are gated on it.
    private(set) var routeGeneration: UInt64 = 0
    private(set) var state: State = .idle
    private(set) var lastOutputTimestamp: Double = 0
    /// Frames offered by non-Program channels or stale generations (dropped).
    private(set) var framesNotRouted = 0

    /// Host clock; injectable so tests can drive hold / standby timing.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    private var isOutputStarted = false
    private var lastProgramFrameAt: TimeInterval = 0
    private var lastGoodBuffer: CVPixelBuffer?
    private var standbyBuffer: CVPixelBuffer?
    private var watchdog: Timer?
    private var faultTicker: Timer?
    private var ports: [ChannelID: RouterChannelPort] = [:]

    init(output: ProgramOutputManager, programChannel: ChannelID = .a) {
        self.output = output
        self.programChannel = programChannel
    }

    func isProgram(_ channel: ChannelID) -> Bool { channel == programChannel }

    /// The port a channel uses for everything it tells the show.
    func port(for channel: ChannelID) -> RouterChannelPort {
        if let existing = ports[channel] { return existing }
        let port = RouterChannelPort(channelID: channel, router: self)
        ports[channel] = port
        return port
    }

    /// What the Program pane and status should say about the routed output.
    var programStatus: ConsoleSnapshot.ProgramOutput {
        switch state {
        case .idle, .routed:
            return .routed
        case .holding(let since):
            let remaining = max(0, Self.holdDuration - (clock() - since))
            return .holding(standbyIn: Int(remaining.rounded(.up)))
        case .standby:
            return .standby
        }
    }

    // MARK: Output lifecycle (driven by the Program channel only)

    func channelStarted(_ channel: ChannelID) {
        guard isProgram(channel) else { return }
        output.start()
        isOutputStarted = true
        state = .idle
        lastProgramFrameAt = 0
        lastGoodBuffer = nil
        startWatchdog()
    }

    func channelStopped(_ channel: ChannelID) {
        guard isProgram(channel) else { return }
        stopTimers()
        output.stop()
        isOutputStarted = false
        state = .idle
        lastGoodBuffer = nil
    }

    func updateCaptureStatus(_ channel: ChannelID, isRunning: Bool) {
        guard isProgram(channel) else { return }
        output.updateCaptureStatus(isRunning: isRunning)
    }

    // MARK: Frames

    /// A channel offers a rendered frame. Only the Program channel under the
    /// current route generation reaches the output.
    func submit(_ buffer: CVPixelBuffer, from channel: ChannelID, isRepeat: Bool,
                routeGeneration generation: UInt64) {
        guard isOutputStarted, isProgram(channel), generation == routeGeneration else {
            framesNotRouted += 1
            return
        }
        lastProgramFrameAt = clock()
        lastGoodBuffer = buffer
        if state != .routed {
            if state != .idle { output.noteDiagnostics("program source restored") }
            state = .routed
            stopFaultTicker()
        }
        send(buffer, isRepeat: isRepeat)
    }

    /// Strictly increasing host-clock timestamp for the next output frame.
    func nextOutputTimestamp() -> Double {
        let timestamp = max(clock(), lastOutputTimestamp + 0.0005)
        lastOutputTimestamp = timestamp
        return timestamp
    }

    private func send(_ buffer: CVPixelBuffer, isRepeat: Bool) {
        output.sendFrame(buffer, timestamp: nextOutputTimestamp(), isRepeat: isRepeat)
    }

    // MARK: Roles

    /// Make `channel` Program. Used by Take (TAKE card), which validates the
    /// candidate first; the router only refuses a stale request. Never called
    /// automatically on a fault.
    @discardableResult
    func setProgram(_ channel: ChannelID, expectedRouteGeneration: UInt64) -> Bool {
        guard expectedRouteGeneration == routeGeneration else { return false }
        programChannel = channel
        routeGeneration &+= 1
        return true
    }

    /// Take commit (TAKE card): send `frame` from `channel` as the next
    /// output frame; only if the sink accepts it do the roles change. Refused
    /// when the request was made under an older route generation, when the
    /// output is not running, or when the sink refuses — old roles are kept.
    func commitTake(_ frame: RenderedChannelFrame, to channel: ChannelID,
                    expectedRouteGeneration: UInt64) -> Bool {
        guard isOutputStarted, expectedRouteGeneration == routeGeneration,
              frame.channelID == channel, !isProgram(channel) else { return false }
        guard output.sendFrameAccepted(frame.pixelBuffer, timestamp: nextOutputTimestamp(), isRepeat: false) else {
            return false
        }
        programChannel = channel
        routeGeneration &+= 1
        lastGoodBuffer = frame.pixelBuffer
        lastProgramFrameAt = clock()
        state = .routed
        stopFaultTicker()
        output.noteDiagnostics("take → \(channel.cameraLabel)")
        return true
    }

    // MARK: Source loss (hold → standby)

    /// Checks the Program source's freshness. Called by the watchdog (10 Hz)
    /// and on every fault tick; public for tests with an injected clock.
    func checkSourceHealth() {
        guard isOutputStarted, lastProgramFrameAt > 0 else { return }
        let now = clock()
        switch state {
        case .routed where now - lastProgramFrameAt > Self.sourceLossAfter:
            state = .holding(since: now)
            output.noteDiagnostics("program source lost: holding last good frame")
            startFaultTicker()
        case .holding(let since) where now - since >= Self.holdDuration:
            state = .standby
            output.noteDiagnostics("program source missing: standby")
        default:
            break
        }
    }

    /// One output tick during a source fault: repeat the last good frame
    /// while holding, the generated black frame in standby.
    func faultTick() {
        checkSourceHealth()
        switch state {
        case .holding:
            if let lastGoodBuffer { send(lastGoodBuffer, isRepeat: true) }
        case .standby:
            if let standby = standbyFrame() { send(standby, isRepeat: true) }
        case .idle, .routed:
            break
        }
    }

    /// Black frame the size of the last Program frame (1920×1080 if none).
    private func standbyFrame() -> CVPixelBuffer? {
        let width = lastGoodBuffer.map(CVPixelBufferGetWidth) ?? 1920
        let height = lastGoodBuffer.map(CVPixelBufferGetHeight) ?? 1080
        if let standbyBuffer,
           CVPixelBufferGetWidth(standbyBuffer) == width, CVPixelBufferGetHeight(standbyBuffer) == height {
            return standbyBuffer
        }
        standbyBuffer = Self.makeBlackFrame(width: width, height: height)
        return standbyBuffer
    }

    nonisolated static func makeBlackFrame(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // BGRA black, opaque: B=G=R=0, A=255.
        for row in 0..<height {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            for column in 0..<width { pixels[column] = UInt32(0xFF00_0000).littleEndian }
        }
        return buffer
    }

    // MARK: Timers

    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSourceHealth() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func startFaultTicker() {
        guard faultTicker == nil else { return }
        let period = 1 / ShowStandard.activeOrCurrent.frameRate
        let timer = Timer(timeInterval: period, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.faultTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        faultTicker = timer
    }

    private func stopFaultTicker() {
        faultTicker?.invalidate()
        faultTicker = nil
    }

    private func stopTimers() {
        watchdog?.invalidate()
        watchdog = nil
        stopFaultTicker()
    }
}

/// A channel's seam to the show through the router. Frames and output
/// lifecycle go to the router; telemetry reaches the show diagnostics only
/// while this channel is Program (the diagnostics describe the routed feed).
final class RouterChannelPort: ChannelOutputPort {
    let channelID: ChannelID
    private unowned let router: ProgramRouter

    init(channelID: ChannelID, router: ProgramRouter) {
        self.channelID = channelID
        self.router = router
    }

    private var isProgram: Bool { router.isProgram(channelID) }
    private var output: ProgramOutputManager { router.output }

    var diagnosticsFileName: String? {
        isProgram ? output.diagnosticsFileName : "not recorded: \(channelID.cameraLabel) is not Program"
    }

    func start() { router.channelStarted(channelID) }
    func stop() { router.channelStopped(channelID) }
    func updateCaptureStatus(isRunning: Bool) { router.updateCaptureStatus(channelID, isRunning: isRunning) }

    var routeGeneration: UInt64 { router.routeGeneration }

    func submitFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool, routeGeneration: UInt64) {
        // Source timestamps are not passed downstream; the router restamps.
        router.submit(pixelBuffer, from: channelID, isRepeat: isRepeat, routeGeneration: routeGeneration)
    }

    func sendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, isRepeat: Bool) {
        submitFrame(pixelBuffer, timestamp: timestamp, isRepeat: isRepeat, routeGeneration: router.routeGeneration)
    }

    func beginDiagnosticsSessionIfNeeded(note: String) { if isProgram { output.beginDiagnosticsSessionIfNeeded(note: note) } }
    func noteDetectionStartIfNeeded() { if isProgram { output.noteDetectionStartIfNeeded() } }
    func noteDiagnostics(_ text: String) { if isProgram { output.noteDiagnostics(text) } }
    func recordSourceIdentity(_ source: DiagnosticsSessionIdentity.Source) { if isProgram { output.recordSourceIdentity(source) } }
    func recordDeliveredDimensions(width: Int, height: Int) { if isProgram { output.recordDeliveredDimensions(width: width, height: height) } }
    func recordInputFrame(timestamp: Double) { if isProgram { output.recordInputFrame(timestamp: timestamp) } }
    func recordMainActorHop(_ seconds: TimeInterval) { if isProgram { output.recordMainActorHop(seconds) } }
    func recordDetectionTiming(queueWait: TimeInterval, visionWall: TimeInterval) {
        if isProgram { output.recordDetectionTiming(queueWait: queueWait, visionWall: visionWall) }
    }
    func recordObservationAge(_ age: TimeInterval) { if isProgram { output.recordObservationAge(age) } }
    func recordLatency(stage: ProgramOutputManager.LatencyStage, duration: TimeInterval, timestamp: TimeInterval) {
        if isProgram { output.recordLatency(stage: stage, duration: duration, timestamp: timestamp) }
    }
    func recordDroppedFrame(timestamp: Double, reason: String, stage: ProgramOutputManager.DropStage) {
        if isProgram { output.recordDroppedFrame(timestamp: timestamp, reason: reason, stage: stage) }
    }
    func recordGateDropTotal(_ total: UInt64) { if isProgram { output.recordGateDropTotal(total) } }
    func recordFramePathCounts(detectedPersons: Int) { if isProgram { output.recordFramePathCounts(detectedPersons: detectedPersons) } }
    func recordPictureQuality(sourceHeight: Int, cropHeightFraction: Double, outputHeight: Int) {
        if isProgram { output.recordPictureQuality(sourceHeight: sourceHeight, cropHeightFraction: cropHeightFraction, outputHeight: outputHeight) }
    }
}
