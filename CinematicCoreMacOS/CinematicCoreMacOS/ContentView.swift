//
//  ContentView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import SwiftUI

struct ContentView: View {
    private enum AdaptiveTier {
        case expanded
        case large
        case medium
        case compact
        case minimal
    }

    @StateObject private var cameraManager = CameraManager()
    @State private var showError = false
    @State private var showCameraList = false
    @State private var showDetections = true // Task 2.1: Toggle for detection overlay
    @State private var showDetectionSettings = false // Task 2.1: Detection settings panel
    @State private var showCropSettings = false // Task 2.2: Crop settings panel
    @State private var showCropIndicator = true // Task 2.2: Show crop rectangle on preview
    @State private var showComposerSettings = false // Task 2.3: Shot composer settings
    @State private var showRecorderSettings = false // Task 3.1: Training data recorder
    @State private var showAgentSettings = false    // Task APP-02: RL agent settings
    @State private var showOutputSettings = false   // Task 2.4: Program output routing
    @State private var showHeaderOverflow = false
    @State private var showDockOverflow = false
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack {
                LiquidGlassBackdrop()

                VStack(spacing: 18) {
                    headerPanel(for: width)
                    previewPanel
                    controlDock(for: width)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .alert("Camera Error", isPresented: $showError, presenting: cameraManager.error) { _ in
            Button("OK") { showError = false }
        } message: { error in
            Text(error.localizedDescription)
        }
        .task {
            await startCamera()
        }
    }

    private func headerPanel(for width: CGFloat) -> some View {
        let tier = adaptiveTier(for: width)

        return ZStack {
            HStack(spacing: 12) {
                headerCommandPanel(title: "Source · Session") {
                    if tier == .expanded || tier == .large || tier == .medium {
                        infoPill(
                            title: cameraManager.selectedCamera?.name ?? "No Camera",
                            detail: cameraManager.selectedCamera?.maxResolution ?? "Unavailable",
                            tint: .white.opacity(0.7)
                        )
                    }

                    Button(action: { showCameraList.toggle() }) {
                        Label("Cameras", systemImage: "camera.circle")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                    .popover(isPresented: $showCameraList) {
                        CameraListView(cameraManager: cameraManager)
                    }

                    if tier == .expanded || tier == .large || tier == .medium {
                        Button(action: { cameraManager.discoverCameras() }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                    }

                    Button(action: toggleCamera) {
                        Label(
                            cameraManager.isRunning ? "Stop Session" : "Start Session",
                            systemImage: cameraManager.isRunning ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(
                        GlassCapsuleButtonStyle(
                            tint: cameraManager.isRunning ? .red : .green,
                            isPrimary: true
                        )
                    )
                    .disabled(cameraManager.error != nil || cameraManager.availableCameras.isEmpty)
                }
                .frame(maxWidth: tier == .minimal ? 240 : 620)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CinematicCore")
                        .font(.system(size: tier == .minimal ? 24 : 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Liquid glass camera console for live autonomous framing")
                        .font(.system(size: tier == .minimal ? 12 : 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        statusBadge(
                            title: cameraManager.isRunning ? "Live Session" : "Offline",
                            systemImage: cameraManager.isRunning ? "dot.radiowaves.left.and.right" : "pause.circle",
                            tint: cameraManager.isRunning ? .green : .orange
                        )

                        if tier != .minimal {
                            statusBadge(
                                title: cameraManager.programOutput.activeRouteTitle,
                                systemImage: cameraManager.programOutput.activeRoute?.systemImage ?? "cable.connector.slash",
                                tint: .cyan
                            )
                        }

                        if tier == .expanded, let selectedCamera = cameraManager.selectedCamera {
                            statusBadge(
                                title: selectedCamera.name,
                                systemImage: "camera.aperture",
                                tint: .white.opacity(0.75)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    metricTile(
                        title: "Persons",
                        value: "\(cameraManager.personDetector.detectedPersons.count)",
                        detail: cameraManager.isRunning ? "Vision live" : "Idle",
                        tint: .mint
                    )

                    if tier != .minimal {
                        metricTile(
                            title: "Detection",
                            value: String(format: "%.1fms", cameraManager.personDetector.stats.lastDetectionTime * 1000),
                            detail: "Frame analysis",
                            tint: .blue
                        )
                    }

                    if tier == .expanded || tier == .large {
                        metricTile(
                            title: "Program",
                            value: "\(cameraManager.programOutput.framesSent)",
                            detail: "Frames routed",
                            tint: .cyan
                        )
                    }

                    if headerHasOverflow(for: tier) {
                        Button(action: { showHeaderOverflow.toggle() }) {
                            overflowButton(title: "More", tint: .white.opacity(0.64))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showHeaderOverflow) {
                            headerOverflowPanel(for: tier)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 30)
    }

    private var previewPanel: some View {
        Group {
            if showDetections {
                CropPreviewView(
                    originalFrame: cameraManager.currentFrame,
                    croppedFrame: cameraManager.croppedFrame,
                    detectedPersons: cameraManager.personDetector.detectedPersons,
                    showDetections: showDetections,
                    cropRect: showCropIndicator ? cameraManager.cropEngine?.currentCrop : nil,
                    activeTargetID: cameraManager.shotComposer.activeTargetID,
                    manualLockedTargetID: cameraManager.manualLockedTargetID,
                    trackedSubjectRect: cameraManager.shotComposer.lastTrackedBounds,
                    onSelectPerson: cameraManager.lockTarget
                )
            } else {
                LiquidPreviewCard(
                    title: "Input · Wide",
                    subtitle: "Raw stage feed",
                    accent: .mint
                ) {
                    CameraPreviewView(
                        image: cameraManager.currentFrame,
                        detectedPersons: cameraManager.personDetector.detectedPersons,
                        showDetections: showDetections,
                        activeTargetID: cameraManager.shotComposer.activeTargetID,
                        manualLockedTargetID: cameraManager.manualLockedTargetID,
                        trackedSubjectRect: cameraManager.shotComposer.lastTrackedBounds,
                        onSelectPerson: cameraManager.lockTarget,
                        cropIndicator: nil
                    )
                }
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 34)
    }

    private func controlDock(for width: CGFloat) -> some View {
        let tier = adaptiveTier(for: width)

        return HStack(alignment: .top, spacing: 14) {
            if tier == .expanded || tier == .large || tier == .medium {
                controlCluster(title: "Inspect") {
                    Toggle(isOn: $showDetections) {
                        Label("Detections", systemImage: "person.crop.rectangle")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(GlassCapsuleButtonStyle(tint: showDetections ? .blue : .white.opacity(0.6)))

                    if tier != .compact {
                        Button(action: { showDetectionSettings.toggle() }) {
                            Label("Detection", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                        .popover(isPresented: $showDetectionSettings) {
                            DetectionSettingsView(personDetector: cameraManager.personDetector)
                        }
                    }
                }
            }

            if let cropEngine = cameraManager.cropEngine {
                controlCluster(title: "Framing") {
                    Toggle(isOn: $cameraManager.cropEnabled) {
                        Label("Crop", systemImage: "crop.rotate")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(GlassCapsuleButtonStyle(tint: cameraManager.cropEnabled ? .mint : .white.opacity(0.6)))

                    if tier != .minimal {
                        Toggle(isOn: $showCropIndicator) {
                            Label("Indicator", systemImage: "viewfinder")
                        }
                        .toggleStyle(.button)
                        .buttonStyle(GlassCapsuleButtonStyle(tint: showCropIndicator ? .cyan : .white.opacity(0.6)))
                        .disabled(!cameraManager.cropEnabled)
                    }

                    if tier == .expanded || tier == .large {
                        Button(action: { showCropSettings.toggle() }) {
                            Label("Crop Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                        .popover(isPresented: $showCropSettings) {
                            CropSettingsView(
                                cropEngine: cropEngine,
                                cameraManager: cameraManager
                            )
                        }
                    }

                    if (tier == .expanded || tier == .large) && cameraManager.isRunning && cameraManager.cropEnabled {
                        infoPill(
                            title: "\(cameraManager.shotComposer.config.shotPreset.title) · \(cameraManager.shotComposer.config.frameProfile.shortTitle)",
                            detail: "\(Int(cropEngine.config.outputSize.width))×\(Int(cropEngine.config.outputSize.height))",
                            tint: cameraManager.trackingPaused ? .orange : .mint
                        )
                    }
                }

                controlCluster(title: "Recovery") {
                    Button(action: { cameraManager.returnToWide() }) {
                        Label("Return to Wide", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .orange, isPrimary: true))
                    .disabled(!cameraManager.isRunning || !cameraManager.cropEnabled || cameraManager.trackingPaused)

                    Button(action: { cameraManager.resumeTracking() }) {
                        Label("Resume Tracking", systemImage: "scope")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .green, isPrimary: true))
                    .disabled(!cameraManager.isRunning || !cameraManager.cropEnabled || !cameraManager.trackingPaused)

                    if cameraManager.isManualTargetLockActive {
                        Button(action: { cameraManager.clearManualTargetLock() }) {
                            Label("Clear Lock", systemImage: "pin.slash")
                        }
                        .buttonStyle(GlassCapsuleButtonStyle(tint: .yellow))
                    }
                }
            }

            if tier == .expanded || tier == .large {
                controlCluster(title: "Modules") {
                    Button(action: { showComposerSettings.toggle() }) {
                        Label("Composer", systemImage: "film")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .purple))
                    .popover(isPresented: $showComposerSettings) {
                        ShotComposerSettingsView(
                            shotComposer: cameraManager.shotComposer
                        )
                    }

                    Button(action: { showAgentSettings.toggle() }) {
                        Label(
                            "Agent",
                            systemImage: cameraManager.useMLAgent
                                ? "brain.filled.head.profile"
                                : "brain.head.profile"
                        )
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: cameraManager.useMLAgent ? .blue : .white.opacity(0.6)))
                    .popover(isPresented: $showAgentSettings) {
                        CinematicAgentSettingsView(cameraManager: cameraManager)
                    }

                    Button(action: { showRecorderSettings.toggle() }) {
                        Label(
                            cameraManager.trainingDataRecorder.isRecording ? "Recorder Live" : "Recorder",
                            systemImage: cameraManager.trainingDataRecorder.isRecording
                                ? "record.circle.fill" : "record.circle"
                        )
                    }
                    .buttonStyle(
                        GlassCapsuleButtonStyle(
                            tint: cameraManager.trainingDataRecorder.isRecording ? .red : .white.opacity(0.6),
                            isPrimary: cameraManager.trainingDataRecorder.isRecording
                        )
                    )
                    .popover(isPresented: $showRecorderSettings) {
                        RecorderSettingsView(
                            recorder: cameraManager.trainingDataRecorder,
                            cameraManager: cameraManager
                        )
                    }

                    Button(action: { showOutputSettings.toggle() }) {
                        Label(
                            "Output",
                            systemImage: cameraManager.programOutput.activeRoute?.systemImage
                                ?? "dot.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .cyan))
                    .popover(isPresented: $showOutputSettings) {
                        ProgramOutputSettingsView(
                            programOutput: cameraManager.programOutput
                        )
                    }
                }
            }

            if dockHasOverflow(for: tier) {
                Button(action: { showDockOverflow.toggle() }) {
                    overflowButton(title: "More", tint: .white.opacity(0.64))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDockOverflow) {
                    dockOverflowPanel(for: tier)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(10)
        .glassPanel(cornerRadius: 30)
    }

    private func startCamera() async {
        do {
            try await cameraManager.startCapture()
        } catch {
            showError = true
        }
    }

    private func toggleCamera() {
        if cameraManager.isRunning {
            cameraManager.stopCapture()
        } else {
            Task {
                await startCamera()
            }
        }
    }

    private func adaptiveTier(for width: CGFloat) -> AdaptiveTier {
        switch width {
        case 1850...:
            return .expanded
        case 1620..<1850:
            return .large
        case 1450..<1620:
            return .medium
        case 1280..<1450:
            return .compact
        default:
            return .minimal
        }
    }

    private func headerHasOverflow(for tier: AdaptiveTier) -> Bool {
        tier != .expanded
    }

    private func dockHasOverflow(for tier: AdaptiveTier) -> Bool {
        tier != .expanded && tier != .large
    }

    @ViewBuilder
    private func controlCluster<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(1.2)

            HStack(spacing: 10) {
                content()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 24, opacity: 0.22)
    }

    @ViewBuilder
    private func headerCommandPanel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(1.2)

            HStack(spacing: 10) {
                content()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassPanel(cornerRadius: 24, opacity: 0.24)
    }

    private func headerOverflowPanel(for tier: AdaptiveTier) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            overflowSection(title: "Status") {
                if tier == .minimal {
                    overflowInfoRow(
                        title: cameraManager.programOutput.activeRouteTitle,
                        detail: "Current output route"
                    )
                }
                if tier != .expanded, let selectedCamera = cameraManager.selectedCamera {
                    overflowInfoRow(
                        title: selectedCamera.name,
                        detail: selectedCamera.maxResolution
                    )
                }
            }

            overflowSection(title: "Source") {
                if tier == .compact || tier == .minimal {
                    overflowInfoRow(
                        title: cameraManager.selectedCamera?.name ?? "No Camera",
                        detail: cameraManager.selectedCamera?.maxResolution ?? "Unavailable"
                    )
                }
                if tier == .compact || tier == .minimal {
                    Button(action: { cameraManager.discoverCameras(); showHeaderOverflow = false }) {
                        Label("Refresh Sources", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                }
            }

            overflowSection(title: "Session") {
                if tier == .compact || tier == .minimal {
                    Button(action: {
                        showHeaderOverflow = false
                        toggleCamera()
                    }) {
                        Label(
                            cameraManager.isRunning ? "Stop Session" : "Start Session",
                            systemImage: cameraManager.isRunning ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(
                        GlassCapsuleButtonStyle(
                            tint: cameraManager.isRunning ? .red : .green,
                            isPrimary: true
                        )
                    )
                    .disabled(cameraManager.error != nil || cameraManager.availableCameras.isEmpty)
                }
            }

            if cameraManager.isManualTargetLockActive {
                overflowSection(title: "Target Lock") {
                    overflowInfoRow(
                        title: "Manual lock active",
                        detail: "Tap another subject or clear the lock below"
                    )

                    Button(action: {
                        cameraManager.clearManualTargetLock()
                        showHeaderOverflow = false
                    }) {
                        Label("Clear Lock", systemImage: "pin.slash")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .yellow))
                }
            }

            overflowSection(title: "Metrics") {
                if tier == .minimal {
                    overflowInfoRow(
                        title: String(format: "%.1fms", cameraManager.personDetector.stats.lastDetectionTime * 1000),
                        detail: "Detection latency"
                    )
                }
                if tier != .expanded && tier != .large {
                    overflowInfoRow(
                        title: "\(cameraManager.programOutput.framesSent)",
                        detail: "Frames routed"
                    )
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .glassPanel(cornerRadius: 26, opacity: 0.28)
    }

    private func dockOverflowPanel(for tier: AdaptiveTier) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if tier == .compact || tier == .minimal {
                overflowSection(title: "Inspect") {
                    if tier == .minimal {
                        Toggle(isOn: $showDetections) {
                            Label("Detections", systemImage: "person.crop.rectangle")
                        }
                        .toggleStyle(.switch)
                    }

                    Button(action: { showDockOverflow = false; showDetectionSettings = true }) {
                        Label("Detection Settings", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                }
            }

            overflowSection(title: "Framing") {
                if tier == .minimal {
                    Toggle(isOn: $showCropIndicator) {
                        Label("Indicator Overlay", systemImage: "viewfinder")
                    }
                    .toggleStyle(.switch)
                    .disabled(!cameraManager.cropEnabled)
                }

                if tier == .medium || tier == .compact || tier == .minimal {
                    Button(action: { showDockOverflow = false; showCropSettings = true }) {
                        Label("Crop Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .white.opacity(0.6)))
                }

                if tier == .medium || tier == .compact || tier == .minimal,
                   let cropEngine = cameraManager.cropEngine,
                   cameraManager.isRunning,
                   cameraManager.cropEnabled {
                    overflowInfoRow(
                        title: "\(Int(cropEngine.config.outputSize.width))×\(Int(cropEngine.config.outputSize.height))",
                        detail: String(format: "%.1fms render", cropEngine.stats.lastRenderTime * 1000)
                    )
                }
            }

            if cameraManager.isManualTargetLockActive {
                overflowSection(title: "Target Lock") {
                    overflowInfoRow(
                        title: "Manual lock active",
                        detail: "Tap a subject in the wide view to reassign"
                    )

                    Button(action: {
                        showDockOverflow = false
                        cameraManager.clearManualTargetLock()
                    }) {
                        Label("Clear Lock", systemImage: "pin.slash")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .yellow))
                }
            }

            if tier != .expanded && tier != .large {
                overflowSection(title: "Modules") {
                    Button(action: { showDockOverflow = false; showComposerSettings = true }) {
                        Label("Composer", systemImage: "film")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .purple))

                    Button(action: { showDockOverflow = false; showAgentSettings = true }) {
                        Label("Agent", systemImage: cameraManager.useMLAgent ? "brain.filled.head.profile" : "brain.head.profile")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: cameraManager.useMLAgent ? .blue : .white.opacity(0.6)))

                    Button(action: { showDockOverflow = false; showRecorderSettings = true }) {
                        Label("Recorder", systemImage: cameraManager.trainingDataRecorder.isRecording ? "record.circle.fill" : "record.circle")
                    }
                    .buttonStyle(
                        GlassCapsuleButtonStyle(
                            tint: cameraManager.trainingDataRecorder.isRecording ? .red : .white.opacity(0.6),
                            isPrimary: cameraManager.trainingDataRecorder.isRecording
                        )
                    )

                    Button(action: { showDockOverflow = false; showOutputSettings = true }) {
                        Label("Output", systemImage: cameraManager.programOutput.activeRoute?.systemImage ?? "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(tint: .cyan))
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .glassPanel(cornerRadius: 26, opacity: 0.28)
    }

    private func statusBadge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.38), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    )
            }
    }

    private func metricTile(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.2)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))

            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(minWidth: 118, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 24, tint: tint.opacity(0.24))
    }

    private func infoPill(title: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.24), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    private func overflowButton(title: String, tint: Color) -> some View {
        Label(title, systemImage: "ellipsis.circle")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.32), .white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    )
            }
    }

    @ViewBuilder
    private func overflowSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(1.2)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private func overflowInfoRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Camera List View

struct CameraListView: View {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Available Cameras")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    cameraManager.discoverCameras()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Camera List
            if cameraManager.availableCameras.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Cameras Found")
                        .font(.headline)
                    Text("Check Xcode Console for diagnostics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cameraManager.availableCameras) { camera in
                            CameraRowView(
                                camera: camera,
                                isSelected: cameraManager.selectedCamera?.id == camera.id,
                                action: {
                                    Task {
                                        do {
                                            try await cameraManager.restartWithCamera(camera)
                                            dismiss()
                                        } catch {
                                            print("❌ Failed to switch camera: \(error)")
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - Camera Row View

struct CameraRowView: View {
    let camera: CameraManager.CameraDevice
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        Label(camera.maxResolution, systemImage: "rectangle.resize")
                            .font(.caption)
                        
                        if camera.supports4K {
                            Label("4K", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        Text("\(camera.formatCount) formats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct LiquidGlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.22),
                    Color.cyan.opacity(0.05),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color.mint.opacity(0.18),
                    Color.mint.opacity(0.04),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 460
            )

            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct LiquidPreviewCard<Content: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let content: Content

    init(
        title: String,
        subtitle: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .padding(16)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.85), .white.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: accent.opacity(0.18), radius: 22, y: 10)
        }
    }
}

struct GlassCapsuleButtonStyle: ButtonStyle {
    var tint: Color = .white.opacity(0.6)
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(isPrimary ? Color.white : Color.white.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(isPrimary ? 0.7 : 0.34),
                                        .white.opacity(isPrimary ? 0.12 : 0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(configuration.isPressed ? 0.26 : 0.14), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(isPrimary ? 0.28 : 0.14), radius: 12, y: 6)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color = .white.opacity(0.1)
    var opacity: CGFloat = 0.18

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(opacity), .white.opacity(0.04), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
            }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat, tint: Color = .white.opacity(0.1), opacity: CGFloat = 0.18) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tint: tint, opacity: opacity))
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
