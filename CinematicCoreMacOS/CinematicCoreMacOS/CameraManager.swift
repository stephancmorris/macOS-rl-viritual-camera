//
//  CameraManager.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import AVFoundation
import CoreVideo
import CoreImage
import Combine
import IOSurface
import OSLog
import os

private final class SendablePixelBufferBox: @unchecked Sendable {
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer

    nonisolated init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

private nonisolated final class CaptureFrameProcessingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isProcessing = false
    private var droppedFrames: UInt64 = 0

    // Windowed throughput diagnostics. The delivered rate here is the ceiling on
    // what reaches the program output: if it sags below the show standard the
    // picture goes choppy. Logged once per second under the existing lock so it
    // stays thread-safe and cheap.
    private static let logger = Logger(subsystem: "com.alfie", category: "CaptureThroughput")
    private var windowStart: CFTimeInterval = CACurrentMediaTime()
    private var windowDelivered: UInt64 = 0
    private var windowDropped: UInt64 = 0

    init() {}

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isProcessing else {
            droppedFrames &+= 1
            windowDropped &+= 1
            logThroughputIfDueLocked()
            return false
        }
        isProcessing = true
        windowDelivered &+= 1
        logThroughputIfDueLocked()
        return true
    }

    /// Caller must hold `lock`. Emits a delivered/dropped FPS summary once the
    /// current 1-second window closes, then opens a new window.
    private func logThroughputIfDueLocked() {
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 1.0 else { return }
        let deliveredFPS = Double(windowDelivered) / elapsed
        let droppedFPS = Double(windowDropped) / elapsed
        let total = windowDelivered + windowDropped
        let dropPercent = total > 0 ? Double(windowDropped) / Double(total) * 100.0 : 0
        Self.logger.notice(
            "Capture throughput: \(deliveredFPS, format: .fixed(precision: 1)) fps delivered to pipeline (target 50), dropped \(droppedFPS, format: .fixed(precision: 1)) fps (\(dropPercent, format: .fixed(precision: 1))% of frames)"
        )
        windowStart = now
        windowDelivered = 0
        windowDropped = 0
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        isProcessing = false
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        isProcessing = false
        droppedFrames = 0
        windowStart = CACurrentMediaTime()
        windowDelivered = 0
        windowDropped = 0
    }

    var droppedFrameCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return droppedFrames
    }
}

enum CameraError: LocalizedError {
    case noCameraAvailable
    case sessionConfigurationFailed
    case unsupportedFormat
    case authorizationDenied
    case noValidationClipSelected
    case invalidValidationClip
    case validationClipPlaybackFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera device found"
        case .sessionConfigurationFailed:
            return "Failed to configure capture session"
        case .unsupportedFormat:
            return "Camera does not support 4K capture"
        case .authorizationDenied:
            return "Camera access denied"
        case .noValidationClipSelected:
            return "Choose a validation clip before starting clip playback"
        case .invalidValidationClip:
            return "The selected validation clip does not contain a readable video track"
        case .validationClipPlaybackFailed(let message):
            return "Validation clip playback failed: \(message)"
        }
    }
}

/// Manages the AVCaptureSession pipeline for 4K video capture
/// Ticket: APP-01 - AVCaptureSession Pipeline
@MainActor
final class CameraManager: NSObject, ObservableObject {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Camera")
    private nonisolated static let signposter = OSSignposter(logger: logger)
    private nonisolated static let firstFrameLogged = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// One-shot log of the delivered pixel buffer dimensions. The activeFormat
    /// is set to 4K, but BMD's CMIO driver has been known to ignore that and
    /// serve 1080p — if this prints anything below 3840x2160 we're cropping a
    /// 1080p source, which would dwarf every other quality fix.
    private nonisolated static func logFirstFrameResolution(_ pixelBuffer: CVPixelBuffer) {
        let shouldLog = firstFrameLogged.withLock { logged -> Bool in
            guard !logged else { return false }
            logged = true
            return true
        }
        guard shouldLog else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        logger.notice("First frame delivered: \(width)x\(height), pixelFormat=\(format, format: .hex, privacy: .public)")
    }
    
    // MARK: - Published Properties
    
    /// Raw camera frame for the wide (left) operator pane, published as its
    /// backing `CVPixelBuffer` so the display path can be a zero-copy IOSurface
    /// layer assignment (see `PixelBufferPreviewView`). Retaining this property
    /// retains the buffer's IOSurface, which the capture side owns for its
    /// lifetime; that is what keeps it on screen safely.
    @Published private(set) var currentFrameBuffer: CVPixelBuffer?
    
    /// Capture session status
    @Published private(set) var isRunning: Bool = false
    
    /// Error state
    @Published private(set) var error: CameraError?
    
    /// Available camera devices  
    @Published private(set) var availableCameras: [CameraDevice] = []
    
    /// Currently selected camera
    @Published var selectedCamera: CameraDevice?

    /// Preferred frame source for the next session start.
    @Published var preferredInputSource: InputSource = .liveCamera

    /// Source currently driving the pipeline.
    @Published private(set) var activeInputSource: InputSource = .liveCamera

    /// Local validation clip selected for Gate 5 playback.
    @Published private(set) var validationClipURL: URL?

    /// When true, the validation clip repeats until the session is stopped.
    @Published var loopValidationClip: Bool = true

    /// Operator-facing summary of the current playback harness state.
    @Published private(set) var validationClipStatus: String = "Select a validation clip to route file playback through Alfie's camera pipeline."
    
    /// Person detector (Task 2.1)
    let personDetector = PersonDetector()
    
    /// Crop engine (Task 2.2 - GFX-01)
    let cropEngine: CropEngine?

    /// Shot composer (Task 2.3 - LOGIC-01)
    let shotComposer = ShotComposer()

    /// RL-trained CoreML agent (Task APP-02)
    let cinematicAgent = CinematicAgent()

    /// When true, the cinematic agent drives the crop instead of ShotComposer.
    @Published var useMLAgent: Bool = false {
        didSet {
            if useMLAgent {
                cinematicAgent.ensureModelLoaded()
            }

            if useMLAgent, cinematicAgent.isModelLoaded, let crop = cropEngine?.currentCrop {
                cinematicAgent.initialize(from: crop)
            }
        }
    }

    /// Training data recorder (Task 3.1 - RL-01)
    let trainingDataRecorder = TrainingDataRecorder()

    /// Routes the processed program feed to the currently active output sink.
    /// Program Display is a fullscreen clean feed on a selected display (e.g.
    /// for an HDMI→SDI converter into an ATEM).
    let programOutput = ProgramOutputManager(
        sinks: [VirtualCameraOutputSink(), DisplayOutputSink()]
    )

    /// Processed program frame for the program (right) operator pane, published
    /// as the crop pool's output `CVPixelBuffer`. Same zero-copy IOSurface
    /// display path as `currentFrameBuffer`. Retaining this property retains the
    /// pool surface so the CropEngine's `CVPixelBufferPool` will not re-vend it
    /// while it is still on screen (this codebase has been bitten by exactly
    /// that surface-recycling bug before).
    @Published private(set) var croppedFrameBuffer: CVPixelBuffer?



    /// Operation modes for crop control
    enum OperationMode {
        case wide
        case autoTracking
        case manualCrop
        case autoPan
    }

    /// Current operation mode for the crop engine
    @Published var activeMode: OperationMode = .wide

    /// Vertical pixel height of the most recent delivered source frame. Drives
    /// the operator-facing output-resolution readout. 0 until the first frame.
    @Published private(set) var sourcePixelHeight: Int = 0

