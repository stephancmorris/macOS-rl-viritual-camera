//
//  OperatorPill.swift
//  CinematicCoreMacOS
//
//  Floating glass operator pill: lock state · shot preset segmented ·
//  push/pull · Return to Wide · Stop session.
//

import SwiftUI

/// Sends the pill's actions. With a show, every action is bound to the show's
/// control target at the moment of the gesture (PILL-TARGET); without one it
/// is today's single-camera path.
@MainActor
struct PillCommandSink {
    let cameraManager: CameraManager
    let show: ShowCoordinator?

    /// Build and deliver one command now. The pill was drawn for
    /// `cameraManager`; if the show's control target has since moved to
    /// another channel (the snapshot lags by up to a refresh), the gesture is
    /// refused rather than retargeted to a camera the operator did not see.
    @discardableResult
    func send(_ action: OperatorCommand.Action) -> CommandResult {
        guard let show else { return cameraManager.dispatch(cameraManager.makeCommand(action)) }
        let bound = show.makeCommand(action)
        guard bound.command.target == .channel(cameraManager.channelID) else {
            return .rejected("Control target changed")
        }
        return show.dispatch(bound)
    }
}

struct OperatorPill: View {
    /// How the target chip is written. Full ("CAM B · PREVIEW") is the default:
    /// even the widest pill (Edit Live, Stage: 1183 pt) fits the 1280 pt
    /// console. Compact ("B · PVW") is for hosts too narrow for that, and is
    /// chosen before any control would be dropped.
    enum ChipStyle { case full, compact }

    @ObservedObject var cameraManager: CameraManager
    let controlTarget: ControlTarget
    /// The show whose control target every action is bound to. nil keeps the
    /// single-camera behaviour (Webcam view, non-multiview console).
    let show: ShowCoordinator?
    let chipStyle: ChipStyle
    /// Set when the lifecycle refuses the on-screen Stop, so it offers
    /// "Try stopping again".
    @State private var stopFailed = false

    init(cameraManager: CameraManager, controlTarget: ControlTarget = .singleCamera,
         show: ShowCoordinator? = nil, chipStyle: ChipStyle = .full) {
        self.cameraManager = cameraManager
        self.controlTarget = controlTarget
        self.show = show
        self.chipStyle = chipStyle
    }

    private var sink: PillCommandSink { PillCommandSink(cameraManager: cameraManager, show: show) }

    /// Stop session belongs to the single-camera view; in a show it is
    /// "Stop session" in the console header, which stops the whole show.
    private var showsStopSession: Bool { show == nil && controlTarget == .singleCamera }

    private var isWebcam: Bool {
        cameraManager.shotComposer.config.cinematicFormat == .webcam
    }

    /// One control group on the pill.
    nonisolated enum Section: Hashable, Sendable {
        case targetChip, lockState, detect, stageShots, webcamShots, crop, manual, autoPan, zoom, returnToWide, stopSession
    }

    /// The pill's controls, left to right. Stage format (Single Cam and
    /// Multi Cam) gets the three Stage shots, Manual and Auto Pan; Webcam gets
    /// Wide / Tight and neither mode. In the Multiview console Stop is
    /// show-level and lives in the header ("Stop session"); a channel's pill
    /// never stops the show.
    nonisolated static func sections(isWebcam: Bool, showsTargetChip: Bool, showsStopSession: Bool) -> [Section] {
        var sections: [Section] = showsTargetChip ? [.targetChip] : []
        sections += [.lockState, .detect]
        sections += isWebcam ? [.webcamShots, .crop] : [.stageShots, .crop, .manual, .autoPan]
        sections += [.zoom, .returnToWide]
        if showsStopSession { sections.append(.stopSession) }
        return sections
    }

    /// This pill's controls, from its channel's format and target.
    var sections: [Section] {
        Self.sections(isWebcam: isWebcam, showsTargetChip: controlTarget != .singleCamera,
                      showsStopSession: showsStopSession)
    }

    /// J4: the pill reads as four groups, 12 pt apart: who Alfie follows,
    /// which shot, how the frame moves, and the session.
    nonisolated enum Cluster: String, Hashable, Sendable {
        case subject = "Subject", shot = "Shot", move = "Move", session = "Session"
    }

    nonisolated struct ClusterGroup: Hashable, Sendable {
        let cluster: Cluster
        let sections: [Section]
    }

    nonisolated static func cluster(of section: Section) -> Cluster {
        switch section {
        case .targetChip, .lockState, .detect: return .subject
        case .stageShots, .webcamShots: return .shot
        case .crop, .manual, .autoPan, .zoom, .returnToWide: return .move
        case .stopSession: return .session
        }
    }

