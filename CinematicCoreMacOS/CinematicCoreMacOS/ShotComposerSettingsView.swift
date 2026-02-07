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

                Toggle("Rule of Thirds", isOn: $shotComposer.config.useRuleOfThirds)
                    .help("Frame head at upper third, waist at lower third")
                    .disabled(!shotComposer.config.isEnabled)
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
                    Text("Padding")
                    Spacer()
                    Text(String(format: "%.0f%%", shotComposer.config.horizontalPadding * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $shotComposer.config.horizontalPadding,
                    in: 0.05...0.30,
                    step: 0.01
                )
                .disabled(!shotComposer.config.isEnabled)
            }

            Section("Status") {
                LabeledContent("Active Target",
                               value: shotComposer.hasActiveTarget ? "Yes" : "No")

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
