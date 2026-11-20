//
//  DetectionCadence.swift
//  CinematicCoreMacOS
//
//  G-01 stage 2. Owns the detection slot and its clocks, which used to be
//  private stored properties of CameraManager: the one-detection-at-a-time
//  flag, the eligible-frame counter behind `DeveloperFlags.detectionFrameInterval`
//  and the Core Image cache-flush clock. Scheduled tracking detection and
//  Director discovery share the slot; the operator-tap scan does not use it.
//

import Foundation

@MainActor
final class DetectionCadence {
    /// One detection at a time. Without this, a pipeline that falls behind
    /// would queue detections faster than they complete and spawn unbounded work.
    private(set) var inFlight = false
    /// Eligible frames counted since the last reset.
    private var eligibleFrameCount: UInt64 = 0
    /// Wall-clock of the last Core Image cache flush; 0 until the first turn.
    private var lastImageCacheFlush: TimeInterval = 0

    /// Take the slot. False when a detection already holds it.
    func claim() -> Bool {
        guard !inFlight else { return false }
        inFlight = true
        return true
    }

    /// The detection that claimed the slot has finished, one way or another.
    func release() { inFlight = false }

    /// Cadence accounting for a frame. Every frame with no detection in
    /// flight advances the count, due or not (see `slotIsDue`). Returns
    /// whether this frame holds a detection slot.
    func advance(interval: Int) -> Bool {
        guard !inFlight else { return false }
        eligibleFrameCount &+= 1
        return Self.slotIsDue(eligibleFrameCount: eligibleFrameCount, interval: interval)
    }

    /// Restart the count. The slot is left as it is: a running detection
    /// keeps it until it actually completes.
    func resetCount() { eligibleFrameCount = 0 }

    /// Whether a periodic cache flush is due now. The first call starts the
    /// clock; an interval of 0 or less turns the flush off.
    func imageCacheFlushIsDue(now: TimeInterval, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return false }
        guard lastImageCacheFlush > 0 else {
            lastImageCacheFlush = now
            return false
        }
        guard now - lastImageCacheFlush >= interval else { return false }
        lastImageCacheFlush = now
        return true
    }

    /// Pure cadence rule: does the Nth eligible frame (every captured frame
    /// where no detection is in flight — counting starts at 1) carry a
    /// detection slot?
    ///
    /// REGRESSION NOTE (Aug 2026): an intermediate version of this gate tested
    /// `(counter + 1) % interval == 0` but only advanced the counter on frames
    /// that were already due. From counter 0 with interval 2 that predicate is
    /// false forever, scheduled detection dead-locked, and tracking froze on
    /// the single tap-time detection — the "tracking box doesn't move" bug.
    /// The rule below is the original, correct accounting: EVERY eligible
    /// frame advances the count; slots land on multiples of the interval. Unit
    /// tested in `DetectionCadenceTests`.
    nonisolated static func slotIsDue(eligibleFrameCount: UInt64, interval: Int) -> Bool {
        let interval = UInt64(max(1, interval))
        return eligibleFrameCount % interval == 0
    }
}