    /// Consecutive sections of one cluster, in pill order.
    nonisolated static func clusters(_ sections: [Section]) -> [ClusterGroup] {
        var groups: [ClusterGroup] = []
        for section in sections {
            let cluster = cluster(of: section)
            if let last = groups.last, last.cluster == cluster {
                groups[groups.count - 1] = ClusterGroup(cluster: cluster, sections: last.sections + [section])
            } else {
                groups.append(ClusterGroup(cluster: cluster, sections: [section]))
            }
        }
        return groups
    }

    /// Between groups: a hairline centred in 12 pt. Within a group, 4 pt.
    static let clusterGap: CGFloat = 12
    static let controlSpacing: CGFloat = 4

    private var commandState: PillCommandState {
        let operatorGeometry = cameraManager.activeMode == .autoPan || cameraManager.activeMode == .manualCrop
        return PillCommandState(
            isRunning: cameraManager.isRunning,
            isWebcam: isWebcam,
            isDiscovering: cameraManager.detectionDiscoveryActive,
            detectEnabled: detectEnabled(operatorGeometry: operatorGeometry),
            canPushIn: cameraManager.canBeginZoom(.pushIn),
            canPullOut: cameraManager.canBeginZoom(.pullOut))
    }

    private func detectEnabled(operatorGeometry: Bool) -> Bool {
        cameraManager.isRunning && !operatorGeometry
            && (!cameraManager.isManualTargetLockActive || cameraManager.canDirectlyReacquire)
            && !cameraManager.shotComposer.isAcquiring
    }

    @ViewBuilder
    private func control(for section: Section) -> some View {
        switch section {
        case .targetChip: targetChip
        case .lockState: lockStateSection
        case .detect: detectButton
        case .stageShots: shotPresetSegmentedSection
        case .webcamShots: webcamPresetSegmentedSection
        case .crop: cropToggleButton
        case .manual: manualCropButton
        case .autoPan: autoPanButton
        case .zoom: zoomButtons
        case .returnToWide: returnToWideButton
        case .stopSession: stopSessionButton
        }
    }

    private var operatorFeedback: String? {
        if cameraManager.isProgramHolding { return "Holding last good program" }
        if let status = cameraManager.controlStatus { return status }
        if cameraManager.isZoomLimited { return "Zoom limited by the source" }
        if cameraManager.cropEngine?.hasZoomAdjustment == true { return cameraManager.framingTitle }
        return cameraManager.detectionDiscoveryActive
            ? "Tap the subject in the wide frame"
            : cameraManager.shotComposer.acquisitionStatusText
    }

    private var zoomButtons: some View {
        HStack(spacing: 4) {
            ZoomShotButton(cameraManager: cameraManager, sink: sink, controlTarget: controlTarget, direction: .pullOut)
            ZoomShotButton(cameraManager: cameraManager, sink: sink, controlTarget: controlTarget, direction: .pushIn)
        }
        .padding(.horizontal, 4)
    }

