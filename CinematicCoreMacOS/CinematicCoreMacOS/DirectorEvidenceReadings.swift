//
//  DirectorEvidenceReadings.swift
//  CinematicCoreMacOS
//
//  S3 B-01: one read-only snapshot of what a channel currently knows about
//  its subject, for the Auto Director's evidence adapter. Reading it never
//  changes tracking, framing or routing. The Director core's own
//  `ChannelEvidenceSample` (A-02) is built from this by the controller (B-03).
//

import Foundation
import QuartzCore

nonisolated struct ChannelEvidenceReadings: Equatable, Sendable {
    let channel: ChannelID
    /// Host-clock time the snapshot was taken.
    let sampledAt: TimeInterval
    let isRunning: Bool
    let sourceMissing: Bool
    let mode: CameraManager.OperationMode
    let revisions: ChannelRevisions

    let lockPhase: RecoveryState.Phase
    let galleryReady: Bool
    let trackingOwnsControl: Bool
    let lockedTargetID: UUID?

    /// Smoothed subject speed, normalized frame units per second.
    let subjectSpeed: Double
    /// The composer has concluded the subject settled and is holding.
    let holdingSteady: Bool
    let cropConverged: Bool
    /// nil until the channel has consumed a detection observation.
    let observationAge: TimeInterval?
    let observedPersonCount: Int
    let operatorGestureInProgress: Bool
}

extension CameraManager {
    func evidenceReadings(now: TimeInterval = CACurrentMediaTime()) -> ChannelEvidenceReadings {
        let recovery = recoveryState
        var phase = recovery.phase, galleryReady = recovery.galleryReady
        var speed = shotComposer.subjectSpeed, steady = shotComposer.isHoldingSteady
        #if DEBUG
        if let synthetic = directorPerceptionForTesting {
            phase = synthetic.phase; galleryReady = synthetic.galleryReady
            speed = synthetic.subjectSpeed; steady = synthetic.holdingSteady
        }
        #endif
        return ChannelEvidenceReadings(
            channel: channelID,
            sampledAt: now,
            isRunning: isRunning,
            sourceMissing: sourceMissing,
            mode: activeMode,
            revisions: revisions,
            lockPhase: phase,
            galleryReady: galleryReady,
            trackingOwnsControl: recovery.trackingOwnsControl,
            lockedTargetID: manualLockedTargetID,
            subjectSpeed: speed,
            holdingSteady: steady,
            cropConverged: cropConverged,
            observationAge: observationAge(now: now),
            observedPersonCount: lastObservationPersonCount,
            operatorGestureInProgress: operatorGestureInProgress)
    }
}
