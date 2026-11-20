//
//  HostFrameQueue.swift
//  CinematicCore
//
//  F-03: the extension's queue of Program frames received from the host.
//  Compiled into the app and the extension (Shared/), so its rules are unit
//  tested in the app's test module without the extension running.
//

import Foundation
import IOSurface

/// Which frame transport the host and the extension agreed on. The host sends
/// its version with `negotiateFrameTransport`; the extension replies with the
/// version it accepted, or `refused`. A host that gets no reply sends no frames.
nonisolated enum FrameTransport {
    /// Frames carry the IOSurface object over XPC (secure coding), so the
    /// extension holds its own reference. The only accepted version.
    static let surfaceObject = 1
    /// The extension's reply when it does not support the host's version.
    static let refused = 0

    /// The extension's rule: accept exactly the surface-object transport.
    static func accept(hostVersion: Int) -> Int {
        hostVersion == surfaceObject ? surfaceObject : refused
    }
}

/// What the extension accepts from the host before it queues a frame.
nonisolated enum HostFrameValidation {
    static let minFrameDimension: Int32 = 16
    static let maxFrameDimension: Int32 = 4096
    static let maxFrameArea: Int64 = 4096 * 4096
    /// The only pixel format the stream advertises.
    static let pixelFormat: OSType = 0x42475241 // kCVPixelFormatType_32BGRA, 'BGRA'

    static func acceptsMetadata(timestamp: Double, width: Int32, height: Int32) -> Bool {
        guard timestamp.isFinite,
              timestamp >= 0,
              width >= minFrameDimension,
              height >= minFrameDimension,
              width <= maxFrameDimension,
              height <= maxFrameDimension else {
            return false
        }
        return Int64(width) * Int64(height) <= maxFrameArea
    }

    /// The metadata must be acceptable and must describe the surface that
    /// actually arrived: its size and its pixel format.
    static func accepts(_ frame: HostFrame) -> Bool {
        acceptsMetadata(timestamp: frame.timestamp, width: frame.width, height: frame.height)
            && IOSurfaceGetWidth(frame.surface) == Int(frame.width)
            && IOSurfaceGetHeight(frame.surface) == Int(frame.height)
            && IOSurfaceGetPixelFormat(frame.surface) == pixelFormat
    }
}

/// A frame the extension holds: the surface, retained by this value, plus
/// the metadata the host sent with it.
nonisolated struct HostFrame {
    let surface: IOSurface
    let timestamp: Double
    let width: Int32
    let height: Int32
}

/// Thread-safe queue for incoming frames from XPC.
///
/// A lock-guarded class rather than an actor on purpose: the playout timer
/// drains it synchronously on its own serial queue. Both enqueue and drain are
/// O(1) work; a lock is the honest primitive here.
///
/// Every surface in the queue, and the one most recently handed to the
/// stream, is marked in use (`IOSurfaceIncrementUseCount`). The use count is
/// what tells the host's CoreVideo pool not to re-vend a surface this process
/// may still be reading. Each count is released exactly once: when a frame is
/// dropped, when a newer frame replaces the presented one, or on `clear()`.
nonisolated final class HostFrameQueue: @unchecked Sendable {
    private var frames: [HostFrame] = []
    /// The last frame handed out by `drainToLatest`. Held, with its use
    /// count, until the next drain or `clear()`, so the frame the stream was
    /// given stays protected for one playout interval.
    private var presented: HostFrame?
    private let maxQueueSize: Int
    private let lock = NSLock()

    init(maxQueueSize: Int = 5) {
        self.maxQueueSize = max(1, maxQueueSize)
        frames.reserveCapacity(self.maxQueueSize + 1)
    }

    /// Adds a frame, marking its surface in use. Returns the number of older
    /// frames dropped to stay within the cap.
    @discardableResult
    func enqueue(_ frame: HostFrame) -> Int {
        lock.lock()
        defer { lock.unlock() }
        IOSurfaceIncrementUseCount(frame.surface)
        frames.append(frame)
        var dropped = 0
        while frames.count > maxQueueSize {
            IOSurfaceDecrementUseCount(frames.removeFirst().surface)
            dropped += 1
        }
        return dropped
    }

    /// Returns the newest frame and discards everything older. The returned
    /// frame becomes the presented frame and keeps its use count until the
    /// next drain or `clear()`; the previously presented frame is released.
    /// An empty queue leaves the presented frame in place.
    func drainToLatest() -> (frame: HostFrame, discarded: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let latest = frames.last else { return nil }
        let discarded = frames.count - 1
        for stale in frames.dropLast() { IOSurfaceDecrementUseCount(stale.surface) }
        frames.removeAll(keepingCapacity: true)
        if let previous = presented { IOSurfaceDecrementUseCount(previous.surface) }
        presented = latest
        return (latest, discarded)
    }

    /// Releases every queued frame and the presented frame.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        for frame in frames { IOSurfaceDecrementUseCount(frame.surface) }
        frames.removeAll(keepingCapacity: true)
        if let previous = presented { IOSurfaceDecrementUseCount(previous.surface) }
        presented = nil
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    var hasPresentedFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return presented != nil
    }

    deinit {
        for frame in frames { IOSurfaceDecrementUseCount(frame.surface) }
        if let presented { IOSurfaceDecrementUseCount(presented.surface) }
    }
}

/// Host side of the frame-transport agreement, per XPC connection. A reply
/// from a retired connection cannot authorize frames on a new one. A refused
/// or unanswered negotiation is final for that connection: the host sends no
/// frames until a new connection is made.
nonisolated struct FrameTransportHandshake: Equatable {
    enum State: Equatable {
        case idle
        case pending(since: TimeInterval)
        case agreed
        /// The extension answered with a version this host does not send.
        case refused
        /// No answer in time: most likely an extension older than F-03,
        /// which does not know the negotiation message and drops it.
        case noReply
    }

    /// How long the host waits for the extension's answer.
    static let replyTimeout: TimeInterval = 3

    private(set) var generation: UInt64 = 0
    private(set) var state: State = .idle

    /// Sends the negotiation through `send` when one is due on this
    /// connection, and starts the reply timeout only once it was sent.
    /// `send` returns false when it could not send (no remote proxy); the
    /// state then stays idle, so the next call tries again and nothing can
    /// expire into a false `noReply`. Returns true when it sent.
    ///
    /// The reply arrives later on the MainActor, after this returns, so the
    /// pending state is in place before `complete` can run.
    mutating func negotiateIfDue(generation: UInt64, now: TimeInterval, send: () -> Bool) -> Bool {
        if self.generation != generation {
            self.generation = generation
            state = .idle
        }
        guard state == .idle, send() else { return false }
        state = .pending(since: now)
        return true
    }

    mutating func complete(generation: UInt64, acceptedVersion: Int) {
        guard generation == self.generation, case .pending = state else { return }
        state = acceptedVersion == FrameTransport.surfaceObject ? .agreed : .refused
    }

    /// Turns a pending negotiation into `noReply` once the timeout has
    /// passed. Returns true only on that change.
    mutating func expireIfDue(now: TimeInterval) -> Bool {
        guard case .pending(let since) = state, now - since >= Self.replyTimeout else { return false }
        state = .noReply
        return true
    }

    func isReady(generation: UInt64) -> Bool {
        self.generation == generation && state == .agreed
    }

    /// The extension cannot take this host's frames on this connection.
    func isMismatched(generation: UInt64) -> Bool {
        self.generation == generation && (state == .refused || state == .noReply)
    }
}
