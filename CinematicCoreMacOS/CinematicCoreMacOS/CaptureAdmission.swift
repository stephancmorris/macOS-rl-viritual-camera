//
//  CaptureAdmission.swift
//  CinematicCoreMacOS
//

import AVFoundation
import CoreVideo
import Foundation
import OSLog
import QuartzCore

/// `CVPixelBuffer` is not `Sendable`. The frame path hands this box across a
/// task and does not touch the buffer again until that task finishes.
final class SendablePixelBufferBox: @unchecked Sendable {
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer

    nonisolated init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

/// Carries the capture session to its channel's serial session executor.
/// AVCaptureSession's start/stop are documented as callable from any thread;
/// each channel only ever touches its session from one serial queue there.
final class CaptureSessionBox: @unchecked Sendable {
    nonisolated(unsafe) let value: AVCaptureSession
    nonisolated init(_ value: AVCaptureSession) { self.value = value }
}

/// Coalesces AVCapture `didDrop` callbacks. A drop used to start one
/// main-actor Task each; under overload that is frame-rate hops onto the actor
/// that is already behind. Drops are counted here on the capture queue, and
/// only the first drop of a burst schedules a hop, which records them all.
nonisolated final class CaptureDropCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Double] = []
    private var overflow = 0
    private var flushScheduled = false
    /// Timestamps kept per flush; beyond this, drops are still counted and
    /// recorded with the newest timestamp.
    static let maxPendingTimestamps = 256

    struct Batch: Equatable {
        var timestamps: [Double] = []
        /// Drops past the timestamp cap; each is recorded at the newest time.
        var overflow = 0

        var all: [Double] {
            guard overflow > 0, let last = timestamps.last else { return timestamps }
            return timestamps + Array(repeating: last, count: overflow)
        }
    }

    init() {}

    /// Record one drop. True when the caller must schedule a flush.
    func note(timestamp: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pending.count < Self.maxPendingTimestamps {
            pending.append(timestamp)
        } else {
            pending[pending.count - 1] = timestamp
            overflow += 1
        }
        guard !flushScheduled else { return false }
        flushScheduled = true
        return true
    }

    /// Take every drop noted since the last flush.
    func drain() -> Batch {
        lock.lock()
        defer { lock.unlock() }
        let batch = Batch(timestamps: pending, overflow: overflow)
        pending.removeAll(keepingCapacity: true)
        overflow = 0
        flushScheduled = false
        return batch
    }
}

nonisolated final class CaptureFrameProcessingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeLease: UInt64?
    private var leaseSequence: UInt64 = 0
    private var droppedFrames: UInt64 = 0

    // Windowed throughput diagnostics. The delivered rate here is the ceiling on
    // what reaches the program output: if it sags below the show standard the
    // picture goes choppy. Logged once per second under the existing lock so it
    // stays thread-safe and cheap.
    private static let logger = Logger(subsystem: "com.alfie", category: "CaptureThroughput")
    private var windowStart: CFTimeInterval = CACurrentMediaTime()
    private var windowDelivered: UInt64 = 0
    private var windowDropped: UInt64 = 0

    init() {}

    func begin() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard activeLease == nil else {
            droppedFrames &+= 1
            windowDropped &+= 1
            logThroughputIfDueLocked()
            return nil
        }
        leaseSequence &+= 1
        activeLease = leaseSequence
        windowDelivered &+= 1
        logThroughputIfDueLocked()
        return leaseSequence
    }

    /// Caller must hold `lock`. Emits a delivered/dropped FPS summary once the
    /// current 1-second window closes, then opens a new window.
    private func logThroughputIfDueLocked() {
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 1.0 else { return }
        let deliveredFPS = Double(windowDelivered) / elapsed
        let droppedFPS = Double(windowDropped) / elapsed
        let total = windowDelivered + windowDropped
        let dropPercent = total > 0 ? Double(windowDropped) / Double(total) * 100.0 : 0
        let targetRate = ShowStandard.activeOrCurrent.frameRate
        Self.logger.notice(
            "Capture throughput: \(deliveredFPS, format: .fixed(precision: 1)) fps delivered to pipeline (target \(targetRate, format: .fixed(precision: 0))), dropped \(droppedFPS, format: .fixed(precision: 1)) fps (\(dropPercent, format: .fixed(precision: 1))% of frames)"
        )
        windowStart = now
        windowDelivered = 0
        windowDropped = 0
    }

    func isCurrent(_ lease: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeLease == lease
    }

    func finish(_ lease: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if activeLease == lease { activeLease = nil }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        activeLease = nil
        droppedFrames = 0
        windowStart = CACurrentMediaTime()
        windowDelivered = 0
        windowDropped = 0
    }

    var droppedFrameCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return droppedFrames
    }
}
