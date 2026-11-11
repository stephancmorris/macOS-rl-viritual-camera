//
//  CropEngine.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
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

    nonisolated struct Config: Sendable, Equatable {
        /// Output resolution (default: 1920x1080 for ATEM)
        var outputSize: CGSize = CGSize(width: 1920, height: 1080)

        /// Spring stiffness for crop motion. 0.10 is the default (k = 60).
        /// Higher is stiffer and snaps faster. The UI range is about 0.05–0.30.
        var transitionSmoothing: Float = 0.10

        /// Lanczos resampling on strong downscales (see `processCrop`). Off,
        /// every frame uses the cheaper bilinear transform.
        var useHighQuality: Bool = true
    }

    /// The motion state itself: target, spring, zoom, pan and quality floor
    /// (D-02 path 2). A plain class with its own lock, so a camera's capture
    /// queue steps it per frame without the main thread. Everything below
    /// that reads or moves the crop forwards to it.
    nonisolated let motion = CropMotionCore()

    /// Operator settings. Published for the settings forms, so the frame path
    /// must not write it per frame; see `applyFrameSmoothing`.
    @Published var config = Config() {
        didSet { motion.settings = config }
    }

    /// Smoothing for the current frame, chosen by the frame path (fast-framing
    /// boost, ML agent, or the operator's setting). Plain storage: it changes
    /// at capture rate, and a publish per frame would also overwrite the Crop
    /// Settings slider. Nil uses `config.transitionSmoothing`.
    var liveSmoothing: Float? {
        get { motion.liveSmoothing }
        set { motion.liveSmoothing = newValue }
    }

    /// Frame-path entry: set this frame's smoothing and mirror the operator's
    /// setting into `config` only when that setting changed.
    func applyFrameSmoothing(_ live: Float, operatorSetting: Float) {
        motion.liveSmoothing = live
        if config.transitionSmoothing != operatorSetting { config.transitionSmoothing = operatorSetting }
    }

    // MARK: - State (read through to the motion core)

    /// Current crop rectangle (normalized 0-1 coordinates). Logic readers
    /// (CameraManager, training recorder, ML agent) read this. UI reads the
    /// 15 Hz `displayedCrop` mirror.
    var currentCrop: CropRect { motion.currentCrop }

    /// Target crop rectangle (where the spring is heading). Assigning it
    /// directly skips the quality floor; use `setTargetCrop`.
    var targetCrop: CropRect {
        get { motion.targetCrop }
        set { motion.targetCrop = newValue; syncMirrors() }
    }

    /// 15 Hz UI mirror of `currentCrop` for the crop-indicator overlay
    /// (see `publishDisplayMirror`).
    @Published private(set) var displayedCrop: CropRect?

    /// Published copy of the core's flags. The core changes them on the
    /// capture queue; this copy is refreshed after every main-thread call and
    /// by the 15 Hz mirror timer, so views observing the engine redraw. Logic
    /// reads the properties below, which always return the core's value.
    @Published private(set) var motionFlags = CropMotionCore.Flags()

    var hasZoomAdjustment: Bool { motion.currentFlags.hasZoomAdjustment }
    var isZoomLimited: Bool { motion.currentFlags.isZoomLimited }
    var zoomDirection: OperatorCommand.ZoomDirection? { motion.currentFlags.zoomDirection }
    /// Whether the spring is still moving toward the target.
    var isInterpolating: Bool { motion.currentFlags.isInterpolating }

    private var publishedCropStateRevision: UInt64 = 0
    private var displayMirrorTimer: Timer?

    private func syncMirrors() {
        let flags = motion.currentFlags
        if motionFlags != flags { motionFlags = flags }
    }

    private func publishDisplayMirror() {
        syncMirrors()
        let revision = motion.revision
        if publishedCropStateRevision != revision {
            publishedCropStateRevision = revision
            displayedCrop = motion.currentCrop
        }
        let now = CACurrentMediaTime()
        if now - lastStatsPublish >= statsPublishInterval {
            lastStatsPublish = now
            let latest = motion.renderStats
            if stats != latest { stats = latest }
        }
    }

    /// Resolution-derived quality floor. Updated from the *actual delivered*
    /// frame resolution (not the advertised capture format). Defaults to
    /// `.unconstrained` until the first frame sets it.
    var qualityFloor: QualityFloor {
        get { motion.qualityFloor }
        set { motion.qualityFloor = newValue }
    }

    /// Assign the target with the quality floor applied (see
    /// `CropMotionCore.setTargetCrop`).
    func setTargetCrop(_ crop: CropRect) {
        motion.setTargetCrop(crop)
        syncMirrors()
    }

    var zoomUsesTopAnchor: Bool {
        get { motion.zoomUsesTopAnchor }
        set { motion.zoomUsesTopAnchor = newValue }
    }
    var adjustedHeight: CGFloat? { motion.adjustedHeight }
    var zoomHasLanded: Bool { motion.zoomHasLanded }

    func adoptVisibleSize(from visible: CropRect? = nil) {
        motion.adoptVisibleSize(from: visible)
        syncMirrors()
    }

    func beginZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                   visibleCrop: CropRect? = nil) {
        motion.beginZoom(direction, to: height, visibleCrop: visibleCrop)
        syncMirrors()
    }

    @discardableResult
    func beginDirectorZoom(_ direction: OperatorCommand.ZoomDirection, to height: CGFloat,
                           maximumRate: Double, visibleCrop: CropRect) -> Bool {
        let began = motion.beginDirectorZoom(direction, to: height, maximumRate: maximumRate, visibleCrop: visibleCrop)
        syncMirrors()
        return began
    }

    /// Stop at the visible size; a later push/pull starts a fresh shot move.
    func endZoom() {
        motion.endZoom()
        syncMirrors()
    }

    func clearZoomAdjustment() {
        motion.clearZoomAdjustment()
        syncMirrors()
    }

    func advanceZoom(now: TimeInterval, aspect: CGFloat) {
        motion.advanceZoom(now: now, aspect: aspect)
        syncMirrors()
    }

    /// Pan position is deterministic; size is advanced separately above.
    func placePan(center: CGPoint, baseSize: CGSize) {
        motion.placePan(center: center, baseSize: baseSize)
        syncMirrors()
    }

    /// Performance statistics, republished from the core at most every
    /// `statsPublishInterval` so the render loop never invalidates SwiftUI.
    @Published private(set) var stats: Stats = .init()

    nonisolated struct Stats: Sendable, Equatable {
        var lastRenderTime: TimeInterval = 0
        var averageRenderTime: TimeInterval = 0
        var totalFramesRendered: Int = 0
    }

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
    nonisolated struct QualityFloor: Sendable, Equatable {
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

    nonisolated struct CropRect: Equatable, Sendable {
        /// Normalized coordinates (0-1)
        var origin: CGPoint  // Bottom-left corner (Vision coordinate system)
        var size: CGSize     // Width and height
        
        var center: CGPoint { CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2) }
        init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
        init(center: CGPoint, size: CGSize) {
            self.init(origin: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), size: size)
        }

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

        /// Clamp crop to valid 0-1 range
        func clamped() -> CropRect {
            let clampedWidth = max(0.001, min(1, size.width))
            let clampedHeight = max(0.001, min(1, size.height))
            let clampedX = max(0, min(1 - clampedWidth, origin.x))
            let clampedY = max(0, min(1 - clampedHeight, origin.y))

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

    isolated deinit {
        displayMirrorTimer?.invalidate()
    }

    // MARK: - Public Methods
    // MARK: - Public Methods

    /// Advance the spring toward the target, then snapshot what a render
    /// needs. The frame loop steps the core directly on the capture queue;
    /// this is the main-thread entry tests use.
    func tickInterpolation(now: TimeInterval = CACurrentMediaTime()) -> (crop: CropRect, outputSize: CGSize, smoothingFactor: Float, highQuality: Bool) {
        let snapshot = motion.tick(now: now)
        syncMirrors()
        return (snapshot.crop, snapshot.outputSize, snapshot.smoothingFactor, snapshot.highQuality)
    }

    /// Serial queue for crop renders. The render used to run synchronously on
    /// the MainActor, so a 4K Lanczos downscale held the one thread the
    /// capture gate waits on (20 ms budget at 50 Hz). Serial here keeps frames
    /// rendering in order and one at a time — the capture gate already
    /// guarantees a single frame in flight, so there is no queueing latency.
    ///
    /// One queue per engine, so per camera (D-02 path 1): cameras render side
    /// by side instead of taking turns on one shared queue.
    private nonisolated let renderQueue = DispatchQueue(
        label: "com.cinematiccore.cropRender",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )

    /// One Lanczos filter reused for every strong downscale instead of one
    /// allocation per frame. `CIFilter` is not thread-safe; it is touched only
    /// from `renderQueue` (serial), inside `processCrop`. Nil if Core Image
    /// does not provide the filter, in which case the bilinear path is used.
    /// Per engine, like the queue: a shared filter would be mutated from two
    /// cameras' queues at once.
    private nonisolated(unsafe) let lanczosFilter = CIFilter(name: "CILanczosScaleTransform")

    /// Carries the source buffer onto `renderQueue`. `CVPixelBuffer` is not
    /// `Sendable`; this is safe because the frame path hands the buffer over
    /// and does not touch it again until the render returns (the capture gate
    /// keeps one frame in flight), and the box's reference keeps the capture
    /// pool from reclaiming it meanwhile.
    private nonisolated struct RenderSource: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
    }

    /// Off-MainActor crop render. Snapshot (crop rect + output size) must have
    /// been taken on the MainActor via `tickInterpolation()` first; only the
    /// Core Image render runs on `renderQueue`. Safety notes: CIContext is
    /// thread-safe; the source buffer is retained for the duration of the
    /// render (capture-pool recycling cannot reclaim it while we hold a
    /// reference); the output pool is NSLock-guarded; and the capture gate
    /// serializes frames, so two renders can never overlap.
    nonisolated func renderCrop(
        _ pixelBuffer: CVPixelBuffer,
        crop: CropRect,
        outputSize: CGSize,
        highQuality: Bool = true
    ) async throws -> CVPixelBuffer {
        let source = RenderSource(pixelBuffer: pixelBuffer)
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    let buffer = try self.processCrop(source.pixelBuffer, crop: crop, outputSize: outputSize, highQuality: highQuality)
                    continuation.resume(returning: buffer)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Crop and scale a video frame using CoreImage. This is the synchronous
    /// render core — the frame path calls it via `renderCrop`, which hops to a
    /// serial render queue so it never occupies the MainActor. (See git history
    /// for the Metal compute path that this replaces; it hit an Apple Silicon
    /// GPU power-state issue where isolated compute kernels were scheduled into
    /// a 30-45ms idle slot.) Runs on `renderQueue` only.
    private nonisolated func processCrop(
        _ pixelBuffer: CVPixelBuffer,
        crop: CropRect,
        outputSize: CGSize,
        highQuality: Bool
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
        if highQuality, min(scaleX, scaleY) < lanczosScaleThreshold, let lanczos = lanczosFilter {
            // Strong downscale: Lanczos. `scale` sets the vertical factor;
            // `aspectRatio` adds any extra horizontal stretch when the crop's
            // aspect differs from the output's (possible during interpolation).
            lanczos.setValue(translated, forKey: kCIInputImageKey)
            lanczos.setValue(scaleY, forKey: kCIInputScaleKey)
            lanczos.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
            scaled = lanczos.outputImage ?? translated.transformed(
                by: CGAffineTransform(scaleX: scaleX, y: scaleY)
            )
            // The output image already holds the graph; drop the filter's own
            // reference so the cached filter does not keep the source buffer.
            lanczos.setValue(nil, forKey: kCIInputImageKey)
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

    /// Diagnostic A/B hook: drop Core Image's internal caches for the crop
    /// renderer. NOT the memory fix — this context already runs with
    /// `cacheIntermediates: false`. Kept only so a soak can A/B
    /// `DeveloperFlags.imageCacheFlushInterval`; keep it off (interval 0).
    nonisolated func flushImageCaches() {
        ciContext.clearCaches()
    }

    /// Reset to a wide shot. Pass the composer's `normalizedAspect` for an
    /// aspect-correct widest crop (largest output-aspect region of the source);
    /// omit it only when an exact full-frame source rect is genuinely wanted
    /// (note: that stretches a non-output-aspect source when rendered).
    func resetToFullFrame(aspect: CGFloat? = nil) {
        motion.resetToFullFrame(aspect: aspect)
        syncMirrors()
    }

    /// Jump to target immediately (no smooth transition)
    func jumpToTarget() {
        motion.jumpToTarget()
        syncMirrors()
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
