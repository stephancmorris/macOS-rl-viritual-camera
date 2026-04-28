//
//  SettingsWindow.swift
//  CinematicCoreMacOS
//
//  Created by Codex on 4/27/2026.
//

import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var selectedTab: SettingsTab = .composer

    enum SettingsTab: String, CaseIterable, Identifiable {
        case composer
        case detection
        case crop
        case output

        var id: String { rawValue }

        var title: String {
            switch self {
            case .composer:
                return "Composer"
            case .detection:
                return "Detection"
            case .crop:
                return "Crop"
            case .output:
                return "Output"
            }
        }

        var systemImage: String {
            switch self {
            case .composer:
                return "film"
            case .detection:
                return "person.crop.rectangle"
            case .crop:
                return "crop.rotate"
            case .output:
                return "video.badge.waveform"
            }
        }

        var summary: String {
            switch self {
            case .composer:
                return "Shot logic, framing style, deadzone, smoothing, and target hold behavior."
            case .detection:
                return "Vision person detection sensitivity, confidence, accuracy mode, and live statistics."
            case .crop:
                return "Crop engine quality, output profile, render smoothing, and GPU performance."
            case .output:
                return "Program route health, dropped frames, reconnect controls, and live latency."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            TabView(selection: $selectedTab) {
                ComposerTab(shotComposer: cameraManager.shotComposer)
                    .tabItem {
                        Label(SettingsTab.composer.title, systemImage: SettingsTab.composer.systemImage)
                    }
                    .tag(SettingsTab.composer)

                DetectionSettingsView(personDetector: cameraManager.personDetector)
                    .tabItem {
                        Label(SettingsTab.detection.title, systemImage: SettingsTab.detection.systemImage)
                    }
                    .tag(SettingsTab.detection)

                cropTab
                    .tabItem {
                        Label(SettingsTab.crop.title, systemImage: SettingsTab.crop.systemImage)
                    }
                    .tag(SettingsTab.crop)

                ProgramOutputSettingsView(programOutput: cameraManager.programOutput)
                    .tabItem {
                        Label(SettingsTab.output.title, systemImage: SettingsTab.output.systemImage)
                    }
                    .tag(SettingsTab.output)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 640, idealHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alfie Settings")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text(selectedTab.summary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var cropTab: some View {
        if let cropEngine = cameraManager.cropEngine {
            CropSettingsView(
                cropEngine: cropEngine,
                cameraManager: cameraManager
            )
        } else {
            SettingsUnavailableView(
                title: "Crop Engine Unavailable",
                systemImage: "exclamationmark.triangle",
                message: "Metal crop controls are unavailable on this Mac or failed to initialize in the current session."
            )
        }
    }
}

// MARK: - Composer tab with Basic / Advanced toggle

private struct ComposerTab: View {
    @ObservedObject var shotComposer: ShotComposer
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showAdvanced) {
                Text("Basic").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Form {
                let view = ShotComposerSettingsView(shotComposer: shotComposer)
                view.basicSection
                if showAdvanced {
                    view.advancedSection
                }
                view.statusSection
            }
            .formStyle(.grouped)
        }
    }
}

private struct SettingsUnavailableView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

#Preview {
    SettingsWindow(cameraManager: CameraManager())
}
