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

    init() {}

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isProcessing else {
            droppedFrames &+= 1
            return false
        }
        isProcessing = true
        return true
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
    
    // MARK: - Published Properties
    
    /// Current camera frame as a CIImage for display
    @Published private(set) var currentFrame: CIImage?
    
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
    let programOutput = ProgramOutputManager(
        sinks: {
            var sinks: [any ProgramOutputSink] = [VirtualCameraOutputSink()]
            if DeveloperFlags.exposeBlackmagicOutputRoute {
                sinks.append(BlackmagicOutputSink())
            }
            return sinks
        }()
    )

    /// Cropped output frame (for ATEM output)
    @Published private(set) var croppedFrame: CIImage?

    /// Raw camera frame cropped to the detection bounding box (no padding, no aspect enforcement)
    @Published private(set) var detectionCroppedFrame: CIImage?
    


    /// Operation modes for crop control
    enum OperationMode {
        case wide
        case autoTracking
        case manualCrop
        case autoPan
    }

    /// Current operation mode for the crop engine
    @Published var activeMode: OperationMode = .wide

    /// The center point for the manual crop (normalized 0-1)
    @Published var manualCropPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // State for Auto Pan
    private var autoPanPhase: CGFloat = 0.5
    private var autoPanDirection: CGFloat = 1.0
    private var autoPanPauseUntil: Double = 0

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
        static let targetFrameRate: Double = 50.0
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
        cropEngine.resetToFullFrame()
        cropEngine.jumpToTarget()
    }

    /// Hand control back to the tracker after a manual wide hold.
    func resumeTracking() {
        activeMode = .autoTracking
        cropEngine?.resetToFullFrame()
        shotComposer.reset()
        cinematicAgent.reset()

        if useMLAgent, let crop = cropEngine?.currentCrop {
            cinematicAgent.initialize(from: crop)
        }
    }

    func lockTarget(personID: UUID) {
        activeMode = .autoTracking
        shotComposer.lockTarget(personID)
    }

    /// Smoothly release the operator's lock and zoom back out to a wide shot.
    /// Differs from `returnToWide()` which snaps — this animates so the
    /// operator gets a soft pull-back when tapping "unlock" on the lock pill.
    func clearManualTargetLock() {
        activeMode = .wide
        shotComposer.clearManualLock()
        boostFramingTransition()
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
        currentFrame = nil
        croppedFrame = nil
        detectionCroppedFrame = nil
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

        if bufferHeight > 0 {
            let bufferAspect = bufferWidth / bufferHeight
            if abs(bufferAspect - lastAppliedSourceAspect) > 0.001 {
                lastAppliedSourceAspect = bufferAspect
                shotComposer.updateSourcePixelAspect(bufferAspect)
            }
        }

        let detectionInterval = Self.signposter.beginInterval("detection")
        let detectionStart = CACurrentMediaTime()
        // Hand the matcher the current operator lock so it can bind that track
        // first with a relaxed threshold (PersonDetector.swift assignTracks).
        personDetector.lockedTargetID = shotComposer.manualLockedTargetID
        let detectedPersons = await personDetector.processFrame(pixelBuffer)
        let detectionDuration = CACurrentMediaTime() - detectionStart
        Self.signposter.endInterval("detection", detectionInterval)
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
        case .resumeTracking:
            activeMode = .autoTracking
            boostFramingTransition()
        }

        let primaryPerson = activeMode != .autoTracking
            ? nil
            : shotComposer.primaryPerson(from: detectedPersons)

        if let person = primaryPerson {
            let bbox = person.boundingBox
            let extent = ciImage.extent
            let cropRect = CGRect(
                x: bbox.origin.x * extent.width,
                y: bbox.origin.y * extent.height,
                width: bbox.width * extent.width,
                height: bbox.height * extent.height
            )
            detectionCroppedFrame = ciImage.cropped(to: cropRect)
        } else {
            detectionCroppedFrame = nil
        }

        func manualCropRect(center: CGPoint) -> CropEngine.CropRect {
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
            
            let originX = center.x - cropWidth / 2.0
            let originY = center.y - cropHeight / 2.0
            
            return CropEngine.CropRect(
                origin: CGPoint(x: originX, y: originY),
                size: CGSize(width: cropWidth, height: cropHeight)
            ).clamped()
        }

        var programImage = ciImage
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
                    cropEngine.targetCrop = .fullFrame
                case .autoTracking:
                    if useMLAgent {
                        cropEngine.config.transitionSmoothing = 0.05
                        let newCrop = cinematicAgent.predict(
                            person: primaryPerson,
                            currentCrop: cropEngine.currentCrop
                        )
                        cropEngine.targetCrop = newCrop
                    } else {
                        let smoothing = CACurrentMediaTime() < fastFramingUntil
                            ? Self.fastFramingSmoothing
                            : shotComposer.config.smoothingFactor
                        cropEngine.config.transitionSmoothing = smoothing
                        if let primaryPerson {
                            frameLog("🔍 DEBUG: Composing shot for person at \(primaryPerson.boundingBox)")
                            if let idealCrop = shotComposer.compose(person: primaryPerson) {
                                cropEngine.targetCrop = idealCrop
                            }
                        } else {
                            frameLog("🔍 DEBUG: No persons detected, holding last position")
                        }
                    }
                case .manualCrop:
                    cropEngine.config.transitionSmoothing = shotComposer.config.smoothingFactor
                    let idealCrop = manualCropRect(center: manualCropPoint)
                    cropEngine.targetCrop = idealCrop
                case .autoPan:
                    cropEngine.config.transitionSmoothing = shotComposer.config.smoothingFactor
                    let now = CACurrentMediaTime()
                    if now > autoPanPauseUntil {
                        autoPanPhase += CGFloat(shotComposer.config.autoPanSpeed) * autoPanDirection * 0.1 // Scaled down the multiplier to make it slower
                        if autoPanPhase >= 1.0 {
                            autoPanPhase = 1.0
                            autoPanDirection = -1.0
                            autoPanPauseUntil = now + 0.4 // Brief beat at the edge before reversing.
                        } else if autoPanPhase <= 0.0 {
                            autoPanPhase = 0.0
                            autoPanDirection = 1.0
                            autoPanPauseUntil = now + 0.4 // Brief beat at the edge before reversing.
                        }
                    }
                    let panCenter = CGPoint(x: autoPanPhase, y: shotComposer.config.autoPanHeight)
                    cropEngine.targetCrop = manualCropRect(center: panCenter)
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
                programImage = CIImage(cvPixelBuffer: croppedBuffer)
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
                    : shotComposer.lastComputedCrop,
                isInterpolating: cropEngine?.isInterpolating ?? false
            )
        }

        currentFrame = ciImage
        croppedFrame = programImage
        programOutput.sendFrame(outputPixelBuffer, timestamp: timestampSeconds)

        let totalDuration = CACurrentMediaTime() - captureStart
        programOutput.recordLatency(stage: .total, duration: totalDuration)
        Self.signposter.endInterval("captureFrame", captureInterval)

        let gateDrops = frameProcessingGate.droppedFrameCount
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
        
        // Set session preset
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        // Find camera to use
        guard let camera = findCameraToUse() else {
            error = .noCameraAvailable
            throw CameraError.noCameraAvailable
        }
        
        // Configure camera format
        try configureCameraDevice(camera)
        
        // Add camera input
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            error = .sessionConfigurationFailed
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addInput(input)
        
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

        if dims.height > 0 {
            let sourceAspect = CGFloat(dims.width) / CGFloat(dims.height)
            shotComposer.updateSourcePixelAspect(sourceAspect)
            lastAppliedSourceAspect = sourceAspect
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
    
    private func findBestAvailableFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        // Get all formats sorted by resolution (highest first)
        let sortedFormats = device.formats.sorted { format1, format2 in
            let dims1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription)
            let dims2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription)
            let pixels1 = dims1.width * dims1.height
            let pixels2 = dims2.width * dims2.height
            return pixels1 > pixels2
        }
        
        // Prefer formats that support 30fps
        let format30fps = sortedFormats.first { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= Config.targetFrameRate &&
                range.maxFrameRate >= Config.targetFrameRate
            }
        }
        
        // If no 30fps format, just use highest resolution
        return format30fps ?? sortedFormats.first
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

