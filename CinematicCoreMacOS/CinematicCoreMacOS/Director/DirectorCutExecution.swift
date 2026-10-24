import Foundation

/// Implementations must enqueue the callback, including zero-length Backup
/// notices. An inline callback fails closed rather than cutting before status
/// can be observed. Scheduling is injected; ordinary construction installs none.
protocol DirectorCutDeadlineScheduling: AnyObject {
    func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// An explicitly installed host-clock scheduler. Its wait only wakes the
/// controller; all final checks and the Take then run in one MainActor turn.
final class TaskDirectorCutDeadlineScheduler: DirectorCutDeadlineScheduling {
    private let clock: () -> TimeInterval
    private var task: Task<Void, Never>?
    init(clock: @escaping () -> TimeInterval) { self.clock = clock }
    func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        cancel()
        let now = clock()
        guard now.isFinite, now >= 0, deadline.isFinite else { return }
        task = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let current = clock()
            if current.isFinite, current >= 0 {
                // Clamp only to the sleep API's integer representation; no
                // editorial timing value is chosen here.
                let nanoseconds = max(0, deadline - current) * 1_000_000_000
                let representable = min(nanoseconds, Double(UInt64.max).nextDown)
                try? await Task.sleep(nanoseconds: UInt64(representable))
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }
    func cancel() { task?.cancel(); task = nil }
}

/// B-08/B-13's explicit Debug trial boundary. Context supplies real history
/// and calibrated candidate confidence; the adapter never makes either up.
/// No configuration, provider or scheduler is installed by the app by default.
final class DirectorCutExecution {
    nonisolated struct Configuration: Sendable {
        let autoNoticeLength: TimeInterval
        let maximumLateness: TimeInterval
        let permitValidity: TimeInterval
        let judgeMaximumAge: TimeInterval
        let minimumProbability: Double?
        let judge: any DirectorJudge
        var isValid: Bool {
            [autoNoticeLength, maximumLateness, permitValidity, judgeMaximumAge]
                .allSatisfy { $0.isFinite && $0 >= 0 } &&
            (minimumProbability.map { $0.isFinite && (0...1).contains($0) } ?? true)
        }
    }
    nonisolated struct Context: Sendable {
        let timeline: DirectorShotPolicy.Timeline
        let prepared: DirectorShotPolicy.Candidate
        let programIdentity: IdentityEvidence
        let program: ChannelID
        let programRevisions: ChannelRevisions
        let previewRevisions: ChannelRevisions
        let routeGeneration: UInt64
    }
    typealias ContextProvider = (TimeInterval) -> Context?

    private weak var show: ShowCoordinator?
    private weak var controller: DirectorController?
    private var configuration: Configuration?
    private var context: ContextProvider?
    private var scheduler: (any DirectorCutDeadlineScheduling)?
    private var scheduling = false
    private var notice = CutNotice()
    private var cancellationDwell: TimeInterval?
    private(set) var lastResult: TakeResult?
    var pending: CutNotice.Token? { notice.pending }
    var isConfigured: Bool { configuration != nil }

    init(show: ShowCoordinator?, controller: DirectorController) {
        self.show = show; self.controller = controller
    }

    func configure(_ configuration: Configuration?, context: ContextProvider?,
                   scheduler: (any DirectorCutDeadlineScheduling)?) {
        retire()
        guard let configuration, configuration.isValid, let context, let scheduler else {
            self.configuration = nil; self.context = nil; self.scheduler = nil
            return
        }
        self.configuration = configuration; self.context = context; self.scheduler = scheduler
    }

    func retire() {
        notice.retire(); scheduler?.cancel(); cancellationDwell = nil
    }

    func nextCut(now: TimeInterval) -> NextShotStatus.DirectorSection.NextCut? {
        guard let value = notice.consoleNextCut(now: now) else { return nil }
        // Backup has no countdown or notice cancellation; Manual still takes over.
        return .init(input: value.input, countdown: value.countdown,
                     cancellable: notice.pending?.level != .backup)
    }

