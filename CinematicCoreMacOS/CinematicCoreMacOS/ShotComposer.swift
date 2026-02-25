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

/// Shot composer that frames the output around the person detection bounding box.
/// The crop follows the detection box directly — same behavior as FaceTime Center Stage.
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

        /// Padding added around the detection box on each side (fraction of box size).
        /// 0.20 = 20% breathing room above/below/left/right.
        var padding: CGFloat = 0.20

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

    // MARK: - Public Methods

    /// Compose a shot centered on the detected person's bounding box.
    /// Returns a CropRect when the target should be updated, nil when within deadzone.
    func compose(person: PersonDetector.DetectedPerson) -> CropEngine.CropRect? {
        guard config.isEnabled else { return nil }
        return composeFromBoundingBox(person.boundingBox)
    }

    /// Reset state (e.g., when switching subjects or losing track)
    func reset() {
        lastAcceptedCenter = nil
        hasActiveTarget = false
        lastComputedCrop = nil
    }

    // MARK: - Private

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

        var crop = CropEngine.CropRect(
            origin: CGPoint(x: originX, y: originY),
            size: CGSize(width: cropWidth, height: cropHeight)
        )
        crop = clampCropToFrame(crop)
        lastComputedCrop = crop

        // Deadzone: only update when person has moved enough to avoid micro-jitter
        let currentCenter = CGPoint(x: centerX, y: centerY)
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

        // Keep crop within [0, 1] canvas
        let x = max(0, min(1.0 - w, crop.origin.x))
        let y = max(0, min(1.0 - h, crop.origin.y))

        return CropEngine.CropRect(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h)
        )
    }
}
