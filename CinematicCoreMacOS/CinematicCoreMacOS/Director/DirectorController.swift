//
//  DirectorController.swift
//  CinematicCoreMacOS
//
//  S3 B-03 (C1, C4): the Auto Director's engine-side owner. It listens to
//  every manual ingress (plan §5.3), samples evidence on an injectable 4 Hz
//  tick, keeps `DirectorAuthority` and `DirectorEvidenceAdapter` current, and
//  publishes the console's `DirectorSection`.
//
//  The default tick observes only. B-05 exposes an explicit Debug-only
//  Preview preparation boundary with supplied settings and qualification.
//  Cut scheduling remains B-08; the B-07 Take boundary always needs a permit.
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
    private(set) var runSheet: RunSheet?
    private(set) var isAttached = false
    /// Style changes retire stale work without changing authority or its epoch.
    enum StyleEvent: Equatable { case policyChanged(segmentID: UUID?) }
    private(set) var lastStyleEvent: StyleEvent?
    private var takePermits = TakePermitIssuer()
    private(set) var shadowRecorder: DirectorShadowRecorder?
    private var shadowTakeID: UUID?
    private var shadowStopCapture: DirectorShadowRecorder.StopActionCapture?
    private lazy var subjectConsole = DirectorSubjectConsole(show: show)
    private let judgeShadow = DirectorJudgeShadow()
    private var captureBindingProvider: DirectorShadowRecorder.CaptureBindingProvider?
    private var captureSettingsGeneration = UUID()
    private var resolvingCaptureBinding = false
    private(set) var evidenceRevision: UInt64 = 0
    private(set) lazy var assistPreparation = DirectorAssistPreparation(show: show, controller: self)
    private(set) lazy var cutExecution = DirectorCutExecution(show: show, controller: self)
    private(set) lazy var backupExecution = DirectorBackupExecution(show: show, controller: self)
    private(set) lazy var onAirMoves = DirectorOnAirMoveExecution(show: show, controller: self)
    private let cutReadinessParameters: DirectorReadiness.Parameters?
    private(set) var policyRevision: UInt64 = 0
    private(set) var nominationRevision: UInt64 = 0
    #if DEBUG
    /// Synthetic rig seam only; never installed by the app or compiled in Release.
    var cutReadinessForTesting: DirectorReadiness?
    #endif
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
         cutReadinessParameters: DirectorReadiness.Parameters? = nil,
         shadowLog: DirectorShadowLog? = nil,
         runSheet: RunSheet? = nil,
         log: ((String) -> Void)? = nil) {
        self.show = show
        self.runSheet = runSheet
        if let shadowLog { self.shadowRecorder = DirectorShadowRecorder(log: shadowLog) }
        self.ticker = ticker
        self.clock = clock
        self.qualifiedLevels = qualifiedLevels
        self.cutReadinessParameters = cutReadinessParameters
        self.adapter = adapterParameters.map(DirectorEvidenceAdapter.init(parameters:))
        self.log = log ?? { Self.logger.notice("[DIRECTOR] \($0, privacy: .public)") }
        // Every launch starts Manual (U2); nothing is restored.
        self.directorSection = .atLaunch(qualified: Self.qualification(qualifiedLevels()))
        refreshSection()
    }

    // MARK: Lifecycle

    /// Install every ingress hook and start ticking. Idempotent.
    func attach() {
        guard let show else { return }
        if !isAttached, !authority.paused {
            forward(.pause, pause: .setupChanged, note: "controller attaching")
        }
        assistPreparation.retire()
        retireAutomaticCuts()
        backupExecution.retire()
        onAirMoves.retire()
        detachHooks()
        show.takeAttemptObserver = { [weak self] origin in self?.takeAttempted(origin: origin) }
        show.takeResultObserver = { [weak self] origin, result in self?.takeFinished(origin: origin, result: result) }
        show.channelsChangedObserver = { [weak self] change in self?.channelsChanged(change) }
        show.router.stateObserver = { [weak self] state in self?.routerStateChanged(state) }
        show.programOutput.$activeRoute.removeDuplicates().dropFirst()
            .sink { [weak self] route in
                if route == nil { self?.forward(.outputFault, pause: .outputProblem) }
            }
            .store(in: &showCancellables)
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
        isAttached = true
        log("attached · default tick observes only; effects require explicit gated requests")
        refreshSection()
    }

    func detach() {
        shadowStopCapture = nil
        let wasAttached = isAttached
        isAttached = false
        assistPreparation.retire()
        retireSubjectDiscovery()
        backupExecution.retire()
        onAirMoves.retire()
        retireAutomaticCuts()
        // No automatic grant crosses a gap in the manual/fault ingress hooks.
        // Reattaching restores observation; explicit handback restores control.
        if wasAttached { forward(.pause, pause: .setupChanged, note: "controller detached") }
        refreshSection()
        ticker.stop()
        detachHooks()
    }

    private func detachHooks() {
        guard let show else { return }
        show.takeAttemptObserver = nil
        show.takeResultObserver = nil
        show.channelsChangedObserver = nil
        show.router.stateObserver = nil
        showCancellables.removeAll()
        for id in channelCancellables.keys { removeChannelHooks(id) }
    }

    private func installChannelHooks(_ id: ChannelID) {
        guard let channel = show?.channel(id) else { return }
        channel.manualActionObserver = { [weak self] action in self?.manualAction(action, on: id) }
        channel.manualResultObserver = { [weak self] command, result in
            guard let self else { return }
            let stopCapture = self.shadowStopCapture
            self.shadowStopCapture = nil
            guard command.origin == .operatorUI else { return }
            self.emitShadow(DirectorShadowRecorder.command(command, outcome: result.wasAccepted ? .accepted : .refused),
                authority: self.authority, stopActionCapture: stopCapture, stopActionChannel: id)
        }
        var bag: Set<AnyCancellable> = []
        channel.$sourceMissing.removeDuplicates().dropFirst()
            .sink { [weak self] missing in
                if missing {
                    if self?.backupExecution.sourceLoss(id) != true { self?.forward(.sourceLoss(id), pause: .sourceLost(id)) }
                } else { self?.forward(.sourceRebound(id), pause: .setupChanged) }
            }
            .store(in: &bag)
        channelCancellables[id] = bag
    }

    private func removeChannelHooks(_ id: ChannelID) {
        shadowStopCapture = nil
        show?.channel(id)?.manualActionObserver = nil
        show?.channel(id)?.manualResultObserver = nil
        channelCancellables[id] = nil
    }

    // MARK: Ingress (plan §5.3)

    private func manualAction(_ action: CameraManager.ManualCameraAction, on channel: ChannelID) {
        shadowStopCapture = nil
        retireSubjectDiscovery()
        switch action {
        case .command(let command):
            if command.origin == .operatorUI {
                let stopCapture = show.flatMap { shadowRecorder?.captureStopAttempt(command, on: channel, show: $0) }
                if emitShadow(DirectorShadowRecorder.command(command), authority: authority) { shadowStopCapture = stopCapture }
            }
            forward(.manualCommand, pause: .operatorTookOver, note: "manual \(command.action.logName) on \(channel.cameraLabel)")
        case .settingsChanged:
            let actionID = UUID()
            emitShadow(DirectorShadowRecorder.action(.settingsChanged, id: actionID), authority: authority)
            forward(.manualCommand, pause: .operatorTookOver, note: "settings changed on \(channel.cameraLabel)")
            // The current settings notification runs before @Published commits
            // the new value. Its completion is not observed at this boundary.
            emitShadow(DirectorShadowRecorder.action(.settingsChanged, id: actionID, outcome: .unobserved), authority: authority)
        }
    }

    private func takeAttempted(origin: TakeOrigin) {
        // Director and fallback Takes consume a permit (B-07); none exist in shadow.
        guard origin == .operatorUI else { return }
        let actionID = UUID()
        shadowTakeID = actionID
        emitShadow(DirectorShadowRecorder.action(.take, id: actionID), authority: authority)
        let style = effectiveStyle
        let timing = style.flatMap { value -> DirectorAuthority.TakeTiming? in
            guard (try? value.validated()) != nil else { return nil }
            return .init(now: clock(), minimumShotDuration: value.minimumShotDuration)
        }
        forward(.operatorTake, pause: .operatorTookOver, takeTiming: timing)
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
        if backupExecution.routerStateChanged(state) { return }
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
        guard now.isFinite, now >= 0 else { return }
        evidenceRevision &+= 1
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
        onAirMoves.validateRunning()
        cutExecution.evaluate(now: now)
        refreshSection()
        let comparisonEpoch = authority.epoch, comparisonEvidence = evidenceRevision
        let comparisonPolicy = policyRevision, comparisonNomination = nominationRevision
        let comparisonSettings = captureSettingsGeneration
        let comparison = judgeShadow.observe(show: show, now: now, evidenceRevision: evidenceRevision,
            style: effectiveStyle, policyRevision: policyRevision)
        if let comparison, comparisonEpoch == authority.epoch, comparisonEvidence == evidenceRevision,
           comparisonPolicy == policyRevision, comparisonNomination == nominationRevision,
           comparisonSettings == captureSettingsGeneration, comparison.style == effectiveStyle {
            if hasCaptureBindingProvider {
                guard let readiness = cutReadinessParameters,
                      let parameters = captureParameters(nil, readiness: readiness,
                          judgeMaximumAge: comparison.maximumAge, minimumProbability: comparison.minimumProbability),
                      comparisonEpoch == authority.epoch, comparisonEvidence == evidenceRevision,
                      comparisonPolicy == policyRevision, comparisonNomination == nominationRevision,
                      comparisonSettings == captureSettingsGeneration else {
                    shadowRecorder?.log.noteDropped(); return
                }
                emitShadow(DirectorShadowRecorder.judgeComparison, authority: authority,
                    judgeObservation: comparison, studyParameters: parameters)
            } else {
                emitShadow(DirectorShadowRecorder.judgeComparison, authority: authority, judgeObservation: comparison)
            }
        } else if !cutExecution.isConfigured {
            emitShadow(DirectorShadowRecorder.noCutPolicy, authority: authority)
        }
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

    /// A-10's chosen shot reaches the real camera boundary in this same turn.
    /// Missing study settings never call this path automatically from the tick.
    func preparePreview(_ shot: DirectorShot, configuration: DirectorAssistPreparation.Configuration) -> DirectorPreparationEffect {
        guard let request = assistPreparation.enqueue(shot, configuration: configuration) else {
            return .rejected([.evidenceUnavailable])
        }
        let result = assistPreparation.commit(request)
        refreshSection()
        return result
    }

    func preparationFailed() {
        log("preparation result or revisions did not match; taking over")
        guard isDirecting else { return }
        apply(.pause, pause: .setupChanged, note: "preparation failed")
    }

    @discardableResult private func emitShadow(_ event: DirectorShadowRecord.Event, authority before: DirectorAuthority,
                            judgeObservation: DirectorJudgeShadow.Observation? = nil,
                            evaluation: DirectorShadowRecorder.Evaluation? = nil,
                            studyParameters: DirectorShadowRecorder.Parameters? = nil,
                            stopActionCapture: DirectorShadowRecorder.StopActionCapture? = nil,
                            stopActionChannel: ChannelID? = nil) -> Bool {
        if event.kind == .operatorAction { shadowStopCapture = nil }
        guard let show else { return false }
        let requiresBinding = hasCaptureBindingProvider
        let parameters = studyParameters ?? (judgeObservation == nil && evaluation == nil ? cutExecution.captureParameters : nil)
        if requiresBinding, evaluation == nil, parameters == nil {
            shadowRecorder?.log.noteDropped(); return false
        }
        return shadowRecorder?.emit(event, show: show, authority: before, policy: policyRevision,
            nomination: nominationRevision, evidence: evidenceRevision, preferences: preferences, segment: runSheet?.current,
            judgeObservation: judgeObservation, eventTime: clock(),
            studyParameters: parameters,
            evaluation: evaluation, stopActionCapture: stopActionCapture, stopActionChannel: stopActionChannel) ?? false
    }

    /// Explicit study naming only. A configured provider owns every capture
    /// producer in this session; nil declines that group without legacy fallback.
    func configureCaptureForStudy(_ provider: DirectorShadowRecorder.CaptureBindingProvider?) {
        captureSettingsGeneration = UUID()
        captureBindingProvider = provider
    }

    var hasCaptureBindingProvider: Bool { captureBindingProvider != nil }
    var captureConfigurationRevision: UUID { captureSettingsGeneration }

    private struct CaptureWorld: Equatable {
        struct Input: Equatable {
            let id: ChannelID
            let object: ObjectIdentifier
            let source: DiagnosticsSessionIdentity.Source?
            let revisions: ChannelRevisions
            let running: Bool
            let missing: Bool
        }
        let program: ChannelID
        let preview: ChannelID?
        let route: UInt64
        let inputs: [Input]
    }
    private func captureWorld() -> CaptureWorld? {
        guard let show else { return nil }
        return .init(program: show.programChannel, preview: show.previewChannel,
            route: show.router.routeGeneration, inputs: ChannelID.allCases.compactMap { id in
                guard let channel = show.channel(id) else { return nil }
                return .init(id: id, object: ObjectIdentifier(channel), source: channel.sourceIdentity,
                    revisions: channel.revisions, running: channel.isRunning, missing: channel.sourceMissing)
            })
    }

    func captureParameters(_ fallback: DirectorShadowRecorder.CaptureBinding?,
                           readiness: DirectorReadiness.Parameters, judgeMaximumAge: Double? = nil,
                           minimumProbability: Double? = nil) -> DirectorShadowRecorder.Parameters? {
        func actualKey() -> DirectorShadowRecorder.CaptureKey? {
            guard let style = effectiveStyle, let adapter, let preferences,
                  (try? preferences.validated()) != nil, readiness.isValid, adapter.parameters.isValid,
                  judgeMaximumAge.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  minimumProbability.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { return nil }
            return .init(policyRevision: policyRevision, preferencesVersion: preferences.version,
                style: style, readiness: readiness, adapter: adapter.parameters,
                judgeMaximumAge: judgeMaximumAge, minimumProbability: minimumProbability)
        }
        guard let key = actualKey() else { return nil }
        let binding: DirectorShadowRecorder.CaptureBinding
        if let provider = captureBindingProvider {
            guard !resolvingCaptureBinding else { return nil }
            let generation = captureSettingsGeneration
            let world = captureWorld()
            resolvingCaptureBinding = true
            defer { resolvingCaptureBinding = false }
            guard let supplied = provider(key), generation == captureSettingsGeneration,
                  actualKey() == key, world == captureWorld() else { return nil }
            binding = supplied
        } else {
            guard let fallback else { return nil }
            binding = fallback
        }
        return .init(binding: binding, style: key.style, readiness: key.readiness, adapter: key.adapter,
                     judgeMaximumAge: key.judgeMaximumAge, minimumProbability: key.minimumProbability)
    }

    var captureCutReadinessParameters: DirectorReadiness.Parameters? { cutReadinessParameters }

    func captureDecision(_ event: DirectorShadowRecord.Event, evaluation: DirectorShadowRecorder.Evaluation) {
        emitShadow(event, authority: authority, evaluation: evaluation)
    }

    private func takeFinished(origin: TakeOrigin, result: TakeResult) {
        guard origin == .operatorUI, let id = shadowTakeID else { return }
        shadowTakeID = nil
        let outcome: DirectorShadowRecord.ActionOutcome
        var program: String?, preview: String?
        if case .committed(let channel) = result {
            outcome = .completed
            func alias(_ id: ChannelID) -> String { "input-\((ChannelID.allCases.firstIndex(of: id) ?? 0) + 1)" }
            program = alias(channel); preview = show?.previewChannel.map(alias)
        } else { outcome = .refused }
        emitShadow(DirectorShadowRecorder.action(.take, id: id, outcome: outcome,
            programAfter: program, previewAfter: preview), authority: authority)
    }

    /// Explicit local export; the caller supplies its user-chosen destination.
    func exportShadowLog(to destination: URL) async throws {
        guard let log = shadowRecorder?.log else { throw DirectorShadowLog.Failure.unavailable }
        try await log.export(session: log.sessionID, to: destination)
    }

    // MARK: One-shot Take boundary (B-07)

    /// Called by B-08 only after a fresh cut decision. No production timing
    /// defaults: the caller supplies the permit lease from approved parameters.
    func issueTakePermit(now: TimeInterval, validity: TimeInterval) -> TakePermit? {
        guard DeveloperFlags.allowDirectorAuto else { return nil }
        return takePermits.issue(live: currentTakeState(now: now), now: now, validity: validity)
    }

    func consumeTakePermit(_ permit: TakePermit, now: TimeInterval) -> Bool {
        // Even a disabled path consumes/discards its own matching attempt.
        guard DeveloperFlags.allowDirectorAuto else { takePermits.discard(permit); return false }
        if case .admitted = takePermits.consume(permit, live: currentTakeState(now: now), now: now) { return true }
        return false
    }

    /// Final cut readiness uses current motion/crop facts, not the previous
    /// tick's cached values. Debounced identity and settled history still come
    /// from the adapter, and stale adapter state cannot authorize a cut.
    static func currentCutInputs(sample: ChannelEvidenceSample, adapter: DirectorEvidenceAdapter,
                                 take: TakeAvailability, now: TimeInterval) -> DirectorReadiness.Inputs? {
        guard adapter.parameters.isValid, now.isFinite, now >= 0, sample.sampledAt == now,
              let state = adapter.state(for: sample.channel), let sampledAt = state.lastSampleAt,
              state.lockedTargetID == sample.lockedTargetID,
              sampledAt >= 0, now >= sampledAt,
              now - sampledAt <= adapter.parameters.maximumObservationAge else { return nil }
        // A new nomination must first pass through the adapter. The previous
        // subject's confirmation and settled duration cannot authorize it in
        // the interval before the next evidence tick.
        let rawIdentity = IdentityEvidence.classify(sample, maximumObservationAge: adapter.parameters.maximumObservationAge)
        let settled = sample.holdingSteady && sample.cropConverged && sample.subjectSpeed.isFinite &&
            sample.subjectSpeed >= 0 && sample.subjectSpeed <= adapter.parameters.stillSpeed
        return .init(take: take, identity: rawIdentity == state.identity ? rawIdentity : .unavailable,
            framingSettledFor: settled ? adapter.settledFor(sample.channel, now: now) : 0,
            motion: sample.subjectSpeed, cropConverged: sample.cropConverged)
    }

    struct TakeSnapshot {
        let live: DirectorTakeState
        let sample: ChannelEvidenceSample?
        let readinessInputs: DirectorReadiness.Inputs?
        let measuredReadiness: DirectorReadiness?
    }

    func currentTakeState(now: TimeInterval) -> DirectorTakeState { currentTakeSnapshot(now: now).live }

    func currentTakeSnapshot(now: TimeInterval) -> TakeSnapshot {
        let preview = show?.previewChannel
        let channel = preview.flatMap { show?.channel($0) }
        var ready = DirectorReadiness(reasons: [.evidenceUnavailable])
        var evidence = false
        var observedSample: ChannelEvidenceSample?
        var evaluatedInputs: DirectorReadiness.Inputs?
        var measuredReadiness: DirectorReadiness?
        if let show, let preview, let channel, let adapter, let p = cutReadinessParameters, let inputs = show.takeInputs() {
            let sample = Self.sample(channel.evidenceReadings(now: now))
            observedSample = sample
            let availability = TakeAvailability.evaluate(take: inputs, program: show.programChannel,
                preview: preview, standard: ShowStandard.activeOrCurrent, editLive: show.editLive)
            if let input = Self.currentCutInputs(sample: sample, adapter: adapter, take: availability, now: now) {
                ready = DirectorReadiness.evaluate(input, parameters: p, bar: .cut)
                evaluatedInputs = input; measuredReadiness = ready
                evidence = IdentityEvidence.classify(sample, maximumObservationAge: adapter.parameters.maximumObservationAge) == .confirmed &&
                    adapter.state(for: preview)?.evidenceAvailable == true
            }
        }
        #if DEBUG
        if let override = cutReadinessForTesting { ready = override; evidence = override.isReady; measuredReadiness = nil }
        #endif
        if show?.editLive == true { ready = .init(reasons: [.takeUnavailable]) }
        let live = DirectorTakeState(world: .init(authority: authority, program: show?.programChannel ?? .a, preview: preview,
            revisions: channel?.revisions, routeGeneration: show?.router.routeGeneration ?? 0,
            sourceMissing: channel?.sourceMissing ?? true, policyRevision: policyRevision,
            nominationRevision: nominationRevision, evidenceAvailable: evidence),
            prerequisites: prerequisites(), cutReadiness: ready,
            operatorGestureInProgress: channel?.operatorGestureInProgress ?? true)
        return .init(live: live, sample: observedSample, readinessInputs: evaluatedInputs,
                     measuredReadiness: measuredReadiness)
    }

    // MARK: Console control (DirectorConsoleControlling)

    @discardableResult
    func setLevel(_ level: Section.Level) -> DirectorControlResult {
        let requested = Self.authorityLevel(level)
        let actionID = UUID()
        emitShadow(DirectorShadowRecorder.action(.setLevel, id: actionID), authority: authority)
        let transition = authority.apply(.enable(requested), prerequisites: prerequisites())
        record(.enable(requested), transition: transition, note: "set level \(level.title)")
        emitShadow(DirectorShadowRecorder.action(.setLevel, id: actionID,
            outcome: transition.refusal == nil ? .accepted : .refused), authority: authority)
        if transition.refusal == nil { pauseReason = nil }
        refreshSection()
        return result(transition.refusal)
    }

    @discardableResult
    func handToAlfie() -> DirectorControlResult {
        let actionID = UUID()
        emitShadow(DirectorShadowRecorder.action(.handToAlfie, id: actionID), authority: authority)
        let transition = authority.apply(.handToAlfie, prerequisites: prerequisites())
        record(.handToAlfie, transition: transition, note: "hand to Alfie")
        emitShadow(DirectorShadowRecorder.action(.handToAlfie, id: actionID,
            outcome: transition.refusal == nil ? .accepted : .refused), authority: authority)
        if transition.refusal == nil { pauseReason = nil }
        refreshSection()
        return result(transition.refusal)
    }

    func takeOver() {
        guard isDirecting else { return }
        let actionID = UUID()
        emitShadow(DirectorShadowRecorder.action(.takeOver, id: actionID), authority: authority)
        apply(.pause, pause: .operatorTookOver, note: "operator took over")
        emitShadow(DirectorShadowRecorder.action(.takeOver, id: actionID, outcome: .accepted), authority: authority)
    }

    /// The console reads the current token at the action boundary.
    func cancelNextCut() { _ = cutExecution.cancel(now: clock()) }

    var currentTime: TimeInterval { clock() }

    /// Explicit trial setup only. Missing settings/provider/scheduler disables
    /// effects; a normal show continues to observe with no cut scheduling.
    func configureAutomaticCuts(_ configuration: DirectorCutExecution.Configuration?,
                                context: DirectorCutExecution.ContextProvider? = nil,
                                scheduler: (any DirectorCutDeadlineScheduling)? = nil) {
        captureSettingsGeneration = UUID()
        retireAutomaticCuts()
        cutExecution.configure(configuration, context: context, scheduler: scheduler)
        refreshSection()
    }

    /// An explicit rehearsal entry point using the same path as the 4 Hz tick.
    func evaluateAutomaticCuts() {
        cutExecution.evaluate(now: clock())
        refreshSection()
    }

    func retireAutomaticCuts() {
        cutExecution.retire()
        takePermits.retire()
    }

    func automaticCutStatusChanged() { refreshSection() }

    /// B-12 claims source loss before ordinary fault handling, then reserves
    /// against the resulting paused epoch. Recovery never grants handback.
    func applyBackupSourceLoss(_ channel: ChannelID) {
        apply(.sourceLoss(channel), pause: .sourceLost(channel), note: nil)
    }

    func backupFallbackFinished(_ result: TakeResult) {
        if case .committed = result { pauseReason = .afterFallback }
        refreshSection()
    }

    /// B-09 remains an explicit request with supplied timing/readiness. No
    /// automatic target selection or production motion settings are installed.
    func moveProgram(_ target: DirectorShot, programStartedAt: TimeInterval,
                     configuration: DirectorOnAirMoveExecution.Configuration) -> DirectorOnAirMoveExecution.Effect {
        guard let plan = onAirMoves.enqueue(target, programStartedAt: programStartedAt,
                                            configuration: configuration) else { return .rejected }
        let effect = onAirMoves.commit(plan)
        refreshSection()
        return effect
    }

    /// Pure notice validation and issuance finish before calling the real Take,
    /// so reentrant Take observers never access an inout notice value.
    func issueNoticePermit(_ token: CutNotice.Token, notice: inout CutNotice,
                           decision: CutPolicy.Decision, now: TimeInterval,
                           validity: TimeInterval) -> TakePermit? {
        guard DeveloperFlags.allowDirectorAuto else { notice.retire(); return nil }
        return notice.fire(token, decision: decision, live: currentTakeState(now: now), now: now,
                           permitValidity: validity, issuer: &takePermits)
    }

    func cancelAutomaticCut(_ token: CutNotice.Token, notice: inout CutNotice,
                            now: TimeInterval, minimumShotDuration: TimeInterval) -> Bool {
        guard notice.cancel(token, authority: &authority, now: now,
                            minimumShotDuration: minimumShotDuration) else { return false }
        takePermits.retire()
        assistPreparation.retire()
        backupExecution.retire()
        onAirMoves.retire()
        log("next cut cancelled · minimum-shot hold")
        return true
    }

    /// Explicitly supplied show context only; no authority or show identity is restored.
    @discardableResult
    func setRunSheet(_ sheet: RunSheet?) -> Bool {
        guard sheet != runSheet else { return true }
        guard policyRevision < UInt64.max else { return false }
        runSheet = sheet
        styleContextChanged()
        return true
    }

    /// Operator advancement is style-scoped. It cannot grant or pause authority.
    func advanceSegment() {
        let actionID = UUID()
        emitShadow(DirectorShadowRecorder.action(.advanceSegment, id: actionID), authority: authority)
        guard var next = runSheet, next.advance(), policyRevision < UInt64.max else {
            emitShadow(DirectorShadowRecorder.action(.advanceSegment, id: actionID, outcome: .refused), authority: authority)
            return
        }
        runSheet = next
        styleContextChanged()
        emitShadow(DirectorShadowRecorder.action(.advanceSegment, id: actionID, outcome: .accepted), authority: authority)
    }

    var effectiveStyle: DirectorStyle? {
        guard let preferences, (try? preferences.validated()) != nil else { return nil }
        return preferences.style(for: runSheet?.current?.type ?? .liveEvent)
    }

    /// Pure preparation choice using the current segment at the time of the call.
    /// The caller still needs the independent preparation and authority gates.
    func choosePreparation(_ timeline: DirectorShotPolicy.Timeline, preview: ChannelID) -> DirectorShotPolicy.Decision {
        guard let style = effectiveStyle else { return .abstain(.invalidInput) }
        return DirectorShotPolicy.choosePreparation(timeline, preview: preview, parameters: .init(style))
    }

    private func styleContextChanged() {
        retireSubjectDiscovery()
        policyRevision += 1
        retireAutomaticCuts()
        assistPreparation.retire()
        backupExecution.retire()
        onAirMoves.retire()
        lastStyleEvent = .policyChanged(segmentID: runSheet?.currentSegmentID)
        refreshSection()
    }

    /// Optional local A/B observation only; never installs a judge in a Take
    /// or preparation sink. Nil configuration/provider disables the trial.
    func configureJudgeShadow(_ configuration: DirectorJudgeShadow.Configuration?,
                              context: DirectorJudgeShadow.ContextProvider? = nil) {
        captureSettingsGeneration = UUID()
        judgeShadow.configure(configuration, context: context)
    }

    /// Sampled by the existing 15 Hz console refresh, never by frame writes.
    func sampleSectionForConsole() -> Section { refreshSection(); return directorSection }

    func overrideSubject(on channel: ChannelID, at point: CGPoint) {
        guard let pick = subjectConsole.picks(now: clock())[channel],
              let request = pick.overrideRequest(at: point) else { return }
        _ = overrideSubject(request)
    }

    @discardableResult
    func overrideSubject(_ request: DirectorSubjectOverrideRequest) -> DirectorControlResult {
        guard isAttached, let show, let camera = show.channel(request.channel),
              let pick = subjectConsole.picks(now: clock())[request.channel], request.matches(pick) else {
            return .refused("The camera or subject view changed; select again")
        }
        // Match the ordinary show command boundary before doing either step.
        guard show.controlTarget == request.channel,
              request.channel != show.programChannel || show.previewChannel == nil || show.editLive else {
            return .refused("Program changes need Edit Live")
        }
        let retarget = camera.manualLockedTargetID != nil
        if !retarget && !camera.detectionDiscoveryActive && !camera.canDirectlyReacquire {
            let armed = show.dispatch(show.makeCommand(.detect))
            guard armed.wasAccepted else { return .refused("Subject selection is unavailable") }
        }
        let result = show.dispatch(show.makeCommand(.selectSubject(request.point, retarget: retarget)))
        guard result.wasAccepted else { refreshSection(); return .refused("Subject selection is unavailable") }
        // This records the accepted nomination intent. Acquisition still has
        // to pass the existing ROI/gallery/identity path on a later frame.
        apply(.nominationChanged, pause: .subjectChanged, note: "operator nominated a subject")
        refreshSection()
        return .accepted
    }

    /// Explicit Debug study setup. Scanning never implies acquisition or a
    /// nomination, and cannot bootstrap missing authority prerequisites.
    func configureSubjectDiscoveryForStudy(_ configuration: DirectorSubjectDiscovery.Configuration?, on id: ChannelID) {
        #if DEBUG
        guard let camera = show?.channel(id) else { return }
        camera.configureSubjectDiscoveryForStudy(configuration) { [weak self] in
            guard let self, let show = self.show else { return nil }
            let pre = self.prerequisites()
            let permitted = self.isAttached && self.authority.running && !self.authority.paused &&
                self.authority.level != .off && self.authority.healthy && pre.sourcesHealthy &&
                pre.outputHealthy && pre.admissionCurrent && !show.editLive &&
                (self.authority.level == .suggest || pre.qualifiedLevels.contains(self.authority.level))
            return .init(program: show.programChannel, routeGeneration: show.router.routeGeneration,
                authorityEpoch: self.authority.epoch, policyRevision: self.policyRevision,
                nominationRevision: self.nominationRevision, permitted: permitted,
                mayAcquire: permitted && self.authority.mayPrepare && pre.nominationsCurrent)
        }
        #endif
    }

    private func retireSubjectDiscovery() {
        guard let show else { return }
        for id in ChannelID.allCases { show.channel(id)?.retireSubjectDiscovery() }
    }

    // MARK: Authority

    /// True while Alfie is directing (any level above Manual).
    private var isDirecting: Bool { authority.level != .off }

    /// While Manual there is nothing to take over: operator activity is the
    /// show, not an intervention. Health and prerequisites are re-checked when
    /// a level is chosen, so these events only matter while directing.
    private func forward(_ event: DirectorAuthority.Event, pause reason: Section.PauseReason?, note: String? = nil,
                         takeTiming: DirectorAuthority.TakeTiming? = nil) {
        guard isDirecting else { return }
        apply(event, pause: reason, note: note, takeTiming: takeTiming)
    }

    private func apply(_ event: DirectorAuthority.Event, pause reason: Section.PauseReason?, note: String?,
                       takeTiming: DirectorAuthority.TakeTiming? = nil) {
        let wasPaused = authority.paused
        let transition = authority.apply(event, takeTiming: takeTiming)
        record(event, transition: transition, note: note)
        if authority.paused, !wasPaused, let reason { pauseReason = reason }
        if !authority.paused { pauseReason = nil }
        refreshSection()
    }

    private func record(_ event: DirectorAuthority.Event, transition: DirectorAuthority.Transition, note: String?) {
        if transition.cancellations.contains(.take) {
            retireAutomaticCuts()
            backupExecution.retire(for: event)
            onAirMoves.retire()
        }
        if transition.cancellations.contains(.prepare) { assistPreparation.retire(); retireSubjectDiscovery() }
        if event == .policyChanged { policyRevision &+= 1 }
        if event == .nominationChanged { nominationRevision &+= 1 }
        if event == .restart { shadowStopCapture = nil; shadowRecorder?.restart() }
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
        section.backupAlert = backupExecution.alert
        section.subjectPicks = subjectConsole.picks(now: clock())
        if let runSheet, let current = runSheet.current {
            section.runSheet = .init(current: RunSheetSegmentText.title(current),
                next: runSheet.next.map(RunSheetSegmentText.title))
        }
        guard isDirecting, authority.level != .suggest else {
            if !authority.running { section.activity = .paused(.showStopped) }
            return section
        }
        section.level = Self.consoleLevel(authority.level)
        section.handedToAlfie = !authority.paused
        section.activity = activity()
        section.alfieSetShot = assistPreparation.alfieSetShots
        section.prepared = assistPreparation.preparedShot
        section.nextCut = cutExecution.nextCut(now: clock())
        if let prepared = section.prepared, section.activity.kind == .active {
            section.activity = .active(.preparing(input: prepared.input, shot: prepared.shot, settled: false))
        }
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
