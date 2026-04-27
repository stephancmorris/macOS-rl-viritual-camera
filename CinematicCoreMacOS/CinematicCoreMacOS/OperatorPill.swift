//
//  OperatorPill.swift
//  CinematicCoreMacOS
//
//  Floating glass operator pill: lock state · framing segmented ·
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
            framingSegmentedSection
            divider
            cropToggleButton
            divider
            returnToWideButton
            divider
            resumeTrackingButton
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
                    .shadow(color: state.dotColor.opacity(0.8), radius: state.dotColor == Color(.sRGB, white: 1, opacity: 0.3) ? 0 : 6)
                Text(state.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(state.isInteractive ? 0.92 : 0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isInteractive)
    }

    private var lockState: LockState {
        if cameraManager.trackingPaused {
            return .recovering
        }
        if cameraManager.isManualTargetLockActive {
            return .locked
        }
        return .idle
    }

    private func lockStateAction() {
        switch lockState {
        case .locked:
            cameraManager.clearManualTargetLock()
        case .recovering:
            cameraManager.resumeTracking()
        case .idle:
            break
        }
    }

    private enum LockState {
        case idle, locked, recovering

        var label: String {
            switch self {
            case .idle: return "Tap a person to lock"
            case .locked: return "Locked on subject · tap to unlock"
            case .recovering: return "Recovering subject…"
            }
        }

        var dotColor: Color {
            switch self {
            case .idle: return Color(.sRGB, white: 1, opacity: 0.3)
            case .locked: return Color(red: 0.04, green: 0.52, blue: 1.0)
            case .recovering: return Color(red: 1.0, green: 0.72, blue: 0.24)
            }
        }

        var isInteractive: Bool {
            switch self {
            case .idle: return false
            case .locked, .recovering: return true
            }
        }
    }

    // MARK: - Framing segmented

    private var framingSegmentedSection: some View {
        let preset = cameraManager.shotComposer.config.shotPreset
        return HStack(spacing: 2) {
            framingSegment(label: "Wide", isOn: preset == .wideSafety) {
                cameraManager.shotComposer.config.shotPreset = .wideSafety
            }
            framingSegment(label: "Medium", isOn: preset == .medium) {
                cameraManager.shotComposer.config.shotPreset = .medium
            }
            framingSegment(label: "Waist Up", isOn: preset == .waistUp) {
                cameraManager.shotComposer.config.shotPreset = .waistUp
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 4)
    }

    private func framingSegment(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
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
        let enabled = cameraManager.isRunning && cameraManager.cropEnabled && !cameraManager.trackingPaused
        return Button {
            cameraManager.returnToWide()
        } label: {
            Text("Return to Wide")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.86 : 0.32))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Crop toggle

    private var cropToggleButton: some View {
        let isOn = cameraManager.cropEnabled
        let enabled = cameraManager.isRunning
        return Button {
            cameraManager.cropEnabled.toggle()
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn
                          ? Color(red: 0.31, green: 0.93, blue: 0.78)
                          : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text("Crop")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? (isOn ? 1.0 : 0.86) : 0.32))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Resume Tracking

    private var resumeTrackingButton: some View {
        let enabled = cameraManager.isRunning && cameraManager.cropEnabled && cameraManager.trackingPaused
        return Button {
            cameraManager.resumeTracking()
        } label: {
            Text("Resume Tracking")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.86 : 0.32))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
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
