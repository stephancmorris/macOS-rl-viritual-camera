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

/// Detects and tracks people in video frames using Apple Vision framework
/// Ticket: VIS-01 - Person Detection
@MainActor
final class PersonDetector: ObservableObject {
    
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
    
    // MARK: - Configuration
    
    struct Config: Sendable {
        /// Minimum confidence threshold (0-1)
        var confidenceThreshold: Float = 0.5
        
        /// Maximum number of persons to track
        var maxPersons: Int = 5
        
        /// Use high accuracy mode (slower but more accurate)
        var useHighAccuracy: Bool = false
    }
    
    nonisolated(unsafe) var config = Config() {
        didSet {
            setupDetectionRequest()
        }
    }
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var detectionRequest: VNDetectHumanRectanglesRequest?
    private nonisolated(unsafe) let poseRequest = VNDetectHumanBodyPoseRequest()
    private let processingQueue = DispatchQueue(
        label: "com.cinematiccore.personDetection",
        qos: .userInitiated
    )
    
    // Person tracking state
    private var trackedPersons: [UUID: TrackedPerson] = [:]
    private let trackingTimeout: TimeInterval = 1.0 // Drop tracks after 1 second
    
    private struct TrackedPerson {
        let id: UUID
        var lastSeen: TimeInterval
        var lastBoundingBox: CGRect
        var confidence: Float
    }
    
    // MARK: - Initialization

    init() {
        // Setup detection request inline to avoid nonisolated call from init
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = true
        detectionRequest = request
    }
    
    // MARK: - Public Methods
    
    /// Process a video frame and detect persons
    /// - Parameter pixelBuffer: The video frame to analyze
    /// - Returns: Array of detected persons
    @discardableResult
    func processFrame(_ pixelBuffer: CVPixelBuffer) async -> [DetectedPerson] {
        guard isEnabled else { return [] }

        let startTime = CACurrentMediaTime()

        // Perform detection on background queue (rect + pose together)
        let (rectObservations, poseObservations) = await performDetection(pixelBuffer: pixelBuffer)

        let detectionTime = CACurrentMediaTime() - startTime

        // Match and update on main actor
        await MainActor.run {
            updateTracking(
                rectObservations: rectObservations,
                poseObservations: poseObservations,
                timestamp: startTime
            )
            updateStats(detectionTime: detectionTime)
        }

        return detectedPersons
    }
    
    /// Process a CIImage frame
    func processFrame(_ ciImage: CIImage) async -> [DetectedPerson] {
        // Convert CIImage to CVPixelBuffer
        guard let pixelBuffer = ciImage.toPixelBuffer() else {
            return []
        }
        return await processFrame(pixelBuffer)
    }
    
    // MARK: - Private Methods
    
    private nonisolated func setupDetectionRequest() {
        let request = VNDetectHumanRectanglesRequest()
        
        // Configure request based on settings
        if config.useHighAccuracy {
            request.revision = VNDetectHumanRectanglesRequestRevision2 // More accurate
        }
        
        // Upper body only for better speaker tracking
        request.upperBodyOnly = true
        
        detectionRequest = request
    }
    
    private nonisolated func performDetection(pixelBuffer: CVPixelBuffer) async -> ([VNHumanObservation], [VNHumanBodyPoseObservation]) {
        guard let rectRequest = detectionRequest else { return ([], []) }

        return await withCheckedContinuation { continuation in
            processingQueue.async {
                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    orientation: .up,
                    options: [:]
                )

                do {
                    // Run both requests together for efficiency
                    try handler.perform([rectRequest, self.poseRequest])

                    let rectResults = (rectRequest.results ?? [])
                        .filter { $0.confidence >= self.config.confidenceThreshold }
                    let limited = Array(rectResults.prefix(self.config.maxPersons))

                    let poseResults = self.poseRequest.results ?? []

                    continuation.resume(returning: (limited, poseResults))
                } catch {
                    print("❌ Person detection error: \(error)")
                    continuation.resume(returning: ([], []))
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
        timestamp: TimeInterval
    ) {
        // Remove stale tracks
        trackedPersons = trackedPersons.filter { _, person in
            timestamp - person.lastSeen < trackingTimeout
        }

        var updatedPersons: [DetectedPerson] = []

        for observation in rectObservations {
            let boundingBox = observation.boundingBox
            let confidence = observation.confidence

            // Match this rect to the best-overlapping pose observation
            let keypoints: PoseKeypoints? = {
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

            // Try to match with existing track
            let matchedID = findMatchingTrack(boundingBox: boundingBox, timestamp: timestamp)
            let personID = matchedID ?? UUID()

            // Update or create track
            trackedPersons[personID] = TrackedPerson(
                id: personID,
                lastSeen: timestamp,
                lastBoundingBox: boundingBox,
                confidence: confidence
            )

            // Create detected person with optional pose keypoints
            let detectedPerson = DetectedPerson(
                id: personID,
                boundingBox: boundingBox,
                confidence: confidence,
                timestamp: timestamp,
                poseKeypoints: keypoints
            )
            updatedPersons.append(detectedPerson)
        }

        detectedPersons = updatedPersons
    }
    
    private func findMatchingTrack(boundingBox: CGRect, timestamp: TimeInterval) -> UUID? {
        // Find track with highest IoU (Intersection over Union)
        var bestMatch: (id: UUID, iou: CGFloat)? = nil
        
        for (id, track) in trackedPersons {
            let iou = calculateIoU(boundingBox, track.lastBoundingBox)
            
            // Require at least 30% overlap to consider it the same person
            if iou > 0.3 {
                if let current = bestMatch {
                    if iou > current.iou {
                        bestMatch = (id, iou)
                    }
                } else {
                    bestMatch = (id, iou)
                }
            }
        }
        
        return bestMatch?.id
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
