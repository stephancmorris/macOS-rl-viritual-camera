//
//  ShotComposer.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/7/2026.
//  Ticket: LOGIC-01 - Rule-Based Shot Composer
//

import Foundation
import Combine
import CoreGraphics
import QuartzCore

/// Shot composer for church-stage speaker framing.
///
/// When pose data is available, the crop aims for a waist-up composition:
/// head in the upper third, waist in the lower third, and enough horizontal
/// breathing room to feel intentional instead of like a raw detection crop.
///
/// When pose data is unavailable, it falls back to padded bounding-box framing.
@MainActor
final class ShotComposer: ObservableObject {

    // MARK: - Configuration

    struct Config: Sendable {
        /// Minimum movement (fraction of frame) before updating target crop.
        /// Prevents jitter from small detection noise.
        var deadzoneThreshold: CGFloat = 0.05 // 5% of frame

        /// Smoothing factor per frame (synced to CropEngine.transitionSmoothing)
        var smoothingFactor: Float = 0.10 // 10% per frame

        /// Padding added around the detection box on each side (fraction of box size).
        /// 0.20 = 20% breathing room above/below/left/right.
        var padding: CGFloat = 0.20

        /// How long to keep the current target "warm" after detections drop.
        var targetHoldDuration: TimeInterval = 0.75

        /// Horizontal stage margin used to ignore off-stage areas near the frame edges.
        var stageHorizontalMargin: CGFloat = 0.08

        /// Vertical stage margin used to avoid drifting into ceiling or front-row space.
        var stageVerticalMargin: CGFloat = 0.03

        /// Minimum margin to preserve between the speaker bounds and crop edges.
        var edgeSafetyMargin: CGFloat = 0.12

        /// Output aspect ratio (width / height)
        var outputAspectRatio: CGFloat = 16.0 / 9.0

        /// Master toggle
        var isEnabled: Bool = true
    }

    @Published var config = Config()

    // MARK: - State

    /// Last accepted detection center (for deadzone comparison)
    private var lastAcceptedCenter: CGPoint?

    /// Whether a valid target has been computed at least once
    @Published private(set) var hasActiveTarget: Bool = false

    /// The most recently computed crop (used by training recorder)
    @Published private(set) var lastComputedCrop: CropEngine.CropRect?

    /// The currently preferred speaker track, if any.
    @Published private(set) var activeTargetID: UUID?

    // Desired vertical positions within the crop for a waist-up shot.
    private let targetHeadPositionY: CGFloat = 0.68
    private let targetWaistPositionY: CGFloat = 0.32
    private var lastTargetSeenTime: TimeInterval?
    private var lastTrackingPoint: CGPoint?

    // MARK: - Public Methods

    /// Select the primary speaker to frame.
    ///
    /// Uses a sticky target preference so the camera does not jump eagerly
    /// between people when a second person appears on stage.
    func primaryPerson(
        from persons: [PersonDetector.DetectedPerson]
    ) -> PersonDetector.DetectedPerson? {
        let now = CACurrentMediaTime()

        guard !persons.isEmpty else {
            if let lastTargetSeenTime,
               now - lastTargetSeenTime > config.targetHoldDuration {
                activeTargetID = nil
                hasActiveTarget = false
            }
            return nil
        }

        let selected = persons.max { lhs, rhs in
            score(for: lhs) < score(for: rhs)
        }

        guard let selected else { return nil }
        activeTargetID = selected.id
        hasActiveTarget = true
        lastTargetSeenTime = now
        lastTrackingPoint = trackingPoint(for: selected)
        return selected
    }

    /// Compose a stage-friendly speaker shot.
    /// Returns a CropRect when the target should be updated, nil when within deadzone.
    func compose(person: PersonDetector.DetectedPerson) -> CropEngine.CropRect? {
        guard config.isEnabled else { return nil }

        if let keypoints = person.poseKeypoints,
           keypoints.head.y > keypoints.waist.y {
            return composeFromPose(person: person, keypoints: keypoints)
        }

        return composeFromBoundingBox(person.boundingBox)
    }

    /// Reset state (e.g., when switching subjects or losing track)
    func reset() {
        lastAcceptedCenter = nil
        hasActiveTarget = false
        lastComputedCrop = nil
        activeTargetID = nil
        lastTargetSeenTime = nil
        lastTrackingPoint = nil
    }

