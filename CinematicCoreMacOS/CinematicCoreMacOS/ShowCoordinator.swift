//
//  ShowCoordinator.swift
//  CinematicCoreMacOS
//
//  Show-level owner (CHANNEL card): the one ProgramOutputManager, the set of
//  channels, and which channel is Program. Channels are per-camera
//  controllers (CameraManager) that receive the shared output; they never
//  create one. Only the Program channel's port reaches the output.
//
//  ProgramRouter owns which channel feeds program output, the output clock,
//  and route generations. CaptureDeviceRegistry leases devices. Commands are
//  bound to a channel id. Channel A starts routed. A second channel is added
//  unrouted.
//

import Combine
import Foundation
import QuartzCore

final class ShowCoordinator: ObservableObject {
    /// The show's single program output. Exactly one per show.
    let programOutput: ProgramOutputManager

    /// Channels by ID. A always exists; R2 adds at most B (C/D are reserved).
    private(set) var channels: [ChannelID: CameraManager] = [:]

    /// Sole owner of routing: which channel feeds `programOutput`, the output
    /// clock, route generations and source-loss hold / standby.
    let router: ProgramRouter

    /// The channel whose port feeds `programOutput`.
    var programChannel: ChannelID { router.programChannel }

    /// Exclusive device leases shared by every channel (DEVICES).
    let deviceRegistry = CaptureDeviceRegistry()

    /// Fair, bounded render / perception admission across channels (SCHEDULER).
    let workScheduler = FrameWorkScheduler()

    var channelA: CameraManager { channels[.a]! }

    /// Single Cam, Multi Cam or Webcam (MODES-SPEC). Every channel's composer
    /// format follows it, including channels added later.
    let operatorModes: OperatorModeStore

    // MARK: Control target (CHANNEL-CMD)

    /// The channel every console control acts on: Preview by default, Program
    /// only while Edit Live is on (or when there is no Preview). Changes
    /// rarely, so it is published.
    @Published private(set) var controlTarget: ChannelID = .a
    @Published private(set) var editLive = false

    /// Increments whenever the control target (or Edit Live) changes. A UI
    /// command created under an older revision is rejected, so a gesture
    /// started for one camera can never land on another.
    private(set) var controlTargetRevision: UInt64 = 0

    /// The non-Program channel. With two inputs Preview is always the other
    /// channel; cueing among 3–4 inputs is the CUE card.
    var previewChannel: ChannelID? {
        ChannelID.allCases.first { $0 != programChannel && channels[$0] != nil }
    }

    /// - Parameter programOutput: injected in tests; the app passes nil and
    ///   gets the real virtual-camera + Program Display output.
    /// - Parameter operatorModes: injected in tests; the app passes nil and
    ///   gets the mode saved in standard user defaults.
    init(programOutput: ProgramOutputManager? = nil, admissionRecords: AdmissionRecordStore? = nil,
         qualificationRecords: DirectorQualificationStore? = nil, directorShadowLog: DirectorShadowLog? = nil,
         directorRunSheet: RunSheet? = nil, operatorModes: OperatorModeStore? = nil) {
        self.operatorModes = operatorModes ?? OperatorModeStore()
        self.initialDirectorShadowLog = directorShadowLog
        self.initialDirectorRunSheet = directorRunSheet
        self.admissionRecords = admissionRecords ?? AdmissionRecordStore()
        self.qualificationRecords = qualificationRecords ?? .applicationSupport()
        let rehearsal: [any ProgramOutputSink] = DeveloperFlags.allowRehearsalOutput ? [RehearsalOutputSink()] : []
        let output = programOutput
            ?? ProgramOutputManager(sinks: [VirtualCameraOutputSink(), DisplayOutputSink()] + rehearsal)
        self.programOutput = output
        self.router = ProgramRouter(output: output, programChannel: .a)
        let router = self.router
        workScheduler.isProgram = { router.isProgram($0) }
        let a = CameraManager(channelID: .a, programOutput: output, outputPort: router.port(for: .a))
        a.deviceRegistry = deviceRegistry
        a.workScheduler = workScheduler
        self.operatorModes.apply(to: a)
        channels[.a] = a
        self.operatorModes.switchDecision = { [weak self] from, to in
            guard let self else { return .allowed }
            return OperatorModeSwitch.decide(from: from, to: to, state: self.modeSwitchState)
        }
        self.operatorModes.modeChanged = { [weak self] from, to in self?.operatorModeChanged(from: from, to: to) }
    }

    /// Any channel is running or starting.
    var isAnyChannelLive: Bool {
        channels.values.contains { $0.isRunning || $0.isStartingSession }
    }

    /// What the live-switch rule needs to know about the show.
    var modeSwitchState: OperatorModeSwitch.ShowState {
        .init(isLive: isAnyChannelLive, programChannel: programChannel,
              otherChannels: ChannelID.allCases.filter { $0 != .a && channels[$0] != nil })
    }

