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
    @ObservedObject var settingsWindowController: SettingsWindowController
    @Binding var isOpen: Bool

    @Environment(\.openSettings) private var openSettings
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
                    PipelineStagesSection(programOutput: cameraManager.programOutput)
                    SetupCheckSection(
                        check: cameraManager.setupCheck,
                        output: cameraManager.programOutput,
                        isCaptureRunning: cameraManager.isRunning)
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

            row("Source Resolution") {
                valueText(cameraManager.sourcePixelHeight > 0
                    ? "\(cameraManager.sourcePixelWidth)×\(cameraManager.sourcePixelHeight) delivered"
                    : "Waiting for frame", monospaced: true)
            }

            Text(cameraManager.captureProfileStatus)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            if let capability = cameraManager.framingCapability {
                row("Crop Geometry") {
                    valueText(capability.enlargement > 1.000001
                        ? String(format: "%.2f× pixel enlargement", Double(capability.enlargement))
                        : "Native/downsampled", monospaced: true)
                }
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
            row("Spring ease") {
                if let cropEngine = cameraManager.cropEngine {
                    valueText(String(format: "%.2f / frame", cropEngine.config.transitionSmoothing), monospaced: true)
                } else {
                    valueText("—", monospaced: true)
                }
            }

            HStack {
                smallButton("Settings…", systemImage: "gearshape", equalWidth: true) {
                    openSettingsWindow(.composer)
                }
            }
            .padding(.top, 10)
        }
    }

    private func openSettingsWindow(_ tab: SettingsTab) {
        settingsWindowController.open(tab)
        openSettings()
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
            HStack(spacing: 8) {
                smallButton("Output settings…", systemImage: "dot.radiowaves.left.and.right") {
                    openSettingsWindow(.output)
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
                openSettingsWindow(.composer)
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
                openSettingsWindow(.output)
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
        let logsURL = AlfieDiagnosticsLog.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logsURL)
    }
}

/// Per-stage frame counts for the last closed diagnostics window (~5 s) and
/// the session. Observes ProgramOutputManager directly; its published values
/// change at most every 0.5 s, and only while this drawer is open.
struct PipelineStagesSection: View {
    @ObservedObject var programOutput: ProgramOutputManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PIPELINE STAGES")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.bottom, 6)

            if let window = programOutput.lastPipelineWindow {
                let totals = programOutput.pipelineTotals
                Text(String(format: "Last %@ window · %.1f s", window.kind == .partial ? "partial" : "full", window.windowSeconds))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 4)
                stageRow("Delivered", fps(Double(window.window.delivered), window), total: Int(totals.delivered))
                stageRow("Admitted", fps(Double(window.window.admitted), window), total: totals.admitted)
                stageRow("Handoff accepted", fps(Double(window.window.handoffAccepted), window), total: totals.handoffAccepted)
                stageRow("Repeated (HOLD)", count(window.window.repeated), total: totals.repeated)
                stageRow("Presented", "unknown", total: nil)
                stageRow("Capture dropped", count(window.window.captureDropped), total: totals.captureDropped)
                stageRow("Gate skipped", count(Int(window.window.gateSkipped)), total: Int(totals.gateSkipped))
                stageRow("Render failed", count(window.window.renderFailed), total: totals.renderFailed)
                stageRow("Handoff refused", count(window.window.handoffRefused), total: totals.handoffRefused)
                stageRow("No route", count(window.window.noRoute), total: totals.noRoute)
                Text("Handoff is when the route accepted the frame; when the display or virtual-camera consumer shows it is not reported to Alfie.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                Text("No window closed yet. Counts appear about 5 s after capture starts.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func fps(_ frames: Double, _ window: DiagnosticsWindow) -> String {
        guard window.windowSeconds > 0 else { return "–" }
        return String(format: "%.1f fps", frames / window.windowSeconds)
    }

    private func count(_ value: Int) -> String { String(value) }

    private func stageRow(_ label: String, _ value: String, total: Int?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
            Text(total.map { "Σ \($0)" } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

/// Runs the single-camera setup check and shows its provisional verdict with
/// the measured reasons. The check only observes the running pipeline.
struct SetupCheckSection: View {
    @ObservedObject var check: SetupCheck
    let output: ProgramOutputManager
    let isCaptureRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETUP CHECK")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.42))

            switch check.phase {
            case .idle:
                caption(String(format: "Measures this source and output route for about %.0f s while it runs. Nothing is changed.", check.approximateDuration))
                runButton("Run setup check")
            case .warmingUp:
                progress("Warming up…")
            case .sampling(let collected, let needed):
                progress("Measuring · window \(collected + 1) of \(needed)")
            case .finished(let report):
                result(report)
                runButton("Run again")
            case .cancelled(let reason):
                caption(reason)
                runButton("Run again")
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func runButton(_ title: String) -> some View {
        Button(title) { check.start(output: output, isCaptureRunning: isCaptureRunning) }
            .controlSize(.small)
            .disabled(!isCaptureRunning)
            .help(isCaptureRunning ? "Sample the running pipeline" : "Start capture first")
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button("Cancel") { check.cancel() }
                .controlSize(.small)
        }
    }

    private func verdictColor(_ verdict: CapabilityVerdict) -> Color {
        switch verdict {
        case .supported: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .limited: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .unverified: return Color.white.opacity(0.55)
        }
    }

    @ViewBuilder
    private func result(_ report: CapabilityReport) -> some View {
        let m = report.measured
        HStack(spacing: 8) {
            Text(report.verdict.title.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(verdictColor(report.verdict))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(verdictColor(report.verdict).opacity(0.5), lineWidth: 1))
            Text(report.context.source)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        Text(String(format: "Delivered %.1f fps · handoff %.1f fps · %.1f ms/frame · %.1f%% skipped · %.0f s measured",
                    m.deliveredFPS, m.handoffFPS, m.frameWallMeanMS, m.gateSkipRatio * 100, m.seconds))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
        ForEach(report.reasons) { reason in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon(reason.kind))
                    .font(.system(size: 10))
                    .foregroundStyle(reason.kind == .limit ? verdictColor(.limited) : .white.opacity(0.5))
                Text(reason.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        caption(CapabilityReport.disclaimer)
    }

    private func icon(_ kind: CapabilityReason.Kind) -> String {
        switch kind {
        case .limit: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        case .note: return "info.circle"
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
