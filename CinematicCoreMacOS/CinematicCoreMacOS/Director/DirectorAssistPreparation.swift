import Foundation

/// B-05: MainActor camera adapter. The pure replay sink cannot safely own a
/// MainActor camera; actor-isolated replays drive this same adapter instead.
/// A-10 chooses the shot before enqueue. This boundary never chooses a subject,
/// changes mode, calls Take, or invents readiness/lease/N4 settings.
final class DirectorAssistPreparation {
    nonisolated struct Configuration: Sendable {
        let readiness: DirectorReadiness.Parameters
        let maximumRequestAge: TimeInterval
        let onePreparationPerTenure: Bool
        /// Explicit study metadata only. Absence never changes preparation admission.
        var capture: DirectorShadowRecorder.CaptureBinding? = nil
    }
    private weak var show: ShowCoordinator?
    private weak var controller: DirectorController?
    private(set) var preparation = DirectorPreparation()
    private var configuration: Configuration?
    private var tenure: DirectorShotPolicy.PreviewTenure?
    private var history: DirectorShotPolicy.PreparationHistory?
    private var ownedShots: [ChannelID: (shot: DirectorShot, revisions: ChannelRevisions)] = [:]
    #if DEBUG
    /// Synthetic detector/dispatch seams. Neither exists in Release.
    var readinessForTesting: DirectorReadiness?
    var dispatchForTesting: ((CameraManager, OperatorCommand) -> CommandResult)?
    #endif

    init(show: ShowCoordinator?, controller: DirectorController) {
        self.show = show; self.controller = controller
    }

    func retire() { preparation.retire(); configuration = nil }

    /// Coordinator ingress only. A delayed completion must use commit and its
    /// captured request; it must never enqueue fresh work on its old behalf.
    func enqueue(_ shot: DirectorShot, configuration c: Configuration) -> DirectorPreparation.Request? {
        guard DeveloperFlags.allowDirectorAssist, c.readiness.isValid,
              c.maximumRequestAge.isFinite, c.maximumRequestAge >= 0,
              let show, let controller, controller.isAttached, let preview = show.previewChannel,
              let channel = show.channel(preview), !show.editLive,
              channel.activeMode == .autoTracking, channel.manualLockedTargetID != nil,
              channel.recoveryState.trackingOwnsControl, !channel.operatorGestureInProgress,
              DirectorShotPolicy.InputFormat(channel.directorShot.preset).ladder.contains(shot) else { return nil }
        let now = show.clock(), current = snapshot(configuration: c, now: now)
        guard now.isFinite, now >= 0, current.ready.isReady, !current.live.sourceMissing, current.live.authority.mayPrepare,
              controller.prerequisites().satisfied,
              controller.prerequisites().qualifiedLevels.contains(controller.authority.level),
              let revisions = current.live.revisions else { return nil }
        if tenure?.preview != preview || tenure?.sourceGeneration != revisions.sourceGeneration ||
            tenure?.routeGeneration != current.live.routeGeneration {
            let next = DirectorShotPolicy.PreviewTenure(id: UUID(), preview: preview,
                sourceGeneration: revisions.sourceGeneration, routeGeneration: current.live.routeGeneration)
            tenure = next; history = .init(tenure: next); preparation.retire()
        }
        guard !c.onePreparationPerTenure || history?.preparedTenure == nil,
              let proposal = DirectorProposal(target: preview, preview: preview, shot: shot,
                reason: "subject evidence", authorityEpoch: controller.authority.epoch,
                revisions: revisions, routeGeneration: current.live.routeGeneration, createdAt: now,
                policyRevision: controller.policyRevision, nominationRevision: controller.nominationRevision),
              let request = preparation.propose(proposal, maximumAge: c.maximumRequestAge, now: now) else { return nil }
        configuration = c
        if c.capture != nil || controller.hasCaptureBindingProvider {
            if let parameters = controller.captureParameters(c.capture, readiness: c.readiness) {
                controller.captureDecision(DirectorShadowRecorder.preparation(request), evaluation: .init(now: now,
                    parameters: parameters, sample: current.sample, revisions: revisions, adapter: controller.adapter,
                    readinessInputs: current.inputs, prepareReadiness: current.measuredReadiness,
                    cutReadiness: nil, timeline: nil))
            } else { controller.shadowRecorder?.log.noteDropped() }
        }
        return request
    }

