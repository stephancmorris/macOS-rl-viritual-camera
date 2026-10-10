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
import CoreVideo
import QuartzCore
import OSLog
@preconcurrency import Vision

/// Shot composer for church-stage speaker framing.
///
/// The program crop is built from a tighter tracked-subject box first, then
/// expanded into the smallest valid output rectangle for the selected frame
/// profile. This keeps the visible crop tied to the moving speaker instead of
/// drifting toward a near-full-frame view on tall detections.
/// Sendable wrapper for handing a CVPixelBuffer across actor boundaries.
/// Declared at file scope so it doesn't inherit ShotComposer's main-actor
/// isolation — needed because `.value` is accessed from detached tasks.
fileprivate struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

@MainActor
final class ShotComposer: ObservableObject {

    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Vision")

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

        nonisolated enum ShotPreset: String, CaseIterable, Identifiable, Sendable {
            case wide
            case fullBody
            case waistUp

            var id: String { rawValue }

            var title: String {
                switch self {
                case .wide: return "Wide"
                case .fullBody: return "Full Body"
                case .waistUp: return "Waist Up"
                }
            }

            var operatorTitle: String {
                switch self {
                case .wide: return "Wide"
                case .fullBody: return "Full Body"
                case .waistUp: return "Waist Up"
                }
            }

            var detail: String {
                switch self {
                case .wide: return "Widest tracked crop (capped at 85% of frame — Return to Wide is the uncropped view)."
                case .fullBody: return "Wide shot with ~2–3 people of context."
                case .waistUp: return "Tightest shot: the speaker with a little context."
                }
            }

            var subjectHeightFraction: CGFloat {
                switch self {
                // Subject-relative so all three presets stay distinct at stage
                // distance, tuned on real church-stage footage (July 2026):
                // each preset sits one "notch" apart — on a typical stage they
                // land at roughly 70% / 55% / 35% of the frame. Frame-fits to
                // the full frame only when the subject is close/large.
                case .wide: return 4.0
                case .fullBody: return 3.0
                case .waistUp: return 1.15
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
                    return "Tight"
                case .waistUp:
                    return "Wide"
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

        var activeFramingTitle: String {
            cinematicFormat == .webcam ? webcamPreset.title : shotPreset.title
        }

        /// Top-level use case. Stage targets distant speakers/performers
        /// (the original behaviour). Webcam targets a close-range subject on a
        /// video call and uses a simpler, tighter, head-anchored framing.
        enum CinematicFormat: String, CaseIterable, Identifiable, Sendable {
            case stage
            case webcam

            var id: String { rawValue }

            var title: String { self == .stage ? "Stage" : "Webcam" }

            var detail: String {
                switch self {
                case .stage:
                    return "Auto-frame a speaker or performer on a stage (distant subjects)."
                case .webcam:
                    return "Close-range framing for a video call or webcam."
                }
            }
        }

        /// Operator-facing crop choice in Webcam format. `wide` is just inside a
        /// full frame; `tight` is a head-and-shoulders shot.
        nonisolated enum WebcamPreset: String, CaseIterable, Identifiable, Sendable {
            case wide
            case tight

            var id: String { rawValue }

            var operatorTitle: String { self == .wide ? "Wide" : "Tight" }
            var title: String { operatorTitle }

            /// Fraction of the tracked subject's height the crop should cover.
            var subjectHeightFraction: CGFloat {
                switch self {
                case .wide: return 1.30
                case .tight: return 0.95
                }
            }
        }

        /// The three discrete auto-pan speeds offered in the UI. Backed by
        /// `autoPanSpeed` phase-rate values consumed in CameraManager's
        /// `.autoPan` case as phase units per second × 3, with phase mapped
        /// onto the visible center range — so the value IS the sweep speed:
        /// Slow crosses the visible travel in ~33 s, Normal ~17 s, Fast ~11 s.
        enum AutoPanSpeed: Float, CaseIterable, Identifiable, Sendable {
            case slow = 0.01
            case normal = 0.02
            case fast = 0.03

            var id: Float { rawValue }

            var title: String {
                switch self {
                case .slow: return "Slow"
                case .normal: return "Normal"
                case .fast: return "Fast"
                }
            }

            /// Nearest option for an arbitrary stored speed, so the control always
            /// shows a selection even if an older value falls between stops.
            static func nearest(to value: Float) -> AutoPanSpeed {
                allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .normal
            }
        }

        /// Beginner-facing tuning bundle. Each non-custom case applies a coherent
        /// set of values across the smoothness↔responsiveness axis (smoothing,
        /// auto-pan speed, deadzone, target hold). `custom` means the operator has
        /// hand-tuned the Advanced sliders away from any named preset.
        enum TuningPreset: String, CaseIterable, Identifiable, Sendable {
            case slowPan
            case balanced
            case fastFollow
            case lockedDown
            case steadyFollow
            case custom

            var id: String { rawValue }

            /// Presets the operator can choose from (excludes `custom`, which is
            /// only ever entered by editing sliders directly).
            /// Steady Follow first: it is the default feel for stage work, so
            /// it leads the list rather than sitting at the end of it.
            static var selectable: [TuningPreset] {
                [.steadyFollow, .balanced, .slowPan, .fastFollow, .lockedDown]
            }

            var title: String {
                switch self {
                case .slowPan: return "Slow Pan"
                case .balanced: return "Balanced"
                case .fastFollow: return "Fast Follow"
                case .lockedDown: return "Locked Down"
                case .steadyFollow: return "Steady Follow"
                case .custom: return "Custom"
                }
            }

            var detail: String {
                switch self {
                case .slowPan:
                    return "Smooth, gentle moves for talks and panels."
                case .balanced:
                    return "Everyday tracking that keeps up without rushing."
                case .fastFollow:
                    return "Snappy tracking for fast-moving presenters."
                case .lockedDown:
                    return "Near-static framing for a fixed podium."
                case .steadyFollow:
                    return "Holds the shot while the speaker stays inside the yellow band; re-centers when they cross it."
                case .custom:
                    return "Custom — adjust the sliders in Advanced."
                }
            }

            /// The tuning bundle this preset applies. `nil` for `custom`.
            /// Order: smoothing, autoPanSpeed, deadzone, targetHold.
            var bundle: (smoothing: Float,
                         autoPanSpeed: Float,
                         deadzone: CGFloat,
                         targetHold: TimeInterval)? {
                switch self {
                // autoPanSpeed is one of the three discrete UI options:
                // Slow 0.01, Normal 0.02, Fast 0.03.
                case .slowPan: return (0.07, 0.01, 0.08, 1.20)
                case .balanced: return (0.10, 0.02, 0.05, 0.75)
                case .fastFollow: return (0.20, 0.03, 0.03, 0.40)
                case .lockedDown: return (0.06, 0.01, 0.12, 2.00)
                // Steady Follow: balanced smoothing; deadzone 0.05 maps to a
                // 0.10 (10%) steady band via the ×2 rule in `apply(_:)`.
                case .steadyFollow: return (0.10, 0.02, 0.05, 0.75)
                case .custom: return nil
                }
            }
        }

        /// Minimum movement (fraction of frame) before updating target crop.
        /// Prevents jitter from small detection noise. Drives the classic
        /// velocity-adaptive gate used by every feel except Steady Follow.
        var deadzoneThreshold: CGFloat = 0.05 // 5% of frame

        /// Full width of the Steady Following band as a fraction of the visible
        /// program crop. While holding, the subject may roam
        /// ±steadyBandWidth/2 of that crop horizontally (and 0.75× that
        /// vertically) around the held center before the camera re-centers.
        /// This keeps the operator-selected tolerance stable as a share of the
        /// output shot rather than enlarging it for a tight crop. Surfaced as
        /// the yellow guide lines in the preview. Only active when
        /// `steadyFollowingEnabled` is true (Steady Follow feel).
        var steadyBandWidth: CGFloat = 0.10

        /// True while the "Steady Follow" feel is selected. Gates the
        /// hold/band state machine + yellow guides; when false the classic
        /// velocity-adaptive deadzone gate runs instead.
        var steadyFollowingEnabled: Bool = true

        /// Spring-response setting (synced to CropEngine.transitionSmoothing).
        var smoothingFactor: Float = 0.10 // 10% per frame

        /// How long to keep the current target "warm" after detections drop.
        var targetHoldDuration: TimeInterval = 0.75

        /// Horizontal stage margin used to ignore off-stage areas near the frame edges.
        var stageHorizontalMargin: CGFloat = 0.08

        /// Vertical stage margin used to avoid drifting into ceiling or front-row space.
        var stageVerticalMargin: CGFloat = 0.04

        /// Speed of the auto pan sweep across the stage. One of the three
        /// discrete UI options: Slow 0.01, Normal 0.02, Fast 0.03 — phase units
        /// per second × 3 over the visible center range (Slow ≈ 33 s per
        /// crossing, Normal ≈ 17 s, Fast ≈ 11 s).
        var autoPanSpeed: Float = 0.02

        /// Vertical center of the auto-pan crop. Vision coordinates: 0 = bottom,
        /// 1 = top of frame. 0.5 keeps the camera at chest height for an
        /// average-height speaker; raise to focus higher (heads), lower for a
        /// fuller-body sweep.
        var autoPanHeight: CGFloat = 0.5

        /// Output frame profile. Default is stream-friendly landscape.
        var frameProfile: FrameProfile = .livestream

        /// Operator-facing shot style.
        var shotPreset: ShotPreset = .wide

        /// Clear space above the detected head as a fraction of the finished
        /// program crop. The quality floor may make the crop much taller than
        /// the requested preset, so this must be measured against the final
        /// crop height rather than the person's bounding box.
        static let defaultFullBodyHeadroom: CGFloat = 0.07
        static let defaultWaistUpHeadroom: CGFloat = 0.06
        static let stageHeadroomRange: ClosedRange<CGFloat> = 0.02...0.20
        private static let fullBodyHeadroomKey = "stageFullBodyHeadroom"
        private static let waistUpHeadroomKey = "stageWaistUpHeadroom"

        var fullBodyHeadroom: CGFloat = defaultFullBodyHeadroom
        var waistUpHeadroom: CGFloat = defaultWaistUpHeadroom

        func headroom(for preset: ShotPreset) -> CGFloat {
            switch preset {
            case .wide: return 0
            case .fullBody: return Self.clampedHeadroom(fullBodyHeadroom)
            case .waistUp: return Self.clampedHeadroom(waistUpHeadroom)
            }
        }

        mutating func setHeadroom(_ value: CGFloat, for preset: ShotPreset,
                                  defaults: UserDefaults = .standard) {
            let value = Self.clampedHeadroom(value)
            switch preset {
            case .wide: return
            case .fullBody:
                fullBodyHeadroom = value
                defaults.set(Double(value), forKey: Self.fullBodyHeadroomKey)
            case .waistUp:
                waistUpHeadroom = value
                defaults.set(Double(value), forKey: Self.waistUpHeadroomKey)
            }
        }

        mutating func resetStageHeadroom(defaults: UserDefaults = .standard) {
            fullBodyHeadroom = Self.defaultFullBodyHeadroom
            waistUpHeadroom = Self.defaultWaistUpHeadroom
            defaults.removeObject(forKey: Self.fullBodyHeadroomKey)
            defaults.removeObject(forKey: Self.waistUpHeadroomKey)
        }

        mutating func restoreStageHeadroom(from defaults: UserDefaults = .standard) {
            if let number = defaults.object(forKey: Self.fullBodyHeadroomKey) as? NSNumber {
                fullBodyHeadroom = Self.clampedHeadroom(CGFloat(number.doubleValue))
            }
            if let number = defaults.object(forKey: Self.waistUpHeadroomKey) as? NSNumber {
                waistUpHeadroom = Self.clampedHeadroom(CGFloat(number.doubleValue))
            }
        }

        private static func clampedHeadroom(_ value: CGFloat) -> CGFloat {
            guard value.isFinite else { return defaultWaistUpHeadroom }
            return min(stageHeadroomRange.upperBound, max(stageHeadroomRange.lowerBound, value))
        }

        /// Vertical framing: chest-up or waist-up. Anchors the crop's top edge
        /// to the top of the tracked subject (plus a small headroom) and
        /// extends downward by a fraction of the subject's height.
        var shotFraming: ShotFraming = .waistUp

        /// Top-level use case. Defaults to Stage (original behaviour).
        var cinematicFormat: CinematicFormat = .stage

        /// Operator-facing crop choice while in Webcam format.
        var webcamPreset: WebcamPreset = .wide

        /// Subject-height fraction for the active format. Stage uses the shot
        /// preset; Webcam uses the webcam preset.
        var activeSubjectHeightFraction: CGFloat {
            switch cinematicFormat {
            case .stage: return shotPreset.subjectHeightFraction
            case .webcam: return webcamPreset.subjectHeightFraction
            }
        }

        /// Output aspect ratio (width / height)
        var outputAspectRatio: CGFloat {
            frameProfile.aspectRatio
        }

        /// Currently selected beginner tuning preset. Defaults to Steady
        /// Follow, whose bundle mirrors the per-field defaults above — the only
        /// difference from Balanced is that the steady band gate is on.
        var tuningPreset: TuningPreset = .steadyFollow

        /// Apply a named tuning preset, writing its bundle into the four
        /// preset-controlled fields. `custom` only records the selection.
        mutating func apply(_ preset: TuningPreset) {
            tuningPreset = preset
            steadyFollowingEnabled = (preset == .steadyFollow)
            guard let bundle = preset.bundle else { return }
            smoothingFactor = bundle.smoothing
            autoPanSpeed = bundle.autoPanSpeed
            deadzoneThreshold = bundle.deadzone
            steadyBandWidth = bundle.deadzone * 2.0
            targetHoldDuration = bundle.targetHold
        }

        /// The preset whose bundle matches the current tuning values (within a
        /// small epsilon), or `.custom` if no preset matches. Used to flip the
        /// selection back to Custom when Advanced sliders are edited.
        var matchedPreset: TuningPreset {
            for preset in TuningPreset.selectable {
                guard let b = preset.bundle else { continue }
                // Steady Follow is a distinct mode, not just different values:
                // it only matches while its gate is on, and no other preset
                // matches while the gate is on.
                guard (preset == .steadyFollow) == steadyFollowingEnabled else { continue }
                if abs(smoothingFactor - b.smoothing) < 0.005,
                   abs(autoPanSpeed - b.autoPanSpeed) < 0.005,
                   abs(steadyBandWidth - b.deadzone * 2.0) < 0.01,
                   abs(targetHoldDuration - b.targetHold) < 0.025 {
                    return preset
                }
            }
            return .custom
        }

        /// Master toggle
        var isEnabled: Bool = true
    }

    @Published var config = Config()

    private struct FramingTuning {
        let minimumCropHeight: CGFloat
        /// Ceiling on the composed crop height. The Wide preset caps at 0.85 so
        /// the widest *preset* stays a visible crop, distinct from Return to
        /// Wide (the uncropped full picture). Everything else allows up to a
        /// full frame-fit.
        let maximumCropHeight: CGFloat
        let horizontalPaddingMultiplier: CGFloat
        let trackedWidthMultiplier: CGFloat
        let trackedAspectFloor: CGFloat
        let poseHeadroomMultiplier: CGFloat
        let poseLowerMarginMultiplier: CGFloat
        let fallbackHeightMultiplier: CGFloat
        let cropHeadroomMultiplier: CGFloat
        let cropLowerMarginMultiplier: CGFloat

        init(minimumCropHeight: CGFloat,
             maximumCropHeight: CGFloat = 1.0,
             horizontalPaddingMultiplier: CGFloat,
             trackedWidthMultiplier: CGFloat,
             trackedAspectFloor: CGFloat,
             poseHeadroomMultiplier: CGFloat,
             poseLowerMarginMultiplier: CGFloat,
             fallbackHeightMultiplier: CGFloat,
             cropHeadroomMultiplier: CGFloat,
             cropLowerMarginMultiplier: CGFloat) {
            self.minimumCropHeight = minimumCropHeight
            self.maximumCropHeight = maximumCropHeight
            self.horizontalPaddingMultiplier = horizontalPaddingMultiplier
            self.trackedWidthMultiplier = trackedWidthMultiplier
            self.trackedAspectFloor = trackedAspectFloor
            self.poseHeadroomMultiplier = poseHeadroomMultiplier
            self.poseLowerMarginMultiplier = poseLowerMarginMultiplier
            self.fallbackHeightMultiplier = fallbackHeightMultiplier
            self.cropHeadroomMultiplier = cropHeadroomMultiplier
            self.cropLowerMarginMultiplier = cropLowerMarginMultiplier
        }
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

    /// Size emitted by the most recent accepted compose, baseline for the
    /// crop-size hysteresis in `clampAndAccept` (keeps the program-crop
    /// rectangle from breathing with Vision bbox noise while the subject is
    /// still). Cleared on reset; rebaselined automatically when framing inputs
    /// change.
    private var lastEmittedCropSize: CGSize?

    /// Relative crop-height delta below which a fresh detection's size is
    /// ignored in favour of the previously emitted size. Above ~5% is a real
    /// approach/retreat, not bbox jitter.
    private static let cropSizeHysteresis: CGFloat = 0.05

    /// Last vertically-emitted crop anchor for TIGHT shots (stage Waist Up,
    /// webcam), baseline for `smoothedVerticalAnchor`. Context shots (Wide /
    /// Full Body) center on body-mid and don't need it.
    private var lastEmittedVerticalAnchor: CGFloat?

    /// Per-frame fraction of a new vertical anchor to adopt for tight shots.
    /// Tight shots anchor the crop's top edge to the subject's HEAD, and a
    /// speaking head bobs at ~1–2 Hz — right where the tracking spring
    /// transmits best, which read as "Waist Up is jumpy". A one-pole low-pass
    /// at the target emitter damps that band (≥60% attenuation at 2 Hz) while
    /// adding only ~60–80 ms of vertical lag. Lateral tracking is untouched.
    private static let verticalAnchorSmoothing: CGFloat = 0.35

    /// Snapshot of the framing inputs the last accepted center was computed under.
    /// When any of these change, the next compose frame bypasses the deadzone gate
    /// once so a new preset/anchor takes effect even when the speaker is still.
    private var lastAppliedFramingFingerprint: FramingFingerprint?

    private var subjectVelocity: CGFloat = 0.0
    private var lastComposeTime: TimeInterval = 0
    private var lastComposeTrackingCenter: CGPoint?

    private struct FramingFingerprint: Equatable {
        let frameProfile: Config.FrameProfile
        let shotPreset: Config.ShotPreset
        let shotFraming: Config.ShotFraming
        let cinematicFormat: Config.CinematicFormat
        let webcamPreset: Config.WebcamPreset
        let fullBodyHeadroom: CGFloat
        let waistUpHeadroom: CGFloat
    }

    private var currentFramingFingerprint: FramingFingerprint {
        FramingFingerprint(
            frameProfile: config.frameProfile,
            shotPreset: config.shotPreset,
            shotFraming: config.shotFraming,
            cinematicFormat: config.cinematicFormat,
            webcamPreset: config.webcamPreset,
            fullBodyHeadroom: config.fullBodyHeadroom,
            waistUpHeadroom: config.waistUpHeadroom
        )
    }

    /// Whether a valid target has been computed at least once.
    /// @Published but written compare-before-write only (transition publish).
    @Published private(set) var hasActiveTarget: Bool = false

    /// The most recently computed crop. Plain per-frame storage — logic
    /// readers (training recorder) read this synchronously; UI reads the
    /// 15 Hz `displayedComputedCrop` mirror instead.
    private(set) var currentComputedCrop: CropEngine.CropRect?

    /// The tighter subject box used to derive the visible program crop.
    /// Plain per-frame storage; UI reads `displayedTrackedBounds`.
    private(set) var currentTrackedBounds: CGRect?

    /// The latest deterministic tracked-subject/program-crop pair. No
    /// producers currently write it; kept plain (non-published) so a future
    /// per-frame writer can't reintroduce per-frame SwiftUI invalidations.
    private(set) var currentGeometrySnapshot: GeometrySnapshot?

    /// 15 Hz UI mirror of `currentComputedCrop` (see `publishDisplayMirrors`).
    @Published private(set) var displayedComputedCrop: CropEngine.CropRect?

    /// 15 Hz UI mirror of `currentTrackedBounds`.
    @Published private(set) var displayedTrackedBounds: CGRect?

    /// Bumped on every per-frame write to the `current*` frame state above.
    /// The 15 Hz coalescer compares it against `publishedFrameStateRevision`
    /// and republishes the mirrors only when something actually changed.
    private var frameStateRevision: UInt64 = 0
    private var publishedFrameStateRevision: UInt64 = 0
    private var displayMirrorTimer: Timer?

    init() {
        // 15 Hz coalescer: the frame path writes plain vars + bumps
        // `frameStateRevision`; this timer republishes the @Published UI
        // mirrors at most 15×/s, and only when the revision moved. The timer
        // fires on the main runloop (scheduled from MainActor init), so
        // `assumeIsolated` is sound.
        displayMirrorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishDisplayMirrors()
            }
        }
    }

    deinit {
        displayMirrorTimer?.invalidate()
    }

    private func publishDisplayMirrors() {
        guard publishedFrameStateRevision != frameStateRevision else { return }
        publishedFrameStateRevision = frameStateRevision
        if displayedComputedCrop != currentComputedCrop {
            displayedComputedCrop = currentComputedCrop
        }
        if displayedTrackedBounds != currentTrackedBounds {
            displayedTrackedBounds = currentTrackedBounds
        }
    }

    /// The currently preferred speaker track, if any.
    /// @Published but written compare-before-write only.
    @Published private(set) var activeTargetID: UUID?

    /// Minimum crop height fraction the CropEngine quality floor allows for
    /// the current delivered source resolution (0 = unconstrained). Pushed by
    /// CameraManager whenever the delivered source height changes so the
    /// composer can anchor floored crops correctly. Plain var — read on the
    /// per-frame compose path, must not publish.
    var qualityFloorHeightFraction: CGFloat = 0

    /// True while the requested shot is tighter than the quality floor permits
    /// (e.g. Waist Up on a 1080p source). Surfaced as a "ZOOM LIMITED" chip so
    /// the operator knows why the shot won't tighten further.
    @Published private(set) var isZoomLimitedByQuality: Bool = false

    /// Transition-only publish: called on the per-frame compose path, so it
    /// must not touch the @Published var unless the value actually changed.
    private func setZoomLimited(_ limited: Bool) {
        if isZoomLimitedByQuality != limited {
            isZoomLimitedByQuality = limited
        }
    }

    // MARK: - Steady Following

    /// The horizontal steady band the camera is currently holding within.
    /// `nil` ⇔ the composer is actively following (no band). Rendered as the
    /// two yellow guide lines in the preview.
    struct SteadyBand: Equatable {
        let centerX: CGFloat
        let width: CGFloat
    }

    /// Non-nil ⇔ holding. The band stays fixed against detection noise; an
    /// operator size move scales its width to the visible program crop.
    @Published private(set) var steadyBand: SteadyBand?

    /// Two-state Steady Following machine. `following` emits targets every
    /// frame (CropEngine spring smooths); `holding` freezes the camera while
    /// the subject roams inside the band. Plain vars — not published.
    private enum SteadyState { case following, holding }
    private var steadyState: SteadyState = .following

    /// Smoothed subject speed (normalized frame units per second) that drives
    /// the velocity-adaptive deadzone. Read-only Director evidence (S3 B-01).
    var subjectSpeed: Double { Double(subjectVelocity) }

    /// The Steady Following machine has concluded the subject settled and is
    /// holding the camera. Read-only Director evidence (S3 B-01).
    var isHoldingSteady: Bool { steadyState == .holding }

    /// Fresh-observation timing for the hold → follow and follow → hold
    /// confirmations. These stay in the detection frame's capture-time clock
    /// domain so their feel does not change with camera/detection cadence.
    private var bandExitStartedAt: TimeInterval?
    private var bandExitLastObservationAt: TimeInterval?
    private var settleStartedAt: TimeInterval?
    private var settleLastObservationAt: TimeInterval?
    /// Position the settle detector is measuring dwell around. Position-based
    /// settling (not velocity): the Vision bbox center jitters a few tenths of
    /// a percent per frame even for a perfectly still subject, which reads as
    /// a nonzero velocity EWMA forever — so dwell-in-a-radius is the signal.
    private var settleAnchor: CGPoint?

    /// Confirmation periods preserve the former two- and twelve-frame feel at
    /// the 50 fps show standard without making slower input look stickier.
    private static let bandExitConfirmation: TimeInterval = 2.0 / 50.0
    private static let settleConfirmation: TimeInterval = 12.0 / 50.0
    /// A long gap means the camera has no continuous evidence of a settled or
    /// out-of-band subject. 150 ms admits 25/50/60 fps sources while rejecting
    /// stale detection work as continuity evidence.
    private static let steadyObservationGap: TimeInterval = 0.150
    /// Vertical half-band as a fraction of the horizontal half-band.
    private static let verticalBandRatio: CGFloat = 0.75

    /// Dwell radius for the settle detector: a quarter of the half-band,
    /// floored at 0.2% of source width — comfortably above bbox jitter, well inside
    /// the band.
    private func settleRadius(for programCropWidth: CGFloat) -> CGFloat {
        max(0.002, programCropWidth * config.steadyBandWidth * 0.125)
    }

    /// Enter the following state and clear the band. Transition-only publish:
    /// only writes `steadyBand` when it actually changes. Also the canonical
    /// reset for the Steady Following machine (reset / lock-loss / mode change),
    /// and safe to call per frame from the legacy gate (compare-before-write).
    private func enterSteadyFollowing() {
        steadyState = .following
        bandExitStartedAt = nil
        bandExitLastObservationAt = nil
        settleStartedAt = nil
        settleLastObservationAt = nil
        settleAnchor = nil
        if steadyBand != nil { steadyBand = nil }
    }

    /// Enter the holding state, re-centering the band on the settled subject.
    /// Transition-only publish.
    private func enterSteadyHolding(centeredOn center: CGPoint, programCropWidth: CGFloat) {
        steadyState = .holding
        bandExitStartedAt = nil
        bandExitLastObservationAt = nil
        settleStartedAt = nil
        settleLastObservationAt = nil
        settleAnchor = nil
        let band = SteadyBand(
            centerX: center.x,
            width: config.steadyBandWidth * min(max(programCropWidth, 0), 1)
        )
        if steadyBand != band { steadyBand = band }
    }

    // MARK: - Lock state machine
    //
    // The lock has a lifecycle: a tap puts it in `tracking`; if the subject
    // goes missing it transitions to `hold` (crop frozen for the configured hold duration); if
    // they don't return it transitions to `wideWaiting` (camera animates
    // to full-frame wide, signature retained for re-acquisition).
    //
    // `manualLockedTargetID` is preserved as a derived published value so
    // existing callers (UI lock-pill, DetectionOverlayView, OperatorPill)
    // keep working unchanged. New callers should consult `lockState`.

    /// One captured reference view of the locked subject. The gallery
    /// holds 6-8 of these covering varied head pose / expression / lighting.
    struct FaceSignature: @unchecked Sendable {
        let featurePrint: VNFeaturePrintObservation
        /// Pose-invariant landmark geometry captured at the same moment.
        /// Nil when Vision returned no landmarks (rare; subject heavily
        /// turned). Re-acquisition falls back to face-print-only matching
        /// against gallery entries that lack landmarks.
        let landmarkVector: LandmarkRatios?
        let capturedAt: TimeInterval
    }

    /// Sliding-window collection of reference signatures captured during
    /// healthy tracking. Compared against during wideWaiting:
    /// re-acquisition takes the *best* (lowest-distance) entry per
    /// candidate, which lets the locked subject return in a pose that
    /// matches only one of the stored views.
    struct FaceSignatureGallery: @unchecked Sendable {
        private(set) var entries: [FaceSignature] = []
        private(set) var lastCaptureAt: TimeInterval = 0

        static let maxSize: Int = 8
        static let captureSpacing: TimeInterval = 0.4
        /// Minimum entries before re-acquisition is allowed to run.
        /// Below this, the gallery hasn't seen enough variation.
        static let readyThreshold: Int = 3

        var isReady: Bool { entries.count >= Self.readyThreshold }
        var size: Int { entries.count }

        /// Append a freshly-captured signature. When the gallery is full,
        /// the oldest entry is evicted (FIFO sliding window) so the
        /// reference adapts to slow lighting / wardrobe drift.
        mutating func append(_ signature: FaceSignature) {
            entries.append(signature)
            if entries.count > Self.maxSize {
                entries.removeFirst(entries.count - Self.maxSize)
            }
            lastCaptureAt = signature.capturedAt
        }

        /// Whether enough time has passed since the last capture to allow
        /// the next one. Throttles the fill so we don't hammer Vision.
        func shouldCapture(at timestamp: TimeInterval) -> Bool {
            timestamp - lastCaptureAt >= Self.captureSpacing
        }
    }

    enum LockState {
        case inactive
        /// Operator tapped a subject; we have a track UUID but haven't locked
        /// yet. Detection runs ROI-only around the subject while the gallery
        /// fills. When `gallery.isReady` we promote to `tracking` (green box)
        /// and cropping begins. No program crop is produced while acquiring.
        case acquiring(targetID: UUID, gallery: FaceSignatureGallery, sinceTime: TimeInterval)
        case tracking(targetID: UUID, gallery: FaceSignatureGallery)
        case hold(targetID: UUID, gallery: FaceSignatureGallery, sinceTime: TimeInterval)
        /// Pulled back to wide, waiting for the original speaker to return.
        /// The gallery may be too small (< readyThreshold) — in that case
        /// re-acquisition is disabled and only an operator action will
        /// move state.
        case wideWaiting(gallery: FaceSignatureGallery)
    }

    @Published private(set) var lockState: LockState = .inactive

    /// Duration the crop holds at last-known position when the locked
    /// subject goes missing, before pulling back to wide. 10 s (Aug 2026,
    /// operator-set): long enough to ride out a speaker stepping off-stage
    /// for a moment without the program flinching, short enough that a real
    /// exit reaches the safety shot quickly.
    static let holdDuration: TimeInterval = 10.0

    // MARK: - Signature capture & re-acquisition

    /// Extractor instance used both for filling the gallery during healthy
    /// tracking and for comparing candidate faces during wideWaiting.
    private let signatureExtractor = FaceSignatureExtractor()

    /// Whether a signature capture is currently in flight. Prevents
    /// multiple concurrent extracts queueing up on a slow Vision call.
    private var signatureCaptureInFlight: Bool = false

    /// Wall-clock of the last frame that upgraded the detection plan for a
    /// gallery refresh scan. Keeps the refresh to the capture throttle even
    /// when the subject's face is not visible (turned away, occluded) — see
    /// `shouldRunGalleryRefreshScan()`.
    private var lastGalleryRefreshAttemptAt: TimeInterval = 0

    /// Returns true at most once per `captureSpacing` while the lock is in
    /// `tracking` and no capture is in flight. The caller upgrades that
    /// frame's detection plan from `.lockedROI` (no face request) to a
    /// face-including ROI scan so `maybeAppendToGallery` can refresh the
    /// gallery — without this, the gallery stays frozen at the 3 signatures
    /// captured during acquisition and re-acquisition can never adapt beyond
    /// those first views.
    ///
    /// The attempt is marked *before* returning, so a subject who is facing
    /// away cannot turn this into a per-frame face inference: locked ROI
    /// dropping the face model every frame was a real latency/load win and
    /// stays the default. Cost when healthy: one extra ~1 ms face-landmarks
    /// inference every ≥0.4 s, scoped to the locked ROI.
    func shouldRunGalleryRefreshScan() -> Bool {
        guard case .tracking = lockState else { return false }
        let now = CACurrentMediaTime()
        guard now - lastGalleryRefreshAttemptAt >= FaceSignatureGallery.captureSpacing else { return false }
        guard !signatureCaptureInFlight else { return false }
        lastGalleryRefreshAttemptAt = now
        return true
    }

    // MARK: - Re-acquisition decision thresholds
    //
    // All `static var` so they can be tuned at runtime without rebuilds.
    // Re-acquisition is allowed only when ALL of these hold:
    //
    //   1. The winning candidate's bestDistance (best-of-gallery print
    //      distance) is below either `absoluteThreshold` (when >1 face
    //      visible) or `soloThreshold` (stricter, when only 1 face).
    //   2. The winning candidate's landmark distance to its
    //      print-best-match gallery entry is below
    //      `landmarkRejectionThreshold`. Else: veto.
    //   3. The winner beats second-best across visible candidates by at
    //      least `marginRatio` (only applies when ≥2 candidates have
    //      recent scores).
    //   4. All of the above hold for `reacquisitionConsecutiveFrames`
    //      consecutive frames.

    /// Print-distance threshold when ≥2 candidates are scoreable this
    /// frame. The margin check carries the discrimination load, so this
    /// can be looser than the solo threshold.
    static var absoluteThreshold: Float = 0.62

    /// Stricter print-distance threshold when only 1 candidate is
    /// scoreable. Without a second candidate to compare against, the
    /// absolute distance has to be tighter to avoid binding to a
    /// look-alike walking back in alone.
    static var soloThreshold: Float = 0.55

    /// Ratio (second-best / best) the best candidate must clear before
    /// binding when ≥2 candidates are visible. 1.25 means the best is at
    /// least 25% closer than the runner-up.
    static var marginRatio: Float = 1.25

    /// Maximum landmark-vector L2 distance allowed between a candidate
    /// and its closest gallery entry. Above this, the candidate is
    /// vetoed regardless of how good their print distance is.
    static var landmarkRejectionThreshold: Float = 0.10

    /// How many consecutive frames the full decision (print + landmarks
    /// + margin) must hold before the lock binds.
    private static let reacquisitionConsecutiveFrames: Int = 3

    /// How long a per-candidate score remains "fresh" for the cross-
    /// candidate margin comparison. Older scores are evicted.
    private static let scoreFreshness: TimeInterval = 0.3

    struct ReacquisitionScore: Sendable {
        let id: UUID
        let printDistance: Float?
        let landmarkDistance: Float?
    }

    /// One decision per completed observation, after ALL visible candidates were scored.
    struct ReacquisitionEvidence {
        private(set) var candidate: UUID?
        private(set) var count = 0
        private var lastObservationID: UInt64?

        mutating func reset() { candidate = nil; count = 0; lastObservationID = nil }

        mutating func consider(observationID: UInt64, scores: [ReacquisitionScore]) -> UUID? {
            // Results can complete out of order when a session/target changes.
            // Only a strictly newer observation may add evidence; duplicates
            // and late older batches are ignored rather than counted twice.
            guard lastObservationID.map({ observationID > $0 }) ?? true else { return nil }
            lastObservationID = observationID
            // Unknown/failed candidates make this observation ambiguous.
            guard !scores.isEmpty, scores.allSatisfy({ $0.printDistance?.isFinite == true }) else {
                candidate = nil; count = 0; return nil
            }
            let eligible = scores.filter { ($0.landmarkDistance ?? 0) <= ShotComposer.landmarkRejectionThreshold }
                .sorted { $0.printDistance! < $1.printDistance! }
            guard let winner = eligible.first,
                  // A landmark-vetoed face is not a viable runner-up and must
                  // not relax the stricter threshold for an effectively solo
                  // candidate.
                  winner.printDistance! < (eligible.count == 1 ? ShotComposer.soloThreshold : ShotComposer.absoluteThreshold),
                  eligible.count < 2 || eligible[1].printDistance! >= winner.printDistance! * ShotComposer.marginRatio else {
                candidate = nil; count = 0; return nil
            }
            count = candidate == winner.id ? count + 1 : 1
            candidate = winner.id
            return count >= ShotComposer.reacquisitionConsecutiveFrames ? winner.id : nil
        }
    }

    private var reacquisitionEvidence = ReacquisitionEvidence()
    private var reacquisitionBatchInFlight = false
    private var recoveryVisibleIDs = Set<UUID>()
    private var recoveryVisibilityRevision: UInt64 = 0
    private var pendingReacquisition: UUID?
    private var lockGeneration: UInt64 = 0
    /// TEST-ONLY: token captured by an asynchronous identity job.
    var identityGenerationForTesting: UInt64 { lockGeneration }
    private var fallbackObservationID: UInt64 = 0
    private var lastGalleryObservationID: UInt64?
    /// Capture time of the newest observation admitted to recovery evidence.
    /// Evidence older than the frame store's lifetime is not allowed to bind.
    private var lastRecoveryObservationAt: TimeInterval?
    private var acquisitionLastSeenAt: TimeInterval = 0
    static let acquisitionTimeout: TimeInterval = 8.0
    @Published private(set) var acquisitionFeedback: String?

    private func invalidateIdentityWork() {
        lockGeneration &+= 1
        reacquisitionEvidence.reset()
        recoveryVisibleIDs.removeAll()
        recoveryVisibilityRevision &+= 1
        pendingReacquisition = nil
        lastGalleryObservationID = nil
        lastRecoveryObservationAt = nil
        lastGalleryRefreshAttemptAt = 0
        // In-flight jobs retain their slot until they finish; generation guards
        // discard their results without allowing unbounded replacement work.
    }

    /// Pause identity decisions when an operator takes the program into a
    /// deterministic mode. Preserve the lock for a later explicit Track request,
    /// but reject any asynchronous gallery/reacquisition result from before it.
    func suspendIdentityWork() {
        invalidateIdentityWork()
    }

    /// Completion gate shared by asynchronous identity work and lifecycle
    /// tests. Retired Pan-era results cannot update recovery evidence.
    @discardableResult
    func finishReacquisitionScoring(
        generation: UInt64,
        visibilityRevision: UInt64,
        observationID: UInt64,
        scores: [ReacquisitionScore]
    ) -> Bool {
        reacquisitionBatchInFlight = false
        guard lockGeneration == generation,
              recoveryVisibilityRevision == visibilityRevision else { return false }
        switch lockState {
        case .hold, .wideWaiting:
            pendingReacquisition = reacquisitionEvidence.consider(
                observationID: observationID, scores: scores)
            return true
        default: return false
        }
    }

    /// Backward-compatible accessor: returns the currently-locked UUID
    /// (when one is bound to a track). Returns nil in `inactive` and
    /// `wideWaiting` — i.e., when no UUID is being tracked this frame.
    /// All existing readers (UI gates, overlay) continue to work.
    var manualLockedTargetID: UUID? {
        switch lockState {
        case .inactive, .wideWaiting:
            return nil
        case .acquiring(let id, _, _), .tracking(let id, _), .hold(let id, _, _):
            return id
        }
    }

    /// The target currently being *acquired* (gallery still filling, not yet
    /// locked). Non-nil only in `acquiring`. Drives the amber overlay box and
    /// the "Acquiring…" button label. Distinct from `activeTargetID`, which is
    /// the locked subject (green box).
    var acquiringTargetID: UUID? {
        if case .acquiring(let id, _, _) = lockState { return id }
        return nil
    }

    /// Whether the lock is mid-acquisition (amber). Exposed for UI.
    var isAcquiring: Bool {
        if case .acquiring = lockState { return true }
        return false
    }

    /// Acquisition progress 0.0–1.0 = captured gallery entries / readyThreshold.
    /// This is the *true* lock-on progress (how close the gallery is to ready),
    /// distinct from per-person detection confidence. Returns nil when not
    /// acquiring. Clamped to 1.0.
    var acquisitionProgress: Double? {
        guard case .acquiring(_, let gallery, _) = lockState else { return nil }
        return min(1.0, Double(gallery.size) / Double(FaceSignatureGallery.readyThreshold))
    }

    /// Operator-facing detail while acquisition is active. The generic
    /// "Acquiring" label alone cannot distinguish a body that is visible from
    /// the missing face samples that are preventing a safe identity lock.
    var acquisitionStatusText: String? {
        guard case .acquiring(_, let gallery, _) = lockState else { return acquisitionFeedback }
        if gallery.size == 0 {
            return "Face not visible — look toward camera"
        }
        return "Learning face \(gallery.size)/\(FaceSignatureGallery.readyThreshold)"
    }

    /// Whether the lock is in the WIDE-WAITING state — armed but pulled
    /// back to a wide shot, scanning for the original speaker to return.
    /// Exposed for UI ("WAITING" pill label).
    var isWideWaiting: Bool {
        if case .wideWaiting = lockState { return true }
        return false
    }

    /// Whether the lock is in HOLD — subject missing, crop frozen.
    var isHolding: Bool {
        if case .hold = lockState { return true }
        return false
    }

    private var lastTrackingPoint: CGPoint?

    // MARK: - Public Methods

    /// Return the locked subject's detection if they are visible and the
    /// lock is in `tracking` state; otherwise nil. During HOLD and
    /// WIDE-WAITING the crop should not be updated, so we return nil and
    /// let the camera-manager either hold the last crop (HOLD) or animate
    /// to wide (WIDE-WAITING — driven by mode switch in `tick`).
    func primaryPerson(
        from persons: [PersonDetector.DetectedPerson]
    ) -> PersonDetector.DetectedPerson? {
        let now = CACurrentMediaTime()

        guard case .tracking(let targetID, _) = lockState else {
            // inactive / hold / wideWaiting — no subject to compose for.
            return nil
        }

        if let lockedPerson = persons.first(where: { $0.id == targetID }) {
            return finalizeSelection(lockedPerson, now: now)
        }

        // Locked target not in this frame's detections. The FSM tick will
        // transition tracking → hold next; for *this* frame we hold the
        // crop by returning nil.
        return nil
    }

    /// Advance the lock state machine for the current frame. Called from
    /// `CameraManager.processFrame` after person detection runs.
    ///
    /// Returns a `TickOutcome` describing any state-driven effect the
    /// camera manager should apply (e.g. pull back to wide).
    enum TickOutcome {
        case noChange
        /// Lock just transitioned hold → wideWaiting. Camera manager should
        /// flip mode to .wide and call `boostFramingTransition()`.
        case pullBackToWide
        /// Lock just transitioned wideWaiting → tracking via re-acquisition
        /// (Step 3). Camera manager should flip mode back to .autoTracking.
        case resumeTracking
        /// Acquisition completed: the gallery reached readyThreshold and the
        /// lock promoted acquiring → tracking. Camera manager should flip to
        /// .autoTracking and boost the framing transition (green box, crop on).
        case acquired
    }

    /// How long acquisition may keep its track-missing grace before giving up
    /// and releasing back to `.inactive` (operator mis-tapped / subject left
    /// before the gallery was ready).
    static let acquireGrace: TimeInterval = 1.5

    @discardableResult
    /// - Parameter isFresh: whether `detections` are new this frame. Detection
    ///   now runs off the frame path, so the same result is presented on
    ///   consecutive frames; anything counting *consecutive sightings* must
    ///   advance only when this is true. The wall-clock transitions in this
    ///   method (`acquireGrace`, `holdDuration`) are unaffected — they read the
    ///   clock, not a frame count, so they stay correct at any tick rate.
    func tick(
        detections: [PersonDetector.DetectedPerson],
        timestamp: TimeInterval,
        pixelBuffer: CVPixelBuffer?,
        isFresh: Bool = true,
        observationID: UInt64? = nil,
        observationTimestamp: TimeInterval? = nil
    ) -> TickOutcome {
        if isFresh { fallbackObservationID &+= 1 }
        let frameID = observationID ?? fallbackObservationID
        let sampleTime = observationTimestamp ?? timestamp
        let isRecovering: Bool = {
            switch lockState {
            case .hold, .wideWaiting: return true
            default: return false
            }
        }()
        if isRecovering {
            // Expire evidence before admitting a newer observation. Otherwise
            // a pending decision from an old batch could bind merely because
            // the same UUID happens to be visible after a long gap.
            if let lastRecoveryObservationAt,
               timestamp - lastRecoveryObservationAt > DetectionFrameStore.maximumAge {
                reacquisitionEvidence.reset()
                recoveryVisibleIDs.removeAll()
                recoveryVisibilityRevision &+= 1
                pendingReacquisition = nil
                self.lastRecoveryObservationAt = nil
            }
            if isFresh {
                lastRecoveryObservationAt = sampleTime
            }
        }
        // Drain any async re-acquisition decision queued from a prior frame's
        // background task. Doing this first keeps all state transitions
        // visible in this single switch.
        if let candidateID = pendingReacquisition {
            pendingReacquisition = nil
            let gallery: FaceSignatureGallery?
            switch lockState {
            case .hold(_, let stored, _), .wideWaiting(let stored): gallery = stored
            default: gallery = nil
            }
            if let gallery, detections.contains(where: { $0.id == candidateID }) {
                lockState = .tracking(targetID: candidateID, gallery: gallery)
                activeTargetID = candidateID
                invalidateIdentityWork()
                enterSteadyFollowing()
                return .resumeTracking
            }
        }

        switch lockState {
        case .inactive:
            return .noChange

        case .acquiring(let targetID, let gallery, let sinceTime):
            if timestamp - sinceTime >= Self.acquisitionTimeout {
                acquisitionFeedback = "Could not learn the face. Tap Detect and try again with the face visible."
                lockState = .inactive
                activeTargetID = nil
                invalidateIdentityWork()
                return .noChange
            }
            let lockedDetection = detections.first { $0.id == targetID }

            if let lockedDetection {
                if isFresh { acquisitionLastSeenAt = sampleTime }
                // Keep filling the gallery from the subject's face. When it
                // reaches readyThreshold we promote to tracking (green box).
                if isFresh, lastGalleryObservationID != frameID {
                    lastGalleryObservationID = frameID
                    maybeAppendToGallery(
                    for: targetID,
                    person: lockedDetection,
                    pixelBuffer: pixelBuffer,
                    gallery: gallery,
                    timestamp: sampleTime
                    )
                }

                if currentGallery(forTarget: targetID)?.isReady ?? gallery.isReady {
                    Self.logger.info("LOCK-STATE old=acquiring new=tracking reason=gallery_ready target=\(String(targetID.uuidString.prefix(8)), privacy: .public)")
                    lockState = .tracking(targetID: targetID, gallery: currentGallery(forTarget: targetID) ?? gallery)
                    activeTargetID = targetID
                    return .acquired
                }
                return .noChange
            }

            // Subject not visible this frame. Allow a short grace (the tap may
            // have briefly missed, or the subject turned). If they stay gone
            // past acquireGrace, release the half-built lock back to inactive.
            if timestamp - acquisitionLastSeenAt >= Self.acquireGrace {
                Self.logger.info("LOCK-STATE old=acquiring new=inactive reason=acquire_timeout target=\(String(targetID.uuidString.prefix(8)), privacy: .public)")
                acquisitionFeedback = "Subject lost during acquisition. Tap Detect to try again."
                lockState = .inactive
                activeTargetID = nil
                invalidateIdentityWork()
                return .noChange
            }
            return .noChange

        case .tracking(let targetID, let gallery):
            let lockedDetection = detections.first { $0.id == targetID }

            if let lockedDetection {
                // Healthy tracking. Opportunistically fill / refresh the
                // gallery — the gallery must reach `readyThreshold` for
                // re-acquisition to ever work after a wide-pull.
                if isFresh, lastGalleryObservationID != frameID {
                    lastGalleryObservationID = frameID
                    maybeAppendToGallery(
                    for: targetID,
                    person: lockedDetection,
                    pixelBuffer: pixelBuffer,
                    gallery: gallery,
                    timestamp: sampleTime
                    )
                }
                return .noChange
            }

            // Subject went missing this frame. Enter HOLD; crop is already
            // at their last position because primaryPerson returned nil
            // so the crop engine's target wasn't updated.
            Self.logger.info("LOCK-STATE old=tracking new=hold reason=subject_absent")
            invalidateIdentityWork()
            lockState = .hold(
                targetID: targetID,
                gallery: gallery,
                sinceTime: timestamp
            )
            // Lock lost the subject — drop out of holding and clear the band.
            enterSteadyFollowing()
            return .noChange

        case .hold(let targetID, let gallery, let sinceTime):
            // If the subject reappears within the hold window, snap back
            // to tracking and resume framing.
            if detections.contains(where: { $0.id == targetID }) {
                Self.logger.info("LOCK-STATE old=hold new=tracking reason=subject_returned")
                lockState = .tracking(targetID: targetID, gallery: gallery)
                return .noChange
            }
            if isFresh, gallery.isReady {
                scheduleReacquisitionScoring(detections: detections, pixelBuffer: pixelBuffer,
                    gallery: gallery, observationID: frameID)
            }
            // Hold window expired? Pull back to wide. Gallery is preserved
            // so re-acquisition can work when the subject returns.
            let held = timestamp - sinceTime
            if held >= Self.holdDuration {
                let heldStr = String(format: "%.2f", held)
                Self.logger.info("LOCK-STATE old=hold new=wide_waiting reason=hold_expired held=\(heldStr, privacy: .public)s gallerySize=\(gallery.size, privacy: .public)")
                lockState = .wideWaiting(gallery: gallery)
                // Pulling back to wide — clear any steady band / holding state.
                enterSteadyFollowing()
                return .pullBackToWide
            }
            return .noChange

        case .wideWaiting(let gallery):
            // Need a usable gallery to do re-acquisition at all.
            guard gallery.isReady else { return .noChange }
            // For each visible person with a detectable face, compare their
            // face against every gallery entry (best-of-N). Decisions
            // arrive on a later tick via `pendingReacquisition`.
            //
            // Fresh detections only: re-acquisition requires N *consecutive
            // matching sightings*, and scoring the same detection twice would
            // let a repeat count as corroboration of itself.
            guard isFresh else { return .noChange }
            scheduleReacquisitionScoring(
                detections: detections,
                pixelBuffer: pixelBuffer,
                gallery: gallery,
                observationID: frameID
            )
            return .noChange
        }
    }

    /// Fire off a signature capture for the locked subject when there is
    /// no existing one OR the existing one is older than the refresh
    /// interval. Runs as a detached task; results are written back to
    /// `lockState` on the main actor with a stale-state guard.
    /// Throttled gallery fill. Fires a new signature capture when:
    ///   - the lock is in `tracking`,
    ///   - the locked subject has a fresh face this frame,
    ///   - enough time has passed since the last capture (`captureSpacing`),
    ///   - no capture is already in flight.
    ///
    /// The captured landmark ratios are also snapshotted into the signature
    /// at the same wall-clock moment so a gallery entry carries *both*
    /// signals captured from the same frame.
    private func maybeAppendToGallery(
        for targetID: UUID,
        person: PersonDetector.DetectedPerson,
        pixelBuffer: CVPixelBuffer?,
        gallery: FaceSignatureGallery,
        timestamp: TimeInterval
    ) {
        guard let pixelBuffer else { return }
        guard let faceBox = person.faceBoundingBox else { return }
        guard !signatureCaptureInFlight else { return }
        guard gallery.shouldCapture(at: timestamp) else { return }

        signatureCaptureInFlight = true
        let bufferBox = SendablePixelBuffer(value: pixelBuffer)
        let captureTimestamp = timestamp
        let extractor = signatureExtractor
        let landmarkVector = person.faceLandmarkRatios
        let generation = lockGeneration

        Task.detached(priority: .userInitiated) { @Sendable [weak self] in
            let result = await Self.runSignatureCapture(
                extractor: extractor,
                bufferBox: bufferBox,
                faceBox: faceBox
            )
            guard let strong = self else { return }
            await MainActor.run {
                strong.signatureCaptureInFlight = false
                guard strong.lockGeneration == generation else { return }
                strong.applySignatureCaptureResult(
                    print: result.print,
                    landmarkVector: landmarkVector,
                    elapsedMs: result.elapsedMs,
                    targetID: targetID,
                    capturedAt: captureTimestamp
                )
            }
        }
    }

    /// Pure non-isolated extraction worker — no `self`, so no actor
    /// isolation is inherited. Performs the Vision request and returns
    /// the print + timing for the main-actor wrapper to apply.
    private static func runSignatureCapture(
        extractor: FaceSignatureExtractor,
        bufferBox: SendablePixelBuffer,
        faceBox: CGRect
    ) async -> (print: VNFeaturePrintObservation?, elapsedMs: Double) {
        let started = CACurrentMediaTime()
        let print = await extractor.extractSignature(
            from: bufferBox.value,
            faceBoundingBox: faceBox
        )
        let elapsedMs = (CACurrentMediaTime() - started) * 1000
        return (print, elapsedMs)
    }

    /// Main-actor side of signature application — runs the stale-state
    /// guard and appends the new entry to the gallery (with FIFO eviction
    /// at maxSize).
    private func applySignatureCaptureResult(
        print: VNFeaturePrintObservation?,
        landmarkVector: LandmarkRatios?,
        elapsedMs: Double,
        targetID: UUID,
        capturedAt: TimeInterval
    ) {
        signatureCaptureInFlight = false
        guard let print else { return }

        let newSig = FaceSignature(
            featurePrint: print,
            landmarkVector: landmarkVector,
            capturedAt: capturedAt
        )

        switch lockState {
        case .acquiring(let currentID, var gallery, let sinceTime) where currentID == targetID:
            gallery.append(newSig)
            let elapsedStr = String(format: "%.1f", elapsedMs)
            let hasLm = landmarkVector != nil ? "yes" : "no"
            Self.logger.info("SIGNATURE captured (acquiring) target=\(String(targetID.uuidString.prefix(8)), privacy: .public) size=\(gallery.size, privacy: .public)/\(FaceSignatureGallery.maxSize, privacy: .public) landmarks=\(hasLm, privacy: .public) in \(elapsedStr, privacy: .public)ms")
            lockState = .acquiring(targetID: targetID, gallery: gallery, sinceTime: sinceTime)
        case .tracking(let currentID, var gallery) where currentID == targetID:
            gallery.append(newSig)
            let elapsedStr = String(format: "%.1f", elapsedMs)
            let hasLm = landmarkVector != nil ? "yes" : "no"
            Self.logger.info("SIGNATURE captured target=\(String(targetID.uuidString.prefix(8)), privacy: .public) size=\(gallery.size, privacy: .public)/\(FaceSignatureGallery.maxSize, privacy: .public) landmarks=\(hasLm, privacy: .public) in \(elapsedStr, privacy: .public)ms")
            lockState = .tracking(targetID: targetID, gallery: gallery)
        case .hold(let currentID, var gallery, let sinceTime) where currentID == targetID:
            gallery.append(newSig)
            lockState = .hold(targetID: targetID, gallery: gallery, sinceTime: sinceTime)
        default:
            break  // discard — state moved on
        }
    }

    /// Read the current gallery bound to `targetID` from `lockState`. Used by
    /// the acquiring branch of `tick()` to check readiness after a capture may
    /// have landed asynchronously on a prior frame.
    private func currentGallery(forTarget targetID: UUID) -> FaceSignatureGallery? {
        switch lockState {
        case .acquiring(let id, let gallery, _) where id == targetID:
            return gallery
        case .tracking(let id, let gallery) where id == targetID:
            return gallery
        case .hold(let id, let gallery, _) where id == targetID:
            return gallery
        default:
            return nil
        }
    }

    /// Compare every visible face against the stored signature. Each
    /// successful per-frame match increments a per-track consecutive
    /// counter; reaching `reacquisitionConsecutiveFrames` queues a
    /// `pendingReacquisition` decision for the next tick.
    private func scheduleReacquisitionScoring(
        detections: [PersonDetector.DetectedPerson],
        pixelBuffer: CVPixelBuffer?,
        gallery: FaceSignatureGallery,
        observationID: UInt64
    ) {
        let candidates = detections.filter { $0.faceBoundingBox != nil }
        let visibleIDs = Set(candidates.map(\.id))
        if recoveryVisibleIDs != visibleIDs {
            recoveryVisibleIDs = visibleIDs
            recoveryVisibilityRevision &+= 1
            reacquisitionEvidence.reset()
            pendingReacquisition = nil
        }
        guard !candidates.isEmpty, let pixelBuffer else {
            reacquisitionEvidence.reset()
            return
        }
        guard !reacquisitionBatchInFlight else { return }
        reacquisitionBatchInFlight = true
        let generation = lockGeneration
        let visibilityRevision = recoveryVisibilityRevision
        let referenceEntries = gallery.entries.map { (print: $0.featurePrint, landmarks: $0.landmarkVector) }
        let bufferBox = SendablePixelBuffer(value: pixelBuffer)
        let extractor = signatureExtractor
        Task.detached(priority: .userInitiated) { [weak self] in
            var scores: [ReacquisitionScore] = []
            for candidate in candidates {
                let result = await Self.runReacquisitionScoring(extractor: extractor,
                    bufferBox: bufferBox, faceBox: candidate.faceBoundingBox!,
                    candidateLandmarks: candidate.faceLandmarkRatios, referenceEntries: referenceEntries)
                scores.append(ReacquisitionScore(id: candidate.id,
                    printDistance: result?.printDistance, landmarkDistance: result?.landmarkDistance))
            }
            let completedScores = scores
            guard let strong = self else { return }
            await MainActor.run {
                strong.finishReacquisitionScoring(
                    generation: generation,
                    visibilityRevision: visibilityRevision,
                    observationID: observationID,
                    scores: completedScores
                )
            }
        }
    }

    /// Pure non-isolated scoring worker. Extracts the candidate face
    /// print, finds the gallery entry with the lowest print distance,
    /// then returns BOTH that print distance and the landmark distance
    /// against the *same* gallery entry. No `self`.
    private static func runReacquisitionScoring(
        extractor: FaceSignatureExtractor,
        bufferBox: SendablePixelBuffer,
        faceBox: CGRect,
        candidateLandmarks: LandmarkRatios?,
        referenceEntries: [(print: VNFeaturePrintObservation, landmarks: LandmarkRatios?)]
    ) async -> (printDistance: Float, landmarkDistance: Float?)? {
        guard let candidatePrint = await extractor.extractSignature(
            from: bufferBox.value,
            faceBoundingBox: faceBox
        ) else { return nil }

        var best: Float = .infinity
        var bestLandmarks: LandmarkRatios? = nil
        for entry in referenceEntries {
            if let d = FaceSignatureExtractor.distance(entry.print, candidatePrint), d < best {
                best = d
                bestLandmarks = entry.landmarks
            }
        }
        guard best.isFinite else { return nil }

        let landmarkDistance: Float? = {
            guard let candidateLandmarks, let bestLandmarks else { return nil }
            return LandmarkRatios.distance(candidateLandmarks, bestLandmarks)
        }()
        return (best, landmarkDistance)
    }

    /// Compose a stage-friendly speaker shot.
    /// Returns a CropRect when the target should be updated, nil when within deadzone.
    /// - Parameters:
    ///   - isFresh: whether this is a new detection observation. Repeated
    ///     detections never contribute to Steady Follow confirmation.
    ///   - observationTimestamp: monotonic capture time of that observation.
    ///     Confirmation uses this rather than display-frame time so it remains
    ///     stable across input and detection rates.
    func compose(
        person: PersonDetector.DetectedPerson,
        isFresh: Bool = true,
        observationTimestamp: TimeInterval? = nil
    ) -> CropEngine.CropRect? {
        guard config.isEnabled else { return nil }
        let sampleTime = observationTimestamp ?? CACurrentMediaTime()

        let subjectBounds = person.boundingBox.standardized

        if let keypoints = person.poseKeypoints,
           keypoints.head.y > keypoints.waist.y {
            let trackedBounds = trackedSubjectBounds(for: person, keypoints: keypoints)
            currentTrackedBounds = trackedBounds
            frameStateRevision &+= 1
            return composeFromTrackedBounds(
                trackedBounds,
                subjectBounds: subjectBounds,
                trackingCenter: CGPoint(x: trackedBounds.midX, y: trackedBounds.midY),
                isFresh: isFresh,
                observationTimestamp: sampleTime
            )
        }

        let trackedBounds = trackedSubjectBounds(for: person, keypoints: nil)
        currentTrackedBounds = trackedBounds
        frameStateRevision &+= 1
        return composeFromTrackedBounds(
            trackedBounds,
            subjectBounds: subjectBounds,
            trackingCenter: CGPoint(x: trackedBounds.midX, y: trackedBounds.midY),
            isFresh: isFresh,
            observationTimestamp: sampleTime
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
        invalidateIdentityWork()
        acquisitionFeedback = nil
        lastAcceptedCenter = nil
        lastAppliedFramingFingerprint = nil
        // @Published transition state: compare-before-write (reset can run
        // repeatedly on the frame path when detections drop).
        if hasActiveTarget { hasActiveTarget = false }
        if activeTargetID != nil { activeTargetID = nil }
        lastSubjectHeight = nil
        visibleZoomHeight = nil
        currentComputedCrop = nil
        currentTrackedBounds = nil
        frameStateRevision &+= 1
        lastTrackingPoint = nil

        subjectVelocity = 0.0
        lastComposeTime = 0
        lastComposeTrackingCenter = nil
        lastEmittedCropSize = nil
        lastEmittedVerticalAnchor = nil

        // Steady Following returns to following + clears the guide lines.
        enterSteadyFollowing()

        if clearManualLock {
            Self.logger.info("LOCK-STATE old=\(self.lockStateName, privacy: .public) new=inactive reason=reset")
            lockState = .inactive
        }
    }

    /// Operator tapped a person — start acquisition. Enters `acquiring` with
    /// an empty gallery; detection runs ROI-only around the subject while the
    /// gallery fills. No program crop is produced yet (amber box). When the
    /// gallery reaches `readyThreshold` the FSM promotes to `tracking` (green
    /// box) and cropping begins. Accuracy/consistency over instant lock.
    func lockTarget(_ targetID: UUID) {
        lastSubjectHeight = nil
        visibleZoomHeight = nil
        acquisitionFeedback = nil
        acquisitionLastSeenAt = CACurrentMediaTime()
        Self.logger.info("LOCK-STATE old=\(self.lockStateName, privacy: .public) new=acquiring reason=operator_select target=\(String(targetID.uuidString.prefix(8)), privacy: .public)")
        lockState = .acquiring(
            targetID: targetID,
            gallery: FaceSignatureGallery(),
            sinceTime: CACurrentMediaTime()
        )
        activeTargetID = nil
        lastAcceptedCenter = nil
        lastAppliedFramingFingerprint = nil
        lastEmittedCropSize = nil
        lastEmittedVerticalAnchor = nil
        enterSteadyFollowing()
        invalidateIdentityWork()
    }

    /// Operator pressed Return to Wide / unlock — discard all lock state.
    func clearManualLock() {
        Self.logger.info("LOCK-STATE old=\(self.lockStateName, privacy: .public) new=inactive reason=operator_release")
        lockState = .inactive
        invalidateIdentityWork()
        enterSteadyFollowing()
    }

    /// TEST-ONLY: promote the current `.acquiring` lock straight to `.tracking`,
    /// exactly as `tick()` does when the gallery reaches `readyThreshold`. Lets
    /// unit tests exercise post-lock behavior without running Vision. Never
    /// call from app code.
    func forceTrackingForTesting() {
        guard case .acquiring(let id, let gallery, _) = lockState else { return }
        lockState = .tracking(targetID: id, gallery: gallery)
    }

    var isManualLockActive: Bool {
        if case .inactive = lockState { return false }
        return true
    }

    /// Human-readable name of the current state for logging.
    private var lockStateName: String {
        switch lockState {
        case .inactive: return "inactive"
        case .acquiring: return "acquiring"
        case .tracking: return "tracking"
        case .hold: return "hold"
        case .wideWaiting: return "wide_waiting"
        }
    }

    // MARK: - Private

    /// Aspect of the crop rect in Vision's normalized coordinate space such
    /// that when the rect is sampled from the source pixels it yields the
    /// configured output pixel aspect.
    var normalizedAspect: CGFloat {
        config.outputAspectRatio / sourcePixelAspect
    }

    private var lastSubjectHeight: CGFloat?
    private var visibleZoomHeight: CGFloat?

    func setVisibleZoomHeight(_ height: CGFloat?) {
        visibleZoomHeight = height
        if let height, let band = steadyBand {
            let updated = SteadyBand(centerX: band.centerX, width: height * normalizedAspect * config.steadyBandWidth)
            if updated != band { steadyBand = updated }
        }
    }

    func reapplyFraming() {
        visibleZoomHeight = nil
        lastAppliedFramingFingerprint = nil
    }

    func destinationHeight(for preset: OperatorCommand.Preset) -> CGFloat? {
        guard let subjectHeight = lastSubjectHeight else { return nil }
        var destination = config
        switch preset {
        case .stage(let shot): destination.shotPreset = shot
        case .webcam(let shot): destination.webcamPreset = shot
        }
        return composedHeight(subjectHeight: subjectHeight, config: destination)
    }

    private func composedHeight(subjectHeight: CGFloat, config: Config) -> CGFloat {
        let tuning = framingTuning(for: config)
        let desired = subjectHeight * config.activeSubjectHeightFraction
        let height = max(qualityFloorHeightFraction,
                         min(tuning.maximumCropHeight, max(desired, tuning.minimumCropHeight, qualityFloorHeightFraction)))
        return min(height, 1, 1 / normalizedAspect)
    }

    private func composeFromTrackedBounds(
        _ trackedBounds: CGRect,
        subjectBounds: CGRect,
        trackingCenter: CGPoint,
        isFresh: Bool,
        observationTimestamp: TimeInterval
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
        let webcamHeadroom = subjectBounds.height * tuning.cropHeadroomMultiplier
        let webcamCropTop = min(1.0, subjectTop + webcamHeadroom)

        // Use the active format's height fraction (stage preset or webcam preset).
        let desiredHeight = subjectBounds.height * config.activeSubjectHeightFraction

        // Apply the CropEngine quality floor HERE, where the desired framing is
        // known, so setTargetCrop's own clamp becomes a no-op double-guard for
        // composer crops instead of silently re-shaping them.
        setZoomLimited(desiredHeight < qualityFloorHeightFraction)
        lastSubjectHeight = subjectBounds.height
        let cropHeight = composedHeight(subjectHeight: subjectBounds.height, config: config)
        let cropWidth = cropHeight * aspect

        let centerX = subjectBounds.midX
        let originX = centerX - cropWidth / 2.0

        let originY: CGFloat
        let isTightShot: Bool
        if config.cinematicFormat == .stage, config.shotPreset == .wide {
            // Wide retains its stage-context composition.
            originY = subjectBounds.midY - (cropHeight / 2.0)
            isTightShot = false
        } else if config.cinematicFormat == .stage {
            // Place the head at the selected percentage of the actual output
            // height. A hard quality floor enlarges the crop below the head
            // instead of adding half of that enlargement above it.
            let headroom = cropHeight * config.headroom(for: config.shotPreset)
            var bottom = subjectTop + headroom - cropHeight
            if config.shotPreset == .fullBody {
                // Keep the shoes and a little floor visible when the physical
                // frame and crop height permit the full person to fit.
                if cropHeight >= subjectBounds.height {
                    let availableMargin = cropHeight - subjectBounds.height
                    let feetMargin = min(subjectBounds.height * tuning.cropLowerMarginMultiplier,
                                         availableMargin)
                    bottom = min(bottom, subjectBounds.minY - feetMargin)
                }
            }
            originY = bottom
            isTightShot = true
        } else {
            // Webcam composition retains its existing close-range framing.
            originY = webcamCropTop - (desiredHeight / 2.0) - (cropHeight / 2.0)
            isTightShot = true
        }

        // Tight shots anchor to the head — damp natural head-bob before the
        // target reaches the spring (see `verticalAnchorSmoothing`).
        var emittedOriginY = originY
        if isTightShot {
            emittedOriginY = smoothedVerticalAnchor(
                originY,
                framingChanged: lastAppliedFramingFingerprint != currentFramingFingerprint
            )
        }

        return clampAndAccept(
            CropEngine.CropRect(
                origin: CGPoint(x: originX, y: emittedOriginY),
                size: CGSize(width: cropWidth, height: cropHeight)
            ),
            trackingCenter: trackingCenter,
            isFresh: isFresh,
            observationTimestamp: observationTimestamp
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

    /// One-pole low-pass on the tight shot's vertical anchor. First frame (or
    /// a framing change) adopts the raw value outright; afterwards each fresh
    /// target moves the emitted anchor only `verticalAnchorSmoothing` of the
    /// remaining distance.
    private func smoothedVerticalAnchor(_ y: CGFloat, framingChanged: Bool) -> CGFloat {
        guard !framingChanged, let last = lastEmittedVerticalAnchor else {
            lastEmittedVerticalAnchor = y
            return y
        }
        let smoothed = last + (y - last) * Self.verticalAnchorSmoothing
        lastEmittedVerticalAnchor = smoothed
        return smoothed
    }

    private func clampAndAccept(
        _ crop: CropEngine.CropRect,
        trackingCenter: CGPoint,
        isFresh: Bool,
        observationTimestamp: TimeInterval
    ) -> CropEngine.CropRect? {
        let fingerprint = currentFramingFingerprint
        let framingChanged = lastAppliedFramingFingerprint != fingerprint

        // Crop-SIZE hysteresis. Position has noise gates (deadzone / Steady
        // Follow band), but the crop's width/height are re-derived from the
        // Vision bbox height every fresh detection, and bbox height wobbles a
        // few percent even for a perfectly still subject — the program-crop
        // rectangle visibly breathed as a result. Below the hysteresis band
        // the previously emitted size is reused (re-centered on the fresh
        // position, so tracking stays responsive); real approach/retreat
        // drifts past the band in 5% quantized steps, which reads as a calm
        // reframe rather than noise. A framing change rebaselines via the
        // emitted-size store below.
        var stabilized = crop
        if !framingChanged,
           let last = lastEmittedCropSize,
           last.height > 0.01, crop.size.height > 0.01 {
            let relativeDelta = abs(crop.size.height - last.height) / last.height
            if relativeDelta < Self.cropSizeHysteresis {
                let centerX = crop.origin.x + crop.size.width / 2
                let centerY = crop.origin.y + crop.size.height / 2
                stabilized.size = last
                stabilized.origin = CGPoint(
                    x: centerX - last.width / 2,
                    y: centerY - last.height / 2
                )
            }
        }

        lastEmittedCropSize = clampCropToFrame(stabilized).size
        if let height = visibleZoomHeight {
            var center = stabilized.center
            if config.cinematicFormat == .webcam || config.shotPreset == .waistUp {
                center.y = stabilized.origin.y + stabilized.size.height - height / 2
            }
            stabilized = .init(center: center, size: CGSize(width: height * normalizedAspect, height: height))
        }
        let clampedCrop = visibleZoomHeight == nil ? clampCropToFrame(stabilized) :
            stabilized.clampedToQualityFloor(.init(minCropHeightFraction: qualityFloorHeightFraction)).clamped()
        currentComputedCrop = clampedCrop
        frameStateRevision &+= 1

        // Calculate velocity for dynamic deadzone
        let now = CACurrentMediaTime()
        if let lastCenter = lastComposeTrackingCenter, lastComposeTime > 0 {
            let dt = max(now - lastComposeTime, 0.001)
            let distance = hypot(trackingCenter.x - lastCenter.x, trackingCenter.y - lastCenter.y)
            let instantVelocity = distance / CGFloat(dt)
            // Smooth the velocity to prevent noise spikes
            subjectVelocity = (subjectVelocity * 0.8) + (instantVelocity * 0.2)
        }
        lastComposeTrackingCenter = trackingCenter
        lastComposeTime = now

        // Every feel except Steady Follow uses the classic velocity-adaptive
        // deadzone gate. `enterSteadyFollowing()` is compare-before-write, so
        // calling it per frame is safe — it guarantees a stale band / yellow
        // guides clear when the operator switches feel away from Steady Follow.
        guard config.steadyFollowingEnabled else {
            enterSteadyFollowing()

            // Dynamic deadzone: if subject is moving fast (e.g. > 2% of screen
            // per second), shrink deadzone to allow continuous tracking for the
            // spring physics. If they are slow, use the configured deadzone to
            // lock down.
            let isMoving = subjectVelocity > 0.02
            let effectiveDeadzone = isMoving ? 0.005 : config.deadzoneThreshold

            // Deadzone: skip updates when the tracked subject anchor hasn't
            // moved enough to matter, so we don't chase detection noise. Bypass
            // the gate once whenever framing inputs change so a new
            // preset/anchor takes effect even with a stationary speaker.
            if !framingChanged, let lastCenter = lastAcceptedCenter {
                let dx = abs(trackingCenter.x - lastCenter.x)
                let dy = abs(trackingCenter.y - lastCenter.y)
                if dx < effectiveDeadzone && dy < effectiveDeadzone {
                    return nil
                }
            }

            lastAcceptedCenter = trackingCenter
            lastAppliedFramingFingerprint = fingerprint
            if !hasActiveTarget { hasActiveTarget = true }
            return clampedCrop
        }

        // Steady Following: a two-state machine, active only for the Steady
        // Follow feel. While `holding`, the subject may roam within the steady
        // band and no new target is emitted (the camera stays put); while
        // `following`, targets are emitted every frame and the CropEngine
        // spring smooths them. Transitions publish `steadyBand`.
        // A band is a proportion of the active program crop, not of the whole
        // source frame. Once holding begins, use the published band width so
        // later bbox-size noise cannot make a parked shot's guides drift.
        let programBandWidth = config.steadyBandWidth * clampedCrop.size.width
        let halfWidth = (steadyBand?.width ?? programBandWidth) / 2.0
        let verticalHalf = halfWidth * Self.verticalBandRatio
        let settleRadius = settleRadius(for: clampedCrop.size.width)

        // Framing inputs changed (new preset/anchor): force back to following,
        // clear the band, and accept one centering target immediately so the
        // new framing takes effect even with a stationary speaker.
        if framingChanged {
            enterSteadyFollowing()
            lastAcceptedCenter = trackingCenter
            lastAppliedFramingFingerprint = fingerprint
            if !hasActiveTarget { hasActiveTarget = true }
            return clampedCrop
        }

        switch steadyState {
        case .holding:
            guard let bandCenter = lastAcceptedCenter else {
                // No band center recorded (shouldn't happen while holding) —
                // recover by resuming following and accepting.
                enterSteadyFollowing()
                lastAcceptedCenter = trackingCenter
                if !hasActiveTarget { hasActiveTarget = true }
                return clampedCrop
            }
            let dx = abs(trackingCenter.x - bandCenter.x)
            let dy = abs(trackingCenter.y - bandCenter.y)
            if dx > halfWidth || dy > verticalHalf {
                // Repeats are not evidence. Fresh capture timestamps preserve
                // the former debounce duration at every supported cadence.
                if isFresh {
                    let isContinuous = bandExitLastObservationAt.map {
                        observationTimestamp >= $0
                            && observationTimestamp - $0 <= Self.steadyObservationGap
                    } ?? true
                    if !isContinuous { bandExitStartedAt = observationTimestamp }
                    if bandExitStartedAt == nil { bandExitStartedAt = observationTimestamp }
                    bandExitLastObservationAt = observationTimestamp
                    if let startedAt = bandExitStartedAt,
                       observationTimestamp - startedAt >= Self.bandExitConfirmation {
                        // Confirmed band exit — resume following and accept.
                        enterSteadyFollowing()
                        lastAcceptedCenter = trackingCenter
                        if !hasActiveTarget { hasActiveTarget = true }
                        return clampedCrop
                    }
                }
            } else if isFresh {
                bandExitStartedAt = nil
                bandExitLastObservationAt = nil
            }
            // Still holding — emit no new target; the camera stays parked.
            return nil

        case .following:
            // Position-based settle detection: velocity EWMA never reads as
            // zero (Vision bbox jitter alone registers ~0.1–0.3 frame-widths/s
            // for a still subject), so settling is dwell-in-a-radius instead.
            // Once the subject stays within `settleRadius` of the anchor for
            // `settleConfirmation` of capture time, re-enter holding,
            // centered on the ANCHOR (not the instantaneous jittered center),
            // and accept one final centering target.
            //
            // Fresh detections only. A repeated detection sits at *exactly* the
            // anchor, so every repeat would be a guaranteed increment — at
            // interval 2 half the evidence for "they have stopped moving" would
            // be manufactured by the detection cadence, and the camera would
            // park about twice as readily as it does today.
            if isFresh {
                if let anchor = settleAnchor,
                   hypot(trackingCenter.x - anchor.x, trackingCenter.y - anchor.y) <= settleRadius {
                    let isContinuous = settleLastObservationAt.map {
                        observationTimestamp >= $0
                            && observationTimestamp - $0 <= Self.steadyObservationGap
                    } ?? true
                    if !isContinuous { settleStartedAt = observationTimestamp }
                } else {
                    settleAnchor = trackingCenter
                    settleStartedAt = observationTimestamp
                }
                if settleStartedAt == nil { settleStartedAt = observationTimestamp }
                settleLastObservationAt = observationTimestamp
                if let startedAt = settleStartedAt,
                   observationTimestamp - startedAt >= Self.settleConfirmation,
                   let anchor = settleAnchor {
                    enterSteadyHolding(centeredOn: anchor, programCropWidth: clampedCrop.size.width)
                    lastAcceptedCenter = anchor
                    lastAppliedFramingFingerprint = fingerprint
                    if !hasActiveTarget { hasActiveTarget = true }
                    return clampedCrop
                }
            }
            // Keep following — emit a target every frame.
            lastAcceptedCenter = trackingCenter
            lastAppliedFramingFingerprint = fingerprint
            if !hasActiveTarget { hasActiveTarget = true }
            return clampedCrop
        }
    }

    private func finalizeSelection(
        _ selected: PersonDetector.DetectedPerson,
        now: TimeInterval
    ) -> PersonDetector.DetectedPerson {
        // Runs once per accepted frame — compare-before-write so a steady
        // subject doesn't fire objectWillChange 30-50×/s.
        if activeTargetID != selected.id { activeTargetID = selected.id }
        if !hasActiveTarget { hasActiveTarget = true }
        lastTrackingPoint = trackingPoint(for: selected)
        return selected
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

    private var framingTuning: FramingTuning { framingTuning(for: config) }

    private func framingTuning(for config: Config) -> FramingTuning {
        switch config.cinematicFormat {
        case .webcam:
            return webcamFramingTuning(for: config)
        case .stage:
            return stageFramingTuning(for: config)
        }
    }

    /// Close-range framing tuned for a video call: low headroom, low minimum
    /// crop height, and tight side padding (single near subject, no stage
    /// context to preserve).
    private func webcamFramingTuning(for config: Config) -> FramingTuning {
        switch config.webcamPreset {
        case .wide:
            return FramingTuning(
                minimumCropHeight: 0.40,
                horizontalPaddingMultiplier: 0.18,
                trackedWidthMultiplier: 0.92,
                trackedAspectFloor: 0.60,
                poseHeadroomMultiplier: 0.10,
                poseLowerMarginMultiplier: 0.14,
                fallbackHeightMultiplier: 0.80,
                cropHeadroomMultiplier: 0.08,
                cropLowerMarginMultiplier: 0.10
            )
        case .tight:
            return FramingTuning(
                minimumCropHeight: 0.30,
                horizontalPaddingMultiplier: 0.12,
                trackedWidthMultiplier: 0.88,
                trackedAspectFloor: 0.56,
                poseHeadroomMultiplier: 0.08,
                poseLowerMarginMultiplier: 0.10,
                fallbackHeightMultiplier: 0.72,
                cropHeadroomMultiplier: 0.08,
                cropLowerMarginMultiplier: 0.06
            )
        }
    }

    private func stageFramingTuning(for config: Config) -> FramingTuning {
        switch (config.frameProfile, config.shotPreset) {
        case (.livestream, .wide):
            return FramingTuning(
                minimumCropHeight: 0.70,
                maximumCropHeight: 0.85,
                horizontalPaddingMultiplier: 0.50,
                trackedWidthMultiplier: 1.00,
                trackedAspectFloor: 0.80,
                poseHeadroomMultiplier: 0.15,
                poseLowerMarginMultiplier: 0.25,
                fallbackHeightMultiplier: 0.90,
                cropHeadroomMultiplier: 0.25,
                cropLowerMarginMultiplier: 0.25
            )
        case (.livestream, .fullBody):
            return FramingTuning(
                minimumCropHeight: 0.55,
                maximumCropHeight: 0.85,
                horizontalPaddingMultiplier: 0.32,
                trackedWidthMultiplier: 0.90,
                trackedAspectFloor: 0.68,
                poseHeadroomMultiplier: 0.10,
                poseLowerMarginMultiplier: 0.22,
                fallbackHeightMultiplier: 0.74,
                cropHeadroomMultiplier: 0.15, // Important: extra headroom
                cropLowerMarginMultiplier: 0.15 // Important: ensure shoes are visible
            )
        case (.livestream, .waistUp):
            return FramingTuning(
                minimumCropHeight: 0.35,
                maximumCropHeight: 0.80,
                horizontalPaddingMultiplier: 0.15,
                trackedWidthMultiplier: 0.76,
                trackedAspectFloor: 0.60,
                poseHeadroomMultiplier: 0.08,
                poseLowerMarginMultiplier: 0.14,
                fallbackHeightMultiplier: 0.62,
                cropHeadroomMultiplier: 0.12,
                cropLowerMarginMultiplier: 0.05
            )
        case (.portrait, .wide):
            return FramingTuning(
                minimumCropHeight: 0.65,
                maximumCropHeight: 0.85,
                horizontalPaddingMultiplier: 0.28,
                trackedWidthMultiplier: 0.96,
                trackedAspectFloor: 0.48,
                poseHeadroomMultiplier: 0.16,
                poseLowerMarginMultiplier: 0.16,
                fallbackHeightMultiplier: 0.82,
                cropHeadroomMultiplier: 0.18,
                cropLowerMarginMultiplier: 0.22
            )
        case (.portrait, .fullBody):
            return FramingTuning(
                minimumCropHeight: 0.45,
                maximumCropHeight: 0.85,
                horizontalPaddingMultiplier: 0.18,
                trackedWidthMultiplier: 0.92,
                trackedAspectFloor: 0.44,
                poseHeadroomMultiplier: 0.14,
                poseLowerMarginMultiplier: 0.14,
                fallbackHeightMultiplier: 0.76,
                cropHeadroomMultiplier: 0.15,
                cropLowerMarginMultiplier: 0.18
            )
        case (.portrait, .waistUp):
            return FramingTuning(
                minimumCropHeight: 0.30,
                maximumCropHeight: 0.85,
                horizontalPaddingMultiplier: 0.10,
                trackedWidthMultiplier: 0.88,
                trackedAspectFloor: 0.40,
                poseHeadroomMultiplier: 0.12,
                poseLowerMarginMultiplier: 0.12,
                fallbackHeightMultiplier: 0.70,
                cropHeadroomMultiplier: 0.12,
                cropLowerMarginMultiplier: 0.12
            )
        }
    }
}