    private func operatorModeChanged(from: OperatorMode, to: OperatorMode) {
        if isAnyChannelLive {
            programOutput.noteDiagnostics("mode \(from.diagnosticsName) -> \(to.diagnosticsName) while live")
        }
        applyOperatorMode()
    }

    /// Bring every channel in line with the operator mode. A single-input
    /// mode (Single Cam, Webcam) leaves Edit Live, and while everything is
    /// stopped also prepares a new show, so no other channel is kept from
    /// Multi Cam and A is Program.
    private func applyOperatorMode() {
        for channel in channels.values { operatorModes.apply(to: channel) }
        if !operatorModes.mode.allowsMultipleInputs {
            setEditLive(false)
            prepareForNewShow()
        }
    }

    func channel(_ id: ChannelID) -> CameraManager? { channels[id] }

    /// Add an unrouted channel. It shares the show output object for
    /// show-level status only; its port cannot start, stop or send to it.
    /// Returns the existing channel if already added.
    @discardableResult
    func addChannel(_ id: ChannelID) -> CameraManager {
        if let existing = channels[id] { return existing }
        let channel = CameraManager(channelID: id, programOutput: programOutput, outputPort: router.port(for: id))
        channel.deviceRegistry = deviceRegistry
        channel.workScheduler = workScheduler
        operatorModes.apply(to: channel)
        channels[id] = channel
        retarget()
        channelsChangedObserver?(.added(id))
        return channel
    }

    /// Stop and drop a non-Program channel. The Program channel cannot be
    /// removed (the show would have no source); stop the show instead.
    /// Channel A is never removed either: it is the show's home channel and
    /// `channelA` relies on it, so after a Take to B, A stays as Preview
    /// (CR-019).
    func removeChannel(_ id: ChannelID) {
        guard id != programChannel, id != .a, let channel = channels[id] else { return }
        channel.stopCapture()
        channels[id] = nil
        retarget()
        channelsChangedObserver?(.removed(id))
    }

    /// Show-level Stop: retires every channel's generation and epoch.
    func stopShow() {
        for id in ChannelID.allCases { channels[id]?.stopCapture() }
        editLive = false
        resetProgramToA()
        retarget()
        channelsChangedObserver?(.showStopped)
    }

    /// A new show starts from A as Program with no other channel, whatever
    /// the last show ended on (roles are never restored). Only while every
    /// channel is stopped.
    func prepareForNewShow() {
        guard channels.values.allSatisfy({ !$0.isRunning && !$0.isStartingSession }) else { return }
        resetProgramToA()
        for id in ChannelID.allCases where id != .a { removeChannel(id) }
        setEditLive(false)
        channelsChangedObserver?(.newShowPrepared)
    }

    // MARK: Auto Director (S3 B-03)

    /// Show-level changes the Director must hear about (plan §5.3).
    enum ChannelChange: Equatable {
        case added(ChannelID), removed(ChannelID), showStopped, newShowPrepared
    }

    var channelsChangedObserver: ((ChannelChange) -> Void)?

    /// Optional, explicitly budgeted metadata storage; no implicit I/O defaults.
    private let initialDirectorShadowLog: DirectorShadowLog?
    private let initialDirectorRunSheet: RunSheet?
    /// Read-only export access must not instantiate the lazy Director.
    var shadowLogForExport: DirectorShadowLog? { initialDirectorShadowLog }
    private weak var startedDirector: DirectorController?
    var directorSectionForConsole: NextShotStatus.DirectorSection? {
        guard DeveloperFlags.runDirectorShadow, let startedDirector, startedDirector.isAttached else { return nil }
        return startedDirector.sampleSectionForConsole()
    }
    /// UI actions use the retained controller; reading status never starts it.
    var directorControlForConsole: (any DirectorConsoleControlling)? {
        guard DeveloperFlags.runDirectorShadow, let startedDirector, startedDirector.isAttached else { return nil }
        return startedDirector
    }
    /// The show owns authority and the configured Debug-only effect boundaries.
    private(set) lazy var director = DirectorController(
        show: self, clock: { [weak self] in self?.clock() ?? CACurrentMediaTime() },
        qualifiedLevels: { [weak self] in self?.qualifiedDirectorLevels ?? [] },
        shadowLog: initialDirectorShadowLog, runSheet: initialDirectorRunSheet)

    /// Start the Director's shadow when the flag allows it. Every launch is Manual.
    func startDirectorShadow() {
        guard DeveloperFlags.runDirectorShadow else { return }
        director.attach()
        startedDirector = director
    }

