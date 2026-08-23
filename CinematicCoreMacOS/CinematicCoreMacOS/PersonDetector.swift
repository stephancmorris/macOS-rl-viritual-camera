//
//  PersonDetector.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/4/2026.
//

@preconcurrency import Vision
import CoreImage
import CoreVideo
import Combine
import QuartzCore
import OSLog

/// Detects and tracks people in video frames using Apple Vision framework
/// Ticket: VIS-01 - Person Detection
@MainActor
final class PersonDetector: ObservableObject {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Vision")
    private nonisolated static let signposter = OSSignposter(logger: logger)
    
    // MARK: - Published Properties

    /// Currently detected persons with bounding boxes. Plain per-frame
    /// storage — every synchronous logic reader (CameraManager, composer)
    /// reads this; UI reads the 15 Hz `displayedPersons` mirror.
    private(set) var detectedPersons: [DetectedPerson] = []

    /// Detection statistics. Plain per-frame storage — logic readers
    /// (CameraManager.recordDetectionTiming) read this; UI reads
    /// `displayedStats`.
    private(set) var stats: DetectionStats = .init()

    /// 15 Hz UI mirror of `detectedPersons` (see `publishDisplayMirrors`).
    @Published private(set) var displayedPersons: [DetectedPerson] = []

    /// 15 Hz UI mirror of `stats`.
    @Published private(set) var displayedStats: DetectionStats = .init()

    /// Bumped on every per-frame write of `detectedPersons` / `stats`; the
    /// 15 Hz coalescer republishes the mirrors only when it moved.
    private var frameStateRevision: UInt64 = 0
    private var publishedFrameStateRevision: UInt64 = 0
    private var displayMirrorTimer: Timer?

    private func publishDisplayMirrors() {
        guard publishedFrameStateRevision != frameStateRevision else { return }
        publishedFrameStateRevision = frameStateRevision
        displayedPersons = detectedPersons
        displayedStats = stats
    }

    // MARK: - Models

    /// Body pose keypoints for rule-of-thirds composition (Task 2.3 - LOGIC-01)
    struct PoseKeypoints: Sendable {
        /// Head position in normalized Vision coordinates (0-1, bottom-left origin)
        let head: CGPoint
        /// Waist/hip position in normalized Vision coordinates
        let waist: CGPoint
        /// Confidence of the pose observation (0-1)
        let confidence: Float
    }

    struct DetectedPerson: Identifiable, Sendable {
        let id: UUID
        let boundingBox: CGRect // Normalized coordinates (0-1)
        let confidence: Float
        let timestamp: TimeInterval
        let poseKeypoints: PoseKeypoints? // nil when pose detection fails
        /// Face bbox in normalized Vision coordinates (bottom-left origin),
        /// when a face was detected inside this person's body bbox.
        /// Consumed by FaceSignatureExtractor for identity capture and
        /// re-acquisition. Nil if the subject is facing away or Vision
        /// could not find a face this frame.
        let faceBoundingBox: CGRect?
        /// Pose-invariant geometry ratios derived from the face landmarks
        /// (eyes / nose / mouth) of the matched face. Used during
        /// re-acquisition as a veto signal — see `LandmarkRatios`. Nil
        /// when landmarks couldn't be extracted (face turned, partly
        /// occluded, or the face wasn't matched to this body).
        let faceLandmarkRatios: LandmarkRatios?

        /// Convert normalized rect to pixel coordinates
        func pixelBoundingBox(imageSize: CGSize) -> CGRect {
            CGRect(
                x: boundingBox.origin.x * imageSize.width,
                y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height, // Vision uses bottom-left origin
                width: boundingBox.width * imageSize.width,
                height: boundingBox.height * imageSize.height
            )
        }
    }
    
    struct DetectionStats: Sendable {
        var totalFramesProcessed: Int = 0
        var averageDetectionTime: TimeInterval = 0
        var lastDetectionTime: TimeInterval = 0
        /// How long the detection block waited on `processingQueue` before it
        /// started running — soak diagnostic separating "Vision got slower"
        /// from "the queue upstream got congested".
        var lastQueueWait: TimeInterval = 0
        var personsDetectedCount: Int = 0
    }

    // MARK: - Detection gating

    /// How detection should run this frame. The pipeline is passive by
    /// default — full-frame multi-person scanning never happens. Vision runs
    /// only when a subject is being selected, acquired, or tracked, and then
    /// only over a region of interest around that one person.
    enum DetectionMode: Sendable, Equatable {
        /// No subject and the operator hasn't tapped Detect — skip Vision entirely.
        case off
        /// Operator tapped Detect; preview shows a tap affordance. Still no Vision.
        case awaitingTap
        /// Operator tapped a point; scan a ROI around it to find + acquire the
        /// single person there (rect + pose + face for gallery fill).
        case acquiring
        /// Subject locked; scan a ROI around their last box. Runs rect + pose
        /// ONLY — the per-frame face request is dropped to save a full
        /// inference per frame. The gallery still refreshes after lock via a
        /// throttled `.acquiring` scan (roughly once per capture spacing, see
        /// `ShotComposer.shouldRunGalleryRefreshScan()`), and re-acquisition
        /// runs faces full-frame in `.reacquiring`.
        case lockedROI
        /// Subject lost and we're wide; face request runs full-frame so a
        /// returning subject can be re-acquired anywhere in the frame.
        case reacquiring
    }

    /// What to run this frame and where. `roi` is a normalized Vision rect
    /// (bottom-left origin) used by `.acquiring` and `.lockedROI`; ignored by
    /// the other modes.
    struct DetectionRequestPlan: Sendable {
        var mode: DetectionMode
        var roi: CGRect?

