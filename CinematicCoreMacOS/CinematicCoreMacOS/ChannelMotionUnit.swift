//
//  ChannelMotionUnit.swift
//  CinematicCoreMacOS
//
//  One camera's per-frame loop, off the main thread (D-02 path 2).
//
//  A capture source (the camera's capture queue, or validation-clip playback
//  on that same queue) calls `process` once per frame. The unit reads the
//  newest directive, steps zoom, pan and the spring, renders, picks the frame
//  to show (the new render, or the held one after a failure) and stores it in
//  the frame mailbox. It never waits for the main thread.
//
//  It asks for the main thread in three ways, each a one-slot message:
//  - hand-off: the Program camera's finished frame, for the router and sink;
//  - control: the raw frame, only while the controller has per-frame work
//    (detection, the lock machine, a shot move);
//  - event: rare changes (failed renders, counted; hold starting or ending).
//
//  The lock machine, the composer and commands stay with the controller
//  (`CameraManager`) on the main thread.
//

import CoreGraphics
import CoreVideo
import Foundation
import OSLog
import QuartzCore

/// Where a camera's frames go, read on the capture queue.
nonisolated struct FrameRoute: Sendable, Equatable {
    /// Stamped on a frame when its processing starts; the router refuses a
    /// frame whose generation is no longer current.
    var generation: UInt64
    /// True when this camera feeds the output. Only then is a frame handed to
    /// the main thread.
    var isProgram: Bool
}

/// Why the loop is asking for the main thread.
nonisolated enum MotionMainHop: Sendable, Equatable {
    case handOff
    case control
    case event
}

/// The raw frame and what the controller needs to know about it.
nonisolated struct ControlTick: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: Double
    let arrivedAt: TimeInterval
    let sourceGeneration: UInt64
    let width: Int
    let height: Int
}

/// A finished Program frame on its way to the router, with this frame's
/// timings for the diagnostics the main thread records.
nonisolated struct ProgramHandOff: @unchecked Sendable {
    let frame: RenderedChannelFrame
    let routeGeneration: UInt64
    let postedAt: TimeInterval
    let sourceWidth: Int
    let sourceHeight: Int
    let renderDuration: TimeInterval
    let totalDuration: TimeInterval
    let cropHeightFraction: Double
    /// Source timestamps of the finished frames this one replaced in the
    /// slot before the main thread took them: frames Program never showed.
    let superseded: [Double]
}

/// What happened on the capture queue since the main thread last asked.
/// Bounded: failures are counted, with timestamps kept up to the coalescer's
/// cap, however long the main thread was away.
nonisolated struct MotionEventBatch: Sendable {
    /// Source timestamp of every failed render, oldest first.
    var failedRenders: [Double] = []
    var lastFailureDescription: String?
    var holdChanged = false

    var isEmpty: Bool { failedRenders.isEmpty && !holdChanged }
}

/// Auto Pan's sweep state. Stepped by the loop; tests step it directly.
nonisolated final class AutoPanState: @unchecked Sendable {
    static let pauseDuration: Double = 1.5

    private let lock = NSLock()
    private var phase: CGFloat = 0.5
    private var direction: CGFloat = 1.0
    private var pauseUntil: Double = 0
    private var lastTick: Double = 0

    /// Entering Auto Pan must not count the time spent in another mode.
    func restartClock() {
        lock.lock()
        lastTick = 0
        lock.unlock()
    }

    /// Advance the sweep and return the crop centre x for a crop `width` wide.
    func advance(now: TimeInterval, width: CGFloat, speed: Double, eased: Bool) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        let dt = lastTick > 0 ? min(0.1, max(0, now - lastTick)) : 0
        lastTick = now
        let width = min(1, max(0, width))
        let travel = 1 - width
        if travel > 0.0001, now > pauseUntil {
            phase += CGFloat(speed) * 3 * direction * CGFloat(dt)
            if phase >= 1 {
                phase = 1; direction = -1; pauseUntil = now + Self.pauseDuration
            } else if phase <= 0 {
                phase = 0; direction = 1; pauseUntil = now + Self.pauseDuration
            }
        }
        return width / 2 + AutoPanMotion.position(phase, eased: eased) * travel
    }
}

