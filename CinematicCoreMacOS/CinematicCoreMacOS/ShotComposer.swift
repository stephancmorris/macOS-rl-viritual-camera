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
/// The program crop is built from a tighter tracked-subject box first, then
/// expanded into the smallest valid output rectangle for the selected frame
/// profile. This keeps the visible crop tied to the moving speaker instead of
/// drifting toward a near-full-frame view on tall detections.
@MainActor
final class ShotComposer: ObservableObject {

    // MARK: - Configuration

    struct Config: Sendable {
        enum FrameProfile: String, CaseIterable, Identifiable, Sendable {
            case livestream
            case portrait

            var id: String { rawValue }

            var title: String {
                switch self {
                case .livestream:
                    return "Livestream Rectangle"
                case .portrait:
                    return "Portrait Profile"
                }
            }

            var shortTitle: String {
                switch self {
                case .livestream:
                    return "16:9 Stream"
                case .portrait:
                    return "9:16 Portrait"
                }
            }

            var detail: String {
                switch self {
                case .livestream:
                    return "Best for YouTube, switchers, and standard live production."
                case .portrait:
                    return "Secondary vertical framing for profile or social-style outputs."
                }
            }

            var aspectRatio: CGFloat {
                switch self {
                case .livestream:
                    return 16.0 / 9.0
                case .portrait:
                    return 9.0 / 16.0
                }
            }

            var defaultOutputSize: CGSize {
                switch self {
                case .livestream:
                    return CGSize(width: 1920, height: 1080)
                case .portrait:
                    return CGSize(width: 1080, height: 1920)
                }
            }
        }

        enum ShotPreset: String, CaseIterable, Identifiable, Sendable {
            case wideSafety
            case medium
            case waistUp

            var id: String { rawValue }

            var title: String {
                switch self {
                case .wideSafety:
                    return "Wide Safety"
                case .medium:
                    return "Medium"
                case .waistUp:
                    return "Waist Up"
                }
            }

            var detail: String {
                switch self {
                case .wideSafety:
                    return "Keeps more stage context and movement room."
                case .medium:
                    return "Balanced framing for live speaking shots."
                case .waistUp:
                    return "Tighter speaker-led framing for livestream focus."
                }
            }
        }

        /// Vertical framing anchored from the top of the tracked subject box.
        /// Drives how far down the crop extends below the head.
        enum ShotFraming: String, CaseIterable, Identifiable, Sendable {
            case chestUp
            case waistUp

            var id: String { rawValue }

            var title: String {
                switch self {
                case .chestUp:
                    return "Chest"
                case .waistUp:
                    return "Waist"
                }
            }

            /// Fraction of the tracked subject's height the crop should cover,
            /// measured downward from the top of the subject box.
            var subjectHeightFraction: CGFloat {
                switch self {
                case .chestUp:
                    return 0.62
                case .waistUp:
                    return 0.82
                }
            }
        }

        /// Minimum movement (fraction of frame) before updating target crop.
        /// Prevents jitter from small detection noise.
        var deadzoneThreshold: CGFloat = 0.05 // 5% of frame

        /// Smoothing factor per frame (synced to CropEngine.transitionSmoothing)
        var smoothingFactor: Float = 0.10 // 10% per frame

        /// Padding added around the tracked subject box before expanding to the
        /// final output aspect ratio. 0.20 = 20% additional breathing room.
        var padding: CGFloat = 0.20

        /// How long to keep the current target "warm" after detections drop.
        var targetHoldDuration: TimeInterval = 0.75

        /// Horizontal stage margin used to ignore off-stage areas near the frame edges.
        var stageHorizontalMargin: CGFloat = 0.08

        /// Vertical stage margin used to avoid drifting into ceiling or front-row space.
        var stageVerticalMargin: CGFloat = 0.03

        /// Minimum margin to preserve between the speaker bounds and crop edges.
        var edgeSafetyMargin: CGFloat = 0.12

        /// Output frame profile. Default is stream-friendly landscape.
        var frameProfile: FrameProfile = .livestream

        /// Operator-facing shot style.
        var shotPreset: ShotPreset = .waistUp

        /// Vertical framing: chest-up or waist-up. Anchors the crop's top edge
        /// to the top of the tracked subject (plus a small headroom) and
        /// extends downward by a fraction of the subject's height.
        var shotFraming: ShotFraming = .chestUp

        /// Output aspect ratio (width / height)
        var outputAspectRatio: CGFloat {
            frameProfile.aspectRatio
        }

        /// Master toggle
        var isEnabled: Bool = true
    }

    @Published var config = Config()

