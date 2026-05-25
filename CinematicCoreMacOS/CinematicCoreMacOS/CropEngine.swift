//
//  CropEngine.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//  Ticket: GFX-01 - Metal Crop Engine
//

import Metal
import CoreVideo
import CoreImage
import QuartzCore
import Combine
import OSLog

/// CoreImage-based crop and scale engine. Renders cropped output at display
/// priority, sidestepping the GPU power-state idling seen with isolated Metal
/// compute kernels on Apple Silicon (~30-45ms scheduler slot per frame).
@MainActor
final class CropEngine: ObservableObject {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "CropEngine")
    private nonisolated static let signposter = OSSignposter(logger: logger)

    // MARK: - Configuration

    struct Config: Sendable {
        /// Output resolution (default: 1920x1080 for ATEM)
        var outputSize: CGSize = CGSize(width: 1920, height: 1080)

        /// Smoothing factor for crop transitions (0 = instant, 1 = very smooth)
        /// 10% per frame as specified by LOGIC-01
        var transitionSmoothing: Float = 0.10

        /// Use high-quality sampling (slightly slower but better quality)
        var useHighQuality: Bool = true

        /// Enable vignette effect for cinematic look
        var enableVignette: Bool = false
    }

    @Published var config = Config()

    // MARK: - State

    /// Current crop rectangle (normalized 0-1 coordinates)
    @Published private(set) var currentCrop: CropRect = .fullFrame

    /// Target crop rectangle (where we're smoothly transitioning to)
    @Published var targetCrop: CropRect = .fullFrame {
        didSet {
            // Automatically start interpolating
            isInterpolating = true
        }
    }

    /// Whether we're actively interpolating between crops
    @Published private(set) var isInterpolating: Bool = false

    /// Spring physics state
    private var velocityOrigin: CGPoint = .zero
    private var velocitySize: CGSize = .zero
    private var lastInterpolationTime: TimeInterval = 0

    /// Performance statistics
    @Published private(set) var stats: Stats = .init()

    struct Stats: Sendable {
        var lastRenderTime: TimeInterval = 0
        var averageRenderTime: TimeInterval = 0
        var totalFramesRendered: Int = 0
        var gpuUtilization: Float = 0
    }

    // MARK: - Rendering Resources

    private let device: MTLDevice
    private let ciContext: CIContext


    // MARK: - Crop Rectangle Model
    
    struct CropRect: Equatable, Sendable {
        /// Normalized coordinates (0-1)
        var origin: CGPoint  // Bottom-left corner (Vision coordinate system)
        var size: CGSize     // Width and height
        
        /// Full frame (no crop)
        static let fullFrame = CropRect(
            origin: CGPoint(x: 0, y: 0),
            size: CGSize(width: 1, height: 1)
        )
        
        /// Create crop from center point and zoom level
        static func centered(at center: CGPoint, zoom: Float) -> CropRect {
            let width = 1.0 / CGFloat(zoom)
            let height = 1.0 / CGFloat(zoom)
            
            return CropRect(
                origin: CGPoint(
                    x: center.x - width / 2,
                    y: center.y - height / 2
                ),
                size: CGSize(width: width, height: height)
            )
        }
        
        /// Create crop to frame a bounding box (with padding)
        static func framing(
            boundingBox: CGRect,
            padding: CGFloat = 0.1
        ) -> CropRect {
            // Add padding
            let paddedBox = boundingBox.insetBy(
                dx: -boundingBox.width * padding,
                dy: -boundingBox.height * padding
            )
            
            // Clamp to 0-1 range
            let clampedOrigin = CGPoint(
                x: max(0, min(1 - paddedBox.width, paddedBox.origin.x)),
                y: max(0, min(1 - paddedBox.height, paddedBox.origin.y))
            )
            
            let clampedSize = CGSize(
                width: min(1, paddedBox.width),
                height: min(1, paddedBox.height)
            )
            
            return CropRect(origin: clampedOrigin, size: clampedSize)
        }
        
        /// Clamp crop to valid 0-1 range
        func clamped() -> CropRect {
            let clampedX = max(0, min(1 - size.width, origin.x))
            let clampedY = max(0, min(1 - size.height, origin.y))
            let clampedWidth = max(0.1, min(1, size.width))
            let clampedHeight = max(0.1, min(1, size.height))
            
            return CropRect(
                origin: CGPoint(x: clampedX, y: clampedY),
                size: CGSize(width: clampedWidth, height: clampedHeight)
            )
        }
        
        /// Interpolate between two crop rectangles
        func lerp(to target: CropRect, factor: Float) -> CropRect {
            let f = CGFloat(factor)
            return CropRect(
                origin: CGPoint(
                    x: origin.x + (target.origin.x - origin.x) * f,
                    y: origin.y + (target.origin.y - origin.y) * f
                ),
                size: CGSize(
                    width: size.width + (target.size.width - size.width) * f,
                    height: size.height + (target.size.height - size.height) * f
                )
            )
        }
    }
    
    // MARK: - Initialization
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logger.error("Metal is not supported on this device")
            return nil
        }
        self.device = device

        self.ciContext = CIContext(
            mtlDevice: device,
            options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                .cacheIntermediates: false,
                .name: "CropEngine.CIContext"
            ]
        )

        Self.logger.notice("CropEngine initialized with Metal device: \(device.name, privacy: .public)")
    }
    
    // MARK: - Public Methods

    /// MainActor-only: advance interpolation toward `targetCrop`, then snapshot
    /// the values `processCrop` needs. Call this from `processFrame` before
    /// invoking `processCrop` so the heavy crop work runs without an actor hop.
    @MainActor
    func tickInterpolation() -> (crop: CropRect, outputSize: CGSize, smoothingFactor: Float) {
        updateInterpolation()
        return (currentCrop, config.outputSize, config.transitionSmoothing)
    }

    /// Crop and scale a video frame using CoreImage. Caller must have already
    /// advanced interpolation via `tickInterpolation()` to obtain the snapshot
    /// values — doing it here would force a MainActor hop that serializes
    /// against SwiftUI rendering. (See git history for the Metal compute path
    /// that this replaces; it hit an Apple Silicon GPU power-state issue where
    /// isolated compute kernels were scheduled into a 30-45ms idle slot.)
    nonisolated func processCrop(
        _ pixelBuffer: CVPixelBuffer,
        crop: CropRect,
        outputSize: CGSize
    ) throws -> CVPixelBuffer {
        let cropInterval = Self.signposter.beginInterval("cropRender")
        defer {
            Self.signposter.endInterval("cropRender", cropInterval)
        }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = sourceImage.extent

        // Vision and CIImage both use bottom-left origin, so we can map the
        // normalized crop directly.
        let cropRect = CGRect(
            x: crop.origin.x * extent.width,
            y: crop.origin.y * extent.height,
            width: crop.size.width * extent.width,
            height: crop.size.height * extent.height
        )

        // Translate the cropped origin to (0,0) before scaling so the renderer
        // writes into the full output buffer.
        let translated = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

        // Lanczos resampling for sharper edges than CoreImage's default
        // bilinear. `scale` sets the vertical factor; `aspectRatio` adds any
        // extra horizontal stretch when the crop's aspect differs from the
        // output's (which can happen during interpolation between targets).
        let scaleY = outputSize.height / cropRect.height
        let scaleX = outputSize.width / cropRect.width
        let lanczos = CIFilter(name: "CILanczosScaleTransform")!
        lanczos.setValue(translated, forKey: kCIInputImageKey)
        lanczos.setValue(scaleY, forKey: kCIInputScaleKey)
        lanczos.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
        let scaled = lanczos.outputImage ?? translated.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY)
        )

        let outputBuffer = try createOutputBuffer(size: outputSize)
        ciContext.render(
            scaled,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        return outputBuffer
    }

    /// MainActor-only: record a completed render for the stats HUD. Called
    /// fire-and-forget after `processCrop` returns so the cooperative thread
    /// isn't blocked on SwiftUI updates.
    @MainActor
    func publishRenderStats(renderTime: TimeInterval) {
        updateStats(renderTime: renderTime)
    }


    /// Set crop to frame a detected person with smooth transition
    func framePerson(_ person: PersonDetector.DetectedPerson, padding: CGFloat = 0.15) {
        targetCrop = CropRect.framing(
            boundingBox: person.boundingBox,
            padding: padding
        ).clamped()
    }
    
    /// Reset to full frame
    func resetToFullFrame() {
        targetCrop = .fullFrame
    }
    
    /// Jump to target immediately (no smooth transition)
    func jumpToTarget() {
        currentCrop = targetCrop
        velocityOrigin = .zero
        velocitySize = .zero
        isInterpolating = false
        lastInterpolationTime = 0
    }
    
    // MARK: - Private Methods
    
    private func updateInterpolation() {
        guard isInterpolating else {
            lastInterpolationTime = 0
            return
        }
        
        let now = CACurrentMediaTime()
        if lastInterpolationTime == 0 {
            lastInterpolationTime = now
            return // Skip first frame to get a valid delta time
        }
        
        let dt = CGFloat(min(now - lastInterpolationTime, 0.1)) // Cap dt at 100ms
        lastInterpolationTime = now
        
        // Map transitionSmoothing (0.05 to 0.30) to a spring stiffness.
        // Higher value = stiffer spring = faster snap.
        let stiffness = CGFloat(config.transitionSmoothing) * 300.0
        let damping = 2.0 * sqrt(stiffness) // Critically damped
        
        // Spring physics: acceleration = (target - current) * stiffness - velocity * damping
        
        // Origin X
        let accX = (targetCrop.origin.x - currentCrop.origin.x) * stiffness - velocityOrigin.x * damping
        velocityOrigin.x += accX * dt
        let newX = currentCrop.origin.x + velocityOrigin.x * dt
        
        // Origin Y
        let accY = (targetCrop.origin.y - currentCrop.origin.y) * stiffness - velocityOrigin.y * damping
        velocityOrigin.y += accY * dt
        let newY = currentCrop.origin.y + velocityOrigin.y * dt
        
        // Size Width
        let accW = (targetCrop.size.width - currentCrop.size.width) * stiffness - velocitySize.width * damping
        velocitySize.width += accW * dt
        let newW = currentCrop.size.width + velocitySize.width * dt
        
        // Size Height
        let accH = (targetCrop.size.height - currentCrop.size.height) * stiffness - velocitySize.height * damping
        velocitySize.height += accH * dt
        let newH = currentCrop.size.height + velocitySize.height * dt
        
        currentCrop = CropRect(
            origin: CGPoint(x: newX, y: newY),
            size: CGSize(width: newW, height: newH)
        )
        
        // Check if we're close enough and moving slow enough to stop interpolating
        let distanceThreshold: CGFloat = 0.001
        let velocityThreshold: CGFloat = 0.005
        
        if abs(currentCrop.origin.x - targetCrop.origin.x) < distanceThreshold &&
           abs(currentCrop.origin.y - targetCrop.origin.y) < distanceThreshold &&
           abs(currentCrop.size.width - targetCrop.size.width) < distanceThreshold &&
           abs(currentCrop.size.height - targetCrop.size.height) < distanceThreshold &&
           abs(velocityOrigin.x) < velocityThreshold &&
           abs(velocityOrigin.y) < velocityThreshold &&
           abs(velocitySize.width) < velocityThreshold &&
           abs(velocitySize.height) < velocityThreshold {
            
            currentCrop = targetCrop
            velocityOrigin = .zero
            velocitySize = .zero
            isInterpolating = false
            lastInterpolationTime = 0
        }
    }
    
    private nonisolated func createOutputBuffer(size: CGSize) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw CropError.bufferCreationFailed
        }
        
        return buffer
    }
    
    private func updateStats(renderTime: TimeInterval) {
        stats.lastRenderTime = renderTime
        stats.totalFramesRendered += 1
        
        // Running average
        let alpha: TimeInterval = 0.1
        stats.averageRenderTime = (alpha * renderTime) + ((1 - alpha) * stats.averageRenderTime)
    }
}

// MARK: - Supporting Types

enum CropError: LocalizedError {
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed: return "Failed to create output buffer"
        }
    }
}