    var body: some View {
        HStack(spacing: 0) {
            let groups = Self.clusters(sections)
            ForEach(Array(groups.enumerated()), id: \.element.cluster) { index, group in
                if index > 0 { divider }
                HStack(spacing: Self.controlSpacing) {
                    ForEach(group.sections, id: \.self) { section in
                        control(for: section)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(group.cluster.rawValue)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(pillBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(controlTarget.isEditingLive ? AlfieColor.tally.program : Color.white.opacity(0.12),
                              lineWidth: controlTarget.isEditingLive ? 1 : 0.5)
        )
        .overlay(alignment: .top) {
            if let feedback = operatorFeedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(AlfieColor.onVideo.emphasis)
                    .padding(10)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .offset(y: -55)
                    .accessibilityLabel(feedback)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 18)
        .shadow(color: .black.opacity(0.35), radius: 60, x: 0, y: 30)
        .modifier(SingleCameraCommands(isPublishing: showsStopSession, state: commandState, sink: sink))
    }

    private var targetChip: some View {
        Text((chipStyle == .full ? controlTarget.chipTitle : controlTarget.compactChipTitle) ?? "")
        // 11 pt floor: a proportional face keeps the chip's width where the
        // 10 pt monospaced one had it, so the widest pill still fits 1280.
        .font(.system(size: 11, weight: .bold))
        .tracking(0.2)
        .foregroundStyle(AlfieColor.onFill)
        .lineLimit(1)
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .background(controlTarget.isEditingLive
                    ? AlfieColor.tally.programChip
                    : AlfieColor.tally.previewChip,
                    in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 2)
        .accessibilityLabel(controlTarget.chipTitle ?? "")
    }

    private var pillBackground: some View {
        OperatorPillBackground()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, (Self.clusterGap - 1) / 2)
            .accessibilityHidden(true)
    }

    // MARK: - Lock state

    private var lockStateSection: some View {
        let state = lockState
        let label = displayedLockLabel
        return Button(action: lockStateAction) {
            ZStack {
                HStack(spacing: 8) {
                    PillLockIndicator(state: state)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(state.labelColor)
                }
                HStack(spacing: 8) {
                    // Reserve the widest indicator too (Locked's dot and
                    // glyph), so locking never moves the rest of the pill.
                    PillLockIndicator(state: .locked)
                    ZStack {
                        ForEach(LockState.allCases, id: \.self) { state in
                            Text(state.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text("Resume")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .hidden()
                .accessibilityHidden(true)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .alfieButtonStyle(.quiet, surface: .video, cornerRadius: 11)
        .targetLabel(controlTarget, label)
        .disabled(!state.isInteractive || cameraManager.recoveryState.action == .none ||
                  (cameraManager.recoveryState.action == .pickSubject &&
                   (cameraManager.activeMode == .autoPan || cameraManager.activeMode == .manualCrop)))
    }

    private var displayedLockLabel: String {
        switch lockState {
        case .awaitingTap, .tapPending: return lockState.label
        default: return cameraManager.recoveryState.statusLabel
        }
    }

    private var lockState: LockState {
        if cameraManager.shotComposer.isAcquiring {
            return .acquiring
        }
        if cameraManager.shotComposer.isHolding { return .recovering }
        if cameraManager.shotComposer.isWideWaiting { return .waiting }
        if cameraManager.isManualTargetLockActive {
            return .locked
        }
        if cameraManager.tapPending {
            return .tapPending
        }
        if cameraManager.detectionDiscoveryActive {
            return .awaitingTap
        }
        return .idle
    }

    private func lockStateAction() {
        switch cameraManager.recoveryState.action {
        case .none: break
        case .unlock: sink.send(.unlock)
        case .resume: sink.send(.resumeTracking)
        case .pickSubject:
            sink.send(.unlock)
            sink.send(.detect)
        }
    }

    enum LockState: CaseIterable, Hashable {
        case idle, awaitingTap, tapPending, acquiring, locked, recovering, waiting

        var label: String {
            switch self {
            case .idle: return "Pick subject"
            case .awaitingTap: return "Tap subject"
            case .tapPending: return "Finding…"
            case .acquiring: return "Acquiring…"
            case .locked: return "Locked"
            case .recovering: return "Recovering"
            case .waiting: return "Searching"
            }
        }

        var dotColor: Color {
            switch self {
            case .idle: return AlfieColor.onVideo.disabled
            case .awaitingTap, .tapPending: return AlfieColor.tracking.candidate
            case .acquiring, .recovering, .waiting: return AlfieColor.tracking.acquiring
            // The same green as the SUBJECT box on the footage.
            case .locked: return AlfieColor.tracking.locked
            }
        }

        var labelColor: Color {
            switch self {
            case .idle: return AlfieColor.onVideo.tertiary
            case .awaitingTap: return AlfieColor.onVideo.secondary
            case .tapPending, .acquiring, .locked, .recovering, .waiting: return AlfieColor.onVideo.primary
            }
        }

        var hasGlow: Bool {
            switch self {
            case .idle: return false
            case .awaitingTap, .tapPending, .acquiring, .locked, .recovering, .waiting: return true
            }
        }

        var isInteractive: Bool {
            switch self {
            case .idle, .awaitingTap, .tapPending, .acquiring: return false
            case .locked, .recovering, .waiting: return true
            }
        }
    }

    // MARK: - Detect button

    private var detectButton: some View {
        let isDiscovering = cameraManager.detectionDiscoveryActive
        let isAcquiring = cameraManager.shotComposer.isAcquiring
        let isLocked = cameraManager.isManualTargetLockActive
        // Disabled (but visible) once a subject is locked — unlock via the pill.
        let operatorGeometryMode = cameraManager.activeMode == .autoPan || cameraManager.activeMode == .manualCrop
        let enabled = detectEnabled(operatorGeometry: operatorGeometryMode)
        let reason = PillUnavailableReason.detect(
            isRunning: cameraManager.isRunning, operatorGeometry: operatorGeometryMode, isLocked: isLocked,
            canReacquire: cameraManager.canDirectlyReacquire, isAcquiring: isAcquiring)
        let label: String = {
            if isAcquiring { return "Acquiring…" }
            if isDiscovering { return "Cancel" }
            return "Detect"
        }()
        let highlighted = isDiscovering || isAcquiring
        return Button {
            if isDiscovering {
                sink.send(.cancelDetect)
            } else {
                sink.send(.detect)
            }
        } label: {
            ZStack {
                HStack(spacing: 7) {
                    Image(systemName: isDiscovering ? "xmark.circle" : "viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                    Text(label)
                        .font(.system(size: 12, weight: highlighted ? .semibold : .medium))
                }
                HStack(spacing: 7) {
                    ZStack {
                        Image(systemName: "viewfinder")
                        Image(systemName: "xmark.circle")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    ZStack {
                        ForEach(["Detect", "Cancel", "Acquiring…"], id: \.self) { label in
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .hidden()
                .accessibilityHidden(true)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .alfieButtonStyle(.quiet, surface: .video, isSelected: highlighted, cornerRadius: 11)
        .targetLabel(controlTarget, label)
        .disabled(!enabled)
        .pillHelp(isDiscovering ? "Cancel Detect (Escape)." : "Detect (key D): click the person you want Alfie to follow.",
                  unavailable: enabled ? nil : reason)
    }

    // MARK: - Shot preset segmented

    private var shotPresetSegmentedSection: some View {
        let preset = cameraManager.shotComposer.config.shotPreset
        return HStack(spacing: 2) {
            ForEach(ShotComposer.Config.ShotPreset.allCases) { option in
                presetSegment(title: option.operatorTitle, isOn: preset == option) {
                    sink.send(.selectPreset(.stage(option)))
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 4)
    }

    private func presetSegment(
        title: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .alfieButtonStyle(.segment, surface: .video, isSelected: isOn, cornerRadius: 11)
        .targetLabel(controlTarget, title)
    }

    // MARK: - Webcam preset segmented

    private var webcamPresetSegmentedSection: some View {
        let preset = cameraManager.shotComposer.config.webcamPreset
        return HStack(spacing: 2) {
            ForEach(ShotComposer.Config.WebcamPreset.allCases) { option in
                presetSegment(title: option.operatorTitle, isOn: preset == option) {
                    sink.send(.selectPreset(.webcam(option)))
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 4)
    }

    // MARK: - Return to Wide

    private var returnToWideButton: some View {
        let isOn = cameraManager.activeMode == .wide
        let enabled = cameraManager.isRunning
        return Button {
            sink.send(.returnToWide)
        } label: {
            Text(returnToWideTitle)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
        }
        .alfieButtonStyle(.quiet, surface: .video, isSelected: isOn, cornerRadius: 11)
        .targetLabel(controlTarget, returnToWideTitle)
        .disabled(!enabled)
        .pillHelp("Show the whole stage.", unavailable: enabled ? nil : PillUnavailableReason.notRunning)
    }

    private var returnToWideTitle: String {
        controlTarget.camera.map { "Return \($0) to Wide" } ?? "Return to Wide"
    }

    /// Crop, Manual and Auto Pan are modes: the shared toggle shows on or
    /// off by shape (a filled dot or a ring) as well as by fill.
    private func modeFace(title: String, isOn: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: isOn ? .semibold : .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
    }

    // MARK: - Crop toggle

    private var cropToggleButton: some View {
        let isOn = cameraManager.activeMode == .autoTracking
        let hasLock = cameraManager.manualLockedTargetID != nil
        let enabled = cameraManager.isRunning && !isOn && hasLock
        return Button {
            sink.send(.setMode(.autoTracking))
        } label: {
            modeFace(title: "Crop", isOn: isOn)
        }
        .alfieButtonStyle(.toggle(isOn: isOn), surface: .video, cornerRadius: 11)
        .targetLabel(controlTarget, "Crop")
        .disabled(!enabled)
        .pillHelp("Frame the locked subject.", unavailable: enabled ? nil
                  : PillUnavailableReason.crop(isRunning: cameraManager.isRunning, isOn: isOn, hasLock: hasLock))
    }

    // MARK: - Manual Crop toggle

    private var manualCropButton: some View {
        let isOn = cameraManager.activeMode == .manualCrop
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            sink.send(.setMode(.manualCrop))
        } label: {
            modeFace(title: "Manual", isOn: isOn)
        }
        .alfieButtonStyle(.toggle(isOn: isOn), surface: .video, cornerRadius: 11)
        .targetLabel(controlTarget, "Manual")
        .disabled(!enabled)
        .pillHelp("Click the wide picture to place the crop yourself.", unavailable: enabled ? nil
                  : PillUnavailableReason.mode("Manual", isRunning: cameraManager.isRunning, isOn: isOn))
    }

    // MARK: - Auto Pan toggle

    private var autoPanButton: some View {
        let isOn = cameraManager.activeMode == .autoPan
        // At full width Pan holds its phase; pushing in restores travel.
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            sink.send(.setMode(.autoPan))
        } label: {
            modeFace(title: "Auto Pan", isOn: isOn)
        }
        .alfieButtonStyle(.toggle(isOn: isOn), surface: .video, cornerRadius: 11)
        .targetLabel(controlTarget, "Auto Pan")
        .disabled(!enabled)
        .pillHelp("Sweep the program crop across the stage.", unavailable: enabled ? nil
                  : PillUnavailableReason.mode("Auto Pan", isRunning: cameraManager.isRunning, isOn: isOn))
    }

    // MARK: - Stop session

    /// D3 and J12: the on-screen Stop needs a 0.8 s hold, or a confirmation
    /// from the keyboard or VoiceOver. The menu's ⌘⌥⇧S stays immediate.
    private var stopSessionButton: some View {
        AlfieHoldToStopButton(
            confirmationMessage: StopRouteCopy.confirmation(for: cameraManager.programOutput.activeRoute),
            stopFailed: stopFailed
        ) {
            stopFailed = false
            if !sink.send(.stopSession).wasAccepted {
                // A later transaction, so a second failure still reads as a change.
                Task { @MainActor in stopFailed = true }
            }
        }
    }
}

extension View {
    /// The pill's help tag: what the control does, or why it can't right now.
    /// The reason is also the VoiceOver hint (`alfieUnavailableReason`).
    func pillHelp(_ help: String, unavailable reason: String?) -> some View {
        self.help(reason ?? help)
            .accessibilityHint(reason ?? "")
    }
}

/// The pill's lock dot. A lock glyph joins it for Locked (J3), so the state
/// is a shape and a word as well as a colour; F4 showed it only under
/// Differentiate Without Colour. The word beside it is what VoiceOver reads.
struct PillLockIndicator: View {
    let state: OperatorPill.LockState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: state.dotColor.opacity(0.8), radius: state.hasGlow ? 6 : 0)
            if state == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.dotColor)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The pill's glass over footage; opaque under Reduce Transparency (UX F4)
/// so its labels read the same over bright and dark pictures.
struct OperatorPillBackground: View {
    var cornerRadius: CGFloat = 22
    private let display = AlfieDisplay()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if display.reduceTransparency {
            shape.fill(AlfieColor.onVideo.glassOpaque)
        } else {
            shape
                .fill(AlfieColor.onVideo.glass)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

/// The "Stop session" button face: the single-camera pill's control, and
/// the Multiview console header's show-level stop (which stops every input).
/// The destructive member of the shared family draws its fill and states.
/// The pill's Stop is now `AlfieHoldToStopButton` (Track A, D3); Track B
/// replaces the console header's.
struct StopSessionLabel: View {
    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AlfieColor.onFill)
                .frame(width: 9, height: 9)
            Text("Stop session")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

/// A normal button tap starts one complete shot move; release has no effect.
/// The move, once admitted, belongs to the channel it was sent to: the pill is
/// rebuilt when the control target changes (`.id`), and that must not cancel
/// a move already running on the old target.
private struct ZoomShotButton: View {
    @ObservedObject var cameraManager: CameraManager
    let sink: PillCommandSink
    let controlTarget: ControlTarget
    let direction: OperatorCommand.ZoomDirection
    private var title: String { direction == .pushIn ? "+ Push in" : "− Pull out" }
    private var enabled: Bool { cameraManager.isRunning && cameraManager.canBeginZoom(direction) }

    var body: some View {
        Button {
            sink.send(.beginZoom(direction))
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 88, height: 36)
        }
        .alfieButtonStyle(.secondary, surface: .video,
                          isSelected: cameraManager.zoomMoveDirection == direction, cornerRadius: 11)
        .targetLabel(controlTarget, direction == .pushIn ? "Push in" : "Pull out")
        .disabled(!enabled)
        .pillHelp("Slow zoom to the next shot size.", unavailable: enabled ? nil
                  : PillUnavailableReason.zoom(direction, isRunning: cameraManager.isRunning,
                                               canBegin: cameraManager.canBeginZoom(direction),
                                               movingDirection: cameraManager.zoomMoveDirection,
                                               isZoomLimited: cameraManager.isZoomLimited))
        .onDisappear {
            // Single camera: leaving the view stops motion, as before. In a
            // show, a target change or Take rebuilds the pill; admitted moves
            // keep running on their own channel.
            if sink.show == nil { cameraManager.cancelOperatorMotion() }
        }
    }
}
