//
//  RecorderSettingsView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/10/2026.
//  Ticket: RL-01 - Training Data Recorder Settings
//

import SwiftUI

/// Settings panel for the training data recorder
struct RecorderSettingsView: View {
    @ObservedObject var recorder: TrainingDataRecorder
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Form {
            Section("Recording") {
                Toggle("Record Training Data", isOn: recordingBinding)
                    .tint(.red)

                Toggle("Manual Crop Labels", isOn: manualOverrideBinding)
                    .help("Use manual crop adjustments as ideal labels instead of auto ShotComposer output")
                    .disabled(!recorder.isRecording)
            }

            Section("Settings") {
                Stepper(
                    "Record every \(recorder.config.subsampleRate) frame(s)",
                    value: $recorder.config.subsampleRate,
                    in: 1...10
                )
                .disabled(recorder.isRecording)

                Stepper(
                    "Buffer size: \(recorder.config.bufferSize)",
                    value: $recorder.config.bufferSize,
                    in: 50...500,
                    step: 50
                )
                .disabled(recorder.isRecording)
            }

            Section("Output") {
                LabeledContent("Directory") {
                    Button("Open in Finder") {
                        recorder.openInFinder()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Session Statistics") {
                LabeledContent("Frames Recorded",
                               value: "\(recorder.stats.framesRecorded)")

                LabeledContent("Duration",
                               value: formatDuration(recorder.stats.sessionDuration))

                LabeledContent("File Size",
                               value: formatBytes(recorder.stats.fileSizeBytes))

                LabeledContent("Dropped Frames",
                               value: "\(recorder.stats.droppedFrames)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 480)
    }

    // MARK: - Bindings

    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { recorder.isRecording },
            set: { newValue in
                if newValue {
                    let cameraName = cameraManager.selectedCamera?.name ?? "Unknown"
                    let resolution = cameraManager.cropEngine?.config.outputSize
                        ?? CGSize(width: 1920, height: 1080)
                    recorder.startRecording(
                        cameraName: cameraName,
                        resolution: resolution,
                        composerConfig: cameraManager.shotComposer.config,
                        detectorConfig: cameraManager.personDetector.config
                    )
                } else {
                    recorder.stopRecording()
                }
            }
        )
    }

    private var manualOverrideBinding: Binding<Bool> {
        Binding(
            get: { recorder.manualCropOverride != nil },
            set: { newValue in
                if newValue {
                    // Start with current crop as the manual baseline
                    recorder.manualCropOverride = cameraManager.cropEngine?.currentCrop ?? .fullFrame
                } else {
                    recorder.manualCropOverride = nil
                }
            }
        )
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

#Preview {
    RecorderSettingsView(
        recorder: TrainingDataRecorder(),
        cameraManager: CameraManager()
    )
}