    /// Explicit operator action against an already attached Director only.
    func advanceDirectorSegment() {
        guard DeveloperFlags.runDirectorShadow, let startedDirector, startedDirector.isAttached else { return }
        startedDirector.advanceSegment()
    }

    /// Styles saved in Settings reach the running Director (CR-037). Only
    /// while the shadow can run: where the flag is off nothing else creates
    /// the Director, and a save must not.
    func directorPreferencesChanged(_ preferences: DirectorPreferences) {
        guard DeveloperFlags.runDirectorShadow else { return }
        director.preferencesChanged(preferences)
    }

    private func resetProgramToA() {
        if programChannel != .a {
            router.setProgram(.a, expectedRouteGeneration: router.routeGeneration)
        }
    }

    // MARK: Admission (ADMISSION)

    /// Measured results by configuration fingerprint.
    let admissionRecords: AdmissionRecordStore

    /// The configuration as it stands now. Any change to devices, delivered
    /// formats, rates, modes, show standard, route or policy changes it.
    func admissionFingerprint() -> AdmissionFingerprint {
        let identity = programOutput.currentSessionIdentity()
        return AdmissionFingerprint(
            machineModel: identity.build.machineModel,
            osVersion: identity.build.osVersion,
            showStandard: ShowStandard.activeOrCurrent.title,
            route: identity.output.route ?? programOutput.preferredRoute.title,
            inputs: ChannelID.allCases.compactMap { channels[$0]?.admissionInput })
    }

    var admissionStatus: AdmissionStatus {
        channels.count < 2 ? .provisional : admissionRecords.status(for: admissionFingerprint())
    }

    /// What the show may do with the second input right now. A single input
    /// needs no pair admission.
    var admissionDecision: AdmissionDecision {
        AdmissionDecision.decide(admissionStatus)
    }

    func recordAdmission(_ result: PairAdmissionResult) {
        admissionRecords.record(result.status, for: admissionFingerprint())
    }

    // MARK: Director qualification (S3 B-06, C16)

    /// Per-level sign-off records bound to the admission fingerprint.
    let qualificationRecords: DirectorQualificationStore

    /// Director levels this rig may select right now. Empty unless a sign-off
    /// matches the current fingerprint; any configuration change empties it.
    var qualifiedDirectorLevels: Set<DirectorAuthority.Level> {
        qualificationRecords.qualifiedLevels(for: admissionFingerprint())
    }

    func pairAdmissionContext(preview: ChannelID) -> PairAdmissionContext {
        let a = channels[programChannel]
        let identity = programOutput.currentSessionIdentity()
        return PairAdmissionContext(
            program: CapabilityContext(
                captureFPS: a?.configuredCaptureFPS ?? identity.source.configuredCaptureFPS,
                showStandard: ShowStandard.activeOrCurrent.title,
                showFPS: ShowStandard.activeOrCurrent.frameRate,
                belowShowRate: identity.source.belowShowRate,
                source: programChannel.cameraLabel,
                route: identity.output.route,
                expectsDetection: channels.values.contains {
                    $0.activeMode == .autoTracking || $0.detectionDiscoveryActive
                }),
            previewCaptureFPS: channels[preview]?.configuredCaptureFPS)
    }

    // MARK: Take (TAKE)

    private var lastTakeAt: TimeInterval = -.infinity
    /// Host clock; injectable for tests.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    /// Freshness window for Take: one show-frame period, or one capture
    /// period when the Preview camera runs below the show rate (a 30 fps
    /// webcam never renders every 20 ms).
    private func framePeriod(for channel: CameraManager) -> TimeInterval {
        let showRate = ShowStandard.activeOrCurrent.frameRate
        let rate = channel.configuredCaptureFPS.map { min($0, showRate) } ?? showRate
        return 1 / max(rate, 1)
    }

    /// Bind a Take at the click to the roles and route generation now.
    func makeTakeRequest() -> TakeRequest? {
        guard let preview = previewChannel else { return nil }
        return TakeRequest(expectedProgram: programChannel, expectedPreview: preview,
                           routeGeneration: router.routeGeneration)
    }

    /// Live Take eligibility for the console (feeds TakeAvailability).
    func takeInputs() -> ConsoleSnapshot.TakeInputs? {
        guard let preview = previewChannel, let channel = channels[preview] else { return nil }
        return TakeRules.inputs(
            frame: channel.latestRenderedFrame, previewChannel: preview, current: channel.revisions,
            sourceMissing: channel.sourceMissing, admission: admissionDecision,
            now: clock(), framePeriod: framePeriod(for: channel))
    }

    /// Hard cut to the prepared Preview. Validates now; never arms a later
    /// cut. Commits only when the output accepts the Preview frame; then roles
    /// swap, Edit Live ends and controls return to the new Preview. Motion on
    /// both channels continues.
    /// S3 B-02: every Take attempt, reported before any check so refused
    /// attempts are seen too.
    var takeAttemptObserver: ((TakeOrigin) -> Void)?
    var takeResultObserver: ((TakeOrigin, TakeResult) -> Void)?

