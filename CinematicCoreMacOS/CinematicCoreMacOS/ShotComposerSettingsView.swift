//
//  ShotComposerSettingsView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/7/2026.
//  Ticket: LOGIC-01 - Rule-Based Shot Composer Settings
//

import SwiftUI

/// Settings panel for the rule-based shot composer
struct ShotComposerSettingsView: View {
    @ObservedObject var shotComposer: ShotComposer

    var body: some View {
        Form {
            Section("Shot Composer") {
                Toggle("Enable Composer", isOn: $shotComposer.config.isEnabled)
                Text("Aims for a stable waist-up shot when pose keypoints are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    Text("Breathing Room")
                    Spacer()
                    Text(String(format: "%.0f%%", shotComposer.config.padding * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $shotComposer.config.padding,
                    in: 0.05...0.50,
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

                HStack {
                    Text("Subject Edge Safety")
                    Spacer()
                    Text(String(format: "%.0f%%", shotComposer.config.edgeSafetyMargin * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $shotComposer.config.edgeSafetyMargin,
                    in: 0.05...0.25,
                    step: 0.01
                )
                .disabled(!shotComposer.config.isEnabled)
            }

            Section("Status") {
                LabeledContent("Active Target",
                               value: shotComposer.hasActiveTarget ? "Yes" : "No")

                LabeledContent("Target Lock",
                               value: shotComposer.activeTargetID == nil ? "None" : "Tracking")

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
        .formStyle(.grouped)
        .frame(width: 350, height: 500)
    }
}

#Preview {
    ShotComposerSettingsView(shotComposer: ShotComposer())
}
