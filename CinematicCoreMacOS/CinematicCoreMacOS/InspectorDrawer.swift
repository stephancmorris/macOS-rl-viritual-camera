//
//  InspectorDrawer.swift
//  CinematicCoreMacOS
//
//  Right-side drawer surfacing all settings that no longer live in the
//  bottom dock: source, composition, output, modules, diagnostics.
//

import AppKit
import Metal
import SwiftUI

struct InspectorDrawer: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var systemExtensionManager: SystemExtensionActivationManager
    @Binding var isOpen: Bool

    @State private var showCameraList = false
    @State private var showAgentSettings = false
    @State private var showRecorderSettings = false
    @State private var showPlaybackSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    sourceSection
                    compositionSection
                    outputSection
                    modulesSection
                    diagnosticsSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 400)
        .frame(maxHeight: .infinity)
        .background(drawerBackground)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 0.5)
                .frame(maxHeight: .infinity),
            alignment: .leading
        )
        .shadow(color: .black.opacity(0.45), radius: 30, x: -8, y: 0)
    }

    private var drawerBackground: some View {
        Rectangle()
            .fill(Color(red: 0.078, green: 0.078, blue: 0.086).opacity(0.78))
            .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Inspector")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.36)) { isOpen = false }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Section primitives

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.42))
    }

    private func row<Right: View>(
        _ label: String,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 12)
            right()
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func valueText(_ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(.system(
                size: 12.5,
                weight: .medium,
                design: monospaced ? .monospaced : .default
            ))
            .foregroundStyle(.white.opacity(0.92))
    }

    private func smallButton(
        _ label: String,
        systemImage: String? = nil,
        equalWidth: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: equalWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ text: String, color: Color, filled: Bool = false) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(filled ? 0.85 : 0.0))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
    }

    // MARK: - Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow("Source")
                .padding(.bottom, 6)

            row("Camera") {
                Picker("", selection: cameraBinding) {
                    ForEach(cameraManager.availableCameras) { camera in
                        Text(camera.name).tag(camera as CameraManager.CameraDevice?)
                    }
                    if cameraManager.availableCameras.isEmpty {
                        Text("No camera").tag(CameraManager.CameraDevice?.none)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.white)
                .fixedSize()
            }

            row("Resolution") {
                valueText(cameraManager.selectedCamera?.maxResolution ?? "—", monospaced: true)
            }

            row("Color") {
                valueText("Rec. 709 · 8-bit", monospaced: true)
            }

            HStack(spacing: 8) {
                smallButton("Refresh devices", systemImage: "arrow.clockwise") {
                    cameraManager.discoverCameras()
                }
                smallButton("Cameras…", systemImage: "camera") {
                    showCameraList.toggle()
                }
                .popover(isPresented: $showCameraList) {
                    CameraListView(cameraManager: cameraManager)
                }
                Spacer()
            }
            .padding(.top, 10)
        }
    }

    private var cameraBinding: Binding<CameraManager.CameraDevice?> {
        Binding(
            get: { cameraManager.selectedCamera },
            set: { newValue in
                guard let newValue else { return }
                cameraManager.selectedCamera = newValue
                if cameraManager.isRunning {
                    Task { try? await cameraManager.restartWithCamera(newValue) }
                }
            }
        )
    }

    // MARK: - Composition

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow("Composition")
                .padding(.bottom, 6)

            row("Target hold") {
                valueText(
                    String(format: "%.2f s", cameraManager.shotComposer.config.targetHoldDuration),
                    monospaced: true
                )
            }
            row("Deadzone") {
                valueText(
                    String(format: "%.1f%%", cameraManager.shotComposer.config.deadzoneThreshold * 100),
                    monospaced: true
                )
            }
            row("Lerp ease") {
                if let cropEngine = cameraManager.cropEngine {
                    valueText(String(format: "%.2f / frame", cropEngine.config.transitionSmoothing), monospaced: true)
                } else {
                    valueText("—", monospaced: true)
                }
            }

            HStack {
                smallButton("Settings…", systemImage: "gearshape", equalWidth: true) {
                    openSettingsWindow()
                }
            }
            .padding(.top, 10)
        }
    }

    private func openSettingsWindow() {
        // Standard macOS hook for the Settings scene. Works with SwiftUI's
        // `Settings { ... }` scene declared in CinematicCoreMacOSApp.
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow("Output")
                .padding(.bottom, 6)

            row("Virtual camera") {
                if cameraManager.programOutput.activeRoute == .virtualCamera {
                    statusPill("Routing", color: Color(red: 0.19, green: 0.82, blue: 0.35))
                } else {
                    statusPill("Idle", color: Color.white.opacity(0.4))
                }
            }
            row("Blackmagic SDI") {
                statusPill("Deferred", color: Color.white.opacity(0.4))
            }
            row("NDI") {
                statusPill("Deferred", color: Color.white.opacity(0.4))
            }

            HStack(spacing: 8) {
                smallButton("Output settings…", systemImage: "dot.radiowaves.left.and.right") {
                    openSettingsWindow()
                }
                Spacer()
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Modules

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow("Modules")
                .padding(.bottom, 6)

            moduleRow(
                name: "Composer",
                description: "Active. Heuristic controller v1.4.",
                isActive: true
            ) {
                openSettingsWindow()
            }

            if DeveloperFlags.exposeClipPlaybackControls {
                moduleRow(
                    name: "Playback",
                    description: cameraManager.preferredInputSource == .validationClip
                        ? "Routing validation clip."
                        : "Last 60 s ring buffer.",
                    isActive: cameraManager.preferredInputSource == .validationClip
                ) {
                    showPlaybackSettings.toggle()
                }
                .popover(isPresented: $showPlaybackSettings) {
                    ValidationClipPlaybackView(cameraManager: cameraManager)
                }
            }

            moduleRow(
                name: "Output",
                description: outputSummary,
                isActive: cameraManager.programOutput.activeRoute != nil
            ) {
                openSettingsWindow()
            }

            if DeveloperFlags.exposeMLAgentControls {
                moduleRow(
                    name: "Cinematic Agent",
                    description: "Developer flag · RL controller",
                    isActive: cameraManager.useMLAgent,
                    badge: "DEV"
                ) {
                    showAgentSettings.toggle()
                }
                .popover(isPresented: $showAgentSettings) {
                    CinematicAgentSettingsView(cameraManager: cameraManager)
                }
            }

            if DeveloperFlags.exposeTrainingRecorderControls {
                moduleRow(
                    name: "Recorder",
                    description: cameraManager.trainingDataRecorder.isRecording
                        ? "Recording training data."
                        : "JSONL recorder · idle.",
                    isActive: cameraManager.trainingDataRecorder.isRecording,
                    badge: "DEV"
                ) {
                    showRecorderSettings.toggle()
                }
                .popover(isPresented: $showRecorderSettings) {
                    RecorderSettingsView(
                        recorder: cameraManager.trainingDataRecorder,
                        cameraManager: cameraManager
                    )
                }
            }
        }
    }

    private var outputSummary: String {
        guard let cropEngine = cameraManager.cropEngine else {
            return "Virtual camera · 1920×1080"
        }
        let w = Int(cropEngine.config.outputSize.width)
        let h = Int(cropEngine.config.outputSize.height)
        return "Virtual camera · \(w)×\(h)"
    }

    private func moduleRow(
        name: String,
        description: String,
        isActive: Bool,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isActive
                          ? Color(red: 0.19, green: 0.82, blue: 0.35)
                          : Color.white.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.0)
                                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.6), lineWidth: 1)
                                )
                        }
                    }
                    Text(description)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow("Diagnostics")
                .padding(.bottom, 6)

            row("Build") {
                valueText(buildString, monospaced: true)
            }
            row("Extension") {
                valueText(extensionStatus, monospaced: true)
            }
            row("GPU") {
                valueText(gpuName, monospaced: true)
            }

            HStack(spacing: 8) {
                smallButton("Reveal logs in Finder", systemImage: "folder") {
                    revealLogsInFinder()
                }
                Spacer()
            }
            .padding(.top, 10)
        }
    }

    private var buildString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var extensionStatus: String {
        if systemExtensionManager.isInstallReady {
            return "cmio · loaded"
        }
        switch systemExtensionManager.status {
        case .unknown: return "cmio · unknown"
        case .notInstalled: return "cmio · not installed"
        case .activationRequested: return "cmio · activating"
        case .awaitingUserApproval: return "cmio · awaiting approval"
        case .installed: return "cmio · loaded"
        case .failed: return "cmio · failed"
        }
    }

    private var gpuName: String {
        MTLCreateSystemDefaultDevice()?.name ?? "Metal unavailable"
    }

    private func revealLogsInFinder() {
        let logsURL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs")
        if let logsURL {
            NSWorkspace.shared.open(logsURL)
        }
    }
}

struct InspectorHandle: View {
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.36)) { isOpen.toggle() }
        } label: {
            Text("⌥")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}
