//
//  CameraManager+SubjectDiscovery.swift
//  CinematicCoreMacOS
//
//  G-01 stage 1. Explicit bounded Director discovery (B-10): the camera side.
//  The discovery state lives privately in `SubjectDiscoveryDriver`; this
//  file binds it to the camera's facts and runs the scan.
//

import CoreVideo
import Foundation
import QuartzCore

extension CameraManager {
    /// Plain metadata, sampled by the existing UI/controller refresh.
    var subjectDiscoverySnapshot: DirectorSubjectDiscovery.Snapshot { subjectDiscovery.snapshot }

    /// Controller/UI reads must supply their current monotonic clock so an
    /// idle source cannot leave an old pick or ambiguous boxes visible.
    func subjectDiscoverySnapshot(at now: TimeInterval) -> DirectorSubjectDiscovery.Snapshot {
        subjectDiscovery.snapshot(at: now)
    }

    /// Successful acquisition origin survives Take and normal tracking. An
    /// operator nomination/unlock or source/identity reset clears it.
    var directorDiscoveredSubject: SubjectSelector.Selection? {
        subjectDiscovery.origin(sourceGeneration: captureGeneration, lockedTarget: manualLockedTargetID)
    }

    #if DEBUG
    /// No normal app path installs this. Missing/invalid study settings fail
    /// closed; scan permission and acquisition authority remain independent.
    func configureSubjectDiscoveryForStudy(_ configuration: DirectorSubjectDiscovery.Configuration?,
                                           eligibility: @escaping () -> DirectorSubjectDiscovery.Context?) {
        retireSubjectDiscovery()
        subjectDiscovery.configure(configuration, eligibility: eligibility)
        setNeedsMotionRefresh()
    }
    #endif

    /// Synchronous lifecycle retirement, including every Take origin. This
    /// cancels a token that has not started, or rejects an already-running
    /// result and counts its overlap truthfully. It never drains/waits for
    /// Vision or invalidates ordinary tracking observations.
    func retireSubjectDiscovery() {
        if subjectDiscovery.retire() {
            // The detection slot excludes a normal scheduled tracking waiter
            // while this token is current. Cancel only our perception lane;
            // render and the operator-tap path are left alone.
            workScheduler?.cancelWaiting(.perception, for: channelID)
        }
    }

    func subjectDiscoveryBinding() -> DirectorSubjectDiscovery.Binding? {
        #if DEBUG
        guard let (configuration, context) = subjectDiscovery.eligibility(),
              context.program != channelID, isRunning, !sourceMissing,
              workScheduler != nil, activeMode == .wide,
              shotComposer.manualLockedTargetID == nil, !operatorGestureInProgress,
              case .inactive = shotComposer.lockState else { return nil }
        return .init(channel: channelID, sourceGeneration: captureGeneration,
                     controlEpoch: commands.epoch, shotRevision: shotRevision,
                     configurationRevision: configuration.revision, context: context)
        #else
        return nil
        #endif
    }

    func scheduleSubjectDiscoveryIfDue(pixelBuffer: CVPixelBuffer) {
        guard let binding = subjectDiscoveryBinding(), let configuration = subjectDiscovery.installedConfiguration else {
            retireSubjectDiscovery(); return
        }
        let requestedAt = CACurrentMediaTime()
        guard !detectionCadence.inFlight,
              let token = subjectDiscovery.request(binding: binding, configuration: configuration,
                                                   now: requestedAt, holdsSlot: true) else { return }
        _ = detectionCadence.claim()
        let box = SendablePixelBufferBox(pixelBuffer)
        Task { [weak self] in
            guard let self else { return }
            var permitAt: TimeInterval?
            defer {
                self.subjectDiscovery.completed(token, requestedAt: requestedAt, permitAt: permitAt)
                self.detectionCadence.release()
            }
            guard self.subjectDiscoveryBinding() == binding, let scheduler = self.workScheduler else {
                self.subjectDiscovery.recordRetirement(of: token); return
            }
            guard let permit = await scheduler.acquire(.perception, for: self.channelID) else {
                self.subjectDiscovery.recordRetirement(of: token); return
            }
            defer { scheduler.release(permit) }
            permitAt = CACurrentMediaTime()
            guard self.subjectDiscoveryBinding() == binding else {
                self.subjectDiscovery.recordRetirement(of: token); return
            }
            let persons = await self.personDetector.processFrame(box.pixelBuffer,
                plan: .init(mode: .discovery, roi: nil), discoveryToken: token)
            // No suspension is permitted between these final checks and the
            // acquisition effect below. A source/route/authority/gesture change
            // cannot substitute a later person or a later input.
            guard token.mayPublish, self.subjectDiscoveryBinding() == binding else {
                self.subjectDiscovery.rejectResult(); return
            }
            _ = self.applySubjectDiscoveryResult(persons, capturedAt: requestedAt, now: CACurrentMediaTime(),
                binding: binding, configuration: configuration)
        }
    }

    @discardableResult
    private func applySubjectDiscoveryResult(_ persons: [PersonDetector.DetectedPerson], capturedAt: TimeInterval,
                                             now: TimeInterval, binding: DirectorSubjectDiscovery.Binding,
                                             configuration: DirectorSubjectDiscovery.Configuration) -> Bool {
        guard subjectDiscoveryBinding() == binding else { subjectDiscovery.rejectResult(); return false }
        let candidates = persons.map { DirectorSubjectDiscovery.Candidate(id: $0.id, bounds: $0.boundingBox) }
        guard let decision = subjectDiscovery.ingest(candidates, capturedAt: capturedAt,
            now: now, binding: binding, configuration: configuration),
              case .selected(let selection) = decision, binding.context.mayAcquire,
              let person = persons.first(where: { $0.id == selection.subject }) else { return false }
        guard binding.context.mayAcquire, subjectDiscoveryBinding() == binding,
              selection.channel == channelID, selection.sourceGeneration == captureGeneration,
              selection.subject == person.id else { return false }
        acquireDiscoveredSubject(selection.subject, bounds: person.boundingBox)
        subjectDiscovery.acquired(selection)
        return true
    }

    #if DEBUG
    /// Raw synthetic detector output for acquire-boundary tests. Production
    /// scheduling and detector-token tests separately exercise actual starts.
    @discardableResult
    func acceptSubjectDiscoveryForTesting(_ persons: [PersonDetector.DetectedPerson],
                                         capturedAt: TimeInterval, now: TimeInterval) -> Bool {
        guard let binding = subjectDiscoveryBinding(), let configuration = subjectDiscovery.installedConfiguration,
              subjectDiscovery.request(binding: binding, configuration: configuration,
                                       now: capturedAt, holdsSlot: false) != nil else { return false }
        return applySubjectDiscoveryResult(persons, capturedAt: capturedAt, now: now,
            binding: binding, configuration: configuration)
    }
    #endif
}
