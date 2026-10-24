import Foundation

/// B-12's Debug rehearsal boundary. It never chooses or prepares a fallback
/// shot: a current, explicitly verified Preview wide must already exist.
/// No configuration is installed by the app and Release cannot run effects.
final class DirectorBackupExecution {
    struct VerifiedSafeWide: Equatable, Sendable {
        let channel: ChannelID
        let revisions: ChannelRevisions
        let shot: DirectorShot
    }
    struct Configuration {
        let verifiedSafeWide: VerifiedSafeWide
        let maximumFrameAge: TimeInterval
        /// Separate current qualification for the fault fallback capability.
        /// A Backup-level record alone does not supply this assertion.
        let fallbackQualified: () -> Bool
    }
    private struct Fault {
        let program: ChannelID
        let routeGeneration: UInt64
        let authorityEpoch: UInt64
        let outputRoute: ProgramOutputManager.Route?
    }
    private weak var show: ShowCoordinator?
    private weak var controller: DirectorController?
    private var configuration: Configuration?
    private var policy = BackupFallbackPolicy()
    private var fault: Fault?
    private(set) var alert: NextShotStatus.DirectorSection.BackupAlert?
    private(set) var lastResult: TakeResult?

    init(show: ShowCoordinator?, controller: DirectorController) {
        self.show = show
        self.controller = controller
    }

    /// Explicit study setup only. Replacing/removing it retires old work.
    func configure(_ configuration: Configuration?) {
        retire()
        self.configuration = configuration
    }

    func retire(for event: DirectorAuthority.Event? = nil) {
        let preserveFallback: Bool
        if let event {
            switch event {
            case .sourceRebound:
                preserveFallback = wasSuccessfulFallback
            case .sourceLoss(let channel):
                preserveFallback = wasSuccessfulFallback && channel != show?.programChannel
            default:
                preserveFallback = false
            }
        } else {
            preserveFallback = false
        }
        policy.retire()
        fault = nil
        alert = preserveFallback ? .pausedAfterFallback : nil
    }

    private var wasSuccessfulFallback: Bool {
        if let lastResult, case .committed = lastResult, alert != nil { return true }
        return false
    }

    /// Called before the controller's ordinary source-loss forwarding. Both
    /// camera-loss-before-hold and hold-before-camera-loss use this path.
    /// The ordinary transition cancels all other work immediately; the pure
    /// reservation afterward binds exactly that resulting paused authority.
    @discardableResult
    func sourceLoss(_ channel: ChannelID) -> Bool {
        guard DeveloperFlags.allowDirectorAuto, let show, let controller,
              controller.isAttached, controller.authority.level == .backup, let configuration else { return false }
        guard channel == show.programChannel else {
            retire(for: .sourceLoss(channel))
            return false
        }
        if let fault, fault.program == channel,
           fault.routeGeneration == show.router.routeGeneration,
           fault.authorityEpoch == controller.authority.epoch {
            return true // Duplicate ingress never extends or reissues a grant.
        }
        let now = show.clock()
        let before = controller.currentTakeState(now: now).world
        let outputRoute = show.programOutput.activeRoute
        controller.applyBackupSourceLoss(channel)
        let next = policy.reserveSourceLoss(channel, before: before, after: controller.authority,
            now: now, maximumFrameAge: configuration.maximumFrameAge)
        fault = .init(program: channel, routeGeneration: show.router.routeGeneration,
                      authorityEpoch: controller.authority.epoch, outputRoute: outputRoute)
        if next != nil { attemptInsideHold() }
        else if show.router.holdWindow != nil { updateStaleAlert() }
        return true
    }

    /// True when this adapter owns the router's source-loss transition. Real
    /// destination/admission faults still use their ordinary controller path.
    @discardableResult
    func routerStateChanged(_ state: ProgramRouter.State) -> Bool {
        guard DeveloperFlags.allowDirectorAuto, let show, let controller,
              controller.isAttached, controller.authority.level == .backup, configuration != nil else { return false }
        switch state {
        case .holding:
            if fault == nil { return sourceLoss(show.programChannel) }
            attemptInsideHold()
            return true
        case .standby:
            guard fault != nil else { return false }
            policy.retire()
            updateStaleAlert()
            return true
        case .routed, .idle:
            // A new Program render or explicit lifecycle ends the old window.
            // This callback also runs during the synchronous fallback commit;
            // attemptInsideHold sets the successful alert after it returns.
            retire()
            return false
        }
    }