    private struct FramingTuning {
        let minimumCropHeight: CGFloat
        let horizontalPaddingMultiplier: CGFloat
        let trackedWidthMultiplier: CGFloat
        let trackedAspectFloor: CGFloat
        let poseHeadroomMultiplier: CGFloat
        let poseLowerMarginMultiplier: CGFloat
        let fallbackHeightMultiplier: CGFloat
        let cropHeadroomMultiplier: CGFloat
        let cropLowerMarginMultiplier: CGFloat
    }

    struct GeometrySnapshot: Equatable, Sendable {
        let trackedSubjectRect: CGRect
        let programCropRect: CropEngine.CropRect
    }

    // MARK: - State

    /// Pixel aspect (width / height) of the source frame currently being
    /// composed against. Used to convert the output aspect from pixel space
    /// into normalized (0–1) space. Defaults to 16:9.
    private var sourcePixelAspect: CGFloat = 16.0 / 9.0

    /// Last accepted detection center (for deadzone comparison)
    private var lastAcceptedCenter: CGPoint?

    /// Whether a valid target has been computed at least once
    @Published private(set) var hasActiveTarget: Bool = false

    /// The most recently computed crop (used by training recorder)
    @Published private(set) var lastComputedCrop: CropEngine.CropRect?

    /// The tighter subject box used to derive the visible program crop.
    @Published private(set) var lastTrackedBounds: CGRect?

    /// The latest deterministic tracked-subject/program-crop pair.
    @Published private(set) var lastGeometrySnapshot: GeometrySnapshot?

    /// The currently preferred speaker track, if any.
    @Published private(set) var activeTargetID: UUID?

    /// Operator-selected subject lock. When set, auto-selection must defer to it.
    @Published private(set) var manualLockedTargetID: UUID?

    private var lastTargetSeenTime: TimeInterval?
    private var lastTrackingPoint: CGPoint?
    private var manualLockLostSince: TimeInterval?

    // MARK: - Public Methods

    /// Select the primary speaker to frame.
    ///
    /// Uses a sticky target preference so the camera does not jump eagerly
    /// between people when a second person appears on stage.
    func primaryPerson(
        from persons: [PersonDetector.DetectedPerson]
    ) -> PersonDetector.DetectedPerson? {
        let now = CACurrentMediaTime()

        if let manualLockedTargetID {
            if let lockedPerson = persons.first(where: { $0.id == manualLockedTargetID }) {
                manualLockLostSince = nil
                return finalizeSelection(lockedPerson, now: now)
            }

            if let manualLockLostSince {
                if now - manualLockLostSince > config.targetHoldDuration {
                    clearManualLock()
                    activeTargetID = nil
                    hasActiveTarget = false
                }
            } else {
                manualLockLostSince = now
            }

            return nil
        }

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
        return finalizeSelection(selected, now: now)
    }

    /// Compose a stage-friendly speaker shot.
    /// Returns a CropRect when the target should be updated, nil when within deadzone.
    func compose(person: PersonDetector.DetectedPerson) -> CropEngine.CropRect? {
        guard config.isEnabled else { return nil }

        let subjectBounds = person.boundingBox.standardized

        if let keypoints = person.poseKeypoints,
           keypoints.head.y > keypoints.waist.y {
            let trackedBounds = trackedSubjectBounds(for: person, keypoints: keypoints)
            lastTrackedBounds = trackedBounds
            return composeFromTrackedBounds(
                trackedBounds,
                subjectBounds: subjectBounds,
                trackingCenter: CGPoint(x: trackedBounds.midX, y: trackedBounds.midY)
            )
        }

        let trackedBounds = trackedSubjectBounds(for: person, keypoints: nil)
        lastTrackedBounds = trackedBounds
        return composeFromTrackedBounds(
            trackedBounds,
            subjectBounds: subjectBounds,
            trackingCenter: CGPoint(x: trackedBounds.midX, y: trackedBounds.midY)
        )
    }

    /// Update the source frame's pixel aspect. Called when the capture
    /// format changes or when new pixel buffers arrive with a different
    /// aspect than the active format's declared dimensions.
    func updateSourcePixelAspect(_ aspect: CGFloat) {
        guard aspect.isFinite, aspect > 0 else { return }
        sourcePixelAspect = aspect
    }

    /// Reset state (e.g., when switching subjects or losing track)
    func reset(clearManualLock: Bool = false) {
        lastAcceptedCenter = nil
        hasActiveTarget = false
        lastComputedCrop = nil
        lastTrackedBounds = nil
        activeTargetID = nil
        lastTargetSeenTime = nil
        lastTrackingPoint = nil
        manualLockLostSince = nil

        if clearManualLock {
            manualLockedTargetID = nil
        }
    }