    /// Starts or refreshes a notice, never a Take. A current abstention retires
    /// the notice immediately. Refreshing the same shot preserves its deadline.
    func evaluate(now: TimeInterval) {
        guard let c = configuration else { return }
        guard let controller, let current = decision(now: now, configuration: c),
              case .cut(let plan) = current.decision else {
            controller?.retireAutomaticCuts(); controller?.automaticCutStatusChanged(); return
        }
        if let pending = notice.pending,
           !pending.plan.matches(current.live) || !pending.plan.hasSameShot(as: plan) || now > pending.expiresAt {
            controller.retireAutomaticCuts(); controller.automaticCutStatusChanged(); return
        }
        let old = notice.pending
        guard let token = notice.begin(current.decision, live: current.live, now: now,
                                       autoNoticeLength: c.autoNoticeLength, maximumLateness: c.maximumLateness) else {
            controller.retireAutomaticCuts(); controller.automaticCutStatusChanged(); return
        }
        cancellationDwell = controller.effectiveStyle?.minimumShotDuration
        controller.automaticCutStatusChanged()
        if old != token { schedule(token) }
    }

    @discardableResult func cancel(now: TimeInterval) -> Bool {
        guard let controller, let token = notice.pending, token.level == .auto else { return false }
        let cancelled = controller.cancelAutomaticCut(token, notice: &notice, now: now,
                                                       minimumShotDuration: cancellationDwell ?? .nan)
        if cancelled { scheduler?.cancel(); cancellationDwell = nil; controller.automaticCutStatusChanged() }
        return cancelled
    }

    private func schedule(_ token: CutNotice.Token) {
        scheduling = true
        scheduler?.schedule(deadline: token.deadline) { [weak self] in self?.deadline(token) }
        scheduling = false
    }

    private func deadline(_ token: CutNotice.Token) {
        // A cancelled/replaced callback cannot touch the new notice or lease.
        guard notice.pending == token, let controller else { return }
        guard !scheduling, let c = configuration else {
            controller.retireAutomaticCuts(); controller.automaticCutStatusChanged(); return
        }
        let now = controller.currentTime
        guard let current = decision(now: now, configuration: c) else {
            controller.retireAutomaticCuts(); controller.automaticCutStatusChanged(); return
        }
        let permit = controller.issueNoticePermit(token, notice: &notice, decision: current.decision,
                                                 now: now, validity: c.permitValidity)
        if notice.pending == nil { scheduler?.cancel(); cancellationDwell = nil }
        if let permit, let show {
            // No suspension or queued closure from fresh policy through permit,
            // consumption, technical validation and the existing router commit.
            let request = TakeRequest(expectedProgram: token.plan.program, expectedPreview: token.plan.preview,
                                      routeGeneration: token.plan.routeGeneration)
            lastResult = show.take(request, origin: .director, permit: permit)
        }
        controller.automaticCutStatusChanged()
    }

    private func decision(now: TimeInterval, configuration c: Configuration)
        -> (decision: CutPolicy.Decision, live: DirectorTakeState)? {
        guard DeveloperFlags.allowDirectorAuto, c.isValid, let controller, controller.isAttached,
              let show, !show.editLive, now.isFinite, now >= 0,
              let context = context?(now), context.timeline.now == now,
              context.program == show.programChannel,
              context.routeGeneration == show.router.routeGeneration,
              let program = show.channel(show.programChannel),
              program.revisions == context.programRevisions,
              program.directorShot == context.timeline.programShot,
              let preview = show.previewChannel, context.prepared.channel == preview,
              let channel = show.channel(preview), channel.revisions == context.previewRevisions,
              channel.directorShot == context.prepared.shot,
              channel.evidenceReadings(now: now).subjectSpeed == context.prepared.movement,
              let style = controller.effectiveStyle else { return nil }
        let segment = controller.runSheet?.current?.type ?? .liveEvent
        if controller.authority.level == .backup,
           [.panel, .performance, .videoBreak].contains(segment), !context.prepared.shot.isWide { return nil }
        let live = controller.currentTakeState(now: now)
        return (CutPolicy.evaluate(live: live, timeline: context.timeline, prepared: context.prepared,
            programIdentity: context.programIdentity, style: style, evidenceRevision: controller.evidenceRevision,
            judge: c.judge, judgeMaximumAge: c.judgeMaximumAge, minimumProbability: c.minimumProbability), live)
    }
}
