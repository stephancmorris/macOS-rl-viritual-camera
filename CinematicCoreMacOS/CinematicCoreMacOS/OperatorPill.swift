//
//  OperatorPill.swift
//  CinematicCoreMacOS
//
//  Floating glass operator pill: lock state · shot preset segmented ·
//  Return to Wide · Resume Tracking · Stop session.
//

import SwiftUI

struct OperatorPill: View {
    @ObservedObject var cameraManager: CameraManager
    var onStop: () -> Void
    var onStart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            lockStateSection
            divider
            shotPresetSegmentedSection
            divider
            cropToggleButton
            divider
            manualCropButton
            divider
            autoPanButton
            divider
            returnToWideButton
            divider
            stopSessionButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(pillBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 18)
        .shadow(color: .black.opacity(0.35), radius: 60, x: 0, y: 30)
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
        return Button(action: lockStateAction) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: state.dotColor.opacity(0.8), radius: state.hasGlow ? 6 : 0)
                Text(state.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(state.labelOpacity))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isInteractive)
    }

    private var lockState: LockState {
        if cameraManager.isManualTargetLockActive {
            return .locked
        }
        if !cameraManager.personDetector.detectedPersons.isEmpty {
            return .idleWithDetections
        }
        return .idle
    }

    private func lockStateAction() {
        switch lockState {
        case .locked:
            cameraManager.clearManualTargetLock()
        case .idle, .idleWithDetections:
            break
        }
    }

    private enum LockState {
        case idle, idleWithDetections, locked

        var label: String {
            switch self {
            case .idle: return "Tap a person in the frame to lock"
            case .idleWithDetections: return "Tap a person in the frame to lock"
            case .locked: return "Locked on subject · tap to unlock"
            }
        }

        var dotColor: Color {
            switch self {
            case .idle: return Color(.sRGB, white: 1, opacity: 0.3)
            case .idleWithDetections: return Color(red: 0.47, green: 0.86, blue: 1.0)
            case .locked: return Color(red: 0.04, green: 0.52, blue: 1.0)
            }
        }

        var labelOpacity: Double {
            switch self {
            case .idle: return 0.45
            case .idleWithDetections: return 0.78
            case .locked: return 0.92
            }
        }

        var hasGlow: Bool {
            switch self {
            case .idle: return false
            case .idleWithDetections, .locked: return true
            }
        }

        var isInteractive: Bool {
            switch self {
            case .idle, .idleWithDetections: return false
            case .locked: return true
            }
        }
    }

    // MARK: - Shot preset segmented

    private var shotPresetSegmentedSection: some View {
        let preset = cameraManager.shotComposer.config.shotPreset
        return HStack(spacing: 2) {
            ForEach(ShotComposer.Config.ShotPreset.allCases) { option in
                shotPresetSegment(option: option, isOn: preset == option) {
                    cameraManager.shotComposer.config.shotPreset = option
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
    }

    // MARK: - Return to Wide

    private var returnToWideButton: some View {
        let isOn = cameraManager.activeMode == .wide
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            cameraManager.returnToWide()
        } label: {
            Text("Return to Wide")
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isOn ? 1.0 : (enabled ? 0.86 : 0.32)))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Crop toggle

    private var cropToggleButton: some View {
        let isOn = cameraManager.activeMode == .autoTracking
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            cameraManager.activeMode = .autoTracking
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
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Manual Crop toggle

    private var manualCropButton: some View {
        let isOn = cameraManager.activeMode == .manualCrop
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            cameraManager.activeMode = .manualCrop
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn
                          ? Color(red: 0.31, green: 0.93, blue: 0.78)
                          : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text("Manual Crop")
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isOn ? 1.0 : (enabled ? 0.86 : 0.32)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Auto Pan toggle

    private var autoPanButton: some View {
        let isOn = cameraManager.activeMode == .autoPan
        let enabled = cameraManager.isRunning && !isOn
        return Button {
            cameraManager.activeMode = .autoPan
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
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Stop session

    private var stopSessionButton: some View {
        Button {
            onStop()
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 9, height: 9)
                Text("Stop session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.92))
            )
        }
        .buttonStyle(.plain)
    }
}
