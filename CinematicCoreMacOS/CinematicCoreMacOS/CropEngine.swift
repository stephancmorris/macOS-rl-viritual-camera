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

    /// Current crop rectangle (normalized 0-1 coordinates). Plain per-frame
    /// storage — written every interpolation tick; logic readers (CameraManager,
    /// training recorder, ML agent) read this. UI reads the 15 Hz
    /// `displayedCrop` mirror.
    private(set) var currentCrop: CropRect = .fullFrame {
        didSet { cropStateRevision &+= 1 }
    }

    /// Target crop rectangle (where we're smoothly transitioning to).
    ///
    /// Every assignment is clamped against `qualityFloor` so no caller — ML
    /// agent, rule-based composer, manual crop, or auto-pan — can request a
    /// crop tighter than the floor. This is the single chokepoint all four
    /// modes pass through. Plain per-frame storage (reassigned on every
    /// accepted compose frame) — never published.
    var targetCrop: CropRect = .fullFrame {
        didSet {
            cropStateRevision &+= 1
            // Automatically start interpolating. Compare-before-write:
            // an unguarded write here would fire an extra objectWillChange
            // per frame even though the value is already true.
            if !isInterpolating { isInterpolating = true }
        }
    }

    /// 15 Hz UI mirror of `currentCrop` for the crop-indicator overlay
    /// (see `publishDisplayMirror`).
    @Published private(set) var displayedCrop: CropRect?

    /// Bumped on every per-frame crop write; the 15 Hz coalescer republishes
    /// the mirror only when it moved.
    private var cropStateRevision: UInt64 = 0
    private var publishedCropStateRevision: UInt64 = 0
    private var displayMirrorTimer: Timer?

    private func publishDisplayMirror() {
        guard publishedCropStateRevision != cropStateRevision else { return }
        publishedCropStateRevision = cropStateRevision
        displayedCrop = currentCrop
    }

    /// Resolution-derived quality floor. Updated from the *actual delivered*
    /// frame resolution (not the advertised capture format). Defaults to
    /// `.unconstrained` until the first frame sets it.
    var qualityFloor: QualityFloor = .unconstrained

    /// Assign `targetCrop` with the quality floor applied. Use this instead of
    /// setting `targetCrop` directly so over-tight crops are enlarged back to
    /// the floor (re-centered) before interpolation.
    func setTargetCrop(_ crop: CropRect) {
        targetCrop = crop.clampedToQualityFloor(qualityFloor)
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

    /// Per-frame stats accumulate here (plain storage); the @Published `stats`
    /// snapshot is republished at most every `statsPublishInterval` so the
    /// 50 fps render loop doesn't fire SwiftUI invalidations on every frame.
    private var statsAccumulator: Stats = .init()
    private var lastStatsPublish: TimeInterval = 0
    private let statsPublishInterval: TimeInterval = 0.5

    // MARK: - Rendering Resources

    private let device: MTLDevice
    private let ciContext: CIContext

    /// Reused pool of output buffers. Allocating a fresh CVPixelBuffer every frame
    /// (50/sec) churns IOSurfaces and shows up in the per-frame budget; the pool
    /// recycles buffers of the current output size instead. Lives in its own
    /// `nonisolated` Sendable box so `processCrop` (which is `nonisolated`) can
    /// reach it without an actor hop.
    private let outputBufferPool = OutputBufferPool()


    // MARK: - Quality Floor

    /// Resolution-derived lower bound on how small a crop may be — a safety
    /// net against degenerate zooms, NOT a sharpness guarantee.
    ///
    /// Subject-relative framing wins over resolution purity: on a real stage a
    /// distant speaker's Waist Up shot needs a crop far tighter than one
    /// resolution tier down, and the old one-tier rule (4K→1080p, 1080p→720p)
    /// forced every tight preset to balloon into the same ~⅔-frame crop. The
    /// floor now allows up to ~4× linear zoom (crop height ≥ source/4, never
    /// below 240 px); anything tighter than the *old* comfort tier is surfaced
    /// to the operator as "ZOOM LIMITED"/soft-zoom territory by the composer.
    ///
    /// This is the single source of truth for the floor; `CinematicAgent`
    /// delegates to it.
    struct QualityFloor: Sendable, Equatable {
        /// Smallest allowed normalized crop *height* (0–1).
        var minCropHeightFraction: CGFloat

        /// No source info yet (or no constraint): allow the full zoom range.
        static let unconstrained = QualityFloor(minCropHeightFraction: 0.0)

        /// Map source pixel height to the quality floor: max ~4× linear zoom,
        /// with an absolute 240 px minimum crop height.
        static func forSource(height: Int) -> QualityFloor {
            guard height > 0 else { return .unconstrained }
            let minCropHeight = max(height / 4, 240)
            return QualityFloor(
                minCropHeightFraction: min(1.0, CGFloat(minCropHeight) / CGFloat(height))
            )
        }
    }

    // MARK: - Crop Rectangle Model

    struct CropRect: Equatable, Sendable {
        /// Normalized coordinates (0-1)
        var origin: CGPoint  // Bottom-left corner (Vision coordinate system)
        var size: CGSize     // Width and height
        
        /// Full frame (no crop). NOTE: this is the entire source rectangle. On a
        /// source whose pixel aspect differs from the output, rendering this to
        /// the output buffer *stretches* the image. For an aspect-correct wide
        /// shot use `widest(aspect:)` with the composer's `normalizedAspect`.
        static let fullFrame = CropRect(
            origin: CGPoint(x: 0, y: 0),
            size: CGSize(width: 1, height: 1)
        )

        /// Largest centered crop with the given normalized aspect (w/h) that
        /// fits inside the [0,1] source canvas. This is the aspect-correct
        /// "wide" shot — it crops off the source's excess height or width so the
        /// rendered output keeps correct proportions instead of stretching.
        ///
        /// `aspect` is the *normalized* crop aspect (`outputAspect / sourcePixelAspect`),
        /// not the raw output aspect.
        static func widest(aspect: CGFloat) -> CropRect {
            guard aspect > 0 else { return .fullFrame }
            var w: CGFloat = 1.0
            var h = w / aspect
            if h > 1.0 {
                h = 1.0
                w = h * aspect
            }
            return CropRect(
                origin: CGPoint(x: (1 - w) / 2, y: (1 - h) / 2),
                size: CGSize(width: w, height: h)
            )
        }

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

        /// Enlarge a too-tight crop back up to the quality floor, preserving the
        /// crop's *own* width:height ratio and center, then re-fit inside the
        /// [0,1] canvas. Crops already at or above the floor are returned
        /// unchanged.
        ///
        /// Scaling both dimensions by the same factor (rather than imposing an
        /// external aspect) is what keeps this correct in any source pixel
        /// aspect — the incoming crop already encodes the right normalized
        /// aspect for the current source, and we must not distort it.
        func clampedToQualityFloor(_ floor: QualityFloor) -> CropRect {
            guard size.height > 0, floor.minCropHeightFraction > size.height else { return self }

            let centerX = origin.x + size.width / 2
            let centerY = origin.y + size.height / 2

            // Uniform scale to bring height up to the floor; width follows so
            // the aspect is unchanged. Cap so neither dimension exceeds 1.0.
            var scale = floor.minCropHeightFraction / size.height
            let maxScale = min(
                size.width  > 0 ? 1.0 / size.width  : .greatestFiniteMagnitude,
                1.0 / size.height
            )
            scale = min(scale, maxScale)

            let w = size.width * scale
            let h = size.height * scale

            let originX = max(0, min(1 - w, centerX - w / 2))
            let originY = max(0, min(1 - h, centerY - h / 2))

            return CropRect(
                origin: CGPoint(x: originX, y: originY),
                size: CGSize(width: w, height: h)
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

        displayMirrorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishDisplayMirror()
            }
        }
    }

    deinit {
        displayMirrorTimer?.invalidate()
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

        // Adaptive resampling. Lanczos's cost scales with the *input* area it
        // filters, not with the scale factor: the wide shot (full 4K frame down
        // to 1080p) is the most expensive case, and on a 4K source the quality
        // floor guarantees every frame is a downscale — so an upscale-only
        // cheap path would be dead code. Lanczos's anti-aliasing only pays off
        // visually on strong shrinks; for mild downscales and the rare upscale
        // (capped ≈2× by the quality floor) the difference from bilinear is
        // marginal, so take the cheap transform there.
        //
        // Frames shrunk by more than this factor get Lanczos; everything else
        // uses the bilinear affine transform. Tune against the `cropRender`
        // stage latency on the rig — if the wide-shot Lanczos still blows the
        // 20 ms budget, lower the threshold (or move to MPSImageLanczosScale).
        let lanczosScaleThreshold: CGFloat = 0.7
        let scaleY = outputSize.height / cropRect.height
        let scaleX = outputSize.width / cropRect.width
        let scaled: CIImage
        if min(scaleX, scaleY) < lanczosScaleThreshold {
            // Strong downscale: Lanczos. `scale` sets the vertical factor;
            // `aspectRatio` adds any extra horizontal stretch when the crop's
            // aspect differs from the output's (possible during interpolation).
            let lanczos = CIFilter(name: "CILanczosScaleTransform")!
            lanczos.setValue(translated, forKey: kCIInputImageKey)
            lanczos.setValue(scaleY, forKey: kCIInputScaleKey)
            lanczos.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
            scaled = lanczos.outputImage ?? translated.transformed(
                by: CGAffineTransform(scaleX: scaleX, y: scaleY)
            )
        } else {
            // Mild downscale or upscale: cheap bilinear.
            scaled = translated.transformed(
                by: CGAffineTransform(scaleX: scaleX, y: scaleY)
            )
        }

        let outputBuffer = try outputBufferPool.dequeue(size: outputSize)
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
    /// isn't blocked on SwiftUI updates. Accumulates every frame but only
    /// republishes the @Published snapshot at `statsPublishInterval`.
    @MainActor
    func publishRenderStats(renderTime: TimeInterval) {
        updateStats(renderTime: renderTime)
        let now = CACurrentMediaTime()
        if now - lastStatsPublish >= statsPublishInterval {
            lastStatsPublish = now
            stats = statsAccumulator
        }
    }


    /// Set crop to frame a detected person with smooth transition
    func framePerson(_ person: PersonDetector.DetectedPerson, padding: CGFloat = 0.15) {
        setTargetCrop(
            CropRect.framing(
                boundingBox: person.boundingBox,
                padding: padding
            ).clamped()
        )
    }
    
    /// Reset to a wide shot. Pass the composer's `normalizedAspect` for an
    /// aspect-correct widest crop (largest output-aspect region of the source);
    /// omit it only when an exact full-frame source rect is genuinely wanted
    /// (note: that stretches a non-output-aspect source when rendered).
    func resetToFullFrame(aspect: CGFloat? = nil) {
        if let aspect {
            targetCrop = .widest(aspect: aspect)
        } else {
            targetCrop = .fullFrame
        }
    }
    
    /// Jump to target immediately (no smooth transition)
    func jumpToTarget() {
        currentCrop = targetCrop
        velocityOrigin = .zero
        velocitySize = .zero
        if isInterpolating { isInterpolating = false }
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
    
    private func updateStats(renderTime: TimeInterval) {
        statsAccumulator.lastRenderTime = renderTime
        statsAccumulator.totalFramesRendered += 1

        // Running average
        let alpha: TimeInterval = 0.1
        statsAccumulator.averageRenderTime = (alpha * renderTime) + ((1 - alpha) * statsAccumulator.averageRenderTime)
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

/// Recycles render output buffers of the current output size. `processCrop` runs
/// `nonisolated`, so this lives in its own `@unchecked Sendable` box with an
/// internal lock rather than on the MainActor-isolated `CropEngine`. The explicit
/// `nonisolated` matters: the module compiles with default MainActor isolation,
/// which would otherwise put `dequeue` back on the MainActor and make every call
/// from `processCrop` a cross-actor hop.
private nonisolated final class OutputBufferPool: @unchecked Sendable {
    private let lock = NSLock()
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    /// Vend a recycled buffer, rebuilding the pool when the output size changes.
    /// Falls back to a one-off allocation if the pool can't be created or is exhausted.
    func dequeue(size: CGSize) throws -> CVPixelBuffer {
        lock.lock()
        defer { lock.unlock() }

        if pool == nil || poolSize != size {
            let bufferAttributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            let poolAttributes: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 6
            ]
            var newPool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttributes as CFDictionary,
                bufferAttributes as CFDictionary,
                &newPool
            )
            if status == kCVReturnSuccess, let newPool {
                pool = newPool
                poolSize = size
            } else {
                pool = nil
                poolSize = .zero
            }
        }

        if let pool {
            var pixelBuffer: CVPixelBuffer?
            if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
               let buffer = pixelBuffer {
                return buffer
            }
        }

        // Pool unavailable/exhausted — fall back to a direct allocation.
        return try Self.allocateBuffer(size: size)
    }

    private static func allocateBuffer(size: CGSize) throws -> CVPixelBuffer {
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
}