    func lockTarget(_ targetID: UUID) {
        manualLockedTargetID = targetID
        activeTargetID = targetID
        manualLockLostSince = nil
    }

    func clearManualLock() {
        manualLockedTargetID = nil
        manualLockLostSince = nil
    }

    var isManualLockActive: Bool {
        manualLockedTargetID != nil
    }

    // MARK: - Private

    /// Aspect of the crop rect in Vision's normalized coordinate space such
    /// that when the rect is sampled from the source pixels it yields the
    /// configured output pixel aspect.
    private var normalizedAspect: CGFloat {
        config.outputAspectRatio / sourcePixelAspect
    }

    private func composeFromTrackedBounds(
        _ trackedBounds: CGRect,
        subjectBounds: CGRect,
        trackingCenter: CGPoint
    ) -> CropEngine.CropRect? {
        let tuning = framingTuning
        let aspect = normalizedAspect

        // Anchor from the top of the full subject detection (the yellow box)
        // with a small headroom gap so the skull isn't clipped. Vision's
        // coordinate space is bottom-left origin, so the *top* of the subject
        // is maxY. The chest/waist fraction is measured against the full
        // subject height (head to feet), not the focused torso region, so a
        // standing speaker produces a true chest-up or waist-up shot.
        let subjectTop = subjectBounds.maxY
        let headroom = subjectBounds.height * tuning.cropHeadroomMultiplier
        let cropTop = min(1.0, subjectTop + headroom)

        let desiredHeight = subjectBounds.height * config.shotFraming.subjectHeightFraction
        var cropHeight = max(desiredHeight, tuning.minimumCropHeight)
        var cropWidth = cropHeight * aspect

        // Frame-fit while preserving 16:9. If either dimension overflows, shrink
        // both proportionally.
        if cropWidth > 1.0 {
            cropWidth = 1.0
            cropHeight = cropWidth / aspect
        }
        if cropHeight > 1.0 {
            cropHeight = 1.0
            cropWidth = cropHeight * aspect
        }

        let centerX = subjectBounds.midX
        let originX = centerX - cropWidth / 2.0
        let originY = cropTop - cropHeight

        return clampAndAccept(
            CropEngine.CropRect(
                origin: CGPoint(x: originX, y: originY),
                size: CGSize(width: cropWidth, height: cropHeight)
            ),
            trackingCenter: trackingCenter
        )
    }

    private func trackedSubjectBounds(
        for person: PersonDetector.DetectedPerson,
        keypoints: PersonDetector.PoseKeypoints?
    ) -> CGRect {
        let bbox = person.boundingBox.standardized
        let tuning = framingTuning

        if let keypoints, keypoints.head.y > keypoints.waist.y {
            let top = min(bbox.maxY, keypoints.head.y + (bbox.height * tuning.poseHeadroomMultiplier))
            let bottom = max(bbox.minY, keypoints.waist.y - (bbox.height * tuning.poseLowerMarginMultiplier))
            let focusedHeight = max(
                top - bottom,
                bbox.height * tuning.fallbackHeightMultiplier
            )

            let focusedWidth = min(
                bbox.width,
                max(
                    bbox.width * tuning.trackedWidthMultiplier,
                    focusedHeight * tuning.trackedAspectFloor
                )
            )

            return normalizedRect(
                centeredAt: CGPoint(x: bbox.midX, y: (top + bottom) / 2.0),
                size: CGSize(width: focusedWidth, height: focusedHeight)
            )
        }

        let focusedHeight = bbox.height * tuning.fallbackHeightMultiplier
        let focusedWidth = min(
            bbox.width,
            max(
                bbox.width * tuning.trackedWidthMultiplier,
                focusedHeight * tuning.trackedAspectFloor
            )
        )
        let top = bbox.maxY - (bbox.height * 0.03)

        return normalizedRect(
            centeredAt: CGPoint(x: bbox.midX, y: top - (focusedHeight / 2.0)),
            size: CGSize(width: focusedWidth, height: focusedHeight)
        )
    }

