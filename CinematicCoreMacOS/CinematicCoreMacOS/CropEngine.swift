//
//  CropEngine.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//  Ticket: GFX-01 - Metal Crop Engine
//

import Metal
import MetalKit
import CoreVideo
import CoreImage
import QuartzCore
import Combine

/// High-performance Metal-based crop and scale engine
/// Maintains full quality while extracting regions from 4K video
@MainActor
final class CropEngine: ObservableObject {

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

    /// Performance statistics
    @Published private(set) var stats: Stats = .init()

    struct Stats: Sendable {
        var lastRenderTime: TimeInterval = 0
        var averageRenderTime: TimeInterval = 0
        var totalFramesRendered: Int = 0
        var gpuUtilization: Float = 0
    }

    // MARK: - Metal Resources (nonisolated for GPU work)

    // These are thread-safe and can be used from any context
    private nonisolated(unsafe) let device: MTLDevice
    private nonisolated(unsafe) let commandQueue: MTLCommandQueue
    private nonisolated(unsafe) let pipelineState: MTLComputePipelineState
    private nonisolated(unsafe) let textureCache: CVMetalTextureCache
    private nonisolated(unsafe) let ciContext: CIContext
    
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
        // Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal is not supported on this device")
            return nil
        }
        self.device = device
        
        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            print("❌ Failed to create Metal command queue")
            return nil
        }
        self.commandQueue = queue
        
        // Load Metal library and create pipeline
        guard let library = device.makeDefaultLibrary(),
              let cropFunction = library.makeFunction(name: "cropAndScale") else {
            print("❌ Failed to load Metal shader library")
            return nil
        }
        
        do {
            self.pipelineState = try device.makeComputePipelineState(function: cropFunction)
            print("✅ Created compute pipeline state")
            print("   - Thread execution width: \(pipelineState.threadExecutionWidth)")
            print("   - Max threads per threadgroup: \(pipelineState.maxTotalThreadsPerThreadgroup)")
        } catch {
            print("❌ Failed to create compute pipeline: \(error)")
            return nil
        }
        
        // Create texture cache for efficient CVPixelBuffer → MTLTexture conversion
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        
        guard result == kCVReturnSuccess, let textureCache = cache else {
            print("❌ Failed to create texture cache")
            return nil
        }
        self.textureCache = textureCache
        
        // Create CIContext for additional image processing if needed
        self.ciContext = CIContext(
            mtlDevice: device,
            options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                .cacheIntermediates: false,
                .name: "CropEngine.CIContext"
            ]
        )
        
        print("✅ CropEngine initialized with Metal device: \(device.name)")
    }
    
    // MARK: - Public Methods
    
    /// Process a video frame and apply the crop
    /// - Parameter pixelBuffer: Input video frame
    /// - Returns: Cropped and scaled pixel buffer
    nonisolated func processCrop(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        print("🔧 CropEngine.processCrop: START")
        let startTime = CACurrentMediaTime()

        // Get ALL data from main actor before doing any work
        print("🔧 CropEngine.processCrop: Getting data from main actor...")
        let (crop, outputSize, smoothingFactor) = await MainActor.run { () -> (CropRect, CGSize, Float) in
            print("🔧 CropEngine.processCrop: Inside MainActor.run, calling updateInterpolation")
            updateInterpolation()
            print("🔧 CropEngine.processCrop: updateInterpolation done, returning config")
            return (currentCrop, config.outputSize, config.transitionSmoothing)
        }
        print("🔧 CropEngine.processCrop: Got data - crop: \(crop), outputSize: \(outputSize)")

        // Create Metal textures from pixel buffers
        print("🔧 CropEngine.processCrop: Creating source texture...")
        guard let sourceTexture = makeTexture(from: pixelBuffer) else {
            print("🔧 CropEngine.processCrop: FAILED to create source texture")
            throw CropError.textureCreationFailed
        }
        print("🔧 CropEngine.processCrop: Source texture created: \(sourceTexture.width)x\(sourceTexture.height)")

        // Create output pixel buffer
        print("🔧 CropEngine.processCrop: Creating output buffer...")
        let outputBuffer = try createOutputBuffer(size: outputSize)
        print("🔧 CropEngine.processCrop: Output buffer created")

        print("🔧 CropEngine.processCrop: Creating output texture...")
        guard let outputTexture = makeTexture(from: outputBuffer) else {
            print("🔧 CropEngine.processCrop: FAILED to create output texture")
            throw CropError.textureCreationFailed
        }
        print("🔧 CropEngine.processCrop: Output texture created: \(outputTexture.width)x\(outputTexture.height)")

        // Perform Metal rendering (GPU work, all off main thread)
        print("🔧 CropEngine.processCrop: Starting Metal render...")
        try render(
            source: sourceTexture,
            destination: outputTexture,
            crop: crop,
            outputSize: outputSize,
            smoothingFactor: smoothingFactor
        )
        print("🔧 CropEngine.processCrop: Metal render complete")

        // Update stats on main actor
        let renderTime = CACurrentMediaTime() - startTime
        await MainActor.run {
            updateStats(renderTime: renderTime)
        }

        print("🔧 CropEngine.processCrop: END (took \(renderTime * 1000)ms)")
        return outputBuffer
    }
    
    /// Process using CIImage (alternative API)
    nonisolated func processCrop(_ ciImage: CIImage) async throws -> CIImage {
        // Update interpolation on main actor
        await MainActor.run {
            updateInterpolation()
        }
        
        // Get current state from main actor
        let crop = await currentCrop
        let outputSize = await config.outputSize
        
        // Use CIImage cropping (less efficient than Metal, but simpler)
        let extent = ciImage.extent
        
        // Convert normalized crop to pixel coordinates
        let cropRect = CGRect(
            x: crop.origin.x * extent.width,
            y: crop.origin.y * extent.height,
            width: crop.size.width * extent.width,
            height: crop.size.height * extent.height
        )
        
        // Crop and scale
        let cropped = ciImage.cropped(to: cropRect)
        let scaled = cropped.transformed(by: CGAffineTransform(
            scaleX: outputSize.width / cropRect.width,
            y: outputSize.height / cropRect.height
        ))
        
        return scaled
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
        isInterpolating = false
    }
    
    // MARK: - Private Methods
    
    private func updateInterpolation() {
        guard isInterpolating else { return }
        
        // Smooth interpolation using configurable factor
        currentCrop = currentCrop.lerp(
            to: targetCrop,
            factor: config.transitionSmoothing
        )
        
        // Check if we're close enough to stop interpolating
        let threshold: CGFloat = 0.001
        if abs(currentCrop.origin.x - targetCrop.origin.x) < threshold &&
           abs(currentCrop.origin.y - targetCrop.origin.y) < threshold &&
           abs(currentCrop.size.width - targetCrop.size.width) < threshold &&
           abs(currentCrop.size.height - targetCrop.size.height) < threshold {
            currentCrop = targetCrop
            isInterpolating = false
        }
    }
    
    private nonisolated func render(
        source: MTLTexture,
        destination: MTLTexture,
        crop: CropRect,
        outputSize: CGSize,
        smoothingFactor: Float
    ) throws {
        print("🔧 render: START")
        print("🔧 render: source texture: \(source.width)x\(source.height)")
        print("🔧 render: destination texture: \(destination.width)x\(destination.height)")
        print("🔧 render: outputSize: \(outputSize)")

        print("🔧 render: Creating command buffer...")
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("🔧 render: FAILED to create command buffer")
            throw CropError.renderingFailed
        }
        print("🔧 render: Command buffer created")

        print("🔧 render: Creating compute encoder...")
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            print("🔧 render: FAILED to create compute encoder")
            throw CropError.renderingFailed
        }
        print("🔧 render: Compute encoder created")

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)

        // Prepare crop parameters
        var params = CropParams(
            cropOrigin: SIMD2<Float>(Float(crop.origin.x), Float(crop.origin.y)),
            cropSize: SIMD2<Float>(Float(crop.size.width), Float(crop.size.height)),
            outputSize: SIMD2<UInt32>(
                UInt32(outputSize.width),
                UInt32(outputSize.height)
            ),
            smoothingFactor: smoothingFactor
        )
        print("🔧 render: CropParams - origin: \(params.cropOrigin), size: \(params.cropSize), output: \(params.outputSize)")

        encoder.setBytes(&params, length: MemoryLayout<CropParams>.size, index: 0)

        // Calculate threadgroup sizes
        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadgroupSize = MTLSize(width: w, height: h, depth: 1)
        print("🔧 render: threadgroupSize: \(threadgroupSize)")

        // Calculate grid size
        let gridSize = MTLSize(
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            depth: 1
        )
        print("🔧 render: gridSize: \(gridSize)")

        // Check if device supports non-uniform threadgroups
        print("🔧 render: Dispatching threads...")
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        print("🔧 render: Encoder ended, committing...")

        commandBuffer.commit()
        print("🔧 render: Committed, waiting for completion...")

        // Wait and check for errors - THIS IS LIKELY WHERE IT HANGS
        commandBuffer.waitUntilCompleted()
        print("🔧 render: Completed!")

        if let error = commandBuffer.error {
            print("❌ Metal command buffer error: \(error)")
            throw CropError.renderingFailed
        }
        print("🔧 render: END (success)")
    }
    
    private nonisolated func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &texture
        )
        
        guard result == kCVReturnSuccess,
              let cvTexture = texture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    private nonisolated func createOutputBuffer(size: CGSize) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
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

/// Crop parameters struct (must match Metal shader layout exactly)
/// Metal aligns structs to 16-byte boundaries, so we need padding
struct CropParams {
    var cropOrigin: SIMD2<Float>      // 8 bytes (offset 0)
    var cropSize: SIMD2<Float>        // 8 bytes (offset 8)
    var outputSize: SIMD2<UInt32>     // 8 bytes (offset 16)
    var smoothingFactor: Float        // 4 bytes (offset 24)
    var _padding: Float = 0           // 4 bytes (offset 28) - padding to reach 32 bytes
}

enum CropError: LocalizedError {
    case textureCreationFailed
    case bufferCreationFailed
    case renderingFailed
    
    var errorDescription: String? {
        switch self {
        case .textureCreationFailed: return "Failed to create Metal texture"
        case .bufferCreationFailed: return "Failed to create output buffer"
        case .renderingFailed: return "Metal rendering failed"
        }
    }
}
