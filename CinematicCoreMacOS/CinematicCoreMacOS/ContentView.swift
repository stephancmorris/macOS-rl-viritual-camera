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
    @StateObject private var readiness: ReadinessObserver
    @StateObject private var stoppedPreview = StoppedCameraPreviewController()
    @State private var requestingPermission = false
    @State private var preparingStart = false
    @State private var readinessRefused = false
    @State private var readinessFocusRequest = 0
    @State private var readinessActionError: String?
    @State private var lastSessionDuration: TimeInterval?
    @State private var sessionRoute: ProgramOutputManager.Route?
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
        let modes = show?.operatorModes
            ?? OperatorModeStore(defaults: UserDefaults(suiteName: "com.alfie.preview") ?? .standard,
                                 multiviewEnabled: false)
        _operatorModes = ObservedObject(wrappedValue: modes)
        _readiness = StateObject(wrappedValue: ReadinessObserver(modeStore: modes,
            cameras: [show?.channelA ?? cameraManager], programOutput: (show?.channelA ?? cameraManager).programOutput,
            extensionManager: systemExtensionManager))
    }

    /// Multiview console and Show setup only in Multi Cam; Single Cam and
    /// Webcam get the single-camera view (ConsolePresentation.screen). The
    /// kill switch is applied by the store: with it off, Multi Cam is never
    /// the mode.
    private let display = AlfieDisplay()
    @Environment(\.openSettings) private var openSettings

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
        contentStack
            .modifier(LiveConsoleAppearance(isLive: screen == .multiviewConsole))
    }

    private var contentStack: some View {
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
                ScrollView {
                    VStack(spacing: 18) {
                        ReadinessChecklistView(readiness: readiness.readiness, inputs: readiness.inputs,
                            requestingPermission: requestingPermission, showsRefusal: readinessRefused,
                            focusRequest: readinessFocusRequest, actionError: readinessActionError,
                            onAction: performReadinessAction)
                            .padding(.top, 64)
                        LiveShowSetup(show: show, startChannelA: { await startCamera() })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StoppedScreen(
                    operatorModes: operatorModes,
                    cameras: OperatorModeChoice.Cameras(cameraManager.availableCameras),
                    lastSessionEndedAt: lastSessionEndedAt,
                    onStart: {
                        // A single-camera session is a new show on A alone:
                        // A is Program and no other channel is kept.
                        Task { await startCamera(prepareNewShow: true) }
                    },
                    onEditRunSheet: show?.showRunSheet.map { runSheet in { runSheet.isPresented = true } },
                    readiness: readiness, lastSessionDuration: lastSessionDuration, lastSessionRoute: sessionRoute,
                    requestingPermission: requestingPermission, showsRefusal: readinessRefused,
                    focusRequest: readinessFocusRequest, actionError: readinessActionError,
                    isStarting: cameraManager.isStartingSession || preparingStart, onReadinessAction: performReadinessAction,
                    preview: stoppedPreview,
                    canPreview: cameraManager.preferredInputSource == .liveCamera,
                    onPreview: toggleStoppedPreview
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
                // Reduce Motion: a cross-fade instead of the slide.
                .transition(display.reduceMotion ? .opacity : .move(edge: .trailing))
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
                sessionRoute = cameraManager.programOutput.activeRoute ?? readiness.inputs.effectiveRoute
                elapsedSeconds = 0
            } else {
                let ended = Date()
                lastSessionEndedAt = ended
                lastSessionDuration = sessionStartedAt.map { ended.timeIntervalSince($0) }
                sessionStartedAt = nil
                readiness.refresh()
                readinessFocusRequest += 1
                OperatorAnnouncement.say(StoppedSessionCopy.line(endedAt: ended, duration: lastSessionDuration,
                    route: sessionRoute ?? readiness.inputs.effectiveRoute))
                elapsedSeconds = 0
            }
        }
        .onChange(of: operatorModes.mode) { _, _ in Task { await stoppedPreview.stop() } }
        .onChange(of: cameraManager.selectedCamera?.uniqueID) { _, _ in Task { await stoppedPreview.stop() } }
        .onDisappear { Task { await stoppedPreview.stop() } }
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

    private func startCamera(prepareNewShow: Bool = false) async {
        // Refresh before any session mutation. Permission and installation are
        // explicit checklist actions; Start never invokes either recovery.
        guard !preparingStart else { return }
        guard Self.canStart(readiness: readiness, requestingPermission: requestingPermission) else {
            readinessRefused = true
            readinessFocusRequest += 1
            return
        }
        guard !cameraManager.isStartingSession, !cameraManager.isRunning else { return }
        preparingStart = true
        defer { preparingStart = false }
        let command = OperatorCommand(target: .session, epoch: cameraManager.commands.epoch,
            expiry: ProcessInfo.processInfo.systemUptime + 120, action: .startSession)
        let modeAtRequest = operatorModes.mode
        await stoppedPreview.stop()
        // Stopping a preview suspends. Recheck prerequisites and intent before
        // dispatch; never resume a Start into a different selected mode.
        readiness.refresh()
        guard operatorModes.mode == modeAtRequest, readiness.readiness.canStart else {
            readinessRefused = true
            readinessFocusRequest += 1
            return
        }
        readinessRefused = false
        if prepareNewShow { show?.prepareForNewShow() }
        OperatorAnnouncement.say("Starting session.")
        cameraManager.dispatch(command)
    }

    private func toggleStoppedPreview() {
        if stoppedPreview.isPreviewing {
            Task {
                await stoppedPreview.stop()
                OperatorAnnouncement.say("Camera previews are off.")
            }
            return
        }
        readiness.refresh()
        if readiness.readiness.rows.first(where: { $0.id == .cameraAccess })?.blocksStart == true {
            readinessRefused = true
            readinessFocusRequest += 1
            return
        }
        Task { await stoppedPreview.start(deviceID: cameraManager.selectedCamera?.uniqueID) }
    }

    private func performReadinessAction(_ action: ReadinessModel.Action) {
        readinessActionError = nil
        switch action {
        case .requestCameraAccess:
            guard !requestingPermission else { return }
            requestingPermission = true
            Task { @MainActor in
                _ = await AVCaptureDevice.requestAccess(for: .video)
                requestingPermission = false
                readiness.refresh()
                readinessFocusRequest += 1
            }
        case .openCameraPrivacySettings:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
            if !NSWorkspace.shared.open(url) {
                readinessActionError = "System Settings could not be opened. Open System Settings, then Privacy & Security, then Camera."
            }
        case .installVirtualCamera:
            Task { @MainActor in
                await systemExtensionManager.triggerPrimaryAction()
                readiness.refresh()
            }
        case .openExtensionSettings:
            if !systemExtensionManager.openSystemSettings() {
                readinessActionError = "System Settings could not be opened. Open System Settings, then Login Items & Extensions, and approve Alfie camera."
            }
        case .chooseOutput:
            settingsWindowController.open(.output)
            openSettings()
        }
        if let readinessActionError { OperatorAnnouncement.say(readinessActionError) }
    }

    /// Used by every stopped Start path; refresh before reading canStart.
    static func canStart(readiness: ReadinessObserver, requestingPermission: Bool = false) -> Bool {
        readiness.refresh()
        return readiness.readiness.canStart && !requestingPermission
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
                        .font(.subheadline)
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
                    .foregroundStyle(isSelected ? AlfieColor.accentText : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        Label(camera.maxResolution, systemImage: "rectangle.resize")
                            .font(.subheadline)
                        
                        if camera.supports4K {
                            Label("4K", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(AlfieColor.live)
                        }
                        
                        Text("\(camera.formatCount) formats")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AlfieColor.accentText)
                }
            }
            .padding(12)
        }
        .alfieButtonStyle(.quiet)
        .background(isSelected ? AlfieColor.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The standby backdrop: a flat Mist (or Navy night) gradient from the
/// background to the sidebar tone. No tinted glows, so the brand palette
/// reads as one surface.
struct LiquidGlassBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: AlfieColor.backdropStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// D2 (5 Nov 2026): while the Multiview console is live it is dark whatever
/// the system appearance, so a live room never flips to a bright surface.
/// Everywhere else the operator's appearance applies.
struct LiveConsoleAppearance: ViewModifier {
    let isLive: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, isLive ? .dark : colorScheme)
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