    /// The center point for the manual crop (normalized 0-1)
    @Published var manualCropPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // MARK: - Passive subject discovery
    //
    // Detection is off by default. The operator taps "Detect" to enter the
    // tap-a-subject state; tapping a point seeds a one-shot ROI scan that finds
    // and acquires that single person. No full-frame multi-person scan ever runs.

    /// True after the operator taps Detect and before a subject is selected.
    /// Drives the `.awaitingTap` detection mode and the preview tap affordance.
    @Published var detectionDiscoveryActive: Bool = false

    /// A tapped point (normalized Vision coords) awaiting its one-shot ROI scan
    /// on the next frame. Cleared once consumed.
    private var pendingTapPoint: CGPoint?

    /// True from the instant the operator taps until that tap has been resolved
    /// (a subject bound, or the scan found no one). Drives an immediate "tap
    /// pending" acknowledgment in the UI so the operator knows the tap landed
    /// even before acquisition begins.
    @Published private(set) var tapPending: Bool = false

    /// Wall-clock deadline after which an unfulfilled discovery auto-cancels
    /// back to `.off` so we don't sit in `.awaitingTap` forever.
    private var discoveryTimeoutAt: TimeInterval = 0
    private static let discoveryTimeout: TimeInterval = 12.0

    /// Padding multiplier applied to the locked subject's last box to form the
    /// tracking ROI, so a moving subject stays inside the scanned region.
    private static let lockedROIPadding: CGFloat = 1.8

    /// Last detected bounding box of the acquiring/locked subject. Updated
    /// every frame from detections and used to seed the next frame's ROI. This
    /// works even during `.acquiring` (before `currentTrackedBounds` is set by
    /// the composer) so ROI scanning stays tight throughout acquisition.
    private var lastSubjectROIBox: CGRect?

    // State for Auto Pan
    private var autoPanPhase: CGFloat = 0.5
    private var autoPanDirection: CGFloat = 1.0
    private var autoPanPauseUntil: Double = 0
    private var autoPanLastTick: Double = 0

    private static let autoPanPauseDuration: Double = 1.5

    // Briefly boost crop smoothing after an operator-driven shot-preset change so
    // the camera reaches the new framing quickly (instead of crawling there with
    // the default subject-tracking smoothing).
    private var fastFramingUntil: Double = 0
    private static let fastFramingDuration: Double = 0.5
    private static let fastFramingSmoothing: Float = 0.25

    /// Call after changing `shotComposer.config.shotPreset` so the crop animates
    /// faster to the newly-chosen framing for the next ~0.5s.
    func boostFramingTransition() {
        fastFramingUntil = CACurrentMediaTime() + Self.fastFramingDuration
    }


    
    // MARK: - Camera Device Model
    
    struct CameraDevice: Identifiable, Hashable {
        let id: String
        let name: String
        let modelID: String
        let uniqueID: String
        let maxResolution: String
        let supports4K: Bool
        let formatCount: Int
        
        var displayName: String {
            "\(name) - \(maxResolution)"
        }
    }