    // MARK: - Private

    /// Build a 16:9 crop from pose keypoints for a more intentional waist-up shot.
    private func composeFromPose(
        person: PersonDetector.DetectedPerson,
        keypoints: PersonDetector.PoseKeypoints
    ) -> CropEngine.CropRect? {
        let head = keypoints.head
        let waist = keypoints.waist
        let boundingBox = person.boundingBox

        let torsoSpan = head.y - waist.y
        guard torsoSpan > 0.02 else {
            return composeFromBoundingBox(boundingBox)
        }

        // Derive height from the desired head/waist placement, then expand slightly
        // using the existing padding control for extra breathing room.
        let targetSpan = targetHeadPositionY - targetWaistPositionY
        let poseHeight = torsoSpan / targetSpan
        let bboxHeight = boundingBox.height * (0.90 + config.padding)
        var cropHeight = max(poseHeight, bboxHeight)
        cropHeight *= (1.0 + config.padding * 0.5)

        // Ensure enough horizontal room for natural movement and gestures.
        let poseWidth = cropHeight * config.outputAspectRatio
        let bboxWidth = boundingBox.width * (1.0 + 2.0 * config.padding)
        let cropWidth = max(poseWidth, bboxWidth)

        let centerX = boundingBox.midX
        let originX = centerX - cropWidth / 2.0
        let originY = waist.y - (targetWaistPositionY * cropHeight)

        let crop = clampAndAccept(
            applyEdgeSafety(
                to: CropEngine.CropRect(
                    origin: CGPoint(x: originX, y: originY),
                    size: CGSize(width: cropWidth, height: cropHeight)
                ),
                subjectBounds: boundingBox
            ),
            trackingCenter: CGPoint(x: centerX, y: waist.y)
        )
        return crop
    }

    /// Build a 16:9 crop that frames the detection bounding box with padding.
    private func composeFromBoundingBox(_ boundingBox: CGRect) -> CropEngine.CropRect? {
        guard boundingBox.height > 0.01 else { return nil }

        // Expand the detection box by padding on every side
        var cropHeight = boundingBox.height * (1.0 + 2.0 * config.padding)
        var cropWidth  = boundingBox.width  * (1.0 + 2.0 * config.padding)

        // Enforce 16:9 by expanding the narrower dimension — never shrink
        if cropWidth / cropHeight < config.outputAspectRatio {
            cropWidth = cropHeight * config.outputAspectRatio
        } else {
            cropHeight = cropWidth / config.outputAspectRatio
        }

        // Center the crop on the detection box midpoint
        let centerX = boundingBox.midX
        let centerY = boundingBox.midY
        let originX = centerX - cropWidth  / 2.0
        let originY = centerY - cropHeight / 2.0

        return clampAndAccept(
            applyEdgeSafety(
                to: CropEngine.CropRect(
                    origin: CGPoint(x: originX, y: originY),
                    size: CGSize(width: cropWidth, height: cropHeight)
                ),
                subjectBounds: boundingBox
            ),
            trackingCenter: CGPoint(x: centerX, y: centerY)
        )
    }

