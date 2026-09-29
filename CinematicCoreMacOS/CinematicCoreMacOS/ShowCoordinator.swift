//
//  ShowCoordinator.swift
//  CinematicCoreMacOS
//
//  Show-level owner (CHANNEL card): the one ProgramOutputManager, the set of
//  channels, and which channel is Program. Channels are per-camera
//  controllers (CameraManager) that receive the shared output; they never
//  create one. Only the Program channel's port reaches the output.
//
//  This first step keeps single-camera behaviour identical: channel A is
//  created routed, exactly as the app ran before. A second channel can be
//  added unrouted and isolated. ROUTER moves the routing decision (and Take)
//  here; DEVICES adds exclusive device leases; CHANNEL-CMD binds commands to
//  channel IDs.
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
    init(programOutput: ProgramOutputManager? = nil, admissionRecords: AdmissionRecordStore? = nil) {
        self.admissionRecords = admissionRecords ?? AdmissionRecordStore()
        let output = programOutput
            ?? ProgramOutputManager(sinks: [VirtualCameraOutputSink(), DisplayOutputSink()])
        self.programOutput = output
        self.router = ProgramRouter(output: output, programChannel: .a)
        let router = self.router
        workScheduler.isProgram = { router.isProgram($0) }
        let a = CameraManager(channelID: .a, programOutput: output, outputPort: router.port(for: .a))
        a.deviceRegistry = deviceRegistry
        a.workScheduler = workScheduler
        channels[.a] = a
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
        channels[id] = channel
        retarget()
        return channel
    }

    /// Stop and drop a non-Program channel. The Program channel cannot be
    /// removed (the show would have no source); stop the show instead.
    func removeChannel(_ id: ChannelID) {
        guard id != programChannel, let channel = channels[id] else { return }
        channel.stopCapture()
        channels[id] = nil
        retarget()
    }

    /// Show-level Stop: retires every channel's generation and epoch.
    func stopShow() {
        for id in ChannelID.allCases { channels[id]?.stopCapture() }
        editLive = false
        retarget()
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
                route: identity.output.route),
            previewCaptureFPS: channels[preview]?.configuredCaptureFPS)
    }

    // MARK: Take (TAKE)

    private var lastTakeAt: TimeInterval = -.infinity
    /// Host clock; injectable for tests.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    private var framePeriod: TimeInterval { 1 / ShowStandard.activeOrCurrent.frameRate }

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
            now: clock(), framePeriod: framePeriod)
    }

    /// Hard cut to the prepared Preview. Validates now; never arms a later
    /// cut. Commits only when the output accepts the Preview frame; then roles
    /// swap, Edit Live ends and controls return to the new Preview. Motion on
    /// both channels continues.
    @discardableResult
    func take(_ request: TakeRequest? = nil) -> TakeResult {
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
        guard router.commitTake(frame, to: preview, expectedRouteGeneration: request.routeGeneration) else {
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
