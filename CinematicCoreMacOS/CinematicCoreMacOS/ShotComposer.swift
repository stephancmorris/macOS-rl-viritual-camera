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

/// Rule-based shot composer for "waist-up" framing using rule of thirds.
/// Designed to be replaced by RL agent in Epic 3 (Task 3.3, Ticket APP-02).
@MainActor
final class ShotComposer: ObservableObject {

    // MARK: - Configuration

    struct Config: Sendable {
        /// Minimum movement (fraction of frame) before updating target crop.
        /// Prevents jitter from small detection noise.
        var deadzoneThreshold: CGFloat = 0.05 // 5% of frame

        /// Smoothing factor per frame (synced to CropEngine.transitionSmoothing)
        var smoothingFactor: Float = 0.10 // 10% per frame

        /// Horizontal padding around the subject (fraction of crop width)
        var horizontalPadding: CGFloat = 0.15

        /// Output aspect ratio (width / height)
        var outputAspectRatio: CGFloat = 16.0 / 9.0

        /// Enable rule-of-thirds composition
        var useRuleOfThirds: Bool = true

        /// Master toggle
        var isEnabled: Bool = true
    }

    @Published var config = Config()

    // MARK: - State

    /// Last accepted speaker center position (for deadzone comparison)
    private var lastAcceptedCenter: CGPoint?

    /// Whether a valid target has been computed at least once
    @Published private(set) var hasActiveTarget: Bool = false

    /// Debug: the most recently computed ideal crop
    @Published private(set) var lastComputedCrop: CropEngine.CropRect?

    // MARK: - Public Methods

    /// Compose a shot given a detected person.
    /// Returns a CropRect if the target should be updated, or nil if within deadzone.
    func compose(person: PersonDetector.DetectedPerson) -> CropEngine.CropRect? {
        guard config.isEnabled else { return nil }

        // If we have pose keypoints, use rule-of-thirds composition
        if let keypoints = person.poseKeypoints, config.useRuleOfThirds {
            return composeFromKeypoints(keypoints, boundingBox: person.boundingBox)
        }

        // Fallback: use bounding box framing
        return composeFromBoundingBox(person.boundingBox)
    }

    /// Reset state (e.g., when switching subjects or losing track)
    func reset() {
        lastAcceptedCenter = nil
        hasActiveTarget = false
        lastComputedCrop = nil
    }

    // MARK: - Private: Rule of Thirds Composition

    private func composeFromKeypoints(
        _ keypoints: PersonDetector.PoseKeypoints,
        boundingBox: CGRect
    ) -> CropEngine.CropRect? {
        // All coordinates in Vision normalized space (0-1, bottom-left origin)
        // In Vision coords: Y increases upward, so head.y > waist.y
        let headY = keypoints.head.y
        let waistY = keypoints.waist.y

        let subjectHeight = headY - waistY
        guard subjectHeight > 0.01 else {
            // Degenerate case: head and waist too close or inverted
            return composeFromBoundingBox(boundingBox)
        }

        // Rule of thirds:
        //   Head at 2/3 from crop bottom (upper third line)
        //   Waist at 1/3 from crop bottom (lower third line)
        //   cropHeight * (2/3 - 1/3) = subjectHeight → cropHeight = 3 * subjectHeight
        let cropHeight = subjectHeight * 3.0
        let cropWidth = cropHeight * config.outputAspectRatio

        // Origin Y: waist at 1/3 from bottom → waistY = originY + cropHeight/3
        let originY = waistY - cropHeight / 3.0

        // Center horizontally on subject
        let subjectCenterX = (keypoints.head.x + keypoints.waist.x) / 2.0
        let originX = subjectCenterX - cropWidth / 2.0

        var crop = CropEngine.CropRect(
            origin: CGPoint(x: originX, y: originY),
            size: CGSize(width: cropWidth, height: cropHeight)
        )
        crop = clampCropToFrame(crop)
        lastComputedCrop = crop

        // Deadzone check
        let currentCenter = CGPoint(x: subjectCenterX, y: (headY + waistY) / 2.0)
        if let lastCenter = lastAcceptedCenter {
            let dx = abs(currentCenter.x - lastCenter.x)
            let dy = abs(currentCenter.y - lastCenter.y)
            if dx < config.deadzoneThreshold && dy < config.deadzoneThreshold {
                return nil // Within deadzone
            }
        }

        lastAcceptedCenter = currentCenter
        hasActiveTarget = true
        return crop
    }

    // MARK: - Private: Bounding Box Fallback

    private func composeFromBoundingBox(_ boundingBox: CGRect) -> CropEngine.CropRect? {
        // Approximate waist-up framing from bounding box.
        // Top of box ≈ head, bottom ≈ waist.
        let headY = boundingBox.origin.y + boundingBox.height
        let waistY = boundingBox.origin.y

        let subjectHeight = headY - waistY
        guard subjectHeight > 0.01 else { return nil }

        // Same rule-of-thirds math
        let cropHeight = subjectHeight * 3.0
        let cropWidth = cropHeight * config.outputAspectRatio
        let originY = waistY - cropHeight / 3.0
        let subjectCenterX = boundingBox.midX
        let originX = subjectCenterX - cropWidth / 2.0

        var crop = CropEngine.CropRect(
            origin: CGPoint(x: originX, y: originY),
            size: CGSize(width: cropWidth, height: cropHeight)
        )
        crop = clampCropToFrame(crop)
        lastComputedCrop = crop

        // Deadzone check
        let currentCenter = CGPoint(x: subjectCenterX, y: (headY + waistY) / 2.0)
        if let lastCenter = lastAcceptedCenter {
            let dx = abs(currentCenter.x - lastCenter.x)
            let dy = abs(currentCenter.y - lastCenter.y)
            if dx < config.deadzoneThreshold && dy < config.deadzoneThreshold {
                return nil
            }
        }

        lastAcceptedCenter = currentCenter
        hasActiveTarget = true
        return crop
    }

    // MARK: - Private: Helpers

    private func clampCropToFrame(_ crop: CropEngine.CropRect) -> CropEngine.CropRect {
        // Ensure crop fits within 0-1 normalized frame
        var h = min(crop.size.height, 1.0)
        var w: CGFloat

        // Enforce minimum zoom (don't zoom in more than 4x)
        h = max(h, 0.25)

        // Maintain aspect ratio
        let desiredWidth = h * config.outputAspectRatio
        if desiredWidth <= 1.0 {
            w = desiredWidth
        } else {
            w = 1.0
            h = w / config.outputAspectRatio
        }

        // Clamp origin so crop stays within frame
        let x = max(0, min(1.0 - w, crop.origin.x))
        let y = max(0, min(1.0 - h, crop.origin.y))

        return CropEngine.CropRect(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h)
        )
    }
}