    private func clampCropToFrame(_ crop: CropEngine.CropRect) -> CropEngine.CropRect {
        var h = min(crop.size.height, 1.0)
        var w: CGFloat

        // Enforce minimum crop size (4× max zoom)
        h = max(h, 0.25)

        // Maintain 16:9
        let desiredWidth = h * config.outputAspectRatio
        if desiredWidth <= 1.0 {
            w = desiredWidth
        } else {
            w = 1.0
            h = w / config.outputAspectRatio
        }

        // Keep crop inside the configured stage region when possible.
        let stageRect = configuredStageRect()
        let minX = w <= stageRect.width ? stageRect.minX : 0.0
        let maxX = (w <= stageRect.width ? stageRect.maxX : 1.0) - w
        let minY = h <= stageRect.height ? stageRect.minY : 0.0
        let maxY = (h <= stageRect.height ? stageRect.maxY : 1.0) - h

        let x = max(minX, min(maxX, crop.origin.x))
        let y = max(minY, min(maxY, crop.origin.y))

        return CropEngine.CropRect(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h)
        )
    }

    private func clampAndAccept(
        _ crop: CropEngine.CropRect,
        trackingCenter: CGPoint
    ) -> CropEngine.CropRect? {
        let clampedCrop = clampCropToFrame(crop)
        lastComputedCrop = clampedCrop

        // Deadzone: only update when the tracked subject anchor has moved enough
        // to matter. This keeps the camera from chasing small detection noise.
        if let lastCenter = lastAcceptedCenter {
            let dx = abs(trackingCenter.x - lastCenter.x)
            let dy = abs(trackingCenter.y - lastCenter.y)
            if dx < config.deadzoneThreshold && dy < config.deadzoneThreshold {
                return nil
            }
        }

        lastAcceptedCenter = trackingCenter
        hasActiveTarget = true
        return clampedCrop
    }

    private func score(for person: PersonDetector.DetectedPerson) -> CGFloat {
        let bbox = person.boundingBox
        let areaScore = min(bbox.width * bbox.height * 4.0, 1.0)

        let centerDistance = hypot(bbox.midX - 0.5, bbox.midY - 0.5)
        let centerScore = max(0.0, 1.0 - (centerDistance / 0.75))
        let stageScore = stagePriorityScore(for: trackingPoint(for: person))

        let continuityScore: CGFloat
        if let lastTrackingPoint {
            let point = trackingPoint(for: person)
            let distance = hypot(point.x - lastTrackingPoint.x, point.y - lastTrackingPoint.y)
            continuityScore = max(0.0, 1.0 - (distance / 0.5))
        } else {
            continuityScore = 0.5
        }

        let stickyBonus: CGFloat = person.id == activeTargetID ? 1.0 : 0.0
        let confidenceScore = CGFloat(person.confidence) * 0.25

        return stickyBonus
            + (continuityScore * 0.9)
            + (centerScore * 0.5)
            + (areaScore * 0.7)
            + (stageScore * 0.9)
            + confidenceScore
    }

    private func trackingPoint(for person: PersonDetector.DetectedPerson) -> CGPoint {
        if let pose = person.poseKeypoints {
            return CGPoint(
                x: person.boundingBox.midX,
                y: pose.waist.y
            )
        }
        return CGPoint(x: person.boundingBox.midX, y: person.boundingBox.midY)
    }

    private func configuredStageRect() -> CGRect {
        let horizontalMargin = min(max(config.stageHorizontalMargin, 0), 0.30)
        let verticalMargin = min(max(config.stageVerticalMargin, 0), 0.30)

        return CGRect(
            x: horizontalMargin,
            y: verticalMargin,
            width: max(0.20, 1.0 - (horizontalMargin * 2.0)),
            height: max(0.20, 1.0 - (verticalMargin * 2.0))
        )
    }

    private func stagePriorityScore(for point: CGPoint) -> CGFloat {
        let stageRect = configuredStageRect()
        if stageRect.contains(point) {
            return 1.0
        }

        let dx = max(stageRect.minX - point.x, point.x - stageRect.maxX, 0)
        let dy = max(stageRect.minY - point.y, point.y - stageRect.maxY, 0)
        let distance = hypot(dx, dy)
        return max(0.0, 1.0 - (distance / 0.25))
    }

    private func applyEdgeSafety(
        to crop: CropEngine.CropRect,
        subjectBounds: CGRect
    ) -> CropEngine.CropRect {
        let safetyMargin = min(max(config.edgeSafetyMargin, 0.02), 0.30)
        let safeScale = max(0.20, 1.0 - (2.0 * safetyMargin))
        let minimumWidth = subjectBounds.width / safeScale
        let minimumHeight = subjectBounds.height / safeScale

        var width = max(crop.size.width, minimumWidth)
        var height = max(crop.size.height, minimumHeight)

        if width / height < config.outputAspectRatio {
            width = height * config.outputAspectRatio
        } else {
            height = width / config.outputAspectRatio
        }

        let centerX = crop.origin.x + (crop.size.width / 2.0)
        let centerY = crop.origin.y + (crop.size.height / 2.0)
        return CropEngine.CropRect(
            origin: CGPoint(
                x: centerX - (width / 2.0),
                y: centerY - (height / 2.0)
            ),
            size: CGSize(width: width, height: height)
        )
    }
}