        static let off = DetectionRequestPlan(mode: .off, roi: nil)

        /// Whether this plan actually runs Vision. `.off` and `.awaitingTap`
        /// return early in `processFrame` without any inference, so they carry
        /// none of the sustained load that the progressive-lag investigation is
        /// about.
        var runsVision: Bool {
            switch mode {
            case .off, .awaitingTap: return false
            case .acquiring, .lockedROI, .reacquiring: return true
            }
        }
    }
    
    // MARK: - Configuration
    
    struct Config: Sendable {
        /// Minimum confidence threshold (0-1)
        var confidenceThreshold: Float = 0.5
        
        /// Maximum number of persons to track
        var maxPersons: Int = 5
        
        /// Use high accuracy mode (slower but more accurate)
        var useHighAccuracy: Bool = false
    }
    
    var config = Config()
    
    // MARK: - Private Properties
    
    private let processingQueue = DispatchQueue(
        label: "com.cinematiccore.personDetection",
        qos: .userInitiated,
        // `.workItem` drains the autorelease pool after every job. Without it
        // the queue inherits its thread's pool, so objects created per frame
        // stay alive until the thread happens to be recycled — measured 26 July
        // as ~40 retained allocations per frame, released in irregular bulk
        // drops minutes apart, each drop restoring 50 fps instantly.
        autoreleaseFrequency: .workItem
    )

    // MARK: - Vision input downscale
    //
    // Vision's person/pose/face models run on an internally normalized input;
    // feeding them the full 4K capture buffer wastes decode/resample work and
    // memory bandwidth every frame. Buffers taller than 1440 px are GPU-scaled
    // to 1080 px height (aspect-preserving) before the VNImageRequestHandler.
    // Results are normalized (0-1), so NOTHING downstream changes — the
    // full-res buffer still flows to crop/output and face-signature capture.
    //
    // All of this state is touched ONLY from `processingQueue` (a serial
    // queue), hence the `nonisolated(unsafe)` — the class is MainActor by
    // default and the detection closure is nonisolated.