    enum InputSource: String, CaseIterable, Identifiable {
        case liveCamera
        case validationClip

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveCamera:
                return "Live Camera"
            case .validationClip:
                return "Validation Clip"
            }
        }

        var systemImage: String {
            switch self {
            case .liveCamera:
                return "camera"
            case .validationClip:
                return "film.stack"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(
        label: "com.cinematiccore.videoOutput",
        qos: .userInteractive
    )
    private var cancellables = Set<AnyCancellable>()
    private var clipPlaybackTask: Task<Void, Never>?
    private nonisolated let frameProcessingGate = CaptureFrameProcessingGate()

    /// Last source pixel aspect (width/height) forwarded to the shot composer.
    /// Used to skip the per-frame update when aspect is unchanged.
    private var lastAppliedSourceAspect: CGFloat = 0

    /// Last delivered source pixel height used to set the crop quality floor.
    /// Skips the per-frame floor update when the resolution is unchanged.
    private var lastFloorSourceHeight: Int = 0

    private nonisolated func frameLog(_ message: @autoclosure () -> String) {
        guard DeveloperFlags.verboseFrameLogging else { return }
        let resolvedMessage = message()
        Self.logger.debug("\(resolvedMessage, privacy: .public)")
    }

    private nonisolated func latencyLog(_ message: @autoclosure () -> String) {
        guard DeveloperFlags.latencyConsoleLogging else { return }
        let resolved = message()
        Self.logger.notice("[LATENCY] \(resolved, privacy: .public)")
    }

    // MARK: - Configuration Constants
    
    private enum Config {
        static let targetWidth: Int32 = 3840
        static let targetHeight: Int32 = 2160
        // Capture format preference and the playout clock must come from the same
        // selection, so this reads the persisted show standard rather than a
        // constant. Defaults to 1080p50 (50.0) when nothing is persisted.
        static var targetFrameRate: Double { ShowStandard.current.frameRate }
        static let pixelFormat = kCVPixelFormatType_32BGRA
    }
    
    // MARK: - Initialization
    
    override init() {
        // Initialize crop engine (Task 2.2 - GFX-01)
        self.cropEngine = CropEngine()
        
        super.init()
        
        if cropEngine == nil {
            Self.logger.warning("CropEngine failed to initialize - Metal may not be available")
        } else {
            Self.logger.notice("CropEngine initialized successfully")
        }

        // Restore the persisted cinematic format (Stage/Webcam) before wiring
        // bindings so the initial state matches the operator's last choice.
        if let raw = UserDefaults.standard.string(forKey: "cinematicFormat"),
           let fmt = ShotComposer.Config.CinematicFormat(rawValue: raw) {
            shotComposer.config.cinematicFormat = fmt
        }

        configureFramingBindings()
        applyFrameProfile(shotComposer.config.frameProfile)

        // Discover cameras on initialization
        discoverCameras()
    }
    
    // MARK: - Public Methods
    
    /// Discover and list all available cameras
    func discoverCameras() {
        Self.logger.notice("Discovering cameras")
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        // TEMP Testing: Filter out Cameras for debugging
        let allDevices = discoverySession.devices
        let devices = allDevices.filter { device in
            !device.localizedName.lowercased().contains("Test")
        }
//        
//        print("   Found \(devices.count) camera(s) (excluding MacBook Pro for testing)")
//        if devices.count != allDevices.count {
//            print("   ⚠️ Filtered out: \(allDevices.count - devices.count) camera(s)")
//        }
        
        if devices.isEmpty {
            availableCameras = []
            return
        }
        
        var cameraDevices: [CameraDevice] = []
        
        for device in devices {
            // Get resolutions
            let resolutions = device.formats.map { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return (width: dims.width, height: dims.height)
            }
            
            // Check 4K support
            let supports4K = device.formats.contains { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width == Config.targetWidth && dims.height == Config.targetHeight
            }
            
            // Get max resolution
            let maxRes = resolutions.max { res1, res2 in
                res1.width * res1.height < res2.width * res2.height
            }
            let maxResString = maxRes.map { "\($0.width)x\($0.height)" } ?? "Unknown"
            
            Self.logger.debug("Camera discovered: \(device.localizedName, privacy: .public) \(maxResString, privacy: .public)\(supports4K ? " (4K)" : "")")
            
            let cameraDevice = CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                modelID: device.modelID,
                uniqueID: device.uniqueID,
                maxResolution: maxResString,
                supports4K: supports4K,
                formatCount: device.formats.count
            )
            cameraDevices.append(cameraDevice)
        }
        
        availableCameras = cameraDevices
        
        // Auto-select first 4K camera, or first available
        if selectedCamera == nil {
            selectedCamera = cameraDevices.first { $0.supports4K } ?? cameraDevices.first
            if let selected = selectedCamera {
                Self.logger.notice("Selected camera: \(selected.name, privacy: .public)")
            }
        }
    }
    
    /// Request camera permissions and start the capture session
    func startCapture() async throws {
        let sourceTitle = preferredInputSource.title
        Self.logger.notice("Starting capture from \(sourceTitle, privacy: .public)")
        frameProcessingGate.reset()
        programOutput.start()

        if preferredInputSource == .validationClip {
            do {
                try await startValidationClipPlayback()
            } catch {
                programOutput.stop()
                throw error
            }
            return
        }
        
        // Check authorization
        let authorized = await checkAuthorization()
        guard authorized else {
            Self.logger.error("Camera authorization denied")
            error = .authorizationDenied
            programOutput.stop()
            throw CameraError.authorizationDenied
        }
        Self.logger.notice("Camera authorized")
        
        // Refresh camera list if no camera selected
        if selectedCamera == nil {
            Self.logger.debug("No selected camera; rediscovering cameras")
            discoverCameras()
        }
        
        // Configure session
        Self.logger.notice("Configuring capture session")
        do {
            try await configureSession()
        } catch {
            programOutput.stop()
            throw error
        }
        Self.logger.notice("Capture session configured")
        
        // Start running
        await MainActor.run {
            captureSession.startRunning()
            // macOS has no .inputPriority preset, and the session's default
            // .high preset re-configures the device's activeFormat (4K →
            // 1080p) DURING startRunning(), silently discarding the format
            // configureCameraDevice() chose — verified empirically with the
            // Elgato 4K X. Re-asserting the format after start is the
            // supported macOS pattern; the session honors it while running.
            reassertConfiguredFormatIfNeeded()
            isRunning = captureSession.isRunning
            activeInputSource = .liveCamera
            if isRunning {
                Self.logger.notice("Capture started successfully")
                programOutput.updateCaptureStatus(isRunning: true)
            } else {
                Self.logger.warning("Session not running after startRunning()")
                programOutput.stop()
            }
        }
    }
    
    /// Stop the capture session
    func stopCapture() {
        Self.logger.notice("Stopping capture")
        clipPlaybackTask?.cancel()
        clipPlaybackTask = nil
        frameProcessingGate.reset()
        if trainingDataRecorder.isRecording {
            Task { await trainingDataRecorder.stopRecording() }
        }
        programOutput.updateCaptureStatus(isRunning: false)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        programOutput.stop()
        isRunning = false
        activeInputSource = preferredInputSource
        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()
        if validationClipURL != nil, preferredInputSource == .validationClip {
            validationClipStatus = "Validation clip stopped."
        }
        Self.logger.notice("Capture stopped")
    }

    /// Hold a wide safety shot while keeping the output path active.
    func returnToWide() {
        guard let cropEngine else { return }

        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()
        cropEngine.resetToFullFrame(aspect: shotComposer.normalizedAspect)
        cropEngine.jumpToTarget()
    }

    /// Hand control back to the tracker after a manual wide hold.
    func resumeTracking() {
        activeMode = .autoTracking
        cropEngine?.resetToFullFrame(aspect: shotComposer.normalizedAspect)
        shotComposer.reset()
        cinematicAgent.reset()

        if useMLAgent, let crop = cropEngine?.currentCrop {
            cinematicAgent.initialize(from: crop)
        }
    }

    func lockTarget(personID: UUID) {
        // Selection made — leave discovery and begin acquisition. Cropping
        // stays wide until the gallery is ready (ShotComposer promotes
        // acquiring → tracking and we get the .acquired tick outcome).
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        tapPending = false
        shotComposer.lockTarget(personID)
    }

    /// Operator tapped the "Detect" button. Arm the tap-a-subject state. No
    /// Vision runs yet — the preview just shows a tap affordance until the
    /// operator taps a point (or the discovery window times out).
    func beginDetection() {
        guard !shotComposer.isManualLockActive else { return }
        detectionDiscoveryActive = true
        pendingTapPoint = nil
        discoveryTimeoutAt = CACurrentMediaTime() + Self.discoveryTimeout
    }

    /// Cancel discovery and return to the passive (off) state.
    func cancelDetection() {
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        tapPending = false
    }

    /// Operator tapped a point on the preview to pick a subject. Stored for a
    /// one-shot ROI scan on the next frame; the scan finds the single person
    /// at that point and starts acquisition.
    func selectSubject(at point: CGPoint) {
        guard detectionDiscoveryActive else { return }
        pendingTapPoint = point
        tapPending = true
    }

    /// Smoothly release the operator's lock and zoom back out to a wide shot.
    /// Differs from `returnToWide()` which snaps — this animates so the
    /// operator gets a soft pull-back when tapping "unlock" on the lock pill.
    func clearManualTargetLock() {
        activeMode = .wide
        detectionDiscoveryActive = false
        pendingTapPoint = nil
        tapPending = false
        shotComposer.clearManualLock()
        boostFramingTransition()
    }

    /// Compute this frame's detection plan from the discovery flag + lock FSM.
    /// This is the single place that decides whether and where Vision runs.
    private func currentDetectionPlan() -> PersonDetector.DetectionRequestPlan {
        // A pending tap takes priority: scan a ROI around it to acquire.
        if let tap = pendingTapPoint {
            return PersonDetector.DetectionRequestPlan(
                mode: .acquiring,
                roi: tapROI(around: tap)
            )
        }

        switch shotComposer.lockState {
        case .acquiring:
            // Acquisition needs the FACE request to fill the gallery, so use
            // `.acquiring` mode (not `.lockedROI`, which drops face). Scan the
            // padded body box so the head is included even when the operator
            // tapped the torso.
            return PersonDetector.DetectionRequestPlan(
                mode: .acquiring,
                roi: lockedROI()
            )
        case .tracking, .hold:
            return PersonDetector.DetectionRequestPlan(
                mode: .lockedROI,
                roi: lockedROI()
            )
        case .wideWaiting:
            return PersonDetector.DetectionRequestPlan(mode: .reacquiring, roi: nil)
        case .inactive:
            return detectionDiscoveryActive
                ? PersonDetector.DetectionRequestPlan(mode: .awaitingTap, roi: nil)
                : .off
        }
    }

    /// ROI for the one-shot SELECTION scan around the operator's tap. The
    /// human-rectangles model needs to see most of a body to fire, so this is
    /// deliberately generous: a near-full-height vertical column centered on
    /// the tap's x. That reliably captures the whole standing/seated person
    /// (head included) while still excluding people to the left/right — which
    /// is what keeps the scan cheap in a crowd. Subsequent acquiring frames
    /// narrow to the detected body box via `lockedROI()`.
    private func tapROI(around point: CGPoint) -> CGRect {
        let halfW: CGFloat = 0.28   // ~56% of frame width, centered on the tap
        return CGRect(
            x: point.x - halfW,
            y: 0,
            width: halfW * 2,
            height: 1
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Padded ROI around the locked subject's last known box. Falls back to a
    /// generous centered region if no tracked bounds are available yet.
    private func lockedROI() -> CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Prefer the subject's last raw detected box (available during
        // acquiring too); fall back to the composer's tracked bounds.
        guard let box = lastSubjectROIBox ?? shotComposer.currentTrackedBounds,
              !box.isEmpty else {
            return unit
        }
        let p = Self.lockedROIPadding
        let w = min(box.width * p, 1)
        let hgt = min(box.height * p, 1)
        return CGRect(
            x: box.midX - w / 2, y: box.midY - hgt / 2,
            width: w, height: hgt
        ).intersection(unit)
    }

    /// Pick the detected person whose box contains the tapped point; if none
    /// contains it (the tap landed just off the body), fall back to the person
    /// whose box center is closest to the tap.
    private func personNearest(
        to point: CGPoint,
        in persons: [PersonDetector.DetectedPerson]
    ) -> PersonDetector.DetectedPerson? {
        if let hit = persons.first(where: { $0.boundingBox.contains(point) }) {
            return hit
        }
        return persons.min { a, b in
            let da = hypot(a.boundingBox.midX - point.x, a.boundingBox.midY - point.y)
            let db = hypot(b.boundingBox.midX - point.x, b.boundingBox.midY - point.y)
            return da < db
        }
    }
    
    /// Restart capture with a different camera
    func restartWithCamera(_ cameraDevice: CameraDevice) async throws {
        Self.logger.notice("Switching to camera: \(cameraDevice.name, privacy: .public)")
        
        // Stop current session
        let wasRunning = isRunning && activeInputSource == .liveCamera
        if wasRunning {
            Self.logger.debug("Stopping current session before camera switch")
            stopCapture()
            // Give the session time to fully stop
            try await Task.sleep(for: .milliseconds(500))
        }
        
        // Update selected camera
        selectedCamera = cameraDevice
        Self.logger.notice("Selected camera updated")
        
        // Start new session if it was running before
        if wasRunning {
            Self.logger.debug("Restarting capture after camera switch")
            try await startCapture()
        }
    }

    func setValidationClipURL(_ url: URL?) {
        validationClipURL = url
        if let url {
            validationClipStatus = "Ready to play \(url.lastPathComponent). Start Session to route it through the live pipeline."
        } else {
            validationClipStatus = "Select a validation clip to route file playback through Alfie's camera pipeline."
        }
    }

    var selectedValidationClipName: String {
        validationClipURL?.lastPathComponent ?? "No Clip Selected"
    }

    var shouldPreflightVirtualCameraInstallation: Bool {
        preferredInputSource == .liveCamera
    }
    
    // MARK: - Private Methods
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureFramingBindings() {
        shotComposer.$config
            .map(\.frameProfile)
            .removeDuplicates()
            .sink { [weak self] profile in
                self?.applyFrameProfile(profile)
            }
            .store(in: &cancellables)

        // Webcam format hides Manual Crop / Auto Pan; if the operator is in one
        // of those modes when switching to Webcam, fall back to a valid mode.
        shotComposer.$config
            .map(\.cinematicFormat)
            .removeDuplicates()
            .sink { [weak self] format in
                guard let self else { return }
                if format == .webcam,
                   self.activeMode == .manualCrop || self.activeMode == .autoPan {
                    self.activeMode = (self.manualLockedTargetID != nil) ? .autoTracking : .wide
                }
            }
            .store(in: &cancellables)
    }

    private func applyFrameProfile(_ profile: ShotComposer.Config.FrameProfile) {
        guard let cropEngine else { return }

        let desiredSize: CGSize
        switch profile {
        case .livestream:
            desiredSize = CGSize(width: 1920, height: 1080)
        case .portrait:
            desiredSize = profile.defaultOutputSize
        }
        if cropEngine.config.outputSize != desiredSize {
            cropEngine.config.outputSize = desiredSize
        }
    }

    private func startValidationClipPlayback() async throws {
        guard let validationClipURL else {
            error = .noValidationClipSelected
            throw CameraError.noValidationClipSelected
        }

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        error = nil
        isRunning = true
        activeInputSource = .validationClip
        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()
        currentFrameBuffer = nil
        croppedFrameBuffer = nil
        validationClipStatus = "Preparing \(validationClipURL.lastPathComponent)…"
        programOutput.updateCaptureStatus(isRunning: true)

        clipPlaybackTask?.cancel()
        clipPlaybackTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                repeat {
                    try await Self.playValidationClip(from: validationClipURL) { pixelBufferBox, timestampSeconds in
                        await self.processValidationFrame(
                            pixelBufferBox,
                            timestampSeconds: timestampSeconds
                        )
                    }

                    let shouldLoop = await self.loopValidationClip
                    if !shouldLoop || Task.isCancelled {
                        break
                    }

                    await self.updateValidationClipStatus(
                        "Looping \(validationClipURL.lastPathComponent)…"
                    )
                } while !Task.isCancelled

                await self.finishValidationClipPlayback(cancelled: Task.isCancelled)
            } catch is CancellationError {
                await self.finishValidationClipPlayback(cancelled: true)
            } catch {
                await self.handleValidationClipFailure(error)
            }
        }
    }

    private func processFrame(pixelBuffer: CVPixelBuffer, timestampSeconds: Double) async {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let captureInterval = Self.signposter.beginInterval("captureFrame")
        let captureStart = CACurrentMediaTime()

        programOutput.recordInputFrame(timestamp: timestampSeconds)

        // Publish the wide (left) pane's raw pixels *before* any processing so
        // the operator sees the live frame at the earliest possible instant,
        // rather than inheriting the full detection→compose→crop latency. This
        // is a zero-copy IOSurface handoff (see PixelBufferPreviewView), so it
        // costs a pointer assignment. Detection overlays are still published
        // post-detection below, so during fast motion the boxes may trail the
        // raw pixels by a frame — that is accepted for a monitoring pane. The
        // program (right) pane still publishes post-crop; it must show output.
        currentFrameBuffer = pixelBuffer

        if bufferHeight > 0 {
            let bufferAspect = bufferWidth / bufferHeight
            if abs(bufferAspect - lastAppliedSourceAspect) > 0.001 {
                lastAppliedSourceAspect = bufferAspect
                shotComposer.updateSourcePixelAspect(bufferAspect)
            }

            // Drive the crop quality floor from the *actual delivered*
            // resolution, not the advertised capture format — some drivers
            // (e.g. BMD CMIO) advertise 4K but deliver 1080p, which would
            // otherwise permit an unsafe 2× zoom. This single update covers
            // all crop modes (the floor is applied in CropEngine.setTargetCrop)
            // and corrects the ML agent's internal clamp to the same numbers.
            let sourceHeight = Int(bufferHeight)
            if sourceHeight != lastFloorSourceHeight {
                lastFloorSourceHeight = sourceHeight
                sourcePixelHeight = sourceHeight
                let floor = CropEngine.QualityFloor.forSource(height: sourceHeight)
                cropEngine?.qualityFloor = floor
                // The composer needs the same number so it can floor the crop
                // at the top anchor instead of letting setTargetCrop's
                // center-preserving clamp re-expand tight presets symmetrically.
                shotComposer.qualityFloorHeightFraction = floor.minCropHeightFraction
                cinematicAgent.updateSourceResolution(
                    width: Int(bufferWidth),
                    height: sourceHeight
                )
            }
        }

        let detectionInterval = Self.signposter.beginInterval("detection")
        let detectionStart = CACurrentMediaTime()
        // Auto-cancel a stale discovery (operator tapped Detect but never
        // picked anyone) so we fall back to the passive off state.
        if detectionDiscoveryActive,
           pendingTapPoint == nil,
           !shotComposer.isManualLockActive,
           CACurrentMediaTime() > discoveryTimeoutAt {
            detectionDiscoveryActive = false
        }

        // Decide whether/where Vision runs this frame (off by default).
        let detectionPlan = currentDetectionPlan()
        // The diagnostics CSV starts on the first frame that actually runs
        // Vision, not at capture start — the progressive lag only appears under
        // detection load, so `elapsed_s` should read as time under load.
        if detectionPlan.runsVision {
            programOutput.beginDiagnosticsSessionIfNeeded(note: "detection start")
        }
        // Hand the matcher the current operator lock so it can bind that track
        // first with a relaxed threshold (PersonDetector.swift assignTracks).
        personDetector.lockedTargetID = shotComposer.manualLockedTargetID
        let detectedPersons = await personDetector.processFrame(pixelBuffer, plan: detectionPlan)

        // The pending tap drove exactly one ROI scan. Bind acquisition to the
        // detected person nearest the tap point. If nothing was found, keep
        // discovery armed so the operator can tap again.
        if let tap = pendingTapPoint {
            pendingTapPoint = nil
            tapPending = false
            if let picked = personNearest(to: tap, in: detectedPersons) {
                lockTarget(personID: picked.id)   // → .acquiring, leaves discovery
                lastSubjectROIBox = picked.boundingBox
            } else {
                // Scan found no one at the tap — re-arm discovery so the
                // operator can try again, and surface that nothing was found.
                detectionDiscoveryActive = true
                discoveryTimeoutAt = CACurrentMediaTime() + Self.discoveryTimeout
            }
        }

        // Track the acquiring/locked subject's latest box to seed the next
        // frame's ROI. Cleared when no subject is being followed.
        if let subjectID = shotComposer.manualLockedTargetID,
           let box = detectedPersons.first(where: { $0.id == subjectID })?.boundingBox {
            lastSubjectROIBox = box
        } else if shotComposer.manualLockedTargetID == nil {
            lastSubjectROIBox = nil
        }
        let detectionDuration = CACurrentMediaTime() - detectionStart
        Self.signposter.endInterval("detection", detectionInterval)
        programOutput.recordDetectionTiming(
            queueWait: personDetector.stats.lastQueueWait,
            visionWall: personDetector.stats.lastDetectionTime
        )
        programOutput.recordLatency(stage: .detection, duration: detectionDuration)

        let composeInterval = Self.signposter.beginInterval("compose")
        let composeStart = CACurrentMediaTime()

        // Advance the lock state machine. tracking → hold when the locked
        // subject goes missing, hold → wideWaiting after holdDuration. The
        // outcome tells us whether to apply a one-shot camera effect
        // (pull-back to wide on hold expiry; resume tracking on re-acq).
        // pixelBuffer is passed so the composer can capture face signatures
        // for re-acquisition.
        let lockOutcome = shotComposer.tick(
            detections: detectedPersons,
            timestamp: CACurrentMediaTime(),
            pixelBuffer: pixelBuffer
        )
        switch lockOutcome {
        case .noChange:
            break
        case .pullBackToWide:
            activeMode = .wide
            boostFramingTransition()
            programOutput.noteDiagnostics("lock lost, pulled back to wide")
        case .resumeTracking:
            activeMode = .autoTracking
            boostFramingTransition()
            programOutput.noteDiagnostics("subject re-acquired")
        case .acquired:
            // Gallery ready → lock promoted to tracking (green box). Start
            // framing the subject and snap toward them quickly.
            activeMode = .autoTracking
            boostFramingTransition()
            programOutput.noteDiagnostics("subject locked, tracking")
        }

        let primaryPerson = activeMode != .autoTracking
            ? nil
            : shotComposer.primaryPerson(from: detectedPersons)

        // Crop dimensions in normalized [0,1] space for the active preset+aspect.
        // Single source of truth for both manualCropRect and the auto-pan range.
        func manualCropSize() -> CGSize {
            let aspect = shotComposer.normalizedAspect
            let baseHeight: CGFloat
            switch shotComposer.config.shotPreset {
            case .wide: baseHeight = 1.0
            case .fullBody: baseHeight = 0.8
            case .waistUp: baseHeight = 0.5
            }
            var cropHeight = baseHeight
            var cropWidth = cropHeight * aspect
            if cropWidth > 1.0 {
                cropWidth = 1.0
                cropHeight = cropWidth / aspect
            }
            if cropHeight > 1.0 {
                cropHeight = 1.0
                cropWidth = cropHeight * aspect
            }
            return CGSize(width: cropWidth, height: cropHeight)
        }

        func manualCropRect(center: CGPoint) -> CropEngine.CropRect {
            let size = manualCropSize()
            let originX = center.x - size.width / 2.0
            let originY = center.y - size.height / 2.0

            return CropEngine.CropRect(
                origin: CGPoint(x: originX, y: originY),
                size: size
            ).clamped()
        }

        var outputPixelBuffer = pixelBuffer
        var composeDuration: TimeInterval = 0
        var cropDuration: TimeInterval = 0
        if let cropEngine {
            switch activeMode {
            case .wide:
                    // Drive the spring toward full frame. Explicit "Return to
                    // Wide" snaps via cropEngine.jumpToTarget() in returnToWide();
                    // entering .wide via a softer path (e.g. unlocking the
                    // subject) animates instead. Honour the framing-boost
                    // window so the pull-back arrives in ~0.5s rather than
                    // crawling at the default subject-tracking smoothing.
                    let smoothing = CACurrentMediaTime() < fastFramingUntil
                        ? Self.fastFramingSmoothing
                        : shotComposer.config.smoothingFactor
                    cropEngine.config.transitionSmoothing = smoothing
                    // Aspect-correct wide: the largest 16:9 region of the
                    // source. Sending .fullFrame here would stretch a non-16:9
                    // source (e.g. 3576×2192) when rendered to the 16:9 output.
                    cropEngine.setTargetCrop(.widest(aspect: shotComposer.normalizedAspect))
                case .autoTracking:
                    if useMLAgent {
                        cropEngine.config.transitionSmoothing = 0.05
                        let newCrop = cinematicAgent.predict(
                            person: primaryPerson,
                            currentCrop: cropEngine.currentCrop
                        )
                        cropEngine.setTargetCrop(newCrop)
                    } else {
                        let smoothing = CACurrentMediaTime() < fastFramingUntil
                            ? Self.fastFramingSmoothing
                            : shotComposer.config.smoothingFactor
                        cropEngine.config.transitionSmoothing = smoothing
                        if let primaryPerson {
                            frameLog("🔍 DEBUG: Composing shot for person at \(primaryPerson.boundingBox)")
                            if let idealCrop = shotComposer.compose(person: primaryPerson) {
                                cropEngine.setTargetCrop(idealCrop)
                            }
                        } else {
                            frameLog("🔍 DEBUG: No persons detected, holding last position")
                        }
                    }
                case .manualCrop:
                    cropEngine.config.transitionSmoothing = shotComposer.config.smoothingFactor
                    let idealCrop = manualCropRect(center: manualCropPoint)
                    cropEngine.setTargetCrop(idealCrop)
                case .autoPan:
                    // Auto-pan drives the crop with deterministic constant-velocity
                    // motion, NOT the subject-tracking spring (jumpToTarget below
                    // snaps the visible crop to the phase each frame, so there is no
                    // velocity-proportional lag and the dwell is exactly
                    // autoPanPauseDuration).
                    //
                    // autoPanPhase is a normalized 0..1 sweep position, remapped onto
                    // the VISIBLE center range [halfW, 1-halfW] — the only range over
                    // which the crop actually moves before clamped() pins it. This
                    // removes the "dead" edge travel that made the camera sit frozen
                    // for tens of seconds at low speed: the reverse + pause now fire
                    // the instant the camera reaches the true visible edge, at any
                    // speed/preset.
                    let now = CACurrentMediaTime()
                    let dt = autoPanLastTick > 0 ? min(now - autoPanLastTick, 0.1) : 0
                    autoPanLastTick = now

                    let cropWidth = manualCropSize().width
                    let halfW = cropWidth / 2.0
                    let travel = max(0.0, 1.0 - cropWidth)   // (1 - halfW) - halfW

                    if travel <= 0.0001 {
                        // Crop fills the width: no horizontal room. Hold center, don't
                        // advance/flip (avoids thrash and a lingering pause state).
                        autoPanPauseUntil = 0
                        cropEngine.setTargetCrop(manualCropRect(center: CGPoint(x: 0.5, y: shotComposer.config.autoPanHeight)))
                        cropEngine.jumpToTarget()
                    } else {
                        if now > autoPanPauseUntil {
                            // Constant phase velocity throughout the sweep.
                            // autoPanSpeed (0.01–0.05) is treated as phase units per
                            // second * 9. The multiplier is high enough that even the
                            // slowest (1%) setting moves visibly — at lower values the
                            // near-edge crawl was only ~0.4 px/frame and looked frozen.
                            let rate = CGFloat(shotComposer.config.autoPanSpeed) * 9.0
                            autoPanPhase += rate * autoPanDirection * CGFloat(dt)
                            if autoPanPhase >= 1.0 {
                                autoPanPhase = 1.0
                                autoPanDirection = -1.0
                                autoPanPauseUntil = now + Self.autoPanPauseDuration
                            } else if autoPanPhase <= 0.0 {
                                autoPanPhase = 0.0
                                autoPanDirection = 1.0
                                autoPanPauseUntil = now + Self.autoPanPauseDuration
                            }
                        }
                        // Map normalized phase onto the visible center range.
                        let centerX = halfW + autoPanPhase * travel
                        let panCenter = CGPoint(x: centerX, y: shotComposer.config.autoPanHeight)
                        cropEngine.setTargetCrop(manualCropRect(center: panCenter))
                        // Zero spring lag: visible crop tracks the phase exactly.
                        cropEngine.jumpToTarget()
                    }
                }
            composeDuration = CACurrentMediaTime() - composeStart
            Self.signposter.endInterval("compose", composeInterval)
            programOutput.recordLatency(stage: .compose, duration: composeDuration)

            frameLog("🔍 DEBUG: About to call processCrop...")
            do {
                let cropStart = CACurrentMediaTime()
                let snapshot = cropEngine.tickInterpolation()
                let croppedBuffer = try cropEngine.processCrop(
                    pixelBuffer,
                    crop: snapshot.crop,
                    outputSize: snapshot.outputSize
                )
                cropDuration = CACurrentMediaTime() - cropStart
                programOutput.recordLatency(stage: .cropRender, duration: cropDuration)
                cropEngine.publishRenderStats(renderTime: cropDuration)
                frameLog("🔍 DEBUG: processCrop returned successfully")
                outputPixelBuffer = croppedBuffer
            } catch {
                Self.logger.error("Crop processing failed: \(error.localizedDescription, privacy: .public)")
                programOutput.recordDroppedFrame(
                    timestamp: timestampSeconds,
                    reason: "Crop processing failed: \(error.localizedDescription)"
                )
            }
            frameLog("🔍 DEBUG: Crop processing complete")
        } else {
            composeDuration = CACurrentMediaTime() - composeStart
            Self.signposter.endInterval("compose", composeInterval)
            programOutput.recordLatency(stage: .compose, duration: composeDuration)
        }

        if trainingDataRecorder.isRecording {
            trainingDataRecorder.recordFrame(
                timestamp: timestampSeconds,
                persons: detectedPersons,
                currentCrop: cropEngine?.currentCrop ?? .fullFrame,
                idealCrop: useMLAgent
                    ? cinematicAgent.lastPredictedCrop
                    : shotComposer.currentComputedCrop,
                isInterpolating: cropEngine?.isInterpolating ?? false
            )
        }

        // Publish the program (right) pane every frame. This is now a zero-copy
        // IOSurface layer assignment (PixelBufferPreviewView) rather than the
        // old per-render CIContext + full-frame createCGImage, so full-rate
        // (50 Hz) publishing is affordable on the MainActor — the earlier
        // half-rate gate (`previewPublishTick`) existed only to amortise that
        // expensive display path, which no longer exists. `outputPixelBuffer`
        // is the crop pool's output surface (every mode renders through
        // processCrop; the raw capture buffer passes through only when no
        // CropEngine exists);
        // holding it in the published property keeps the pool from re-vending it
        // while on screen. The wide pane was already published above, pre-crop.
        croppedFrameBuffer = outputPixelBuffer
        programOutput.sendFrame(outputPixelBuffer, timestamp: timestampSeconds)

        let totalDuration = CACurrentMediaTime() - captureStart
        programOutput.recordLatency(stage: .total, duration: totalDuration)
        Self.signposter.endInterval("captureFrame", captureInterval)

        let gateDrops = frameProcessingGate.droppedFrameCount
        programOutput.recordGateDropTotal(gateDrops)
        latencyLog(
            "total=\(String(format: "%.1f", totalDuration * 1000))ms " +
            "detect=\(String(format: "%.1f", detectionDuration * 1000))ms " +
            "crop=\(String(format: "%.1f", cropDuration * 1000))ms " +
            "compose=\(String(format: "%.1f", composeDuration * 1000))ms " +
            "gateDrops=\(gateDrops)"
        )
    }

    private func processValidationFrame(
        _ pixelBufferBox: SendablePixelBufferBox,
        timestampSeconds: Double
    ) async {
        await processFrame(
            pixelBuffer: pixelBufferBox.pixelBuffer,
            timestampSeconds: timestampSeconds
        )
    }

    private func updateValidationClipStatus(_ status: String) {
        validationClipStatus = status
    }

    private func handleValidationClipFailure(_ error: Error) {
        Self.logger.error("Validation clip playback failed: \(error.localizedDescription, privacy: .public)")
        self.error = .validationClipPlaybackFailed(error.localizedDescription)
        validationClipStatus = "Playback failed: \(error.localizedDescription)"
        finishValidationClipPlayback(cancelled: false)
    }

    private func finishValidationClipPlayback(cancelled: Bool) {
        guard activeInputSource == .validationClip || isRunning else { return }

        clipPlaybackTask = nil
        programOutput.updateCaptureStatus(isRunning: false)
        programOutput.stop()
        isRunning = false
        activeInputSource = preferredInputSource
        activeMode = .wide
        shotComposer.reset(clearManualLock: true)
        cinematicAgent.reset()

        if let validationClipURL {
            validationClipStatus = cancelled
                ? "Stopped \(validationClipURL.lastPathComponent)."
                : "Finished \(validationClipURL.lastPathComponent)."
        } else {
            validationClipStatus = cancelled
                ? "Validation clip stopped."
                : "Validation clip finished."
        }
    }

    private nonisolated static func playValidationClip(
        from url: URL,
        onFrame: @escaping @Sendable (SendablePixelBufferBox, Double) async -> Void
    ) async throws {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CameraError.invalidValidationClip
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw CameraError.validationClipPlaybackFailed("AVAssetReader could not attach the video output")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw CameraError.validationClipPlaybackFailed(
                reader.error?.localizedDescription ?? "AVAssetReader failed to start"
            )
        }

        var previousTimestamp: Double?
        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if let previousTimestamp {
                let delta = max(0, timestampSeconds - previousTimestamp)
                if delta > 0 {
                    try await Task.sleep(
                        nanoseconds: UInt64((delta * 1_000_000_000).rounded())
                    )
                }
            }
            previousTimestamp = timestampSeconds

            let pixelBufferBox = SendablePixelBufferBox(pixelBuffer)
            await onFrame(pixelBufferBox, timestampSeconds)
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        if reader.status == .failed {
            throw CameraError.validationClipPlaybackFailed(
                reader.error?.localizedDescription ?? "AVAssetReader failed while reading"
            )
        }
    }
    
    private func configureSession() async throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        // Remove existing inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        // Do NOT set a session preset. AVCaptureSessionPresetInputPriority is
        // iOS-only; the macOS equivalent is to leave the session at its default
        // (no preset), which lets configureCameraDevice() own the activeFormat
        // selection. A concrete preset like .high would reconfigure the device
        // to match the preset resolution, clobbering the manually chosen 4K format.
        
        // Find camera to use
        guard let camera = findCameraToUse() else {
            error = .noCameraAvailable
            throw CameraError.noCameraAvailable
        }

        // Add camera input
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            error = .sessionConfigurationFailed
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addInput(input)

        // Configure camera format AFTER attaching the input: with the device already
        // in the session and inside this begin/commitConfiguration transaction, the
        // format chosen here dictates the session's quality of service (macOS has no
        // .inputPriority preset), rather than being clobbered when the input is added.
        try configureCameraDevice(camera)
        
        // Configure video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Config.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        
        guard captureSession.canAddOutput(output) else {
            error = .sessionConfigurationFailed
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addOutput(output)
        self.videoOutput = output
    }
    
    private func findCameraToUse() -> AVCaptureDevice? {
        // Use selected camera if available
        if let selected = selectedCamera,
           let device = AVCaptureDevice(uniqueID: selected.uniqueID) {
            return device
        }
        
        // Otherwise auto-select
        return findBestCamera()
    }
    
    private func findBestCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        
        // Prefer 4K capable camera, then any available
        return devices.first(where: { hasAny4KFormat($0) }) ?? devices.first
    }
    
    private func hasAny4KFormat(_ device: AVCaptureDevice) -> Bool {
        device.formats.contains { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == Config.targetWidth && dimensions.height == Config.targetHeight
        }
    }
    
    /// Format explicitly chosen in configureCameraDevice(), re-asserted after
    /// startRunning() because the macOS .high session preset clobbers it
    /// (see reassertConfiguredFormatIfNeeded).
    private var configuredCaptureDevice: AVCaptureDevice?
    private var configuredCaptureFormat: AVCaptureDevice.Format?
    private var configuredMinFrameDuration: CMTime?
    private var configuredMaxFrameDuration: CMTime?

    private func configureCameraDevice(_ device: AVCaptureDevice) throws {
        Self.logger.notice("Configuring device: \(device.localizedName, privacy: .public)")
        
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Find best format (4K or best available)
        guard let format = findBest4KFormat(for: device) ?? findBestAvailableFormat(for: device) else {
            error = .unsupportedFormat
            throw CameraError.unsupportedFormat
        }
        
        device.activeFormat = format

        // DEBUG: Print supported frame rates
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        Self.logger.notice("Active format: \(dims.width)x\(dims.height)")

        // Remember the choice so startCapture() can re-assert it after
        // startRunning() — the .high session preset overwrites activeFormat
        // when the session starts (see reassertConfiguredFormatIfNeeded).
        configuredCaptureDevice = device
        configuredCaptureFormat = format

        if dims.height > 0 {
            let sourceAspect = CGFloat(dims.width) / CGFloat(dims.height)
            shotComposer.updateSourcePixelAspect(sourceAspect)
            lastAppliedSourceAspect = sourceAspect
            // First-guess clamp from the advertised format. processFrame()
            // overrides this with the *actual delivered* resolution on the
            // first frame (some drivers advertise 4K but deliver 1080p), which
            // is the authoritative source for both the agent clamp and the
            // CropEngine quality floor.
            cinematicAgent.updateSourceResolution(width: Int(dims.width), height: Int(dims.height))
        }

        Self.logger.debug("Supported frame rates follow")
        for range in format.videoSupportedFrameRateRanges {
            Self.logger.debug("\(range.minFrameRate, privacy: .public) to \(range.maxFrameRate, privacy: .public) fps")
        }
        
        // Set frame rate using EXACT duration from supported range
        // DO NOT construct CMTime manually - use the range's exact values
        if let range30fps = format.videoSupportedFrameRateRanges.first(where: { range in
            range.minFrameRate <= Config.targetFrameRate && range.maxFrameRate >= Config.targetFrameRate
        }) {
            Self.logger.notice("Using 30fps-supported range")
            device.activeVideoMinFrameDuration = range30fps.minFrameDuration
            device.activeVideoMaxFrameDuration = range30fps.maxFrameDuration
        } else {
            Self.logger.warning("No 30fps range found; using first available range")
            if let firstRange = format.videoSupportedFrameRateRanges.first {
                device.activeVideoMinFrameDuration = firstRange.minFrameDuration
                device.activeVideoMaxFrameDuration = firstRange.maxFrameDuration
            }
        }

        configuredMinFrameDuration = device.activeVideoMinFrameDuration
        configuredMaxFrameDuration = device.activeVideoMaxFrameDuration
    }

    /// The .high session preset (macOS default; .inputPriority is iOS-only)
    /// re-configures the capture device's activeFormat during startRunning(),
    /// silently replacing the 4K format chosen in configureCameraDevice with
    /// 1080p. Verified empirically with the Elgato 4K X: activeFormat reads
    /// 3840×2160 after commitConfiguration and 1920×1080 immediately after
    /// startRunning. Re-asserting the stored format after start sticks — the
    /// session only performs its preset-driven reconfiguration at start time.
    private func reassertConfiguredFormatIfNeeded() {
        guard let device = configuredCaptureDevice,
              let format = configuredCaptureFormat,
              device.activeFormat != format else { return }
        let clobbered = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let wanted = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        Self.logger.warning(
            "Session preset clobbered activeFormat to \(clobbered.width)x\(clobbered.height); re-asserting \(wanted.width)x\(wanted.height)"
        )
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let min = configuredMinFrameDuration { device.activeVideoMinFrameDuration = min }
            if let max = configuredMaxFrameDuration { device.activeVideoMaxFrameDuration = max }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Failed to re-assert capture format: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func findBest4KFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            
            // Check if resolution matches 4K (3840x2160)
            guard dimensions.width == Config.targetWidth,
                  dimensions.height == Config.targetHeight else {
                return false
            }
            
            // Check if format supports our target frame rate
            let frameRateRanges = format.videoSupportedFrameRateRanges
            let supportsTargetFrameRate = frameRateRanges.contains { range in
                range.minFrameRate <= Config.targetFrameRate &&
                range.maxFrameRate >= Config.targetFrameRate
            }
            
            return supportsTargetFrameRate
        }
    }
    
    /// Fallback format choice, used only when `findBest4KFormat` found no exact
    /// 3840×2160 format at the show standard's rate. Cameras that satisfy that
    /// exact match (the show rig) never reach this function.
    ///
    /// Preference order is shape-first, because the pipeline crops to 16:9
    /// regardless: pixels above and below a widescreen region are captured,
    /// carried through detection and the GPU crop, and then discarded. A
    /// slightly smaller 16:9 format therefore delivers the same program output
    /// for less work — and makes the operator's input pane match the program
    /// pane instead of appearing squarer.
    private func findBestAvailableFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        // All formats, highest pixel count first. Every tier below picks the
        // largest format meeting its criteria.
        let sortedFormats = device.formats.sorted { format1, format2 in
            let dims1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription)
            let dims2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription)
            return dims1.width * dims1.height > dims2.width * dims2.height
        }

        // 16:9 within a tolerance tight enough to exclude DCI 4K (4096×2160 is
        // 1.896, noticeably wider) while accepting genuine 16:9 modes.
        func isWidescreen(_ format: AVCaptureDevice.Format) -> Bool {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.height > 0 else { return false }
            let aspect = Double(dims.width) / Double(dims.height)
            return abs(aspect - 16.0 / 9.0) < 0.02
        }

        func supportsShowFrameRate(_ format: AVCaptureDevice.Format) -> Bool {
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= Config.targetFrameRate &&
                range.maxFrameRate >= Config.targetFrameRate
            }
        }

        // Tiered rather than a blunt "16:9 always wins", so a camera whose only
        // widescreen mode is tiny still ends up on something sensible.
        return sortedFormats.first { isWidescreen($0) && supportsShowFrameRate($0) }
            ?? sortedFormats.first { isWidescreen($0) }
            ?? sortedFormats.first { supportsShowFrameRate($0) }
            ?? sortedFormats.first
    }
}

