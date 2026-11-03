//
//  ShotComposerConfig.swift
//  CinematicCoreMacOS
//
//  ShotComposer.Config and its nested option enums.
//  Moved out of ShotComposer.swift unchanged (hygiene B13).
//

import Foundation
import CoreGraphics
import CoreVideo
@preconcurrency import Vision

extension ShotComposer {
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
        /// Derived from the operator mode (Single Cam and Multi Cam are Stage)
        /// and written only by `OperatorModeStore`.
        nonisolated enum CinematicFormat: String, CaseIterable, Identifiable, Sendable {
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

        /// Top-level use case. Defaults to Stage (original behaviour); in the
        /// app `OperatorModeStore` sets it from the operator mode.
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
}
