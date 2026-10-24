import Foundation

/// An eased, one-rung log-height projection. The cubic's maximum derivative
/// is 3/2, so its duration guarantees normalized rung progress <= maximumRate.
/// Geometry and rate are explicit; this is neither a production rate nor a
/// claim about display/consumer timing.
nonisolated struct DirectorShotMoveTrajectory: Equatable, Sendable {
    let originHeight: Double
    let destinationHeight: Double
    let maximumRate: Double
    let duration: TimeInterval

    init?(originHeight: Double, destinationHeight: Double, maximumRate: Double) {
        guard originHeight.isFinite, originHeight > 0,
              destinationHeight.isFinite, destinationHeight > 0,
              originHeight != destinationHeight, maximumRate.isFinite, maximumRate > 0 else { return nil }
        let duration = 1.5 / maximumRate
        let distance = log(destinationHeight / originHeight)
        guard duration.isFinite, duration > 0, distance.isFinite else { return nil }
        self.originHeight = originHeight; self.destinationHeight = destinationHeight
        self.maximumRate = maximumRate; self.duration = duration
    }

    func height(at elapsed: TimeInterval) -> Double {
        let u = min(1, max(0, elapsed / duration))
        if u == 0 { return originHeight }
        if u == 1 { return destinationHeight }
        let progress = u * u * (3 - 2 * u)
        return originHeight * exp(log(destinationHeight / originHeight) * progress)
    }
}

/// B-09's explicit Debug execution boundary. No tick chooses a target or
/// installs configuration. N2 and rig qualification remain separate gates.
final class DirectorOnAirMoveExecution {
    nonisolated struct Configuration: Sendable {
        let readiness: DirectorReadiness.Parameters
        let maximumSampleAge: TimeInterval
        var isValid: Bool {
            readiness.isValid && maximumSampleAge.isFinite && maximumSampleAge >= 0
        }
    }
    nonisolated enum Effect: Equatable, Sendable { case started(UUID), rejected, failed }
    private struct Pending {
        let plan: OnAirMovePolicy.Plan
        let configuration: Configuration
        let programStartedAt: TimeInterval
        let subject: UUID
    }
    private struct Running {
        let pending: Pending
        let postRevisions: ChannelRevisions
    }

    private weak var show: ShowCoordinator?
    private weak var controller: DirectorController?
    private(set) var policy = OnAirMovePolicy()
    /// Nil until an explicit request supplies all study settings.
    private var pending: Pending?
    private var running: Running?
    private var startingID: UUID?
    #if DEBUG
    /// Synthetic evidence seam; the app never installs it. Geometry, source,
    /// authority, qualification, subject and revision gates remain real.
    var programReadinessForTesting: DirectorReadiness?
    var betterInputCutReadyForTesting: Bool??
    #endif

    init(show: ShowCoordinator?, controller: DirectorController) {
        self.show = show; self.controller = controller
    }

    func retire() {
        policy.retire(); pending = nil
        if let running { show?.channel(running.pending.plan.program)?.cancelDirectorShotMove(id: running.pending.plan.id) }
        running = nil
    }

    /// Caller supplies the start of this Program tenure; route binding stops
    /// that clock being reused after a Take. No fallback tenure is invented.
    func enqueue(_ target: DirectorShot, programStartedAt: TimeInterval,
                 configuration: Configuration) -> OnAirMovePolicy.Plan? {
        validateRunning()
        guard running == nil, DeveloperFlags.allowDirectorAuto, configuration.isValid,
              let show, let controller, let style = controller.effectiveStyle,
              let channel = show.channel(show.programChannel), let subject = channel.manualLockedTargetID,
              let context = snapshot(target: target, programStartedAt: programStartedAt,
                  configuration: configuration, now: show.clock()),
              case .move(let plan) = policy.propose(context, style: style, now: show.clock(),
                  maximumSampleAge: configuration.maximumSampleAge) else {
            policy.retire(); pending = nil
            return nil
        }
        pending = Pending(plan: plan, configuration: configuration, programStartedAt: programStartedAt, subject: subject)
        return plan
    }

    /// Policy consumption and narrow camera admission share one MainActor turn.
    /// Refused attempts do not enqueue a delayed retry.
    func commit(_ plan: OnAirMovePolicy.Plan) -> Effect {
        guard let request = pending, request.plan == plan else { return .rejected }
        pending = nil
        guard DeveloperFlags.allowDirectorAuto, let show, let controller,
              let style = controller.effectiveStyle, let channel = show.channel(plan.program),
              let context = snapshot(target: plan.to, programStartedAt: request.programStartedAt,
                  configuration: request.configuration, now: show.clock()),
              channel.manualLockedTargetID == request.subject,
              channel.revisions.controlEpoch < UInt64.max, channel.revisions.shotRevision < UInt64.max,
              policy.consume(plan, live: context, style: style, now: show.clock(),
                  maximumSampleAge: request.configuration.maximumSampleAge) != nil else {
            policy.retire(); return .rejected
        }
        let expected = ChannelRevisions(sourceGeneration: channel.revisions.sourceGeneration,
            controlEpoch: channel.revisions.controlEpoch + 1, shotRevision: channel.revisions.shotRevision + 1)
        let owner = Running(pending: request, postRevisions: expected)
        startingID = plan.id
        defer { startingID = nil }
        let result = channel.beginDirectorShotMove(id: plan.id, to: plan.to, maximumRate: plan.maximumRate) { [weak self, weak channel] in
            guard let self, let channel else { return false }
            return self.isCurrent(owner, hasStarted: channel.hasDirectorShotMove(id: plan.id))
        }
        guard result.wasAccepted, channel.revisions == expected, channel.hasDirectorShotMove(id: plan.id) else {
            channel.cancelDirectorShotMove(id: plan.id)
            return .failed
        }
        running = owner
        return .started(plan.id)
    }