    private func clampCropToFrame(_ crop: CropEngine.CropRect) -> CropEngine.CropRect {
        // Preserve the intended crop center while fitting the requested crop
        // into a valid 16:9 rectangle inside the source frame.
        let centerX = crop.origin.x + (crop.size.width / 2.0)
        let centerY = crop.origin.y + (crop.size.height / 2.0)
        let aspect = normalizedAspect

        let minHeight = framingTuning.minimumCropHeight
        let minWidth = minHeight * aspect

        // Enforce strict 16:9 with the larger dimension driving, then cap at
        // the frame while preserving the aspect ratio.
        var w = max(crop.size.width, minWidth)
        var h = max(crop.size.height, minHeight)
        w = max(w, h * aspect)
        h = w / aspect

        if w > 1.0 {
            w = 1.0
            h = w / aspect
        }
        if h > 1.0 {
            h = 1.0
            w = h * aspect
        }

        // Crop position is clamped only to the physical frame. Stage margins
        // are used for subject selection, not for restricting crop movement —
        // the crop must be free to follow a speaker to the edge of frame.
        let proposedX = centerX - (w / 2.0)
        let proposedY = centerY - (h / 2.0)
        let x = max(0.0, min(1.0 - w, proposedX))
        let y = max(0.0, min(1.0 - h, proposedY))

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

    private func finalizeSelection(
        _ selected: PersonDetector.DetectedPerson,
        now: TimeInterval
    ) -> PersonDetector.DetectedPerson {
        activeTargetID = selected.id
        hasActiveTarget = true
        lastTargetSeenTime = now
        lastTrackingPoint = trackingPoint(for: selected)
        return selected
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

    private func normalizedRect(centeredAt center: CGPoint, size: CGSize) -> CGRect {
        let width = min(max(size.width, 0.01), 1.0)
        let height = min(max(size.height, 0.01), 1.0)
        let originX = max(0.0, min(1.0 - width, center.x - (width / 2.0)))
        let originY = max(0.0, min(1.0 - height, center.y - (height / 2.0)))
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private var framingTuning: FramingTuning {
        switch (config.frameProfile, config.shotPreset) {
        case (.livestream, .wideSafety):
            return FramingTuning(
                minimumCropHeight: 0.28,
                horizontalPaddingMultiplier: 0.32,
                trackedWidthMultiplier: 0.90,
                trackedAspectFloor: 0.68,
                poseHeadroomMultiplier: 0.10,
                poseLowerMarginMultiplier: 0.22,
                fallbackHeightMultiplier: 0.74,
                cropHeadroomMultiplier: 0.12,
                cropLowerMarginMultiplier: 0.08
            )
        case (.livestream, .medium):
            return FramingTuning(
                minimumCropHeight: 0.22,
                horizontalPaddingMultiplier: 0.20,
                trackedWidthMultiplier: 0.82,
                trackedAspectFloor: 0.64,
                poseHeadroomMultiplier: 0.08,
                poseLowerMarginMultiplier: 0.18,
                fallbackHeightMultiplier: 0.68,
                cropHeadroomMultiplier: 0.10,
                cropLowerMarginMultiplier: 0.06
            )
        case (.livestream, .waistUp):
            return FramingTuning(
                minimumCropHeight: 0.18,
                horizontalPaddingMultiplier: 0.05,
                trackedWidthMultiplier: 0.76,
                trackedAspectFloor: 0.60,
                poseHeadroomMultiplier: 0.06,
                poseLowerMarginMultiplier: 0.14,
                fallbackHeightMultiplier: 0.62,
                cropHeadroomMultiplier: 0.10,
                cropLowerMarginMultiplier: 0.04
            )
        case (.portrait, .wideSafety):
            return FramingTuning(
                minimumCropHeight: 0.36,
                horizontalPaddingMultiplier: 0.28,
                trackedWidthMultiplier: 0.96,
                trackedAspectFloor: 0.48,
                poseHeadroomMultiplier: 0.16,
                poseLowerMarginMultiplier: 0.16,
                fallbackHeightMultiplier: 0.82,
                cropHeadroomMultiplier: 0.12,
                cropLowerMarginMultiplier: 0.22
            )
        case (.portrait, .medium):
            return FramingTuning(
                minimumCropHeight: 0.30,
                horizontalPaddingMultiplier: 0.18,
                trackedWidthMultiplier: 0.92,
                trackedAspectFloor: 0.44,
                poseHeadroomMultiplier: 0.14,
                poseLowerMarginMultiplier: 0.14,
                fallbackHeightMultiplier: 0.76,
                cropHeadroomMultiplier: 0.10,
                cropLowerMarginMultiplier: 0.18
            )
        case (.portrait, .waistUp):
            return FramingTuning(
                minimumCropHeight: 0.24,
                horizontalPaddingMultiplier: 0.10,
                trackedWidthMultiplier: 0.88,
                trackedAspectFloor: 0.40,
                poseHeadroomMultiplier: 0.12,
                poseLowerMarginMultiplier: 0.12,
                fallbackHeightMultiplier: 0.70,
                cropHeadroomMultiplier: 0.08,
                cropLowerMarginMultiplier: 0.12
            )
        }
    }
}