    @discardableResult
    func take(_ request: TakeRequest? = nil, origin: TakeOrigin = .operatorUI,
              permit: TakePermit? = nil, fallbackPermit: BackupFallbackPolicy.Permit? = nil) -> TakeResult {
        // Retire only discovery leases before every origin's Take boundary.
        // Never drain Vision or invalidate ordinary tracking evidence here.
        for channel in channels.values { channel.retireSubjectDiscovery() }
        takeAttemptObserver?(origin)
        let result = performTake(request, origin: origin, permit: permit, fallbackPermit: fallbackPermit)
        takeResultObserver?(origin, result)
        return result
    }

    private func performTake(_ request: TakeRequest?, origin: TakeOrigin, permit: TakePermit?,
                             fallbackPermit: BackupFallbackPolicy.Permit?) -> TakeResult {
        // Every matching attempt is consumed before technical checks. The
        // fault grant is a distinct type and never borrows a normal permit.
        var fallbackWindow: ProgramRouter.HoldWindow?
        switch origin {
        case .operatorUI: break
        case .director:
            guard let permit, director.consumeTakePermit(permit, now: clock()), fallbackPermit == nil else {
                return .rejected(.directorNotAuthorized)
            }
        case .fallback:
            // Preserve the old rejection's terminal normal-lease behavior.
            if let permit { _ = director.consumeTakePermit(permit, now: clock()) }
            guard let fallbackPermit,
                  let window = director.backupExecution.consume(fallbackPermit, now: clock()), permit == nil else {
                return .rejected(.directorNotAuthorized)
            }
            fallbackWindow = window
        }
        guard let request = request ?? makeTakeRequest(), let preview = previewChannel,
              let channel = channels[preview] else {
            return .rejected(.noPreview)
        }
        guard request.expectedProgram == programChannel, request.expectedPreview == preview,
              request.routeGeneration == router.routeGeneration else {
            return .rejected(.superseded)
        }
        let now = clock()
        guard now - lastTakeAt >= TakeRules.minimumInterval else { return .rejected(.tooSoon) }

        guard let inputs = takeInputs() else { return .rejected(.noPreview) }
        let availability = TakeAvailability.evaluate(
            take: inputs, program: programChannel, preview: preview,
            standard: ShowStandard.activeOrCurrent, editLive: editLive)
        guard availability.isEligible, let frame = channel.latestRenderedFrame else {
            return .rejected(.notEligible(availability.reason))
        }
        guard router.commitTake(frame, to: preview, expectedRouteGeneration: request.routeGeneration,
                                fallbackWindow: fallbackWindow) else {
            return .rejected(.outputRefused)
        }
        lastTakeAt = now
        channel.publishSourceIdentityToProgramOutput()
        editLive = false
        retarget()
        return .committed(newProgram: preview)
    }

    // MARK: Commands

    /// A UI intent bound at gesture start: the camera command (addressed to a
    /// stable ChannelID with that channel's epoch) plus the control-target
    /// revision it was created under.
    struct ShowCommand {
        let command: OperatorCommand
        let controlTargetRevision: UInt64
    }

    /// Bind a camera action to the current control target, now.
    func makeCommand(_ action: OperatorCommand.Action) -> ShowCommand {
        let channel = channels[controlTarget] ?? channelA
        return ShowCommand(command: channel.makeCommand(action),
                           controlTargetRevision: controlTargetRevision)
    }

    /// Deliver a bound command to the channel it names — never to whatever is
    /// selected now. Rejects commands from before a control-target change and
    /// live edits to Program without Edit Live.
    func dispatch(_ show: ShowCommand) -> CommandResult {
        guard show.controlTargetRevision == controlTargetRevision else {
            return .rejected("Control target changed")
        }
        guard case .channel(let id) = show.command.target, let channel = channels[id] else {
            return .rejected("Wrong command target")
        }
        if id == programChannel, previewChannel != nil, !editLive {
            return .rejected("Program changes need Edit Live")
        }
        return channel.dispatch(show.command)
    }

    /// Enter or leave the explicit live-edit state. Never changes routing.
    func setEditLive(_ enabled: Bool) {
        guard enabled != editLive else { return }
        editLive = enabled
        retarget()
    }

    /// Recompute the control target. Pending gestures on the channel losing
    /// control are cancelled; admitted moves on either channel continue.
    private func retarget() {
        let target = (editLive || previewChannel == nil) ? programChannel : (previewChannel ?? programChannel)
        if target != controlTarget {
            channels[controlTarget]?.cancelPendingOperatorGestures()
            controlTarget = target
        }
        controlTargetRevision &+= 1
    }
}
