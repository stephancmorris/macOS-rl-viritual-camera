//
//  ShotComposerSettingsView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/7/2026.
//  Ticket: LOGIC-01 - Rule-Based Shot Composer Settings
//

import SwiftUI

/// Settings panel for the rule-based shot composer.
/// Body is split into `basicSection` and `advancedSection` so the unified
/// Settings window can host them under a Basic/Advanced toggle.
struct ShotComposerSettingsView: View {
    @ObservedObject var shotComposer: ShotComposer

    var body: some View {
        Form {
            basicSection
            advancedSection
            statusSection
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 500)
    }

    /// The everyday operator-facing knobs: enable/disable, frame profile,
    /// shot preset, head anchor.
    @ViewBuilder
    var basicSection: some View {
        Section("Shot Composer") {
            Toggle("Enable Composer", isOn: $shotComposer.config.isEnabled)
            Text("Aims for a stable waist-up shot when pose keypoints are available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Framing Style") {
            Picker("Frame Profile", selection: $shotComposer.config.frameProfile) {
                ForEach(ShotComposer.Config.FrameProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }

            Picker("Shot Preset", selection: $shotComposer.config.shotPreset) {
                ForEach(ShotComposer.Config.ShotPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Text("Use `Livestream Rectangle` for normal YouTube or switcher feeds. `Portrait Profile` is a secondary vertical option.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(shotComposer.config.shotPreset.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Head anchor") {
            LiquidFramingSwitch(selection: $shotComposer.config.shotFraming)
                .disabled(!shotComposer.config.isEnabled)

            Text("Anchors the crop's vertical position to the speaker's chest or waist. Distinct from the pill's shot preset, which controls overall tightness.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Tuning knobs that change live but are too subtle for an everyday operator.
    @ViewBuilder
    var advancedSection: some View {
        Section("Tuning") {
            HStack {
                Text("Deadzone")
                Spacer()
                Text(String(format: "%.0f%%", shotComposer.config.deadzoneThreshold * 100))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: $shotComposer.config.deadzoneThreshold,
                in: 0.01...0.15,
                step: 0.01
            )
            .disabled(!shotComposer.config.isEnabled)

            HStack {
                Text("Smoothing")
                Spacer()
                Text(String(format: "%.0f%%",
                            Double(shotComposer.config.smoothingFactor) * 100))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(shotComposer.config.smoothingFactor) },
                    set: { shotComposer.config.smoothingFactor = Float($0) }
                ),
                in: 0.05...0.30,
                step: 0.01
            )
            .disabled(!shotComposer.config.isEnabled)

            HStack {
                Text("Hold After Loss")
                Spacer()
                Text(String(format: "%.2fs", shotComposer.config.targetHoldDuration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: $shotComposer.config.targetHoldDuration,
                in: 0.25...2.0,
                step: 0.05
            )
            .disabled(!shotComposer.config.isEnabled)

            HStack {
                Text("Stage Side Margin")
                Spacer()
                Text(String(format: "%.0f%%", shotComposer.config.stageHorizontalMargin * 100))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: $shotComposer.config.stageHorizontalMargin,
                in: 0.00...0.20,
                step: 0.01
            )
            .disabled(!shotComposer.config.isEnabled)

            HStack {
                Text("Stage Top/Bottom Margin")
                Spacer()
                Text(String(format: "%.0f%%", shotComposer.config.stageVerticalMargin * 100))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: $shotComposer.config.stageVerticalMargin,
                in: 0.00...0.15,
                step: 0.01
            )
            .disabled(!shotComposer.config.isEnabled)
        }
    }

    @ViewBuilder
    var statusSection: some View {
        Section("Status") {
            LabeledContent("Active Target",
                           value: shotComposer.hasActiveTarget ? "Yes" : "No")

            LabeledContent("Target Lock",
                           value: shotComposer.activeTargetID == nil ? "None" : "Tracking")

            LabeledContent(
                "Manual Override",
                value: shotComposer.isManualLockActive ? "Locked" : "Auto"
            )

            LabeledContent(
                "Frame Profile",
                value: shotComposer.config.frameProfile.shortTitle
            )

            LabeledContent(
                "Shot Preset",
                value: shotComposer.config.shotPreset.title
            )

            LabeledContent(
                "Stage Window",
                value: String(
                    format: "L/R %.0f%%  T/B %.0f%%",
                    shotComposer.config.stageHorizontalMargin * 100,
                    shotComposer.config.stageVerticalMargin * 100
                )
            )

            if let crop = shotComposer.lastComputedCrop {
                LabeledContent("Crop Origin",
                               value: String(format: "(%.2f, %.2f)",
                                             crop.origin.x, crop.origin.y))
                LabeledContent("Crop Size",
                               value: String(format: "%.2f x %.2f",
                                             crop.size.width, crop.size.height))
            }
        }
    }
}

// MARK: - Liquid Glass Framing Switch

struct LiquidFramingSwitch: View {
    @Binding var selection: ShotComposer.Config.ShotFraming
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ShotComposer.Config.ShotFraming.allCases) { option in
                segment(for: option)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    @ViewBuilder
    private func segment(for option: ShotComposer.Config.ShotFraming) -> some View {
        let isSelected = selection == option
        Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = option
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(for: option))
                    .font(.system(size: 11, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : Color.white.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.mint.opacity(0.95),
                                    Color.green.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .mint.opacity(0.35), radius: 8, y: 2)
                        .matchedGeometryEffect(id: "framingIndicator", in: indicatorNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func icon(for option: ShotComposer.Config.ShotFraming) -> String {
        switch option {
        case .chestUp: return "person.crop.rectangle"
        case .waistUp: return "person.fill"
        }
    }
}

#Preview {
    ShotComposerSettingsView(shotComposer: ShotComposer())
}
