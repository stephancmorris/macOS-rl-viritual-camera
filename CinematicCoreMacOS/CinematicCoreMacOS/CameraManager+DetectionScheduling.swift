//
//  CameraManager+DetectionScheduling.swift
//  CinematicCoreMacOS
//
//  G-01 stage 2. Off-critical-path detection: the camera side. The slot and
//  its clocks live privately in `DetectionCadence`; this file arms the
//  scheduled detection and the diagnostic cache flush.
//
//  Detection used to be awaited inline, so every frame waited for Vision
//  before the crop could run. Measured 26 July: Vision 16.4 ms + ~17 ms of
//  crop/compose/output against a 20 ms budget at 50 Hz — the capture gate
//  then rejected 4 frames in 10 and the program feed ran at 30 fps.
//
//  Detection now runs alongside the picture. Each frame composes from the
//  most recent completed detection (20–40 ms old at interval 2) and never
//  waits, so the frame path costs only the ~17 ms it always did.
//

import CoreVideo
import Foundation
import QuartzCore

extension CameraManager {
    /// Diagnostic A/B hook: drop both Core Image contexts' caches on a fixed
    /// schedule. NOT the memory fix — the autorelease drains and
    /// `cacheIntermediates: false` contexts are the fix (July 2026); this hook
    /// only exists so a soak can A/B the flush back in via
    /// `DeveloperFlags.imageCacheFlushInterval`. One cheap comparison per
    /// frame; the flush itself runs at most every `interval` seconds.
    func flushImageCachesIfDue(now: TimeInterval) {
        guard detectionCadence.imageCacheFlushIsDue(now: now,
            interval: DeveloperFlags.imageCacheFlushInterval) else { return }
        cropEngine?.flushImageCaches()
        personDetector.flushImageCaches()
        // Marked in the diagnostics CSV so a flush can be lined up against the
        // heap and frame-rate columns when reviewing a session.
        outputPort.noteDiagnostics("image cache flush")
    }

    /// Start a detection if none is running and `due` says this frame holds a
    /// cadence slot. Slot accounting happens once per frame in the control
    /// turn (so the detection plan knows whether Vision will run); this
    /// function only re-checks and arms the work. Returns immediately either
    /// way — the caller never awaits.
    func scheduleDetectionIfDue(
        pixelBuffer: CVPixelBuffer,
        sourceTimestamp: Double,
        plan: PersonDetector.DetectionRequestPlan,
        due: Bool
    ) {
        guard due, detectionCadence.claim() else { return }
        let generation = detectionFrames.generation
        let id = detectionFrames.nextObservationID()
        let capturedAt = CACurrentMediaTime()
        let box = SendablePixelBufferBox(pixelBuffer)
        Task { [weak self] in
            guard let self else { return }
            // Whatever happens to this detection, a control turn follows it:
            // a result reaches the picture without waiting for the next
            // frame's turn, and a detector left idle is cleared.
            defer {
                self.detectionCadence.release()
                self.requestControlWake()
            }
            // The task may sit behind other MainActor work after it was
            // scheduled. Do not let it begin Vision under a newer
            // session/target generation and mutate the detector before the
            // frame store gets its post-work rejection chance.
            guard self.detectionFrames.generation == generation else { return }
            // Vision is admitted fairly across tracking channels. A superseded
            // or cancelled request skips this detection slot (latest-only).
            let scheduler = self.workScheduler
            var permit: FrameWorkScheduler.Permit?
            if let scheduler {
                guard let granted = await scheduler.acquire(.perception, for: self.channelID) else { return }
                permit = granted
            }
            defer { if let permit { scheduler?.release(permit) } }
            guard self.detectionFrames.generation == generation else { return }
            let persons = await self.personDetector.processFrame(box.pixelBuffer, plan: plan)
            let frame = DetectionFrame(observationID: id, capturedAt: capturedAt,
                sourceTimestamp: sourceTimestamp, pixelBuffer: box.pixelBuffer, persons: persons,
                queueWait: self.personDetector.stats.lastQueueWait,
                detectionDuration: self.personDetector.stats.lastDetectionTime,
                coverage: .scanned(mode: plan.mode, roi: plan.roi))
            guard self.detectionFrames.publish(frame, generation: generation) else { return }
            self.outputPort.recordDetectionTiming(queueWait: frame.queueWait, visionWall: frame.detectionDuration)
            self.outputPort.recordLatency(stage: .detection, duration: frame.detectionDuration)
        }
    }

    /// Pure cadence rule, kept here for the cadence and scenario tests. See
    /// `DetectionCadence.slotIsDue`.
    nonisolated static func detectionSlotIsDue(eligibleFrameCount: UInt64, interval: Int) -> Bool {
        DetectionCadence.slotIsDue(eligibleFrameCount: eligibleFrameCount, interval: interval)
    }
}