extension CameraManager {
    var manualLockedTargetID: UUID? {
        shotComposer.manualLockedTargetID
    }

    var isManualTargetLockActive: Bool {
        shotComposer.isManualLockActive
    }
}

@MainActor
private final class VirtualCameraOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .virtualCamera
    private static let logger = Logger(subsystem: "com.alfie", category: "VirtualCameraOutput")
    private static let signposter = OSSignposter(logger: logger)

    private let xpcManager = XPCConnectionManager()
    private(set) var lastFrameSendDuration: TimeInterval?
    private var hasLoggedFirstFrameSend = false

    /// The XPC message carries only an IOSurfaceID — nothing on the extension
    /// side retains the backing CVPixelBuffer for us. The extension's frame
    /// queue can hold a frame for ~166 ms (5 frames drained at 30 Hz), while
    /// the CropEngine pool recycles a buffer as soon as the app drops its last
    /// reference (~one frame later). Retaining the most recent sends here keeps
    /// a surface alive until the extension has certainly consumed it; without
    /// this, the next render can overwrite a surface the extension is still
    /// reading (visible as tearing).
    private static let retainedFrameDepth = 10
    private var recentlySentBuffers: [CVPixelBuffer] = []
    var onStateChange: (() -> Void)? {
        didSet {
            xpcManager.onStateChange = onStateChange
        }
    }

    var isAvailable: Bool {
        if case .connected = xpcManager.connectionState {
            return true
        }
        return false
    }

    var summary: String {
        switch xpcManager.connectionState {
        case .connected:
            return "CMIO extension is connected and ready."
        case .connecting:
            return "Connecting to the CMIO extension."
        case .disconnected:
            return "Virtual camera route is idle."
        case .error:
            return "Virtual camera route hit a connection problem."
        }
    }

    var detail: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Frames are being sent to the system extension over XPC."
        case .connecting:
            return "Waiting for the extension service to answer the connection check."
        case .disconnected:
            return "Start capture to connect the host app to the virtual camera extension."
        case .error(let message):
            return message
        }
    }

    var lastErrorDescription: String? {
        xpcManager.lastErrorDescription
    }

    var canReconnect: Bool {
        xpcManager.canReconnect
    }

    var reconnectStatus: String? {
        xpcManager.reconnectStatusDescription
    }

    var bringUpChecks: [OutputBringUpCheck] {
        [
            OutputBringUpCheck(
                id: "virtual.xpc",
                title: "Virtual Camera · XPC Link",
                status: xpcStatusTitle,
                detail: xpcStatusDetail,
                level: xpcStatusLevel
            ),
            OutputBringUpCheck(
                id: "virtual.frames",
                title: "Virtual Camera · Frame Handoff",
                status: frameHandoffStatusTitle,
                detail: frameHandoffDetail,
                level: frameHandoffLevel
            )
        ]
    }

    func connect() {
        xpcManager.connect()
    }

    func disconnect() {
        xpcManager.disconnect()
        recentlySentBuffers.removeAll()
    }

    func reconnect() {
        xpcManager.forceReconnect()
    }

    func updateCaptureStatus(isRunning: Bool) {
        if isRunning {
            Self.logger.notice("Sending capture status RUNNING to virtual camera extension")
        } else {
            Self.logger.notice("Sending capture status STOPPED to virtual camera extension")
        }
        xpcManager.remoteProxy()?.updateCaptureStatus(isRunning: isRunning)
    }

    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        let sendInterval = Self.signposter.beginInterval("xpcSend")
        let sendStart = CACurrentMediaTime()
        guard let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
              let proxy = xpcManager.remoteProxy() else {
            lastFrameSendDuration = nil
            Self.signposter.endInterval("xpcSend", sendInterval)
            return false
        }

        proxy.sendVideoFrame(
            surfaceID: IOSurfaceGetID(ioSurface),
            timestamp: timestamp,
            width: Int32(CVPixelBufferGetWidth(pixelBuffer)),
            height: Int32(CVPixelBufferGetHeight(pixelBuffer))
        )
        recentlySentBuffers.append(pixelBuffer)
        if recentlySentBuffers.count > Self.retainedFrameDepth {
            recentlySentBuffers.removeFirst()
        }
        if !hasLoggedFirstFrameSend {
            hasLoggedFirstFrameSend = true
            Self.logger.notice(
                "First frame handed to virtual camera extension at \(timestamp, privacy: .public)s"
            )
        }
        lastFrameSendDuration = CACurrentMediaTime() - sendStart
        Self.signposter.endInterval("xpcSend", sendInterval)
        return true
    }

    private var xpcStatusTitle: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    private var xpcStatusDetail: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Host app can reach the CMIO extension Mach service."
        case .connecting:
            return "Waiting for the extension service to answer the XPC ping."
        case .disconnected:
            return "The CMIO extension is not connected. Check that the system extension is installed and loaded."
        case .error(let message):
            return message
        }
    }

    private var xpcStatusLevel: OutputCheckLevel {
        switch xpcManager.connectionState {
        case .connected:
            return .ok
        case .connecting:
            return .info
        case .disconnected:
            return .warning
        case .error:
            return .error
        }
    }

    private var frameHandoffStatusTitle: String {
        if lastFrameSendDuration != nil {
            return "Sending"
        }
        if case .connected = xpcManager.connectionState {
            return "Connected"
        }
        return "Waiting"
    }

    private var frameHandoffDetail: String {
        if let lastFrameSendDuration {
            return String(
                format: "Frames are being handed to the extension over XPC. Last send: %.2f ms.",
                lastFrameSendDuration * 1000
            )
        }
        if case .connected = xpcManager.connectionState {
            return "XPC is connected, but no program frames have been handed off yet."
        }
        return "No frame handoff is possible until the XPC link is connected."
    }

    private var frameHandoffLevel: OutputCheckLevel {
        if lastFrameSendDuration != nil {
            return .ok
        }
        if case .connected = xpcManager.connectionState {
            return .info
        }
        return .warning
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Extract pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Verify IOSurface backing (zero-copy requirement)
        guard CVPixelBufferGetIOSurface(pixelBuffer) != nil else {
            assertionFailure("PixelBuffer must be IOSurface-backed for zero-copy operations")
            return
        }

        Self.logFirstFrameResolution(pixelBuffer)

        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // No per-drop logging here. Under overload this fires at frame rate on
        // the capture delegate queue, and the logging itself then contributes to
        // the overload. The gate already emits a delivered/dropped summary once
        // per second (`CaptureThroughput`), and the [SOAK] line carries the
        // running total.
        guard frameProcessingGate.begin() else { return }

        let sendableBuffer = SendablePixelBufferBox(pixelBuffer)

        // Soak diagnostic: how long the frame Task waits for the MainActor.
        // A growing hopLag with flat Vision wall time is the signature of
        // MainActor/SwiftUI accumulation (see the [SOAK] line).
        let enqueueTime = CACurrentMediaTime()

        Task(priority: .userInitiated) { @MainActor in
            defer { self.frameProcessingGate.finish() }
            self.programOutput.recordMainActorHop(CACurrentMediaTime() - enqueueTime)
            await self.processFrame(
                pixelBuffer: sendableBuffer.pixelBuffer,
                timestampSeconds: timestampSeconds
            )
        }
    }
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Performance monitoring: frame drops indicate system overload
        latencyLog("avcapture-drop (system overload upstream of processing gate)")
        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        Task(priority: .userInitiated) { @MainActor in
            self.programOutput.recordDroppedFrame(
                timestamp: timestampSeconds,
                reason: "AVCapture dropped a frame before processing."
            )
        }
    }
}
