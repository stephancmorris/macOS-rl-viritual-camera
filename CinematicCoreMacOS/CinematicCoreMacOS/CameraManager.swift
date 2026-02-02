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
        super.init()
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
            !device.localizedName.lowercased().contains("stephan")
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
        // Check authorization
        let authorized = await checkAuthorization()
        guard authorized else {
            error = .authorizationDenied
            throw CameraError.authorizationDenied
        }
        
        // Refresh camera list
        discoverCameras()
        
        // Configure session
        try await configureSession()
        
        // Start running
        await MainActor.run {
            captureSession.startRunning()
            isRunning = captureSession.isRunning
            if isRunning {
                print("✓ Capture started")
            }
        }
    }
    
    /// Stop the capture session
    func stopCapture() {
        captureSession.stopRunning()
        isRunning = false
    }
    
    /// Restart capture with a different camera
    func restartWithCamera(_ cameraDevice: CameraDevice) async throws {
        // Stop current session
        if isRunning {
            stopCapture()
            try await Task.sleep(for: .milliseconds(500))
        }
        
        // Update selected camera
        selectedCamera = cameraDevice
        
        // Start new session
        try await startCapture()
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
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Find best format (4K or best available)
        guard let format = findBest4KFormat(for: device) ?? findBestAvailableFormat(for: device) else {
            error = .unsupportedFormat
            throw CameraError.unsupportedFormat
        }
        
        device.activeFormat = format
        
        // DEBUG: Print supported frame rates
        print("   📊 Format: \(CMVideoFormatDescriptionGetDimensions(format.formatDescription).width)x\(CMVideoFormatDescriptionGetDimensions(format.formatDescription).height)")
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
        assert(CVPixelBufferGetIOSurface(pixelBuffer) != nil,
               "PixelBuffer must be IOSurface-backed for zero-copy operations")
        
        // Convert to CIImage for display
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Update on main thread
        Task { @MainActor in
            self.currentFrame = ciImage
        }
        
        // TODO (Epic 1, Task 1.3): Share IOSurfaceID with System Extension
        // let surfaceID = CVPixelBufferGetIOSurface(pixelBuffer).map(IOSurfaceGetID)
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
