//
//  ContentView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import Combine
import OSLog
import SwiftUI

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.alfie", category: "ContentView")

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var systemExtensionManager: SystemExtensionActivationManager

    @State private var showError = false
    @State private var inspectorOpen = false
    @State private var showSystemExtensionStatus = false
    @State private var elapsedSeconds: Int = 0
    @State private var sessionStartedAt: Date?
    @State private var lastSessionEndedAt: Date?

    private let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(cameraManager: CameraManager, systemExtensionManager: SystemExtensionActivationManager) {
        self.cameraManager = cameraManager
        self.systemExtensionManager = systemExtensionManager
    }

    var body: some View {
        ZStack {
            // Layer 0: backdrop
            LiquidGlassBackdrop()

            // Layer 1: dual feed (or stopped screen) fills the window
            if cameraManager.isRunning {
                CropPreviewView(
                    originalFrame: cameraManager.currentFrame,
                    croppedFrame: cameraManager.croppedFrame,
                    detectedPersons: cameraManager.personDetector.detectedPersons,
                    showDetections: true,
                    cropRect: cameraManager.cropEnabled ? cameraManager.cropEngine?.currentCrop : nil,
                    activeTargetID: cameraManager.shotComposer.activeTargetID,
                    manualLockedTargetID: cameraManager.manualLockedTargetID,
                    trackedSubjectRect: cameraManager.shotComposer.lastTrackedBounds,
                    isRecovering: cameraManager.trackingPaused,
                    framingTitle: cameraManager.shotComposer.config.shotPreset.title,
                    onSelectPerson: cameraManager.lockTarget
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StoppedScreen(
                    lastSessionEndedAt: lastSessionEndedAt,
                    onStart: { Task { await startCamera() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Layer 2: floating overlays — only while running
            if cameraManager.isRunning {
                IdentityStackOverlay(
                    cameraManager: cameraManager,
                    elapsedSeconds: elapsedSeconds
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 24)
                .padding(.top, 24)
                .allowsHitTesting(false)

                TelemetryOverlay(cameraManager: cameraManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 28)
                    .padding(.trailing, 72)
                    .allowsHitTesting(false)

                ProgramOnAirBadgeAnchor()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                OperatorPill(
                    cameraManager: cameraManager,
                    onStop: { toggleCamera() },
                    onStart: { Task { await startCamera() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26)
            }

            // Layer 3: inspector handle — always visible
            InspectorHandle(isOpen: $inspectorOpen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16)
                .padding(.trailing, 16)

            // Layer 4: inspector drawer — slides over the right edge
            if inspectorOpen {
                InspectorDrawer(
                    cameraManager: cameraManager,
                    systemExtensionManager: systemExtensionManager,
                    isOpen: $inspectorOpen
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.36), value: inspectorOpen)
        .frame(minWidth: 1280, minHeight: 800)
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            if cameraManager.availableCameras.isEmpty {
                cameraManager.discoverCameras()
            }
        }
        .onChange(of: cameraManager.isRunning) { _, isRunning in
            if isRunning {
                sessionStartedAt = Date()
                elapsedSeconds = 0
            } else {
                lastSessionEndedAt = Date()
                sessionStartedAt = nil
                elapsedSeconds = 0
            }
        }
        .onReceive(elapsedTimer) { _ in
            guard let start = sessionStartedAt else { return }
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }
        .alert("Camera Error", isPresented: $showError, presenting: cameraManager.error) { _ in
            Button("OK") { showError = false }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func startCamera() async {
        if cameraManager.shouldPreflightVirtualCameraInstallation, !systemExtensionManager.isInstallReady {
            let extensionReady = await systemExtensionManager.ensureInstalledForSessionStart()
            if !extensionReady {
                showSystemExtensionStatus = true
            }
        }

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
            Task { await startCamera() }
        }
    }
}


// MARK: - Camera List View

struct CameraListView: View {
    private static let logger = Logger(subsystem: "com.alfie", category: "CameraListView")

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
                        ForEach(
                            Array(cameraManager.availableCameras),
                            id: \CameraManager.CameraDevice.id
                        ) { camera in
                            CameraRowView(
                                camera: camera,
                                isSelected: cameraManager.selectedCamera?.id == camera.id,
                                action: {
                                    Task {
                                        do {
                                            try await cameraManager.restartWithCamera(camera)
                                            dismiss()
                                        } catch {
                                            Self.logger.error("Failed to switch camera: \(error.localizedDescription, privacy: .public)")
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
    ContentView(
        cameraManager: CameraManager(),
        systemExtensionManager: SystemExtensionActivationManager()
    )
        .frame(width: 1200, height: 800)
}