    /// Metal-backed context for the downscale render. Working color space nil:
    /// detection doesn't care about color accuracy, skip the conversion.
    nonisolated(unsafe) private static let downscaleContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: NSNull(),
        // This context renders a fresh 1080p proxy on every detection and never
        // reuses an intermediate, so caching them only accumulates. CropEngine's
        // context already runs this way.
        .cacheIntermediates: false
    ])

    /// Source height above which detection input is downscaled to 1080 px.
    nonisolated static let downscaleTriggerHeight = 1440
    /// Target height for downscaled detection input.
    nonisolated static let downscaleTargetHeight = 1080

    /// Pool of BGRA, IOSurface-backed, Metal-compatible target buffers.
    /// Rebuilt lazily whenever the target dimensions change.
    nonisolated(unsafe) private var downscalePool: CVPixelBufferPool?
    nonisolated(unsafe) private var downscalePoolWidth = 0
    nonisolated(unsafe) private var downscalePoolHeight = 0
    nonisolated(unsafe) private var loggedDownscaleFailure = false

    /// Returns a ≤1080p buffer for Vision, or the original buffer when it is
    /// already small enough or the downscale fails (logged once). Runs on
    /// `processingQueue` inside the existing detection timing, so the [SOAK]
    /// visionWall metric includes the scale cost.
    private nonisolated func downscaledForDetection(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        let srcHeight = CVPixelBufferGetHeight(buffer)
        guard srcHeight > Self.downscaleTriggerHeight else { return buffer }
        let srcWidth = CVPixelBufferGetWidth(buffer)

        let targetHeight = Self.downscaleTargetHeight
        let scale = CGFloat(targetHeight) / CGFloat(srcHeight)
        var targetWidth = Int((CGFloat(srcWidth) * scale).rounded())
        if targetWidth % 2 != 0 { targetWidth += 1 } // even width

        if downscalePool == nil
            || downscalePoolWidth != targetWidth
            || downscalePoolHeight != targetHeight {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
            downscalePool = pool
            downscalePoolWidth = targetWidth
            downscalePoolHeight = targetHeight
        }

        guard let pool = downscalePool else {
            logDownscaleFailureOnce("pool creation failed")
            return buffer
        }
        var scaled: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &scaled)
        guard let scaledBuffer = scaled else {
            logDownscaleFailureOnce("pooled buffer allocation failed")
            return buffer
        }

        let image = CIImage(cvPixelBuffer: buffer)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        Self.downscaleContext.render(image, to: scaledBuffer)
        return scaledBuffer
    }

    private nonisolated func logDownscaleFailureOnce(_ reason: String) {
        guard !loggedDownscaleFailure else { return }
        loggedDownscaleFailure = true
        Self.logger.error("Vision downscale disabled (\(reason, privacy: .public)); detecting on full-resolution frames")
    }
    
    // Person tracking state
    private var trackedPersons: [UUID: TrackedPerson] = [:]
    private let trackingTimeout: TimeInterval = 1.0 // Drop tracks after 1 second

    /// UUID of the operator-locked subject, pushed from CameraManager each frame.
    /// When set, the matcher binds this track first (Pass A) via the
    /// probation + coast policy in `resolveLockedAssignment`.
    var lockedTargetID: UUID? = nil {
        didSet {
            if lockedTargetID != oldValue { lockProbation = nil }
        }
    }

    /// Probation state carried between frames for a discontinuous locked-track
    /// candidate. Cleared on lock change, stale lock, acceptance, or when the
    /// candidate stops persisting.
    private var lockProbation: LockProbation?

    // Matching thresholds for normal (non-locked) tracks.
    private static let normalIoUThreshold: CGFloat = 0.2
    private static let normalCentroidThreshold: CGFloat = 0.15

    // MARK: Locked-track matcher tunables
    //
    // Internal (not private) so the unit tests exercise the same numbers.

    /// A candidate overlapping the lock's last box by at least this IoU is the
    /// same physical object and is accepted instantly (no probation).
    nonisolated static let lockedSameObjectIoU: CGFloat = 0.30
    /// Consecutive frames a discontinuous candidate must persist before the
    /// lock re-binds (~60–100 ms at 30–50 fps).
    nonisolated static let lockedProbationFrames = 3
    /// Longer probation when the candidate is better explained by another live
    /// track (an occluder standing where the subject was).
    nonisolated static let lockedProbationFramesContested = 8
    /// The best candidate must beat the runner-up by this factor for instant
    /// acceptance; otherwise the frame is ambiguous and the lock coasts.
    nonisolated static let lockedScoreMargin: CGFloat = 1.15
    /// Base radius (normalized frame units) a stationary locked subject may
    /// move between sightings. Replaces the old fixed 0.5 gate that let the
    /// lock jump to anyone within half a frame in a single frame.
    nonisolated static let lockedBaseJumpRadius: CGFloat = 0.12
    /// Cap on the adaptive radius (base + velocity × time-unseen) so a long
    /// occlusion can't re-open the whole frame.
    nonisolated static let lockedMaxJumpRadius: CGFloat = 0.35
    
    // Cached Vision Requests
    nonisolated(unsafe) private let cachedRectRequest: VNDetectHumanRectanglesRequest = {
        let req = VNDetectHumanRectanglesRequest()
        req.upperBodyOnly = false
        return req
    }()
    
    nonisolated(unsafe) private let cachedPoseRequest: VNDetectHumanBodyPoseRequest = {
        let req = VNDetectHumanBodyPoseRequest()
        return req
    }()

    /// Face detection request — runs alongside rect + pose. Produces both
    /// the face bbox AND landmark points (eyes, nose, mouth) so the lock
    /// FSM can extract pose-invariant geometry ratios for the
    /// re-acquisition veto signal (see `LandmarkRatios`). Cost ~1 ms,
    /// roughly the same as the bbox-only request — the landmark model is
    /// fast on Apple Silicon.
    nonisolated(unsafe) private let cachedFaceRequest: VNDetectFaceLandmarksRequest = {
        let req = VNDetectFaceLandmarksRequest()
        return req
    }()
    
    private struct TrackedPerson {
        let id: UUID
        /// When this track was first created — the occluder guard only trusts
        /// tracks that have existed long enough to be established (> 0.5 s).
        var firstSeen: TimeInterval
        var lastSeen: TimeInterval
        var lastBoundingBox: CGRect
        var confidence: Float
        var lastVelocity: CGVector = .zero
        var lastPose: PoseKeypoints? = nil
        var lastPoseTime: TimeInterval = 0
    }

    // Velocity clamp in frame-widths-per-second. Prevents stale tracks with a
    // large dt from extrapolating a wildly displaced predicted box.
    private static let maxVelocityComponent: CGFloat = 2.0
    
    // MARK: - Initialization

    init() {
        // 15 Hz coalescer for the UI mirrors. The detection path writes plain
        // vars + bumps `frameStateRevision`; this timer republishes at most
        // 15×/s and only when the revision moved. Fires on the main runloop
        // (scheduled from MainActor init), so `assumeIsolated` is sound.
        displayMirrorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishDisplayMirrors()
            }
        }
    }

    deinit {
        displayMirrorTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Process a video frame and detect persons
    /// - Parameter pixelBuffer: The video frame to analyze
    /// - Returns: Array of detected persons
    @discardableResult
    func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        plan: DetectionRequestPlan = DetectionRequestPlan(mode: .acquiring, roi: nil)
    ) async -> [DetectedPerson] {
        // Off / awaitingTap: no Vision at all. Clear detections so the overlay
        // shows nothing and the crop holds wide — the passive default.
        if plan.mode == .off || plan.mode == .awaitingTap {
            if !detectedPersons.isEmpty {
                detectedPersons = []
                frameStateRevision &+= 1
            }
            trackedPersons.removeAll()
            return []
        }

        let detectionInterval = Self.signposter.beginInterval("visionDetection")
        let startTime = CACurrentMediaTime()
        let configSnapshot = config

        // Perform detection on background queue (rect + pose + face together).
        let (rectObservations, poseObservations, faceObservations, queueWait) = await performDetection(
            pixelBuffer: pixelBuffer,
            config: configSnapshot,
            plan: plan
        )

        let detectionTime = CACurrentMediaTime() - startTime
        Self.signposter.endInterval("visionDetection", detectionInterval)

        // Match and update on main actor
        await MainActor.run {
            updateTracking(
                rectObservations: rectObservations,
                poseObservations: poseObservations,
                faceObservations: faceObservations,
                timestamp: startTime
            )
            updateStats(detectionTime: detectionTime, queueWait: queueWait)
        }

        return detectedPersons
    }
    
    /// Diagnostic A/B hook: drop Core Image's caches for the detection
    /// downscaler. NOT the memory fix — the downscale context is created with
    /// `.cacheIntermediates: false` (see `downscaleContext`), so it should no
    /// longer accumulate on its own. This exists only to A/B against
    /// `DeveloperFlags.imageCacheFlushInterval` while a soak proves the
    /// autorelease fix; keep it off (interval 0) in normal operation.
    nonisolated func flushImageCaches() {
        Self.downscaleContext.clearCaches()
    }

    /// Synchronous equivalent of the `.off` / `.awaitingTap` early-out in
    /// `processFrame`, for callers that no longer await detection at all.
    ///
    /// Without this, a frame in a non-detecting mode would still have to suspend
    /// on `processFrame` just to be told there is nothing to do — one MainActor
    /// hop per frame for no work.
    func clearForInactiveMode() {
        if !detectedPersons.isEmpty {
            detectedPersons = []
            frameStateRevision &+= 1
        }
        if !trackedPersons.isEmpty {
            trackedPersons.removeAll()
        }
    }

    // MARK: - Private Methods

    private struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    private nonisolated func performDetection(
        pixelBuffer: CVPixelBuffer,
        config: Config,
        plan: DetectionRequestPlan
    ) async -> ([VNHumanObservation], [VNHumanBodyPoseObservation], [VNFaceObservation], TimeInterval) {
        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        let enqueueTime = CACurrentMediaTime()

        return await withCheckedContinuation { continuation in
            processingQueue.async { [self] in
                autoreleasepool {
                    let queueWait = CACurrentMediaTime() - enqueueTime
                    if config.useHighAccuracy {
                        self.cachedRectRequest.revision = VNDetectHumanRectanglesRequestRevision2
                    } else {
                        self.cachedRectRequest.revision = VNDetectHumanRectanglesRequestRevision1
                    }

                    // Region of interest. Acquiring / lockedROI scope every request
                    // to the padded box around the one subject, so cost is flat
                    // regardless of how many other guests are in frame. Other modes
                    // reset to the full frame. Vision still returns results in
                    // full-image normalized coords, so nothing downstream changes.
                    let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
                    let roi: CGRect
                    switch plan.mode {
                    case .acquiring, .lockedROI:
                        roi = (plan.roi ?? fullFrame).intersection(fullFrame)
                    case .off, .awaitingTap, .reacquiring:
                        roi = fullFrame
                    }
                    let effectiveROI = roi.isEmpty ? fullFrame : roi
                    self.cachedRectRequest.regionOfInterest = effectiveROI
                    self.cachedPoseRequest.regionOfInterest = effectiveROI
                    self.cachedFaceRequest.regionOfInterest = effectiveROI

                    // Which requests to run. Each request is a separate model
                    // inference; ROI does NOT shrink that cost, so the latency win
                    // once locked comes from running fewer requests.
                    //   acquiring  → rect + pose + face  (fills the gallery at
                    //                lock-on AND on the throttled refresh scans
                    //                that keep it current after lock)
                    //   lockedROI  → rect + pose ONLY    (per-frame default while
                    //                locked; face matters only for gallery refresh
                    //                and re-acquisition, both of which use other
                    //                modes — dropping it removes a full inference
                    //                per frame)
                    //   reacquiring→ rect + pose + face  (returning subject anywhere)
                    // `if case` avoids needing Equatable on the main-actor-isolated
                    // enum from this nonisolated closure.
                    let isLockedROI: Bool = { if case .lockedROI = plan.mode { return true }; return false }()
                    var requests: [VNRequest] = [
                        self.cachedRectRequest,
                        self.cachedPoseRequest
                    ]
                    if !isLockedROI {
                        requests.append(self.cachedFaceRequest)
                    }

                    // Detect on a ≤1080p proxy of tall (4K) buffers. Vision results
                    // are normalized, so downstream consumers are unaffected; the
                    // original full-res buffer is untouched and continues to feed
                    // crop/output and face-signature capture.
                    let detectionBuffer = self.downscaledForDetection(sendablePixelBuffer.value)

                    let handler = VNImageRequestHandler(
                        cvPixelBuffer: detectionBuffer,
                        orientation: .up,
                        options: [:]
                    )

                    do {
                        try handler.perform(requests)

                        let rectResults = (self.cachedRectRequest.results ?? [])
                            .filter { $0.confidence >= config.confidenceThreshold }
                        let limited = Array(rectResults.prefix(config.maxPersons))

                        let poseResults = self.cachedPoseRequest.results ?? []
                        // Only read face results when the face request actually ran
                        // this frame — otherwise the cached request still holds the
                        // previous frame's faces, which would attach a stale face to
                        // the locked subject and trigger spurious gallery captures.
                        let faceResults = isLockedROI ? [] : (self.cachedFaceRequest.results ?? [])

                        continuation.resume(returning: (limited, poseResults, faceResults, queueWait))
                    } catch {
                        Self.logger.error("Person detection error: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(returning: ([], [], [], queueWait))
                    }
                }
            }
        }
    }

    /// Extract head and waist keypoints from a pose observation
    private func extractKeypoints(from pose: VNHumanBodyPoseObservation) -> PoseKeypoints? {
        guard let allPoints = try? pose.recognizedPoints(.all) else { return nil }

        // Head: prefer average of ears, fallback to nose
        let head: CGPoint? = {
            let leftEar = allPoints[.leftEar]
            let rightEar = allPoints[.rightEar]
            let nose = allPoints[.nose]

            if let le = leftEar, let re = rightEar, le.confidence > 0.3, re.confidence > 0.3 {
                return CGPoint(
                    x: (le.location.x + re.location.x) / 2,
                    y: (le.location.y + re.location.y) / 2
                )
            } else if let n = nose, n.confidence > 0.3 {
                return n.location
            }
            return nil
        }()

        // Waist: prefer root (center hip), fallback to hip average
        let waist: CGPoint? = {
            let root = allPoints[.root]
            let leftHip = allPoints[.leftHip]
            let rightHip = allPoints[.rightHip]

            if let r = root, r.confidence > 0.3 {
                return r.location
            } else if let lh = leftHip, let rh = rightHip, lh.confidence > 0.3, rh.confidence > 0.3 {
                return CGPoint(
                    x: (lh.location.x + rh.location.x) / 2,
                    y: (lh.location.y + rh.location.y) / 2
                )
            }
            return nil
        }()

        guard let h = head, let w = waist else { return nil }

        return PoseKeypoints(head: h, waist: w, confidence: pose.confidence)
    }
    
    private func updateTracking(
        rectObservations: [VNHumanObservation],
        poseObservations: [VNHumanBodyPoseObservation],
        faceObservations: [VNFaceObservation],
        timestamp: TimeInterval
    ) {
        // Remove stale tracks
        trackedPersons = trackedPersons.filter { _, person in
            timestamp - person.lastSeen < trackingTimeout
        }

        // Assign track IDs to detections via two-pass optimal-greedy matching:
        //   Pass A: locked track binds first against a relaxed threshold.
        //   Pass B: all remaining (detection, track) pairs are scored and the
        //           highest-scoring pair is taken repeatedly until none clear
        //           the threshold. This avoids the classic greedy failure where
        //           two detections both overlap one track and the second is
        //           assigned a fresh UUID.
        let assignments = assignTracks(
            detections: rectObservations,
            timestamp: timestamp
        )

        var updatedPersons: [DetectedPerson] = []

        for (index, observation) in rectObservations.enumerated() {
            let boundingBox = observation.boundingBox
            let confidence = observation.confidence

            // Match this rect to the best-overlapping pose observation
            let freshKeypoints: PoseKeypoints? = {
                let bestPose = poseObservations.max { a, b in
                    let bboxA = poseBoundingBox(a)
                    let bboxB = poseBoundingBox(b)
                    return calculateIoU(boundingBox, bboxA) < calculateIoU(boundingBox, bboxB)
                }
                guard let pose = bestPose,
                      calculateIoU(boundingBox, poseBoundingBox(pose)) > 0.2 else {
                    return nil
                }
                return extractKeypoints(from: pose)
            }()

            // Match this rect to a face that sits inside it. A person's bbox
            // is in normalised Vision coords (bottom-left origin); so is the
            // face bbox. The face is "inside" the body when its centroid
            // falls within the body bbox. If multiple faces qualify (rare
            // for typical framing), take the one with highest confidence.
            //
            // We keep the full VNFaceObservation (not just the bbox) so we
            // can extract landmark ratios for the re-acquisition veto
            // signal — see `LandmarkRatios`.
            let matchedFace: VNFaceObservation? = {
                let candidates = faceObservations.filter { face in
                    let centroid = CGPoint(x: face.boundingBox.midX, y: face.boundingBox.midY)
                    return boundingBox.contains(centroid)
                }
                return candidates.max { $0.confidence < $1.confidence }
            }()
            let faceBoundingBox = matchedFace?.boundingBox
            let faceLandmarkRatios = matchedFace.flatMap { LandmarkRatios.extract(from: $0) }

            let matchedID = assignments[index]
            let personID = matchedID ?? UUID()
            let existing = matchedID.flatMap { trackedPersons[$0] }

            // Compute velocity from the previous box position (Step 1). On
            // first sighting (no existing track) velocity is zero.
            let velocity: CGVector
            if let existing {
                let dt = max(timestamp - existing.lastSeen, 0.001)
                let rawDx = (boundingBox.midX - existing.lastBoundingBox.midX) / CGFloat(dt)
                let rawDy = (boundingBox.midY - existing.lastBoundingBox.midY) / CGFloat(dt)
                velocity = CGVector(
                    dx: clamp(rawDx, to: Self.maxVelocityComponent),
                    dy: clamp(rawDy, to: Self.maxVelocityComponent)
                )
            } else {
                velocity = .zero
            }

            // Pose carry-forward (Step 3). If this frame's pose match failed
            // but the track has a recent pose (<0.3s old), reuse it to keep
            // the composer on its pose-driven framing branch.
            let cachedPose = existing?.lastPose
            let cachedPoseTime = existing?.lastPoseTime ?? 0
            let keypoints: PoseKeypoints?
            let poseTimeToStore: TimeInterval
            if let freshKeypoints {
                keypoints = freshKeypoints
                poseTimeToStore = timestamp
            } else if let cachedPose, timestamp - cachedPoseTime < 0.3 {
                keypoints = cachedPose
                poseTimeToStore = cachedPoseTime
            } else {
                keypoints = nil
                poseTimeToStore = cachedPoseTime
            }
            let poseToStore = keypoints ?? cachedPose

            trackedPersons[personID] = TrackedPerson(
                id: personID,
                firstSeen: existing?.firstSeen ?? timestamp,
                lastSeen: timestamp,
                lastBoundingBox: boundingBox,
                confidence: confidence,
                lastVelocity: velocity,
                lastPose: poseToStore,
                lastPoseTime: poseTimeToStore
            )

            let detectedPerson = DetectedPerson(
                id: personID,
                boundingBox: boundingBox,
                confidence: confidence,
                timestamp: timestamp,
                poseKeypoints: keypoints,
                faceBoundingBox: faceBoundingBox,
                faceLandmarkRatios: faceLandmarkRatios
            )
            updatedPersons.append(detectedPerson)
        }

        // Cached-detection fallback (Step 2). When Vision dropped this frame
        // entirely, synthesize entries from recent tracks so the composer
        // doesn't see [] and lose lock. Only triggered when rectObservations
        // is empty — if Vision found anyone, trust its result.
        if rectObservations.isEmpty {
            for (id, track) in trackedPersons {
                let age = timestamp - track.lastSeen
                guard age < 0.3 else { continue }
                let projectedBox = predictedBox(for: track, at: timestamp)
                let synthesized = DetectedPerson(
                    id: id,
                    boundingBox: projectedBox,
                    confidence: track.confidence * 0.5,
                    timestamp: timestamp,
                    poseKeypoints: track.lastPose,
                    faceBoundingBox: nil,           // synthesized entries have no fresh face
                    faceLandmarkRatios: nil
                )
                updatedPersons.append(synthesized)
            }
        }

        detectedPersons = updatedPersons
        frameStateRevision &+= 1
    }

    private func clamp(_ value: CGFloat, to absLimit: CGFloat) -> CGFloat {
        return min(max(value, -absLimit), absLimit)
    }
    
    /// Assign every detection (by index) to at most one track UUID.
    ///
    /// Two passes:
    ///   1. The locked track (if any) gets first pick against a relaxed
    ///      threshold (lower IoU floor, larger centroid radius). Brief
    ///      occlusion or a detection-confidence wobble can't steal it.
    ///   2. Remaining detections and tracks are paired by repeatedly taking
    ///      the highest-scoring qualifying pair from a precomputed cost
    ///      matrix. Each detection and each track is consumed at most once,
    ///      so two detections can never both claim the same track.
    ///
    /// Returns a sparse map: index → UUID for matched detections only.
    /// Unmatched detection indices receive a fresh UUID upstream.
    private func assignTracks(
        detections: [VNHumanObservation],
        timestamp: TimeInterval
    ) -> [Int: UUID] {
        guard !detections.isEmpty, !trackedPersons.isEmpty else { return [:] }

        // Precompute predicted boxes once per track.
        let predicted: [UUID: CGRect] = trackedPersons.mapValues {
            predictedBox(for: $0, at: timestamp)
        }

        var assignments: [Int: UUID] = [:]
        var usedDetections = Set<Int>()
        var usedTracks = Set<UUID>()

        // Pass A — locked track first.
        //
        // Livestream principle: the lock must stick to the same physical person
        // even when another detection scores higher under naive IoU. Tiebreaks
        // use *geometric identity* (size + aspect + position) — never Vision's
        // detection-confidence score, which reshuffles frame-to-frame.
        //
        // We also use the track's *last known* box (not the velocity-projected
        // box) as the reference. Velocity projection over-extrapolates when a
        // subject is held still or being carried, dragging the reference into
        // a neighbour's detection.
        var lockedDiag: (lockedID: UUID, referenceBox: CGRect, allowedDistance: CGFloat, chosen: Int?)? = nil
        if let lockedID = lockedTargetID {
            if let lockedTrack = trackedPersons[lockedID] {
                let referenceBox = lockedTrack.lastBoundingBox
                let elapsed = max(timestamp - lockedTrack.lastSeen, 0)
                let velocityMagnitude = (
                    lockedTrack.lastVelocity.dx * lockedTrack.lastVelocity.dx
                    + lockedTrack.lastVelocity.dy * lockedTrack.lastVelocity.dy
                ).squareRoot()
                // Predicted boxes of other *established* tracks (alive > 0.5 s):
                // the occluder guard's evidence that a candidate is better
                // explained by someone else's track than by the stale lock box.
                let otherTrackBoxes = trackedPersons.compactMap { id, track -> CGRect? in
                    guard id != lockedID,
                          timestamp - track.firstSeen > 0.5 else { return nil }
                    return predicted[id]
                }
                let resolution = Self.resolveLockedAssignment(
                    detections: detections.map(\.boundingBox),
                    referenceBox: referenceBox,
                    lockVelocityMagnitude: velocityMagnitude,
                    timeSinceLockSeen: elapsed,
                    otherTrackBoxes: otherTrackBoxes,
                    probation: lockProbation
                )
                lockProbation = resolution.probation
                if let index = resolution.assignedIndex {
                    assignments[index] = lockedID
                    usedDetections.insert(index)
                    usedTracks.insert(lockedID)
                }
                let allowedDistance = min(
                    Self.lockedMaxJumpRadius,
                    Self.lockedBaseJumpRadius + velocityMagnitude * CGFloat(elapsed)
                )
                lockedDiag = (lockedID, referenceBox, allowedDistance, resolution.assignedIndex)
            } else {
                // Locked track went stale — drop any half-built probation.
                lockProbation = nil
            }
        }

        // Pass B — build cost matrix over remaining detections × tracks,
        // then repeatedly take the best qualifying pair.
        struct Pair {
            let detectionIndex: Int
            let trackID: UUID
            let score: CGFloat
        }

        var pairs: [Pair] = []
        pairs.reserveCapacity(detections.count * trackedPersons.count)

        for (idx, det) in detections.enumerated() where !usedDetections.contains(idx) {
            for (id, box) in predicted where !usedTracks.contains(id) {
                let score = matchScore(
                    detection: det.boundingBox,
                    predicted: box,
                    iouThreshold: Self.normalIoUThreshold,
                    centroidThreshold: Self.normalCentroidThreshold
                )
                if score > 0 {
                    pairs.append(Pair(detectionIndex: idx, trackID: id, score: score))
                }
            }
        }

        // Sort once, then sweep — each detection/track can only be claimed once,
        // so we skip pairs whose endpoints are already used. N is tiny (≤ maxPersons²).
        pairs.sort { $0.score > $1.score }
        for pair in pairs {
            if usedDetections.contains(pair.detectionIndex) { continue }
            if usedTracks.contains(pair.trackID) { continue }
            assignments[pair.detectionIndex] = pair.trackID
            usedDetections.insert(pair.detectionIndex)
            usedTracks.insert(pair.trackID)
        }

        // Diagnostic: when a lock is active and >1 person is in view, log per-
        // detection IoU/distance/score against the locked track plus the
        // probation/coast state. Filter the Console for subsystem com.alfie,
        // category Vision to capture these.
        if let diag = lockedDiag, detections.count > 1 {
            let shortID = String(diag.lockedID.uuidString.prefix(8))
            let perDet = detections.enumerated().map { idx, det in
                let iou = Self.iou(det.boundingBox, diag.referenceBox)
                let dx = det.boundingBox.midX - diag.referenceBox.midX
                let dy = det.boundingBox.midY - diag.referenceBox.midY
                let dist = (dx * dx + dy * dy).squareRoot()
                let score = Self.lockedMatchScore(
                    detection: det.boundingBox,
                    reference: diag.referenceBox,
                    allowedDistance: diag.allowedDistance
                )
                let marker = idx == diag.chosen ? "*" : " "
                return String(
                    format: "%@d%d[conf=%.2f iou=%.3f dist=%.3f score=%.3f]",
                    marker, idx,
                    det.confidence,
                    Float(iou),
                    Float(dist),
                    Float(score)
                )
            }.joined(separator: " ")
            let state: String
            if diag.chosen != nil {
                state = "BOUND"
            } else if let probation = lockProbation {
                state = "COAST probation=\(probation.framesAgreed)"
            } else {
                state = "COAST"
            }
            let radius = String(format: "radius=%.3f", Float(diag.allowedDistance))
            if diag.chosen == nil {
                Self.logger.warning("LOCK-PASS-A lock=\(shortID, privacy: .public) \(state, privacy: .public) \(radius, privacy: .public) \(perDet, privacy: .public)")
            } else {
                Self.logger.info("LOCK-PASS-A lock=\(shortID, privacy: .public) \(state, privacy: .public) \(radius, privacy: .public) \(perDet, privacy: .public)")
            }
        }

        return assignments
    }

    // MARK: - Locked-track resolution (pure, unit-tested)

    /// Probation state for a discontinuous locked-track candidate.
    struct LockProbation: Equatable {
        var candidateBox: CGRect
        var framesAgreed: Int
    }

    /// Outcome of one frame of locked-track matching.
    struct LockedResolution: Equatable {
        /// Detection index the lock accepted this frame; nil while coasting.
        let assignedIndex: Int?
        /// Probation state to carry into the next frame.
        let probation: LockProbation?
    }

    /// The entire Pass A policy as a pure, deterministic function — no actor,
    /// Vision, or clock dependencies, so unit tests drive it with synthetic
    /// box sequences.
    ///
    /// Policy:
    ///  - **Adaptive gate**: candidates beyond `lockedBaseJumpRadius +
    ///    velocity × timeUnseen` (capped at `lockedMaxJumpRadius`) score 0.
    ///    A stationary subject keeps a tight radius; a moving subject occluded
    ///    for a while may legitimately re-emerge displaced.
    ///  - **Instant accept only for continuity**: the best candidate is
    ///    accepted immediately iff it overlaps the lock's last box
    ///    (IoU ≥ `lockedSameObjectIoU`), is not better explained by another
    ///    established track (occluder guard), and beats the runner-up by
    ///    `lockedScoreMargin`. This covers continuous tracking — the common
    ///    case — with zero added latency.
    ///  - **Probation otherwise**: a discontinuous candidate must persist for
    ///    `lockedProbationFrames` consecutive frames
    ///    (`lockedProbationFramesContested` when contested) before the lock
    ///    re-binds. Until then the lock coasts: no assignment, and the
    ///    candidate stays available to Pass B so its own track survives —
    ///    which is what keeps the occluder guard's evidence alive.
    nonisolated static func resolveLockedAssignment(
        detections: [CGRect],
        referenceBox: CGRect,
        lockVelocityMagnitude: CGFloat,
        timeSinceLockSeen: TimeInterval,
        otherTrackBoxes: [CGRect],
        probation: LockProbation?
    ) -> LockedResolution {
        let allowedDistance = min(
            lockedMaxJumpRadius,
            lockedBaseJumpRadius + lockVelocityMagnitude * CGFloat(timeSinceLockSeen)
        )

        var best: (index: Int, score: CGFloat)? = nil
        var secondScore: CGFloat = 0
        for (idx, box) in detections.enumerated() {
            let score = lockedMatchScore(
                detection: box,
                reference: referenceBox,
                allowedDistance: allowedDistance
            )
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                secondScore = best?.score ?? 0
                best = (idx, score)
            } else if score > secondScore {
                secondScore = score
            }
        }

        guard let best else {
            // Nothing inside the radius: coast. Probation is preserved — a
            // candidate Vision missed for one frame keeps its progress.
            return LockedResolution(assignedIndex: nil, probation: probation)
        }

        let candidate = detections[best.index]
        let iouRef = iou(candidate, referenceBox)
        let iouOther = otherTrackBoxes.reduce(CGFloat(0)) { max($0, iou(candidate, $1)) }
        let marginOK = secondScore == 0 || best.score >= secondScore * lockedScoreMargin

        // Occluder guard: someone standing where the subject was overlaps
        // their own live track's predicted box more than the lock's stale box.
        if iouRef >= lockedSameObjectIoU && iouRef >= iouOther && marginOK {
            return LockedResolution(assignedIndex: best.index, probation: nil)
        }

        let required = iouOther > iouRef
            ? lockedProbationFramesContested
            : lockedProbationFrames
        if let probation, iou(candidate, probation.candidateBox) > 0.5 {
            let framesAgreed = probation.framesAgreed + 1
            if framesAgreed >= required {
                return LockedResolution(assignedIndex: best.index, probation: nil)
            }
            return LockedResolution(
                assignedIndex: nil,
                probation: LockProbation(candidateBox: candidate, framesAgreed: framesAgreed)
            )
        }
        return LockedResolution(
            assignedIndex: nil,
            probation: LockProbation(candidateBox: candidate, framesAgreed: 1)
        )
    }

    /// Score a candidate detection against the locked subject's *last known*
    /// box, prioritising geometric identity over overlap.
    ///
    /// When two people stand close together (e.g. a parent holding a child),
    /// both detections will overlap the locked reference box. Picking by
    /// overlap is a coin flip — the larger person usually wins, which is
    /// exactly the "lock jumps to the bigger person" bug.
    ///
    /// Identity cues, in order of weight:
    ///   1. Size similarity — a child's bbox area differs from an adult's by
    ///      ~3-10×. Strong discriminator even at close range.
    ///   2. Aspect-ratio similarity — body proportions differ between adults
    ///      and children, and between standing and crouching poses.
    ///   3. Centroid proximity — relevant only when the above ties.
    ///
    /// Returns 0 if the candidate is clearly not the same subject (size or
    /// position too divergent). Higher score = better identity match.
    nonisolated static func lockedMatchScore(
        detection: CGRect,
        reference: CGRect,
        allowedDistance: CGFloat
    ) -> CGFloat {
        let dx = detection.midX - reference.midX
        let dy = detection.midY - reference.midY
        let distance = (dx * dx + dy * dy).squareRoot()

        // Hard reject outside the adaptive radius (see resolveLockedAssignment).
        guard distance < allowedDistance else { return 0 }

        let detArea = max(detection.width * detection.height, 0.0001)
        let refArea = max(reference.width * reference.height, 0.0001)
        let areaRatio = min(detArea, refArea) / max(detArea, refArea)  // 0..1, 1 = identical

        // Hard reject: a candidate that's less than a third the area of the
        // locked subject (or more than 3×) is a different physical person.
        // This is the daughter-vs-adult guard.
        guard areaRatio > 0.33 else { return 0 }

        let detAspect = detection.width / max(detection.height, 0.0001)
        let refAspect = reference.width / max(reference.height, 0.0001)
        let aspectRatio = min(detAspect, refAspect) / max(detAspect, refAspect)  // 0..1

        // Weights: size dominates (it's the strongest identity cue), then
        // aspect, then position. Position is last because the locked subject
        // can move — but they can't change size suddenly.
        let sizeTerm = areaRatio * 0.6
        let aspectTerm = aspectRatio * 0.25
        let positionTerm = max(0, (allowedDistance - distance) / allowedDistance) * 0.15

        return sizeTerm + aspectTerm + positionTerm
    }

    /// Score a (detection, predicted-track) pair. Returns 0 when neither the
    /// IoU nor the centroid distance qualifies. Higher score = better match.
    /// IoU dominates when overlap exists; otherwise centroid proximity rescues
    /// fast lateral motion where the predicted box just barely misses.
    private func matchScore(
        detection: CGRect,
        predicted: CGRect,
        iouThreshold: CGFloat,
        centroidThreshold: CGFloat
    ) -> CGFloat {
        let iou = calculateIoU(detection, predicted)
        if iou > iouThreshold {
            return 1.0 + iou
        }
        let dx = detection.midX - predicted.midX
        let dy = detection.midY - predicted.midY
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < centroidThreshold {
            return (centroidThreshold - distance) / centroidThreshold
        }
        return 0
    }

    private func predictedBox(for track: TrackedPerson, at timestamp: TimeInterval) -> CGRect {
        let dt = CGFloat(max(timestamp - track.lastSeen, 0))
        return track.lastBoundingBox.offsetBy(
            dx: track.lastVelocity.dx * dt,
            dy: track.lastVelocity.dy * dt
        )
    }
    
    /// Compute an approximate bounding box from a pose observation's recognized points
    private func poseBoundingBox(_ pose: VNHumanBodyPoseObservation) -> CGRect {
        guard let allPoints = try? pose.recognizedPoints(.all) else {
            return .zero
        }

        var minX: CGFloat = 1.0
        var minY: CGFloat = 1.0
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0
        var count = 0

        for (_, point) in allPoints where point.confidence > 0.1 {
            minX = min(minX, point.location.x)
            minY = min(minY, point.location.y)
            maxX = max(maxX, point.location.x)
            maxY = max(maxY, point.location.y)
            count += 1
        }

        guard count > 0 else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func calculateIoU(_ rect1: CGRect, _ rect2: CGRect) -> CGFloat {
        Self.iou(rect1, rect2)
    }

    nonisolated static func iou(_ rect1: CGRect, _ rect2: CGRect) -> CGFloat {
        let intersection = rect1.intersection(rect2)

        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let union = (rect1.width * rect1.height) + (rect2.width * rect2.height) - intersectionArea

        return intersectionArea / union
    }
    
    private func updateStats(detectionTime: TimeInterval, queueWait: TimeInterval = 0) {
        stats.totalFramesProcessed += 1
        stats.lastDetectionTime = detectionTime
        stats.lastQueueWait = queueWait
        stats.personsDetectedCount = detectedPersons.count
        
        // Running average of detection time
        let alpha: TimeInterval = 0.1 // Smoothing factor
        stats.averageDetectionTime = (alpha * detectionTime) + ((1 - alpha) * stats.averageDetectionTime)
        frameStateRevision &+= 1
    }
}
