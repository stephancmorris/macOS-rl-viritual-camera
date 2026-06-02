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
    
    /// Currently detected persons with bounding boxes
    @Published private(set) var detectedPersons: [DetectedPerson] = []
    
    /// Detection statistics
    @Published private(set) var stats: DetectionStats = .init()
    
    /// Enable/disable detection
    @Published var isEnabled: Bool = true
    
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
        /// ONLY — the face request is dropped to save a full inference per
        /// frame (the gallery is already full and re-acquisition only needs
        /// faces in the wide `.reacquiring` state).
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
        qos: .userInitiated
    )
    
    // Person tracking state
    private var trackedPersons: [UUID: TrackedPerson] = [:]
    private let trackingTimeout: TimeInterval = 1.0 // Drop tracks after 1 second

    /// UUID of the operator-locked subject, pushed from CameraManager each frame.
    /// When set, the matcher binds this track first using a relaxed threshold so
    /// a same-frame confidence reshuffle can't yank the lock onto a neighbour.
    var lockedTargetID: UUID? = nil

    // Matching thresholds. Looser for the locked track so brief occlusion or a
    // detection-confidence flicker doesn't drop it.
    private static let normalIoUThreshold: CGFloat = 0.2
    private static let normalCentroidThreshold: CGFloat = 0.15
    private static let lockedIoUThreshold: CGFloat = 0.1
    private static let lockedCentroidThreshold: CGFloat = 0.25
    
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

    init() {}
    
    // MARK: - Public Methods
    
    /// Process a video frame and detect persons
    /// - Parameter pixelBuffer: The video frame to analyze
    /// - Returns: Array of detected persons
    @discardableResult
    func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        plan: DetectionRequestPlan = DetectionRequestPlan(mode: .acquiring, roi: nil)
    ) async -> [DetectedPerson] {
        guard isEnabled else { return [] }

        // Off / awaitingTap: no Vision at all. Clear detections so the overlay
        // shows nothing and the crop holds wide — the passive default.
        if plan.mode == .off || plan.mode == .awaitingTap {
            if !detectedPersons.isEmpty { detectedPersons = [] }
            trackedPersons.removeAll()
            return []
        }

        let detectionInterval = Self.signposter.beginInterval("visionDetection")
        let startTime = CACurrentMediaTime()
        let configSnapshot = config

        // Perform detection on background queue (rect + pose + face together).
        let (rectObservations, poseObservations, faceObservations) = await performDetection(
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
            updateStats(detectionTime: detectionTime)
        }

        return detectedPersons
    }
    
    /// Process a CIImage frame
    func processFrame(
        _ ciImage: CIImage,
        plan: DetectionRequestPlan = DetectionRequestPlan(mode: .acquiring, roi: nil)
    ) async -> [DetectedPerson] {
        // Convert CIImage to CVPixelBuffer
        guard let pixelBuffer = ciImage.toPixelBuffer() else {
            return []
        }
        return await processFrame(pixelBuffer, plan: plan)
    }
    
    // MARK: - Private Methods
    
    private struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    private nonisolated func performDetection(
        pixelBuffer: CVPixelBuffer,
        config: Config,
        plan: DetectionRequestPlan
    ) async -> ([VNHumanObservation], [VNHumanBodyPoseObservation], [VNFaceObservation]) {
        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)

        return await withCheckedContinuation { continuation in
            processingQueue.async { [self] in
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
                //   acquiring  → rect + pose + face  (face fills the gallery)
                //   lockedROI  → rect + pose ONLY    (gallery already full; face
                //                only matters for re-acquisition, which is wide.
                //                Dropping it removes a full inference per frame.)
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

                let handler = VNImageRequestHandler(
                    cvPixelBuffer: sendablePixelBuffer.value,
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

                    continuation.resume(returning: (limited, poseResults, faceResults))
                } catch {
                    Self.logger.error("Person detection error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: ([], [], []))
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
        var lockedDiag: (lockedID: UUID, scores: [(idx: Int, iou: CGFloat, dist: CGFloat, score: CGFloat)], chosen: Int?)? = nil
        if let lockedID = lockedTargetID,
           let lockedTrack = trackedPersons[lockedID] {
            let referenceBox = lockedTrack.lastBoundingBox
            var best: (index: Int, score: CGFloat)? = nil
            var diagScores: [(idx: Int, iou: CGFloat, dist: CGFloat, score: CGFloat)] = []
            for (idx, det) in detections.enumerated() {
                let iou = calculateIoU(det.boundingBox, referenceBox)
                let dx = det.boundingBox.midX - referenceBox.midX
                let dy = det.boundingBox.midY - referenceBox.midY
                let dist = (dx * dx + dy * dy).squareRoot()
                let score = lockedMatchScore(
                    detection: det.boundingBox,
                    reference: referenceBox
                )
                diagScores.append((idx, iou, dist, score))
                guard score > 0 else { continue }
                if best == nil || score > best!.score {
                    best = (idx, score)
                }
            }
            if let best {
                assignments[best.index] = lockedID
                usedDetections.insert(best.index)
                usedTracks.insert(lockedID)
            }
            lockedDiag = (lockedID, diagScores, best?.index)
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
        // detection IoU/distance/score against the locked track. Filter the
        // Console for subsystem com.alfie, category Vision to capture these.
        if let diag = lockedDiag, detections.count > 1 {
            let shortID = String(diag.lockedID.uuidString.prefix(8))
            let perDet = diag.scores.map { entry in
                let marker = entry.idx == diag.chosen ? "*" : " "
                return String(
                    format: "%@d%d[conf=%.2f iou=%.3f dist=%.3f score=%.3f]",
                    marker, entry.idx,
                    detections[entry.idx].confidence,
                    Float(entry.iou),
                    Float(entry.dist),
                    Float(entry.score)
                )
            }.joined(separator: " ")
            if diag.chosen == nil {
                Self.logger.warning("LOCK-PASS-A lock=\(shortID, privacy: .public) NO_MATCH \(perDet, privacy: .public)")
            } else {
                Self.logger.info("LOCK-PASS-A lock=\(shortID, privacy: .public) \(perDet, privacy: .public)")
            }
        }

        return assignments
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
    private func lockedMatchScore(
        detection: CGRect,
        reference: CGRect
    ) -> CGFloat {
        let dx = detection.midX - reference.midX
        let dy = detection.midY - reference.midY
        let distance = (dx * dx + dy * dy).squareRoot()

        // Hard reject: if the candidate is more than half a frame-width away,
        // it's definitely not the locked subject.
        guard distance < 0.5 else { return 0 }

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
        let positionTerm = max(0, (0.5 - distance) / 0.5) * 0.15

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
        let intersection = rect1.intersection(rect2)
        
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let union = (rect1.width * rect1.height) + (rect2.width * rect2.height) - intersectionArea
        
        return intersectionArea / union
    }
    
    private func updateStats(detectionTime: TimeInterval) {
        stats.totalFramesProcessed += 1
        stats.lastDetectionTime = detectionTime
        stats.personsDetectedCount = detectedPersons.count
        
        // Running average of detection time
        let alpha: TimeInterval = 0.1 // Smoothing factor
        stats.averageDetectionTime = (alpha * detectionTime) + ((1 - alpha) * stats.averageDetectionTime)
    }
}

// MARK: - CIImage Extension

private extension CIImage {
    /// Convert CIImage to CVPixelBuffer for Vision framework
    func toPixelBuffer() -> CVPixelBuffer? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        var pixelBuffer: CVPixelBuffer?
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        context.render(self, to: buffer)
        return buffer
    }
}