    /// Validation, one-shot reservation, actual command and revision audit are
    /// one MainActor turn. Matching refusal is terminal; no deferred retry.
    func commit(_ request: DirectorPreparation.Request) -> DirectorPreparationEffect {
        guard preparation.request == request, let c = configuration else { return .rejected([.requestReplaced]) }
        guard DeveloperFlags.allowDirectorAssist, let show, let controller, controller.isAttached else {
            preparation.discard(request); return .failed
        }
        let now = show.clock(), current = snapshot(configuration: c, now: now)
        guard now.isFinite, now >= 0 else { preparation.discard(request); return .rejected([.expired]) }
        if case .stale(let reasons) = preparation.validate(request, live: current.live, now: now) {
            preparation.discard(request); return .rejected(reasons)
        }
        guard current.ready.isReady, controller.prerequisites().satisfied,
              controller.prerequisites().qualifiedLevels.contains(controller.authority.level),
              !show.editLive, let preview = show.previewChannel, preview == request.intent.target,
              let channel = show.channel(preview), channel.activeMode == .autoTracking,
              channel.manualLockedTargetID != nil, channel.recoveryState.trackingOwnsControl,
              !channel.operatorGestureInProgress, let tenure, history?.currentTenure == tenure,
              tenure.preview == preview, tenure.routeGeneration == show.router.routeGeneration,
              tenure.sourceGeneration == channel.revisions.sourceGeneration,
              !c.onePreparationPerTenure || history?.preparedTenure == nil,
              channel.revisions.controlEpoch < UInt64.max, channel.revisions.shotRevision < UInt64.max else {
            preparation.discard(request); return .rejected([.evidenceUnavailable])
        }
        let expected = ChannelRevisions(sourceGeneration: channel.revisions.sourceGeneration,
            controlEpoch: channel.revisions.controlEpoch + 1, shotRevision: channel.revisions.shotRevision + 1)
        guard let receipt = preparation.commit(request, live: current.live, now: now, postRevisions: expected) else { return .failed }
        let command = channel.makeCommand(.selectPreset(request.intent.shot.preset), origin: .director)
        let result: CommandResult
        #if DEBUG
        result = dispatchForTesting?(channel, command) ?? channel.dispatch(command)
        #else
        result = channel.dispatch(command)
        #endif
        guard result.wasAccepted, channel.revisions == expected,
              preparation.acknowledge(receipt, live: snapshot(configuration: c, now: now).live) else {
            retire(); controller.preparationFailed(); return .failed
        }
        _ = history?.recordCommittedPreparation(receipt, tenure: tenure)
        ownedShots[preview] = (request.intent.shot, expected)
        return .committed(receipt)
    }

    var alfieSetShots: Set<ChannelID> {
        Set(ownedShots.compactMap { id, owned in show?.channel(id)?.revisions == owned.revisions ? id : nil })
    }

    var preparedShot: NextShotStatus.DirectorSection.PreparedShot? {
        guard let show, let controller, let value = preparation.composition,
              value.intent.authorityEpoch == controller.authority.epoch,
              value.intent.target == show.previewChannel,
              value.intent.routeGeneration == show.router.routeGeneration,
              value.revisions == show.channel(value.intent.target)?.revisions else { return nil }
        return .init(input: value.intent.target, shot: value.intent.shot)
    }

    private func snapshot(configuration c: Configuration, now: TimeInterval)
        -> (live: DirectorLiveState, ready: DirectorReadiness, sample: ChannelEvidenceSample?,
            inputs: DirectorReadiness.Inputs?, measuredReadiness: DirectorReadiness?) {
        let preview = show?.previewChannel, channel = preview.flatMap { show?.channel($0) }
        var ready = DirectorReadiness(reasons: [.evidenceUnavailable]), evidence = false
        var observedSample: ChannelEvidenceSample?, evaluatedInputs: DirectorReadiness.Inputs?
        var measuredReadiness: DirectorReadiness?
        if let controller, let adapter = controller.adapter, let channel, let show, let inputs = show.takeInputs() {
            let sample = DirectorController.sample(channel.evidenceReadings(now: now))
            observedSample = sample
            let take = TakeAvailability.evaluate(take: inputs, program: show.programChannel, preview: preview,
                standard: ShowStandard.activeOrCurrent, editLive: show.editLive)
            if let input = DirectorController.currentCutInputs(sample: sample, adapter: adapter, take: take, now: now) {
                ready = DirectorReadiness.evaluate(input, parameters: c.readiness, bar: .prepare)
                evaluatedInputs = input; measuredReadiness = ready
                evidence = input.identity == .confirmed
            }
        }
        #if DEBUG
        if let override = readinessForTesting { ready = override; evidence = override.isReady; measuredReadiness = nil }
        #endif
        return (.init(authority: controller?.authority ?? DirectorAuthority(reviewPolicy: .conservative),
            program: show?.programChannel ?? .a, preview: preview, revisions: channel?.revisions,
            routeGeneration: show?.router.routeGeneration ?? 0, sourceMissing: channel?.sourceMissing ?? true,
            policyRevision: controller?.policyRevision ?? 0, nominationRevision: controller?.nominationRevision ?? 0,
            evidenceAvailable: evidence), ready, observedSample, evaluatedInputs, measuredReadiness)
    }
}
