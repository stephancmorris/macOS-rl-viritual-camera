//
//  CinematicAgentSettingsView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/25/2026.
//  Ticket: APP-02 - CoreML Agent Settings
//

import SwiftUI

/// Settings panel for the RL-trained CoreML cinematic agent.
struct CinematicAgentSettingsView: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Form {
            Section("Cinematic Agent") {
                Toggle("Use RL Agent", isOn: $cameraManager.useMLAgent)
                    .help("Replace the rule-based shot composer with the trained CoreML model")
                    .disabled(!cameraManager.cinematicAgent.isModelLoaded)
            }

            Section("Model Status") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(cameraManager.cinematicAgent.isModelLoaded
                                  ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(cameraManager.cinematicAgent.modelStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let crop = cameraManager.cinematicAgent.lastPredictedCrop {
                Section("Last Prediction") {
                    LabeledContent("Origin",
                                   value: String(format: "(%.3f, %.3f)",
                                                 crop.origin.x, crop.origin.y))
                    LabeledContent("Size",
                                   value: String(format: "%.3f × %.3f",
                                                 crop.size.width, crop.size.height))
                    LabeledContent("Zoom",
                                   value: String(format: "%.2f×",
                                                 crop.size.height > 0.001
                                                 ? 1.0 / crop.size.height : 1.0))
                }
            }

            if !cameraManager.cinematicAgent.isModelLoaded {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To enable the RL agent:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("1. Run the training pipeline (see training/TRAINING_GUIDE.md)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("2. Export: python export_coreml.py --model models/ppo_final.zip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("3. Drag CinematicFraming.mlpackage into Xcode project navigator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("4. Rebuild the app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 380)
        .onAppear {
            cameraManager.cinematicAgent.ensureModelLoaded()
        }
    }
}

#Preview {
    CinematicAgentSettingsView(cameraManager: CameraManager())
}