@MainActor
private final class BlackmagicOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .blackmagicSDI
    private let bridge = DeckLinkOutputBridge()
    private static let logger = Logger(subsystem: "com.alfie", category: "BlackmagicOutput")
    private static let signposter = OSSignposter(logger: logger)
    private var hasLoggedFirstFrameSend = false

    var onStateChange: (() -> Void)?

    var isAvailable: Bool {
        bridge.isConnected
    }

    var summary: String {
        if bridge.isConnected {
            return "Blackmagic SDI output is connected and active."
        }
        return "Blackmagic SDI output is disconnected."
    }

    var detail: String {
        if bridge.isConnected {
            return "Sending video frames to the connected UltraStudio device."
        }
        if let error = bridge.lastErrorDescription {
            return "Connection failed: \(error)"
        }
        return "Start capture to initialize the Blackmagic SDI output."
    }

    var lastErrorDescription: String? {
        bridge.lastErrorDescription
    }

    var bringUpChecks: [OutputBringUpCheck] {
        [
            OutputBringUpCheck(
                id: "blackmagic.connection",
                title: "Blackmagic SDI · Hardware",
                status: bridge.isConnected ? "Connected" : "Disconnected",
                detail: bridge.isConnected ? "UltraStudio HD is connected." : (bridge.lastErrorDescription ?? "Waiting for connection."),
                level: bridge.isConnected ? .ok : (bridge.lastErrorDescription != nil ? .error : .warning)
            )
        ]
    }

    func connect() {
        Self.logger.notice("Initializing Blackmagic SDI Output...")
        bridge.connect()
        onStateChange?()
    }

    func disconnect() {
        bridge.disconnect()
        onStateChange?()
    }

    func reconnect() {
        bridge.reconnect()
        onStateChange?()
    }

    func updateCaptureStatus(isRunning: Bool) {
        if isRunning && !bridge.isConnected {
            connect()
        } else if !isRunning && bridge.isConnected {
            disconnect()
        }
    }

    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        let sendInterval = Self.signposter.beginInterval("sdiSend")
        let result = bridge.sendFrame(with: pixelBuffer, timestamp: timestamp)
        
        if result && !hasLoggedFirstFrameSend {
            hasLoggedFirstFrameSend = true
            Self.logger.notice("First frame handed to DeckLink output bridge at \(timestamp, privacy: .public)s")
        }
        
        Self.signposter.endInterval("sdiSend", sendInterval)
        return result
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
        
        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        guard frameProcessingGate.begin() else {
            Self.logger.warning("Dropped frame: processing gate busy")
            return
        }

        let sendableBuffer = SendablePixelBufferBox(pixelBuffer)

        Task(priority: .userInitiated) { @MainActor in
            defer { self.frameProcessingGate.finish() }
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
