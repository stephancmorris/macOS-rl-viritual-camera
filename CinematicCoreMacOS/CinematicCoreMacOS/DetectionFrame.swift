import CoreVideo
import Foundation

/// An immutable observation owns the exact pixels Vision analyzed. The render
/// frame may be newer; identity extraction must only use this buffer.
@MainActor
struct DetectionFrame {
    let observationID: UInt64
    let capturedAt: TimeInterval
    let sourceTimestamp: Double
    let pixelBuffer: CVPixelBuffer
    let persons: [PersonDetector.DetectedPerson]
    let queueWait: TimeInterval
    let detectionDuration: TimeInterval
}

/// Bounded latest-result mailbox, isolated with its producer/consumer on MainActor.
@MainActor
final class DetectionFrameStore {
    private(set) var generation: UInt64 = 0
    private(set) var latest: DetectionFrame?
    private var sequence: UInt64 = 0
    private var consumedID: UInt64?
    private var newestPublishedID: UInt64?
    static let maximumAge: TimeInterval = 0.5

    func nextObservationID() -> UInt64 { sequence &+= 1; return sequence }

    func invalidate() {
        generation &+= 1
        latest = nil
        consumedID = nil
        newestPublishedID = nil
    }

    @discardableResult
    func publish(_ frame: DetectionFrame, generation: UInt64) -> Bool {
        guard generation == self.generation,
              newestPublishedID == nil || frame.observationID > newestPublishedID! else { return false }
        newestPublishedID = frame.observationID
        latest = frame
        return true
    }

    func consume(at now: TimeInterval) -> (frame: DetectionFrame?, isFresh: Bool) {
        guard let frame = latest, now - frame.capturedAt <= Self.maximumAge else {
            // Release expired pixels and let the FSM observe a missing subject.
            latest = nil
            return (nil, false)
        }
        let fresh = consumedID != frame.observationID
        consumedID = frame.observationID
        return (frame, fresh)
    }
}
