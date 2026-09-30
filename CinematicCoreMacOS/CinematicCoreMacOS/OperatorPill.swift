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

    private var operatorFeedback: String? {
        if cameraManager.isProgramHolding { return "Holding last good program" }
        if let status = cameraManager.controlStatus { return status }
        if cameraManager.isZoomLimited { return "ZOOM LIMITED" }
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
            if controlTarget != .singleCamera {
                targetChip
            }
            lockStateSection
            divider
            detectButton
            divider
            if isWebcam {
                webcamPresetSegmentedSection
                divider
                cropToggleButton
                divider
            } else {
                shotPresetSegmentedSection
                divider
                cropToggleButton
                divider
                manualCropButton
                divider
                autoPanButton
                divider
            }
            zoomButtons
            divider
            returnToWideButton
            // In the Multiview console Stop is show-level and lives in the
            // header ("Stop session"); a channel's pill never stops the show.
            if showsStopSession {
                divider
                stopSessionButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(pillBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(controlTarget.isEditingLive ? Color(red: 1, green: 0.27, blue: 0.23) : Color.white.opacity(0.12),
                              lineWidth: controlTarget.isEditingLive ? 1 : 0.5)
        )
        .overlay(alignment: .top) {
            if let feedback = operatorFeedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .offset(y: -55)
                    .accessibilityLabel(feedback)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 18)
        .shadow(color: .black.opacity(0.35), radius: 60, x: 0, y: 30)
    }

    private var targetChip: some View {
        Text((chipStyle == .full ? controlTarget.chipTitle : controlTarget.compactChipTitle) ?? "")
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .background(controlTarget.isEditingLive
                    ? Color(red: 0.6, green: 0.1, blue: 0.1)
                    : Color(red: 0.1, green: 0.38, blue: 0.25),
                    in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 2)
        .accessibilityLabel(controlTarget.chipTitle ?? "")
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.55))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    // MARK: - Lock state

    private var lockStateSection: some View {
        let state = lockState
        let label = displayedLockLabel
        return Button(action: lockStateAction) {
            ZStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.dotColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: state.dotColor.opacity(0.8), radius: state.hasGlow ? 6 : 0)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(state.labelOpacity))
                }
                HStack(spacing: 8) {
                    Circle()
                        .frame(width: 7, height: 7)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private enum LockState: CaseIterable, Hashable {
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
            case .idle: return Color(.sRGB, white: 1, opacity: 0.3)
            case .awaitingTap: return Color(red: 0.47, green: 0.86, blue: 1.0)
            case .tapPending: return Color(red: 0.47, green: 0.86, blue: 1.0)
            case .acquiring: return Color(red: 1.0, green: 0.74, blue: 0.23)
            case .recovering, .waiting: return .orange
            case .locked: return Color(red: 0.04, green: 0.52, blue: 1.0)
            }
        }

        var labelOpacity: Double {
            switch self {
            case .idle: return 0.45
            case .awaitingTap: return 0.78
            case .tapPending: return 0.85
            case .acquiring: return 0.85
            case .locked, .recovering, .waiting: return 0.92
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
        let enabled = cameraManager.isRunning && !operatorGeometryMode && (!isLocked || cameraManager.canDirectlyReacquire) && !isAcquiring
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
                        .foregroundStyle(.white.opacity(highlighted ? 1.0 : (enabled ? 0.86 : 0.32)))
                    Text(label)
                        .font(.system(size: 12, weight: highlighted ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(highlighted ? 1.0 : (enabled ? 0.86 : 0.32)))
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
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(highlighted ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, label)
        .disabled(!enabled)
        .help("Detect: tap, then click the subject you want Alfie to follow.")
    }

    // MARK: - Shot preset segmented

    private var shotPresetSegmentedSection: some View {
        let preset = cameraManager.shotComposer.config.shotPreset
        return HStack(spacing: 2) {
            ForEach(ShotComposer.Config.ShotPreset.allCases) { option in
                shotPresetSegment(option: option, isOn: preset == option) {
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

    private func shotPresetSegment(
        option: ShotComposer.Config.ShotPreset,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(option.operatorTitle)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isOn ? 1.0 : 0.62))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, option.operatorTitle)
    }

    // MARK: - Webcam preset segmented

    private var webcamPresetSegmentedSection: some View {
        let preset = cameraManager.shotComposer.config.webcamPreset
        return HStack(spacing: 2) {
            ForEach(ShotComposer.Config.WebcamPreset.allCases) { option in
                webcamPresetSegment(option: option, isOn: preset == option) {
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

    private func webcamPresetSegment(
        option: ShotComposer.Config.WebcamPreset,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(option.operatorTitle)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isOn ? 1.0 : 0.62))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, option.operatorTitle)
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
                .foregroundStyle(.white.opacity(isOn ? 1.0 : (enabled ? 0.86 : 0.32)))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, returnToWideTitle)
        .disabled(!enabled)
    }

    private var returnToWideTitle: String {
        controlTarget.camera.map { "Return \($0) to Wide" } ?? "Return to Wide"
    }

    // MARK: - Crop toggle

    private var cropToggleButton: some View {
        let isOn = cameraManager.activeMode == .autoTracking
        let hasLock = cameraManager.manualLockedTargetID != nil
        let enabled = cameraManager.isRunning && !isOn && hasLock
        return Button {
            sink.send(.setMode(.autoTracking))
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn
                          ? Color(red: 0.31, green: 0.93, blue: 0.78)
                          : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text("Crop")
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isOn ? 1.0 : (enabled ? 0.86 : 0.32)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, "Crop")
        .disabled(!enabled)
        .help(hasLock ? "Frame the locked subject." : "Tap a person in the preview to lock a subject first.")
    }

    // MARK: - Manual Crop toggle

    private var manualCropButton: some View {
        let isOn = cameraManager.activeMode == .manualCrop
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            sink.send(.setMode(.manualCrop))
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn
                          ? Color(red: 0.31, green: 0.93, blue: 0.78)
                          : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text("Manual")
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isOn ? 1.0 : (enabled ? 0.86 : 0.32)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, "Manual")
        .disabled(!enabled)
    }

    // MARK: - Auto Pan toggle

    private var autoPanButton: some View {
        let isOn = cameraManager.activeMode == .autoPan
        // At full width Pan holds its phase; pushing in restores travel.
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            sink.send(.setMode(.autoPan))
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn
                          ? Color(red: 0.31, green: 0.93, blue: 0.78)
                          : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text("Auto Pan")
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isOn ? 1.0 : (enabled ? 0.86 : 0.32)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
            .help("Sweep the program crop across the stage")
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, "Auto Pan")
        .disabled(!enabled)
    }

    // MARK: - Stop session

    private var stopSessionButton: some View {
        Button {
            sink.send(.stopSession)
        } label: {
            StopSessionLabel()
        }
        .buttonStyle(.plain)
    }
}

/// The red "Stop session" button face: the single-camera pill's control, and
/// the Multiview console header's show-level stop (which stops every input).
struct StopSessionLabel: View {
    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .frame(width: 9, height: 9)
            Text("Stop session")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.92))
        )
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
                .foregroundStyle(.white.opacity(enabled || cameraManager.zoomMoveDirection == direction ? 0.95 : 0.32))
                .frame(width: 88, height: 36)
                .background(.white.opacity(cameraManager.zoomMoveDirection == direction ? 0.2 : 0.07),
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .targetLabel(controlTarget, direction == .pushIn ? "Push in" : "Pull out")
        .disabled(!enabled)
        .help("Slow zoom to the next shot size.")
        .onDisappear {
            // Single camera: leaving the view stops motion, as before. In a
            // show, a target change or Take rebuilds the pill; admitted moves
            // keep running on their own channel.
            if sink.show == nil { cameraManager.cancelOperatorMotion() }
        }
    }
}