    /// Called only by ShowCoordinator at its synchronous Take boundary. It
    /// consumes the matching permit before all remaining technical checks.
    func consume(_ permit: BackupFallbackPolicy.Permit, now: TimeInterval) -> ProgramRouter.HoldWindow? {
        guard DeveloperFlags.allowDirectorAuto, let show, let controller, controller.isAttached, let configuration,
              let window = show.router.holdWindow,
              let snapshot = snapshot(now: now, window: window),
              policy.consume(permit, snapshot: snapshot, now: now,
                             maximumFrameAge: configuration.maximumFrameAge) != nil else {
            // A matching invalid attempt must also be terminal if settings or
            // the router window disappeared before consumption.
            if policy.pending == permit { policy.retire() }
            return nil
        }
        return window
    }

    private func attemptInsideHold() {
        guard let show, let controller, let configuration,
              let reservation = policy.reservation, let window = show.router.holdWindow else { return }
        let now = show.clock()
        guard let snapshot = snapshot(now: now, window: window),
              let permit = policy.issueReserved(reservation, snapshot: snapshot, now: now,
                  maximumFrameAge: configuration.maximumFrameAge) else {
            policy.retire()
            updateStaleAlert()
            return
        }
        let request = TakeRequest(expectedProgram: permit.program, expectedPreview: permit.preview,
                                  routeGeneration: permit.routeGeneration)
        let result = show.take(request, origin: .fallback, fallbackPermit: permit)
        // Take's router observer may have retired the captured context. A
        // refused or accepted attempt is terminal in either case.
        policy.retire()
        lastResult = result
        if case .committed(let channel) = result { alert = .switchedTo(channel) }
        else { updateStaleAlert() }
        controller.backupFallbackFinished(result)
    }

    private func snapshot(now: TimeInterval, window: ProgramRouter.HoldWindow) -> BackupFallbackPolicy.Snapshot? {
        guard let show, let controller, let configuration, let fault,
              let preview = show.previewChannel, let channel = show.channel(preview),
              window.program == fault.program, window.routeGeneration == fault.routeGeneration,
              show.programChannel == fault.program, controller.authority.epoch == fault.authorityEpoch else { return nil }
        let current = controller.currentTakeState(now: now)
        let ordinary = current.prerequisites
        // A router hold is the exceptional source fault. Output health comes
        // from the actual active destination, never a fabricated routed state.
        let prerequisites = DirectorAuthority.Prerequisites(
            nominationsCurrent: ordinary.nominationsCurrent,
            previewAvailable: ordinary.previewAvailable,
            sourcesHealthy: ordinary.sourcesHealthy,
            outputHealthy: fault.outputRoute != nil && show.programOutput.activeRoute == fault.outputRoute,
            admissionCurrent: ordinary.admissionCurrent,
            qualifiedLevels: ordinary.qualifiedLevels)
        let verified = configuration.verifiedSafeWide
        let inputs = show.takeInputs()
        let technical = inputs.map { TakeAvailability.evaluate(take: $0, program: show.programChannel,
            preview: preview, standard: ShowStandard.activeOrCurrent, editLive: show.editLive).isEligible } ?? false
        return .init(live: current.world, prerequisites: prerequisites,
            fallbackQualified: configuration.fallbackQualified(),
            verifiedSafeWide: verified.channel == preview && verified.revisions == channel.revisions &&
                verified.shot == channel.directorShot,
            previewShot: channel.directorShot, previewFrameAt: channel.latestRenderedFrame?.renderedAt,
            technicalTakeEligible: technical && channel.isRunning && !show.editLive,
            operatorGestureInProgress: current.operatorGestureInProgress,
            programStillMissing: show.channel(fault.program)?.sourceMissing == true || show.router.holdWindow != nil,
            routerHolding: show.router.holdWindow == window, holdDeadline: window.deadline)
    }

    private func updateStaleAlert() {
        guard let show, let preview = show.previewChannel, let channel = show.channel(preview) else { return }
        let inputs = show.takeInputs()
        let fresh = inputs.map { $0.sourcePresent && $0.hasFreshRender && !$0.isHeldFrame } ?? false
        if channel.sourceMissing || !fresh { alert = .bothInputsStale }
    }
}
