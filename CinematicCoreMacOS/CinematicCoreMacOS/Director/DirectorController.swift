//
//  DirectorController.swift
//  CinematicCoreMacOS
//
//  S3 B-03 (C1, C4): the Auto Director's engine-side owner. It listens to
//  every manual ingress (plan §5.3), samples evidence on an injectable 4 Hz
//  tick, keeps `DirectorAuthority` and `DirectorEvidenceAdapter` current, and
//  publishes the console's `DirectorSection`.
//
//  Shadow only: this controller has **no camera effects**. It never
//  dispatches a command and never calls Take. Off-air preparation arrives in
//  B-05 (behind its own Debug flag), cuts in B-08.
//

import Combine
import Foundation
import OSLog
import QuartzCore

/// Drives the controller's evaluation. Injected so tests control time. The
/// tick returns false once its owner has gone, and the ticker then stops.
protocol DirectorTicker: AnyObject {
    func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool)
    func stop()
}

/// Production ticker: a MainActor task that sleeps between ticks. Not on the
/// frame path; each tick reads plain per-channel values only.
final class TaskDirectorTicker: DirectorTicker {
    private var task: Task<Void, Never>?

    func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, tick() else { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

final class DirectorController: ObservableObject, DirectorConsoleControlling {
    typealias Section = NextShotStatus.DirectorSection

    /// 4 Hz (plan C1). A scheduling rate, not a behavioural threshold.
    static let tickInterval: TimeInterval = 0.25

    /// Published only when it changes: at most once per tick or hook.
    @Published private(set) var directorSection: Section

    private(set) var authority = DirectorAuthority(reviewPolicy: .conservative)
    /// Nil until the owner records adapter parameters (T1–T3, sitting 2).
    /// Without them identity is never confirmed, so nothing can be prepared.
    private(set) var adapter: DirectorEvidenceAdapter?
    private(set) var preferences: DirectorPreferences?
    /// Every authority event applied, newest last (bounded). Diagnostics and tests.
    private(set) var appliedEvents: [DirectorAuthority.Event] = []

    private weak var show: ShowCoordinator?
    private let ticker: DirectorTicker
    private let clock: () -> TimeInterval
    private let qualifiedLevels: () -> Set<DirectorAuthority.Level>
    private let log: (String) -> Void

    private var pauseReason: Section.PauseReason?
    private var showCancellables: Set<AnyCancellable> = []
    private var channelCancellables: [ChannelID: Set<AnyCancellable>] = [:]
    private var lastAdmissionRefused = false
    private var lastLogged: String?
    private static let eventHistoryLimit = 64

    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Director")

    init(show: ShowCoordinator,
         ticker: DirectorTicker = TaskDirectorTicker(),
         clock: @escaping () -> TimeInterval = { CACurrentMediaTime() },
         qualifiedLevels: @escaping () -> Set<DirectorAuthority.Level> = { [] },
         adapterParameters: DirectorEvidenceAdapter.Parameters? = nil,
         log: ((String) -> Void)? = nil) {
        self.show = show
        self.ticker = ticker
        self.clock = clock
        self.qualifiedLevels = qualifiedLevels
        self.adapter = adapterParameters.map(DirectorEvidenceAdapter.init(parameters:))
        self.log = log ?? { Self.logger.notice("[DIRECTOR] \($0, privacy: .public)") }
        // Every launch starts Manual (U2); nothing is restored.
        self.directorSection = .atLaunch(qualified: Self.qualification(qualifiedLevels()))
    }

    // MARK: Lifecycle

    /// Install every ingress hook and start ticking. Idempotent.
    func attach() {
        guard let show else { return }
        detachHooks()
        show.takeAttemptObserver = { [weak self] origin in self?.takeAttempted(origin: origin) }
        show.channelsChangedObserver = { [weak self] change in self?.channelsChanged(change) }
        show.router.stateObserver = { [weak self] state in self?.routerStateChanged(state) }
        show.$editLive.removeDuplicates().dropFirst()
            .sink { [weak self] live in self?.forward(.editLive(live), pause: live ? .editLive : nil) }
            .store(in: &showCancellables)
        for id in ChannelID.allCases { if show.channel(id) != nil { installChannelHooks(id) } }
        lastAdmissionRefused = Self.isRefused(show.admissionDecision)
        ticker.start(every: Self.tickInterval) { [weak self] in
            guard let self else { return false }
            self.tick()
            return true
        }
        log("attached · shadow only, no camera effects")
        refreshSection()
    }

    func detach() {
        ticker.stop()
        detachHooks()
    }

    private func detachHooks() {
        guard let show else { return }
        show.takeAttemptObserver = nil
        show.channelsChangedObserver = nil
        show.router.stateObserver = nil
        showCancellables.removeAll()
        for id in channelCancellables.keys { removeChannelHooks(id) }
    }

    private func installChannelHooks(_ id: ChannelID) {
        guard let channel = show?.channel(id) else { return }
        channel.manualActionObserver = { [weak self] action in self?.manualAction(action, on: id) }
        var bag: Set<AnyCancellable> = []
        channel.$sourceMissing.removeDuplicates().dropFirst()
            .sink { [weak self] missing in
                if missing { self?.forward(.sourceLoss(id), pause: .sourceLost(id)) }
                else { self?.forward(.sourceRebound(id), pause: .setupChanged) }
            }
            .store(in: &bag)
        channelCancellables[id] = bag
    }

    private func removeChannelHooks(_ id: ChannelID) {
        show?.channel(id)?.manualActionObserver = nil
        channelCancellables[id] = nil
    }

    // MARK: Ingress (plan §5.3)

    private func manualAction(_ action: CameraManager.ManualCameraAction, on channel: ChannelID) {
        switch action {
        case .command(let command):
            forward(.manualCommand, pause: .operatorTookOver, note: "manual \(command.action.logName) on \(channel.cameraLabel)")
        case .settingsChanged:
            forward(.manualCommand, pause: .operatorTookOver, note: "settings changed on \(channel.cameraLabel)")
        }
    }

    private func takeAttempted(origin: TakeOrigin) {
        // Director and fallback Takes consume a permit (B-07); none exist in shadow.
        guard origin == .operatorUI else { return }
        forward(.operatorTake, pause: .operatorTookOver)
    }

    private func channelsChanged(_ change: ShowCoordinator.ChannelChange) {
        switch change {
        case .added(let id):
            installChannelHooks(id)
            forward(.sourceRebound(id), pause: .setupChanged)
        case .removed(let id):
            removeChannelHooks(id)
            forward(.sourceLoss(id), pause: .setupChanged)
        case .showStopped:
            apply(.stopShow, pause: .showStopped, note: "show stopped")
        case .newShowPrepared:
            apply(.restart, pause: nil, note: "new show · Manual")
        }
    }

    private func routerStateChanged(_ state: ProgramRouter.State) {
        switch state {
        case .holding, .standby:
            // Backup's own fallback (B-12) will claim the source-loss hold first.
            forward(.outputFault, pause: .outputProblem)
        case .idle, .routed:
            break
        }
    }

    /// C-04 saved new styles. Parameters change, so Alfie pauses (§5.3).
    func preferencesChanged(_ preferences: DirectorPreferences) {
        self.preferences = preferences
        forward(.policyChanged, pause: .styleChanged, note: "styles saved")
    }

    // MARK: Tick

    /// One evaluation: sample every channel's evidence, update the adapter
    /// and authority, re-check health and admission, publish status.
    func tick() {
        guard let show else { return }
        let now = clock()
        guard now.isFinite else { return }
        let preview = show.previewChannel
        for id in ChannelID.allCases {
            guard let channel = show.channel(id) else { continue }
            let readings = channel.evidenceReadings(now: now)
            guard var current = adapter else { continue }
            let events = current.ingest(Self.sample(readings))
            adapter = current
            for event in events { evidenceEvent(event, preview: preview) }
        }

        let refused = Self.isRefused(show.admissionDecision)
        if refused, !lastAdmissionRefused { forward(.admissionLost, pause: .setupChanged) }
        lastAdmissionRefused = refused

        if isDirecting, !authority.healthy, prerequisites().sourcesHealthy, prerequisites().outputHealthy {
            apply(.healthRestored, pause: nil, note: "health restored")
        }
        refreshSection()
    }

    private func evidenceEvent(_ event: DirectorEvidenceAdapter.Event, preview: ChannelID?) {
        switch event {
        case .evidenceAvailable(let channel, let available):
            // Preparation targets Preview, so only its evidence gates it.
            guard channel == preview else { return }
            apply(.evidenceAvailable(available), pause: nil, note: nil)
        case .identityLost(let channel):
            forward(.identityLost(channel), pause: .subjectLost(channel))
        case .nominationChanged:
            forward(.nominationChanged, pause: .subjectChanged)
        }
    }

    // MARK: Console control (DirectorConsoleControlling)

    @discardableResult
    func setLevel(_ level: Section.Level) -> DirectorControlResult {
        let requested = Self.authorityLevel(level)
        let transition = authority.apply(.enable(requested), prerequisites: prerequisites())
        record(.enable(requested), transition: transition, note: "set level \(level.title)")
        if transition.refusal == nil { pauseReason = nil }
        refreshSection()
        return result(transition.refusal)
    }

    @discardableResult
    func handToAlfie() -> DirectorControlResult {
        let transition = authority.apply(.handToAlfie, prerequisites: prerequisites())
        record(.handToAlfie, transition: transition, note: "hand to Alfie")
        if transition.refusal == nil { pauseReason = nil }
        refreshSection()
        return result(transition.refusal)
    }

    func takeOver() {
        guard isDirecting else { return }
        apply(.pause, pause: .operatorTookOver, note: "operator took over")
    }

    /// Cuts arrive in B-08; there is never a next cut to cancel in shadow.
    func cancelNextCut() {}

    /// Run-sheet segments arrive with A-13 / B-11.
    func advanceSegment() {}

    /// Subject override arrives with B-10 (E1).
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {}

    // MARK: Authority

    /// True while Alfie is directing (any level above Manual).
    private var isDirecting: Bool { authority.level != .off }

    /// While Manual there is nothing to take over: operator activity is the
    /// show, not an intervention. Health and prerequisites are re-checked when
    /// a level is chosen, so these events only matter while directing.
    private func forward(_ event: DirectorAuthority.Event, pause reason: Section.PauseReason?, note: String? = nil) {
        guard isDirecting else { return }
        apply(event, pause: reason, note: note)
    }

    private func apply(_ event: DirectorAuthority.Event, pause reason: Section.PauseReason?, note: String?) {
        let wasPaused = authority.paused
        let transition = authority.apply(event)
        record(event, transition: transition, note: note)
        if authority.paused, !wasPaused, let reason { pauseReason = reason }
        if !authority.paused { pauseReason = nil }
        refreshSection()
    }

    private func record(_ event: DirectorAuthority.Event, transition: DirectorAuthority.Transition, note: String?) {
        appliedEvents.append(event)
        if appliedEvents.count > Self.eventHistoryLimit { appliedEvents.removeFirst(appliedEvents.count - Self.eventHistoryLimit) }
        if let refusal = transition.refusal { log("\(note ?? "event") refused: \(refusal)") }
        else if let note { log(note) }
    }

    private func result(_ refusal: DirectorAuthority.Refusal?) -> DirectorControlResult {
        switch refusal {
        case nil: return .accepted
        case .notQualified: return .refused(Section.notQualifiedCaption)
        case .prerequisites, .paused, .exhausted:
            // The current status sentence says why (no invented text).
            let activity = directorSection.activity
            return .refused(activity.kind == .active ? Section.AbstainReason.cannotDecide.text : activity.text)
        }
    }

    /// Test seam: replaces the live prerequisite reading. Never set by the app.
    var prerequisitesOverride: (() -> DirectorAuthority.Prerequisites)?

    func prerequisites() -> DirectorAuthority.Prerequisites {
        if let prerequisitesOverride { return prerequisitesOverride() }
        guard let show else {
            return .init(nominationsCurrent: false, previewAvailable: false, sourcesHealthy: false,
                         outputHealthy: false, admissionCurrent: false)
        }
        let channels = ChannelID.allCases.compactMap { show.channel($0) }
        let preview = show.previewChannel.flatMap { show.channel($0) }
        return .init(
            // E1: the operator has nominated a subject on the input Alfie would prepare.
            nominationsCurrent: preview?.evidenceReadings(now: clock()).lockedTargetID != nil,
            previewAvailable: preview != nil,
            sourcesHealthy: !channels.isEmpty && channels.allSatisfy { $0.isRunning && !$0.sourceMissing },
            outputHealthy: show.router.state == .routed,
            admissionCurrent: !Self.isRefused(show.admissionDecision),
            qualifiedLevels: qualifiedLevels())
    }

    // MARK: Status

    private func refreshSection() {
        let next = makeSection()
        guard next != directorSection else { return }
        if next.statusLine != directorSection.statusLine { log("status: \(next.statusLine)") }
        directorSection = next
    }

    private func makeSection() -> Section {
        let qualified = Self.qualification(qualifiedLevels())
        var section = Section.atLaunch(qualified: qualified)
        guard isDirecting, authority.level != .suggest else {
            if !authority.running { section.activity = .paused(.showStopped) }
            return section
        }
        section.level = Self.consoleLevel(authority.level)
        section.handedToAlfie = !authority.paused
        section.activity = activity()
        return section
    }

    private func activity() -> Section.Activity {
        if !authority.running { return .paused(.showStopped) }
        if authority.paused { return .paused(pauseReason ?? .operatorTookOver) }
        guard let show, let preview = show.previewChannel else { return .abstaining(.noPreview) }
        guard let adapter else { return .abstaining(.cannotDecide) }
        guard let state = adapter.state(for: preview) else { return .inhibited(.noFreshView(preview)) }
        if state.operatorGestureInProgress { return .inhibited(.operatorAdjusting(preview)) }
        switch state.identity {
        case .confirmed: return .active(.watching)
        case .acquiring: return .inhibited(.learningSubject(preview))
        case .holding: return .inhibited(.recoveringSubject(preview))
        case .ambiguous: return .abstaining(.moreThanOnePerson(preview))
        case .lost: return .paused(.subjectLost(preview))
        case .unavailable: return .inhibited(.noFreshView(preview))
        }
    }

    // MARK: Mapping

    static func sample(_ r: ChannelEvidenceReadings) -> ChannelEvidenceSample {
        ChannelEvidenceSample(channel: r.channel, sampledAt: r.sampledAt, lockPhase: r.lockPhase,
            trackingOwnsControl: r.trackingOwnsControl, galleryReady: r.galleryReady,
            lockedTargetID: r.lockedTargetID, observationAge: r.observationAge, subjectSpeed: r.subjectSpeed,
            holdingSteady: r.holdingSteady, cropConverged: r.cropConverged,
            operatorGestureInProgress: r.operatorGestureInProgress, observedPersonCount: r.observedPersonCount)
    }

    static func consoleLevel(_ level: DirectorAuthority.Level) -> Section.Level {
        switch level {
        case .off, .suggest: .manual
        case .assist: .assist
        case .auto: .auto
        case .backup: .backup
        }
    }

    static func authorityLevel(_ level: Section.Level) -> DirectorAuthority.Level {
        switch level {
        case .manual: .off
        case .assist: .assist
        case .auto: .auto
        case .backup: .backup
        }
    }

    static func qualification(_ levels: Set<DirectorAuthority.Level>) -> Section.Qualification {
        .init(assist: levels.contains(.assist), auto: levels.contains(.auto), backup: levels.contains(.backup))
    }

    private static func isRefused(_ decision: AdmissionDecision) -> Bool {
        if case .refused = decision { return true }
        return false
    }
}

private extension OperatorCommand.Action {
    /// Category only: no coordinates or names reach the log.
    var logName: String {
        let text = String(describing: self)
        return String(text.prefix { $0 != "(" })
    }
}
