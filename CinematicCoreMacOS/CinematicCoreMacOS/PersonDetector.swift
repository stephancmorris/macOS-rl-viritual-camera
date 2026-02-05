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
    
    struct DetectedPerson: Identifiable, Sendable {
        let id: UUID
        let boundingBox: CGRect // Normalized coordinates (0-1)
        let confidence: Float
        let timestamp: TimeInterval
        
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
        
        // Perform detection on background queue
        let observations = await performDetection(pixelBuffer: pixelBuffer)
        
        let detectionTime = CACurrentMediaTime() - startTime
        
        // Update on main actor
        await MainActor.run {
            updateTracking(observations: observations, timestamp: startTime)
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
    
    private nonisolated func performDetection(pixelBuffer: CVPixelBuffer) async -> [VNHumanObservation] {
        guard let request = detectionRequest else { return [] }
        
        return await withCheckedContinuation { continuation in
            processingQueue.async {
                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    orientation: .up,
                    options: [:]
                )
                
                do {
                    try handler.perform([request])
                    
                    let observations = request.results ?? []
                    
                    // Filter by confidence
                    let filtered = observations.filter { observation in
                        observation.confidence >= self.config.confidenceThreshold
                    }
                    
                    // Limit to max persons
                    let limited = Array(filtered.prefix(self.config.maxPersons))
                    
                    continuation.resume(returning: limited)
                } catch {
                    print("❌ Person detection error: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func updateTracking(observations: [VNHumanObservation], timestamp: TimeInterval) {
        // Remove stale tracks
        trackedPersons = trackedPersons.filter { _, person in
            timestamp - person.lastSeen < trackingTimeout
        }
        
        var updatedPersons: [DetectedPerson] = []
        
        for observation in observations {
            let boundingBox = observation.boundingBox
            let confidence = observation.confidence
            
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
            
            // Create detected person
            let detectedPerson = DetectedPerson(
                id: personID,
                boundingBox: boundingBox,
                confidence: confidence,
                timestamp: timestamp
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
