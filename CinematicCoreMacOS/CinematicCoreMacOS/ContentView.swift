//
//  ContentView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import AVFoundation
import Combine
import OSLog
import SwiftUI

struct ContentView: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var systemExtensionManager: SystemExtensionActivationManager
    @ObservedObject var settingsWindowController: SettingsWindowController
    /// The show; drives the Multiview console in Multi Cam.
    let show: ShowCoordinator?
    /// The operator mode, observed so a change swaps the console.
    @ObservedObject private var operatorModes: OperatorModeStore

    @State private var showError = false
    @State private var inspectorOpen = false
    @State private var showSystemExtensionStatus = false
    @State private var elapsedSeconds: Int = 0
    @State private var sessionStartedAt: Date?
    @State private var lastSessionEndedAt: Date?

    private let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        cameraManager: CameraManager,
        systemExtensionManager: SystemExtensionActivationManager,
        settingsWindowController: SettingsWindowController,
        show: ShowCoordinator? = nil
    ) {
        // A real show's channel is authoritative. Keep the standalone camera
        // argument for previews, never as a second source of app ownership.
        self.cameraManager = show?.channelA ?? cameraManager
        self.systemExtensionManager = systemExtensionManager
        self.settingsWindowController = settingsWindowController
        self.show = show
        // Without a show (previews) there is no Multi Cam: a throwaway store
        // that never touches the saved mode.
        _operatorModes = ObservedObject(wrappedValue: show?.operatorModes
            ?? OperatorModeStore(defaults: UserDefaults(suiteName: "com.alfie.preview") ?? .standard,
                                 multiviewEnabled: false))
    }

    /// Multiview console and Show setup only in Multi Cam; Single Cam and
    /// Webcam get the single-camera view (ConsolePresentation.screen). The
    /// kill switch is applied by the store: with it off, Multi Cam is never
    /// the mode.
    private var screen: ConsolePresentation.Screen {
        ConsolePresentation.screen(for: operatorModes.mode, channelA: cameraManager, show: show)
    }

    var body: some View {
        // The optional show needs its own observed boundary: watching A alone
        // misses B starting or remaining live after A stops. The show forwards
        // lifecycle changes only, so this adds no per-frame subscription.
        if let show {
            ShowLifecycleContent(show: show) { content }
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            // Layer 0: backdrop
            LiquidGlassBackdrop()

            // Layer 1: dual feed (or stopped screen) fills the window
            if screen == .multiviewConsole, let show {
                LiveMultiviewConsole(show: show)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .singleCameraLive {
                CropPreviewView(
                    originalFrame: cameraManager.currentFrameBuffer,
                    croppedFrame: cameraManager.croppedFrameBuffer,
                    detectedPersons: cameraManager.personDetector.displayedPersons,
                    showDetections: true,
                    cropRect: cameraManager.activeMode != .wide ? cameraManager.cropEngine?.displayedCrop : nil,
                    activeTargetID: cameraManager.shotComposer.activeTargetID,
                    manualLockedTargetID: cameraManager.manualLockedTargetID,
                    acquiringTargetID: cameraManager.shotComposer.acquiringTargetID,
                    trackedSubjectRect: cameraManager.shotComposer.displayedTrackedBounds,
                    isRecovering: cameraManager.recoveryState.isRecovering,
                    isZoomLimited: cameraManager.isZoomLimited,
                    steadyBand: cameraManager.shotComposer.steadyBand,
                    framingTitle: cameraManager.framingTitle,
                    onSelectPerson: nil,
                    onTapPoint: tapPointHandler,
                    onHoldPoint: holdPointHandler
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Live video and what floats on it stay dark in every
                // appearance so footage and its labels read true.
                .environment(\.colorScheme, .dark)
            } else if screen == .showSetup, let show {
                // Show setup (SHOW-SETUP) replaces the stopped screen in
                // Multi Cam. Channel A starts through startCamera() so
                // extension preflight is unchanged.
                LiveShowSetup(show: show, startChannelA: { await startCamera() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StoppedScreen(
                    operatorModes: operatorModes,
                    cameras: OperatorModeChoice.Cameras(cameraManager.availableCameras),
                    lastSessionEndedAt: lastSessionEndedAt,
                    onStart: {
                        // A single-camera session is a new show on A alone:
                        // A is Program and no other channel is kept.
                        show?.prepareForNewShow()
                        Task { await startCamera() }
                    },
                    onEditRunSheet: show?.showRunSheet.map { runSheet in { runSheet.isPresented = true } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Hot-plug: re-enumerate so a second camera unlocks Multi Cam
                // in the mode picker (discovery only; no session opens).
                .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)
                    .merge(with: NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification))
                    .receive(on: RunLoop.main)) { _ in
                    cameraManager.discoverCameras()
                }
            }

            // Layer 2: floating overlays — only in the single-camera view (the
            // Multiview console carries its own pill and status)
            if screen == .singleCameraLive {
                Group {
                    IdentityStackOverlay(
                        cameraManager: cameraManager,
                        elapsedSeconds: elapsedSeconds
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 24)
                    .padding(.top, 24)
                    .allowsHitTesting(false)

                    TelemetryOverlay(cameraManager: cameraManager, programOutput: cameraManager.programOutput)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 28)
                        .padding(.trailing, 72)
                        .allowsHitTesting(false)

                    ProgramOnAirBadgeAnchor()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)

                    OperatorPill(cameraManager: cameraManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 26)
                }
                .environment(\.colorScheme, .dark)
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
                    settingsWindowController: settingsWindowController,
                    isOpen: $inspectorOpen,
                    show: show
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.36), value: inspectorOpen)
        .frame(minWidth: 1280, minHeight: 800)
        .modifier(ShowRunSheetPresenter(show: show))
        .background(ConsoleStyle.background)
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
        .onChange(of: cameraManager.error != nil) { _, hasError in
            if hasError { showError = true }
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
        .alert(systemExtensionManager.summaryText, isPresented: $showSystemExtensionStatus) {
            if let action = systemExtensionManager.primaryActionTitle {
                Button(action) { Task { await systemExtensionManager.triggerPrimaryAction() } }
            }
            Button("OK", role: .cancel) { showSystemExtensionStatus = false }
        } message: {
            Text(systemExtensionManager.detailText)
        }
    }

    /// Preview tap handler. While discovering a subject (operator tapped
    /// Detect), a tap picks the subject to acquire. From HOLD or WIDE-WAITING
    /// (the "lost the green box" states) a tap directly re-acquires whoever is
    /// under it — no Detect press needed. In manual-crop mode it repositions
    /// the crop. Otherwise taps are ignored.
    private var tapPointHandler: ((CGPoint) -> Void)? {
        if cameraManager.activeMode == .autoPan { return nil }
        if cameraManager.detectionDiscoveryActive {
            return { point in cameraManager.dispatch(cameraManager.makeCommand(.selectSubject(point))) }
        }
        if cameraManager.activeMode == .manualCrop {
            return { point in cameraManager.dispatch(cameraManager.makeCommand(.moveManualCenter(point))) }
        }
        if cameraManager.recoveryState.allowsDirectSelection {
            return { point in cameraManager.dispatch(cameraManager.makeCommand(.selectSubject(point))) }
        }
        return nil
    }

    /// Press-and-hold handler. Only live while a subject is already locked —
    /// holding on someone else switches the shot to them without going back
    /// through the Detect button. Suppressed in manual-crop mode, where the
    /// pointer is already driving the crop.
    private var holdPointHandler: ((CGPoint) -> Void)? {
        guard cameraManager.activeMode != .manualCrop && cameraManager.activeMode != .autoPan else { return nil }
        guard cameraManager.manualLockedTargetID != nil else { return nil }
        return { point in cameraManager.dispatch(cameraManager.makeCommand(.selectSubject(point, retarget: true))) }
    }

    private func startCamera() async {
        // Capture intent before any installation UI suspends. A later Stop
        // must retire this Start rather than letting it restart the session.
        let command = OperatorCommand(target: .session, epoch: cameraManager.commands.epoch,
                                      expiry: ProcessInfo.processInfo.systemUptime + 120,
                                      action: .startSession)
        // Only the route that needs the virtual camera should invoke its
        // installer. Direct output and the explicit rehearsal destination can
        // start without an installed extension, including Xcode-run builds.
        let directOutputAvailable = ProgramDisplaySelection.resolvedTargetDisplayID()
            .flatMap(ProgramDisplaySelection.screen(for:)) != nil
        let needsVirtualCamera = Self.startNeedsVirtualCamera(
            preferredRoute: cameraManager.programOutput.preferredRoute,
            directOutputAvailable: directOutputAvailable)
        if cameraManager.shouldPreflightVirtualCameraInstallation, needsVirtualCamera,
           !systemExtensionManager.isInstallReady {
            let extensionReady = await systemExtensionManager.ensureInstalledForSessionStart()
            if !extensionReady {
                showSystemExtensionStatus = true
                // Without the virtual camera, Program would have nowhere to go
                // unless Direct output is the chosen, connected destination
                // (CR-036).
                // Installation UI suspended this request; use the route and
                // connected displays that are current after it returns.
                let directOutputAvailable = ProgramDisplaySelection.resolvedTargetDisplayID()
                    .flatMap(ProgramDisplaySelection.screen(for:)) != nil
                if Self.startNeedsVirtualCamera(preferredRoute: cameraManager.programOutput.preferredRoute,
                                                directOutputAvailable: directOutputAvailable) {
                    return
                }
            }
        }

        cameraManager.dispatch(command)
    }

    /// Whether Start must wait for the virtual camera. Direct output on a
    /// connected port, or the development rehearsal route, carries Program
    /// without it. Anything else resolves to the virtual camera (it is also
    /// the fallback when the chosen port is missing).
    static func startNeedsVirtualCamera(preferredRoute: ProgramOutputManager.Route,
                                        directOutputAvailable: Bool) -> Bool {
        switch preferredRoute {
        case .display: return !directOutputAvailable
        case .rehearsal: return false
        case .virtualCamera: return true
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.06, green: 0.08, blue: 0.13),
                       Color(red: 0.03, green: 0.05, blue: 0.09),
                       Color.black]
                    : [Color(red: 0.97, green: 0.97, blue: 0.98),
                       Color(red: 0.95, green: 0.95, blue: 0.97),
                       Color(red: 0.92, green: 0.93, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(isDark ? 0.22 : 0.12),
                    Color.cyan.opacity(isDark ? 0.05 : 0.03),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color.mint.opacity(isDark ? 0.18 : 0.10),
                    Color.mint.opacity(isDark ? 0.04 : 0.02),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 460
            )

            LinearGradient(
                colors: [AlfieColor.ink.opacity(0.05), .clear, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color = AlfieColor.ink.opacity(0.1)
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
                                    colors: [tint.opacity(opacity), AlfieColor.ink.opacity(0.04), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AlfieColor.ink.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
            }
    }
}

#Preview {
    ContentView(
        cameraManager: CameraManager(),
        systemExtensionManager: SystemExtensionActivationManager(),
        settingsWindowController: SettingsWindowController()
    )
    .frame(width: 1200, height: 800)
}

/// Observes the show only when a real show exists. The wrapped content still
/// reads authoritative state; this boundary stores no copy of channel liveness.
struct ShowLifecycleContent<Content: View>: View {
    @ObservedObject var show: ShowCoordinator
    @ViewBuilder var content: () -> Content

    var body: some View { content() }
}