nonisolated final class ChannelMotionUnit: @unchecked Sendable {
    typealias CropRect = CropEngine.CropRect
    typealias Renderer = @Sendable (CVPixelBuffer, CropRect, CGSize, Bool) throws -> CVPixelBuffer

    private static let logger = Logger(subsystem: "com.alfie", category: "MotionUnit")

    let channelID: ChannelID
    let core: CropMotionCore
    let targets: MotionTargetMailbox
    let frames: ChannelFrameMailbox
    let pan: AutoPanState

    private let render: Renderer
    private let route: @Sendable () -> FrameRoute
    private let clock: @Sendable () -> TimeInterval

    // One-slot messages for the main thread, and its way in.
    private let lock = NSLock()
    private var hop: (@Sendable (MotionMainHop) -> Void)?
    private var pendingHandOff: ProgramHandOff?
    private var handOffHopPending = false
    private let supersededHandOffs = CaptureDropCoalescer()
    private var pendingControlTick: ControlTick?
    private var controlWake = false
    private var controlHopPending = false
    private let failedRenders = CaptureDropCoalescer()
    private var lastFailureDescription: String?
    private var holdChangedPending = false
    private var eventHopPending = false

    // Touched only by the capture source's queue, inside `process`.
    private var loopGeneration: UInt64?
    private var lastWidth = 0
    private var lastHeight = 0
    private var stats = (stored: 0, discarded: 0, lastLogAt: 0.0)

    init(channelID: ChannelID, core: CropMotionCore, targets: MotionTargetMailbox,
         frames: ChannelFrameMailbox, pan: AutoPanState,
         route: @escaping @Sendable () -> FrameRoute,
         clock: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() },
         render: @escaping Renderer) {
        self.channelID = channelID
        self.core = core
        self.targets = targets
        self.frames = frames
        self.pan = pan
        self.route = route
        self.clock = clock
        self.render = render
    }

    /// Install the controller's way onto the main thread. Until then the loop
    /// still renders and stores; it only has nobody to tell.
    func setMainHop(_ hop: @escaping @Sendable (MotionMainHop) -> Void) {
        lock.lock()
        self.hop = hop
        lock.unlock()
    }

    // MARK: The loop

    /// One frame: read the target, step, render, store. Call from one serial
    /// queue per camera. Returns true when a frame was stored.
    @discardableResult
    func process(_ pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        let started = clock()
        let admission = frames.admission
        // A hot unplug retires the generation but keeps the session running so
        // the output holds and then sends standby. A buffer the stopping
        // session still delivers must not be rendered, sent, or replace the
        // cleared hold.
        guard admission.isRunning, !admission.sourceMissing else { return false }
        // Stamp the route now: if roles change while this frame renders, the
        // router refuses it on arrival.
        let route = self.route()

        // The wide pane's raw pixels, before any processing.
        guard frames.storeSource(pixelBuffer, sourceGeneration: admission.sourceGeneration) else { return false }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var formatChanged = false
        if loopGeneration != admission.sourceGeneration || width != lastWidth || height != lastHeight {
            loopGeneration = admission.sourceGeneration
            lastWidth = width
            lastHeight = height
            formatChanged = true
            // The floor follows the delivered pixels, before the first step.
            if height > 0 { core.setDeliveredQualityFloor(.forSource(height: height)) }
        }
        // A size the controller has not applied yet: the directive still
        // carries the previous size's aspect and wide target.
        let formatKnown = admission.formatWidth == width && admission.formatHeight == height

        // The controller's per-frame work, if it has any. Never awaited.
        if admission.controlWanted || formatChanged || !formatKnown {
            postControl(ControlTick(pixelBuffer: pixelBuffer, timestamp: timestamp, arrivedAt: started,
                                    sourceGeneration: admission.sourceGeneration, width: width, height: height))
        }
        // No frame with the wrong aspect is rendered, stored or handed to
        // Program. The first frame or two of a new size wait here for the
        // controller's one turn; the wide pane already has the raw frame.
        guard formatKnown else { return discard() }

        let snapshot = step(now: clock())

        let renderStart = clock()
        let result: Result<CVPixelBuffer, Error>
        do {
            result = .success(try render(pixelBuffer, snapshot.crop, snapshot.outputSize, snapshot.highQuality))
        } catch {
            result = .failure(error)
        }
        let renderDuration = clock() - renderStart
        core.recordRender(renderTime: renderDuration)

        // A command, a retarget, a stop or a rebind during the render retires
        // this frame; the hold state is left as it was.
        let after = frames.admission
        guard after.sourceGeneration == admission.sourceGeneration,
              after.detectionGeneration == admission.detectionGeneration,
              after.controlEpoch == admission.controlEpoch,
              after.isRunning else {
            return discard()
        }

        // The new render, or after a failure the last good frame. Refused
        // for a retired generation in the same locked step as the choice, so
        // a retired frame cannot refill a hold the main thread just reset.
        let rendered: CVPixelBuffer?
        switch result {
        case .success(let buffer):
            rendered = buffer
        case .failure(let error):
            rendered = nil
            noteFailedRender(timestamp: timestamp, description: error.localizedDescription)
        }
        guard let selection = frames.selectProgram(rendered: rendered, crop: rendered == nil ? nil : snapshot.crop,
                                                   sourceGeneration: admission.sourceGeneration) else {
            return discard()
        }
        if selection.holdingChanged { noteHoldChanged() }
        let isHolding = selection.isHolding
        guard let chosen = selection.buffer else { return discard() }

        let renderedAt = clock()
        let crop = selection.crop ?? snapshot.crop
        let frame = RenderedChannelFrame(
            channelID: channelID,
            revisions: admission.revisions,
            sourceTimestamp: timestamp,
            processingStartedAt: started,
            renderedAt: renderedAt,
            crop: crop,
            outputSize: snapshot.outputSize,
            isRepeat: isHolding,
            pixelBuffer: chosen)
        guard frames.store(frame) else { return discard() }
        stats.stored += 1
        logStatsIfDue(chosen, now: renderedAt)

        // Only Program reaches the main thread, once per frame.
        if route.isProgram {
            postHandOff(frame: frame, routeGeneration: route.generation, postedAt: renderedAt,
                        width: width, height: height, renderDuration: renderDuration,
                        totalDuration: renderedAt - started,
                        cropHeightFraction: Double(snapshot.crop.size.height))
        }
        return true
    }

    /// Zoom, target and spring for one frame, as one locked step on the live
    /// state. The directive is read inside the step, so it and the state
    /// belong to the same side of any main-thread transaction.
    private func step(now: TimeInterval) -> CropMotionCore.Snapshot {
        core.step { state in
            let directive = targets.read()
            state.zoomUsesTopAnchor = directive.zoomUsesTopAnchor
            state.advanceZoom(now: now, aspect: directive.aspect)
            if let smoothing = directive.smoothing {
                if let boost = directive.boost, now < boost.until {
                    state.liveSmoothing = boost.smoothing
                } else {
                    state.liveSmoothing = smoothing
                }
            }
            switch directive.mode {
            case .wide(let target):
                state.setTargetCrop(target)
            case .tracking:
                if directive.trackingSerial != state.appliedTargetSerial {
                    state.appliedTargetSerial = directive.trackingSerial
                    if let target = directive.trackingTarget { state.setTargetCrop(target) }
                }
            case .manual(let center):
                let size = directive.cropSize(adjustedHeight: state.adjustedHeight)
                state.setTargetCrop(Self.manualCrop(center: center, size: size))
            case .autoPan(let speed, let height, let eased):
                let size = directive.cropSize(adjustedHeight: state.adjustedHeight)
                let legal = CropRect(center: CGPoint(x: 0.5, y: 0.5), size: size)
                    .clampedToQualityFloor(state.qualityFloor).clamped()
                let centerX = pan.advance(now: now, width: legal.size.width, speed: speed, eased: eased)
                state.placePan(center: CGPoint(x: centerX, y: height), baseSize: size)
            }
            return state.tick(now: now)
        }
    }

    static func manualCrop(center: CGPoint, size: CGSize) -> CropRect {
        CropRect(origin: CGPoint(x: center.x - size.width / 2.0, y: center.y - size.height / 2.0),
                 size: size).clamped()
    }

    private func discard() -> Bool {
        stats.discarded += 1
        logStatsIfDue(nil, now: clock())
        return false
    }

    /// One line per camera every 5 s: frames stored for Preview and the
    /// router, or discarded (retired session, stopped, no render), so a
    /// console showing no picture can be told apart from a pipeline producing
    /// none.
    private func logStatsIfDue(_ buffer: CVPixelBuffer?, now: TimeInterval) {
        guard now - stats.lastLogAt >= 5 else { return }
        stats.lastLogAt = now
        let level = buffer.map(CameraManager.sampledLevel) ?? -1
        let stored = stats.stored
        let discarded = stats.discarded
        let running = frames.admission.isRunning
        Self.logger.notice("[RENDER] ch=\(self.channelID.letter, privacy: .public) published=\(stored) discarded=\(discarded) level=\(level, format: .fixed(precision: 1)) running=\(running)")
        stats.stored = 0
        stats.discarded = 0
    }

    // MARK: Messages to the main thread

    private func send(_ kind: MotionMainHop) {
        lock.lock()
        let hop = self.hop
        lock.unlock()
        hop?(kind)
    }

    private func postHandOff(frame: RenderedChannelFrame, routeGeneration: UInt64, postedAt: TimeInterval,
                             width: Int, height: Int, renderDuration: TimeInterval,
                             totalDuration: TimeInterval, cropHeightFraction: Double) {
        lock.lock()
        // A frame still in the slot is one Program never showed: counted,
        // with its timestamp, for the hand-off that does get through.
        if let replaced = pendingHandOff { _ = supersededHandOffs.note(timestamp: replaced.frame.sourceTimestamp) }
        pendingHandOff = ProgramHandOff(
            frame: frame, routeGeneration: routeGeneration, postedAt: postedAt,
            sourceWidth: width, sourceHeight: height, renderDuration: renderDuration,
            totalDuration: totalDuration, cropHeightFraction: cropHeightFraction,
            superseded: [])
        let needsHop = !handOffHopPending
        handOffHopPending = true
        lock.unlock()
        if needsHop { send(.handOff) }
    }

    /// Main thread: the newest Program frame not yet handed on, if any, with
    /// the timestamps of the frames it replaced.
    func takeHandOff() -> ProgramHandOff? {
        lock.lock()
        defer { lock.unlock() }
        handOffHopPending = false
        guard let item = pendingHandOff else { return nil }
        pendingHandOff = nil
        return ProgramHandOff(
            frame: item.frame, routeGeneration: item.routeGeneration, postedAt: item.postedAt,
            sourceWidth: item.sourceWidth, sourceHeight: item.sourceHeight,
            renderDuration: item.renderDuration, totalDuration: item.totalDuration,
            cropHeightFraction: item.cropHeightFraction, superseded: supersededHandOffs.drain().all)
    }

    /// Main thread: true while a message is waiting for it (test seam).
    var hasPendingMainWork: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handOffHopPending || controlHopPending || eventHopPending
    }

    private func postControl(_ tick: ControlTick) {
        lock.lock()
        pendingControlTick = tick
        let needsHop = !controlHopPending
        controlHopPending = true
        lock.unlock()
        if needsHop { send(.control) }
    }

    /// Main thread: ask for a control turn with no new frame (a detection
    /// finished). Returns true when the caller must start the turn itself.
    func requestControlWake() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        controlWake = true
        let needsStart = !controlHopPending
        controlHopPending = true
        return needsStart
    }

    /// Main thread: the next control turn's input. `hasWork` false means the
    /// slot is empty and a later post will ask for the main thread again.
    func takeControl() -> (hasWork: Bool, tick: ControlTick?) {
        lock.lock()
        defer { lock.unlock() }
        let tick = pendingControlTick
        let wake = controlWake
        pendingControlTick = nil
        controlWake = false
        guard tick != nil || wake else {
            controlHopPending = false
            return (false, nil)
        }
        return (true, tick)
    }

    private func noteFailedRender(timestamp: Double, description: String) {
        _ = failedRenders.note(timestamp: timestamp)
        requestEventHop { lastFailureDescription = description }
    }

    private func noteHoldChanged() {
        requestEventHop { holdChangedPending = true }
    }

    private func requestEventHop(_ record: () -> Void) {
        lock.lock()
        record()
        let needsHop = !eventHopPending
        eventHopPending = true
        lock.unlock()
        if needsHop { send(.event) }
    }

    /// Main thread: what happened since the last call. Bounded however long
    /// the main thread was away: failures are counted, not queued one by one.
    func takeEvents() -> MotionEventBatch {
        lock.lock()
        defer { lock.unlock() }
        let batch = MotionEventBatch(failedRenders: failedRenders.drain().all,
                                     lastFailureDescription: lastFailureDescription,
                                     holdChanged: holdChangedPending)
        lastFailureDescription = nil
        holdChangedPending = false
        eventHopPending = false
        return batch
    }
}
