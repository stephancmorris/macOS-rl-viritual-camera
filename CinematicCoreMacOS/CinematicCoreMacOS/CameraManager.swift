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

/// Manages the AVCaptureSession pipeline for 4K video capture
/// Ticket: APP-01 - AVCaptureSession Pipeline
@MainActor
final class CameraManager: NSObject, ObservableObject {
    
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
    
    /// Person detector (Task 2.1)
    let personDetector = PersonDetector()
    
    /// Crop engine (Task 2.2 - GFX-01)
    let cropEngine: CropEngine?

    /// Shot composer (Task 2.3 - LOGIC-01)
    let shotComposer = ShotComposer()

    /// Training data recorder (Task 3.1 - RL-01)
    let trainingDataRecorder = TrainingDataRecorder()

    /// Cropped output frame (for ATEM output)
    @Published private(set) var croppedFrame: CIImage?
    
    /// Enable/disable cropping
    @Published var cropEnabled: Bool = false
    
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
    
    // MARK: - Private Properties
    
    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(
        label: "com.cinematiccore.videoOutput",
        qos: .userInteractive
    )
    private let xpcManager = XPCConnectionManager()
    
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
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        // Initialize crop engine (Task 2.2 - GFX-01)
        self.cropEngine = CropEngine()
        
        super.init()
        
        if cropEngine == nil {
            print("⚠️ CropEngine failed to initialize - Metal may not be available")
        } else {
            print("✅ CropEngine initialized successfully")
        }
        
        // Discover cameras on initialization
        discoverCameras()
    }
    
    // MARK: - Public Methods
    
    /// Discover and list all available cameras
    func discoverCameras() {
        print("\n🔍 Discovering cameras...")
        
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
            
            print("   - \(device.localizedName): \(maxResString)\(supports4K ? " (4K)" : "")")
            
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
                print("   ✓ Selected: \(selected.name)")
            }
        }
    }
    
    /// Request camera permissions and start the capture session
    func startCapture() async throws {
        print("\n▶️ Starting capture...")
        
        // Check authorization
        let authorized = await checkAuthorization()
        guard authorized else {
            print("   ❌ Authorization denied")
            error = .authorizationDenied
            throw CameraError.authorizationDenied
        }
        print("   ✓ Camera authorized")
        
        // Refresh camera list if no camera selected
        if selectedCamera == nil {
            print("   Discovering cameras...")
            discoverCameras()
        }
        
        // Configure session
        print("   Configuring session...")
        try await configureSession()
        print("   ✓ Session configured")
        
        // Start running
        await MainActor.run {
            captureSession.startRunning()
            isRunning = captureSession.isRunning
            if isRunning {
                print("   ✓ Capture started successfully")
            } else {
                print("   ⚠️ Session not running after startRunning() call")
            }
        }
    }
    
    /// Stop the capture session
    func stopCapture() {
        print("   ⏹️ Stopping capture...")
        captureSession.stopRunning()
        isRunning = false
        print("   ✓ Capture stopped")
    }
    
    /// Restart capture with a different camera
    func restartWithCamera(_ cameraDevice: CameraDevice) async throws {
        print("\n🔄 Switching to camera: \(cameraDevice.name)")
        
        // Stop current session
        let wasRunning = isRunning
        if wasRunning {
            print("   Stopping current session...")
            stopCapture()
            // Give the session time to fully stop
            try await Task.sleep(for: .milliseconds(500))
        }
        
        // Update selected camera
        selectedCamera = cameraDevice
        print("   ✓ Selected camera updated")
        
        // Start new session if it was running before
        if wasRunning {
            print("   Starting new session...")
            try await startCapture()
        }
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
        print("   🎥 Configuring device: \(device.localizedName)")
        
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
        print("   📊 Format: \(dims.width)x\(dims.height)")
        print("   📊 Supported frame rates:")
        for range in format.videoSupportedFrameRateRanges {
            print("      - \(range.minFrameRate) to \(range.maxFrameRate) fps")
        }
        
        // Set frame rate using EXACT duration from supported range
        // DO NOT construct CMTime manually - use the range's exact values
        if let range30fps = format.videoSupportedFrameRateRanges.first(where: { range in
            range.minFrameRate <= Config.targetFrameRate && range.maxFrameRate >= Config.targetFrameRate
        }) {
            print("   ✓ Using 30fps range: min=\(range30fps.minFrameDuration.value)/\(range30fps.minFrameDuration.timescale)")
            device.activeVideoMinFrameDuration = range30fps.minFrameDuration
            device.activeVideoMaxFrameDuration = range30fps.maxFrameDuration
        } else {
            print("   ⚠️ No 30fps range found, using first available")
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
        guard let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            assertionFailure("PixelBuffer must be IOSurface-backed for zero-copy operations")
            return
        }
        
        // Get IOSurface ID for XPC sharing
        let surfaceID = IOSurfaceGetID(ioSurface)
        
        // Get frame dimensions
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Get presentation timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampSeconds = timestamp.seconds
        
        // Convert to CIImage for display
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Process frame asynchronously (avoid blocking capture queue)
        Task { @MainActor in
            // Task 2.1: Run person detection
            let detectedPersons = await self.personDetector.processFrame(pixelBuffer)

            // Task 2.2: Apply crop if enabled (GFX-01)
            var croppedImage: CIImage?
            if self.cropEnabled, let cropEngine = self.cropEngine {
                print("🔍 DEBUG: Crop enabled, starting crop processing...")

                // Task 2.3 (LOGIC-01): Use ShotComposer for intelligent framing
                cropEngine.config.transitionSmoothing = self.shotComposer.config.smoothingFactor
                if let primaryPerson = detectedPersons.first {
                    print("🔍 DEBUG: Composing shot for person at \(primaryPerson.boundingBox)")
                    if let idealCrop = self.shotComposer.compose(person: primaryPerson) {
                        cropEngine.targetCrop = idealCrop
                    }
                    // nil = within deadzone, CropEngine continues interpolating to last target
                } else {
                    print("🔍 DEBUG: No persons detected, holding last position")
                }

                // Process crop (heavy GPU work)
                print("🔍 DEBUG: About to call processCrop...")
                do {
                    let croppedBuffer = try await cropEngine.processCrop(pixelBuffer)
                    print("🔍 DEBUG: processCrop returned successfully")
                    croppedImage = CIImage(cvPixelBuffer: croppedBuffer)
                } catch {
                    print("❌ Crop processing failed: \(error)")
                }
                print("🔍 DEBUG: Crop processing complete")
            }

            // Task 3.1 (RL-01): Record training data
            if self.trainingDataRecorder.isRecording {
                self.trainingDataRecorder.recordFrame(
                    timestamp: timestampSeconds,
                    persons: detectedPersons,
                    currentCrop: self.cropEngine?.currentCrop ?? .fullFrame,
                    idealCrop: self.shotComposer.lastComputedCrop,
                    isInterpolating: self.cropEngine?.isInterpolating ?? false
                )
            }

            // Update UI (already on main actor)
            self.currentFrame = ciImage
            self.croppedFrame = croppedImage

            // Send frame to system extension via XPC
            if let proxy = self.xpcManager.remoteProxy() {
                proxy.sendVideoFrame(
                    surfaceID: surfaceID,
                    timestamp: timestampSeconds,
                    width: Int32(width),
                    height: Int32(height)
                )
            }
        }
    }
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Performance monitoring: frame drops indicate system overload
        print("⚠️ Dropped frame")
    }
}