    /// Hook/tick cleanup only. CameraManager also checks the same owner before
    /// every active frame's advance, without a detector call, I/O or UI publish.
    func validateRunning() {
        guard let running else { return }
        guard let channel = show?.channel(running.pending.plan.program),
              channel.hasDirectorShotMove(id: running.pending.plan.id) else { self.running = nil; return }
        if !isCurrent(running, hasStarted: true) { retire() }
    }

    private func isCurrent(_ owner: Running, hasStarted: Bool) -> Bool {
        let request = owner.pending, plan = request.plan
        guard DeveloperFlags.allowDirectorAuto, let show, let controller,
              running?.pending.plan.id == plan.id || startingID == plan.id,
              show.programChannel == plan.program, show.router.routeGeneration == plan.routeGeneration,
              !show.editLive, controller.authority.epoch == plan.epoch,
              controller.authority.mayIssueTake(at: show.clock()),
              controller.policyRevision == plan.policyRevision, controller.nominationRevision == plan.nominationRevision,
              controller.effectiveStyle == plan.style,
              controller.prerequisites().satisfied,
              controller.prerequisites().qualifiedLevels.contains(controller.authority.level),
              let channel = show.channel(plan.program), channel.isRunning, !channel.sourceMissing,
              channel.revisions == (hasStarted ? owner.postRevisions : plan.programRevisions),
              channel.activeMode == .autoTracking, channel.manualLockedTargetID == request.subject,
              channel.recoveryState.trackingOwnsControl, !channel.operatorGestureInProgress else { return false }
        let now = show.clock()
        guard now.isFinite, now >= plan.proposedAt else { return false }
        #if DEBUG
        if let readiness = programReadinessForTesting { return readiness.isReady }
        #endif
        guard let adapter = controller.adapter, adapter.parameters.isValid,
              let state = adapter.state(for: plan.program), state.lockedTargetID == request.subject,
              state.identity == .confirmed, state.evidenceAvailable,
              let sampledAt = state.lastSampleAt, now >= sampledAt,
              now - sampledAt <= adapter.parameters.maximumObservationAge else { return false }
        // Crop convergence is intentionally not required while our move runs.
        // Current identity, observation freshness and subject motion still are.
        let sample = DirectorController.sample(channel.evidenceReadings(now: now))
        return IdentityEvidence.classify(sample, maximumObservationAge: adapter.parameters.maximumObservationAge) == .confirmed &&
            sample.subjectSpeed.isFinite && sample.subjectSpeed >= 0 && sample.subjectSpeed <= request.configuration.readiness.maximumMotion
    }

    private func snapshot(target: DirectorShot, programStartedAt: TimeInterval,
                          configuration: Configuration, now: TimeInterval) -> OnAirMovePolicy.Context? {
        guard DeveloperFlags.allowDirectorAuto, configuration.isValid, now.isFinite, now >= 0,
              let show, let controller, !show.editLive,
              let channel = show.channel(show.programChannel), channel.isRunning, !channel.sourceMissing,
              channel.activeMode == .autoTracking, channel.manualLockedTargetID != nil,
              channel.recoveryState.trackingOwnsControl, !channel.operatorGestureInProgress,
              running == nil else { return nil }
        var ready = DirectorReadiness(reasons: [.evidenceUnavailable])
        if let adapter = controller.adapter, adapter.parameters.isValid {
            let sample = DirectorController.sample(channel.evidenceReadings(now: now))
            let rate = channel.configuredCaptureFPS.map { min($0, ShowStandard.activeOrCurrent.frameRate) }
                ?? ShowStandard.activeOrCurrent.frameRate
            let frame = TakeRules.inputs(frame: channel.latestRenderedFrame, previewChannel: channel.channelID,
                current: channel.revisions, sourceMissing: channel.sourceMissing, admission: show.admissionDecision,
                now: now, framePeriod: 1 / max(1, rate))
            // Evaluate the active channel's rendered geometry/freshness, not an
            // actual Take. This object never reaches the router or console.
            let availability = TakeAvailability.evaluate(take: frame, program: show.programChannel,
                preview: channel.channelID, standard: ShowStandard.activeOrCurrent, editLive: show.editLive)
            if let inputs = DirectorController.currentCutInputs(sample: sample, adapter: adapter, take: availability, now: now) {
                ready = DirectorReadiness.evaluate(inputs, parameters: configuration.readiness, bar: .cut)
            }
        }
        let offAir = controller.currentTakeState(now: now)
        let unknown: Set<DirectorReadiness.Reason> = [.evidenceUnavailable, .invalidParameters, .invalidEvidence]
        var better: Bool? = offAir.cutReadiness.reasons.contains(where: { unknown.contains($0) }) ? nil : offAir.cutReadiness.isReady
        #if DEBUG
        if let override = programReadinessForTesting { ready = override }
        if let override = betterInputCutReadyForTesting { better = override }
        #endif
        return .init(authority: controller.authority, prerequisites: controller.prerequisites(), program: show.programChannel,
            programRevisions: channel.revisions, routeGeneration: show.router.routeGeneration,
            policyRevision: controller.policyRevision, nominationRevision: controller.nominationRevision,
            currentShot: channel.directorShot, targetShot: target,
            runningInputs: Set(show.channels.compactMap { $0.value.isRunning ? $0.key : nil }),
            betterInputCutReady: better, readiness: ready, sourceHealthy: !channel.sourceMissing,
            operatorGestureInProgress: channel.operatorGestureInProgress, programStartedAt: programStartedAt, sampledAt: now)
    }
}
