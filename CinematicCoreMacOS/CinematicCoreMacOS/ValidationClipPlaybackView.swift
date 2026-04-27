//
//  ValidationClipPlaybackView.swift
//  CinematicCoreMacOS
//
//  Created by Codex on 4/26/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ValidationClipPlaybackView: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Form {
            Section("Source") {
                Picker("Session Source", selection: $cameraManager.preferredInputSource) {
                    ForEach(CameraManager.InputSource.allCases) { source in
                        Label(source.title, systemImage: source.systemImage)
                            .tag(source)
                    }
                }

                Text("When Validation Clip is selected, Start Session replays the chosen file through the same detection, compose, crop, and output path as the live camera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Validation Clip") {
                LabeledContent("Selected Clip", value: cameraManager.selectedValidationClipName)

                if let url = cameraManager.validationClipURL {
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        chooseClip()
                    } label: {
                        Label("Choose Clip", systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        cameraManager.setValidationClipURL(nil)
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(cameraManager.validationClipURL == nil)
                }

                Toggle("Loop Clip", isOn: $cameraManager.loopValidationClip)

                Text(cameraManager.validationClipStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Validation Flow") {
                Text("Recommended clip set: podium speaker, walking speaker, two-person stage, brief occlusion, and low-motion sermon framing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Use Start Session with Crop enabled so the right pane reflects the exact crop behavior you'll tune against.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }

    private func chooseClip() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Validation Clip"
        panel.message = "Select a recorded stage clip to replay through Alfie's pipeline."
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first

        if panel.runModal() == .OK, let url = panel.url {
            cameraManager.setValidationClipURL(url)
        }
    }
}

#Preview {
    ValidationClipPlaybackView(cameraManager: CameraManager())
}
