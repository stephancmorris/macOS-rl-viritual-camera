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
        sinks: [
            VirtualCameraOutputSink(),
            BlackmagicOutputSink()
        ]
    )

    /// Cropped output frame (for ATEM output)
    @Published private(set) var croppedFrame: CIImage?

    /// Raw camera frame cropped to the detection bounding box (no padding, no aspect enforcement)
    @Published private(set) var detectionCroppedFrame: CIImage?
    
    /// Enable/disable cropping
    @Published var cropEnabled: Bool = false {
        didSet {
            if !cropEnabled {
                trackingPaused = false
                shotComposer.reset(clearManualLock: true)
                cinematicAgent.reset()
            }
        }
    }

    /// Operator override that forces a safe wide shot until tracking is resumed.
    @Published private(set) var trackingPaused: Bool = false
    
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

    private final class SendablePixelBufferBox: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer

        init(_ pixelBuffer: CVPixelBuffer) {
            self.pixelBuffer = pixelBuffer
        }
    }

    /// Last source pixel aspect (width/height) forwarded to the shot composer.
    /// Used to skip the per-frame update when aspect is unchanged.
    private var lastAppliedSourceAspect: CGFloat = 0

    private nonisolated func frameLog(_ message: @autoclosure () -> String) {
        guard DeveloperFlags.verboseFrameLogging else { return }
        let resolvedMessage = message()
        Self.logger.debug("\(resolvedMessage, privacy: .public)")
    }

    // MARK: - Configuration Constants
    
    private enum Config {
        static let targetWidth: Int32 = 3840
        static let targetHeight: Int32 = 2160
        static let targetFrameRate: Double = 30.0
        static let pixelFormat = kCVPixelFormatType_32BGRA
    }
    
    // MARK: - Error Types
    
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
        programOutput.updateCaptureStatus(isRunning: false)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        programOutput.stop()
        isRunning = false
        activeInputSource = preferredInputSource
        trackingPaused = false
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

        trackingPaused = true
        shotComposer.reset()
        cinematicAgent.reset()
        cropEngine.resetToFullFrame()
        cropEngine.jumpToTarget()
    }

    /// Hand control back to the tracker after a manual wide hold.
    func resumeTracking() {
        trackingPaused = false
        shotComposer.reset()
        cinematicAgent.reset()

        if useMLAgent, let crop = cropEngine?.currentCrop {
            cinematicAgent.initialize(from: crop)
        }
    }

    func lockTarget(personID: UUID) {
        shotComposer.lockTarget(personID)
    }

    func clearManualTargetLock() {
        shotComposer.clearManualLock()
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
        trackingPaused = false
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
        let detectedPersons = await personDetector.processFrame(pixelBuffer)
        let detectionDuration = CACurrentMediaTime() - detectionStart
        Self.signposter.endInterval("detection", detectionInterval)
        programOutput.recordLatency(stage: .detection, duration: detectionDuration)

        let composeInterval = Self.signposter.beginInterval("compose")
        let composeStart = CACurrentMediaTime()
        let primaryPerson = trackingPaused
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

        var programImage = ciImage
        var outputPixelBuffer = pixelBuffer
        if cropEnabled, let cropEngine {
            frameLog("🔍 DEBUG: Crop enabled, starting crop processing...")

            if trackingPaused {
                frameLog("🔍 DEBUG: Tracking paused, holding wide safety shot")
            } else if useMLAgent {
                cropEngine.config.transitionSmoothing = 0.05
                let newCrop = cinematicAgent.predict(
                    person: primaryPerson,
                    currentCrop: cropEngine.currentCrop
                )
                cropEngine.targetCrop = newCrop
            } else {
                cropEngine.config.transitionSmoothing = shotComposer.config.smoothingFactor
                if let primaryPerson {
                    frameLog("🔍 DEBUG: Composing shot for person at \(primaryPerson.boundingBox)")
                    if let idealCrop = shotComposer.compose(person: primaryPerson) {
                        cropEngine.targetCrop = idealCrop
                    }
                } else {
                    frameLog("🔍 DEBUG: No persons detected, holding last position")
                }
            }
            let composeDuration = CACurrentMediaTime() - composeStart
            Self.signposter.endInterval("compose", composeInterval)
            programOutput.recordLatency(stage: .compose, duration: composeDuration)

            frameLog("🔍 DEBUG: About to call processCrop...")
            do {
                let cropStart = CACurrentMediaTime()
                let croppedBuffer = try await cropEngine.processCrop(pixelBuffer)
                let cropDuration = CACurrentMediaTime() - cropStart
                programOutput.recordLatency(stage: .cropRender, duration: cropDuration)
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
            let composeDuration = CACurrentMediaTime() - composeStart
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
        trackingPaused = false
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
        output.alwaysDiscardsLateVideoFrames = false
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
    var onStateChange: (() -> Void)? {
        didSet {
            xpcManager.onStateChange = onStateChange
        }
    }

    var isAvailable: Bool {
        true
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
        lastFrameSendDuration = CACurrentMediaTime() - sendStart
        Self.signposter.endInterval("xpcSend", sendInterval)
        return true
    }
}

@MainActor
private final class BlackmagicOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .blackmagicSDI
    var onStateChange: (() -> Void)?

    var isAvailable: Bool {
        false
    }

    var summary: String {
        "Blackmagic playback sink is not integrated yet."
    }

    var detail: String {
        "Add the Desktop Video SDK playback path here to send the processed feed to UltraStudio or DeckLink hardware."
    }

    var lastErrorDescription: String? {
        nil
    }

    func connect() {}
    func disconnect() {}
    func reconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { false }
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

        // Process frame asynchronously (avoid blocking capture queue)
        Task { @MainActor in
            await self.processFrame(
                pixelBuffer: pixelBuffer,
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
        frameLog("⚠️ Dropped frame")
        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        Task { @MainActor in
            self.programOutput.recordDroppedFrame(
                timestamp: timestampSeconds,
                reason: "AVCapture dropped a frame before processing."
            )
        }
    }
}
