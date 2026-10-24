// Capture selection is a pure policy so advertised formats can be tested without
// opening a camera. The chosen format is applied only during session setup.
//
// Stage cameras normally deliver the show standard's exact rate. An explicit
// built-in-camera testing option can use that camera's own HD rate instead;
// this exception is labelled and never changes the output standard.
// Webcam mode (video calls through the virtual camera) prefers the show rate too, but when the webcam has no format at that
// rate it falls back to its fastest HD (1080p/720p-class) format and says so,
// rather than refusing the camera. The output keeps the show standard.
// Development builds can give Stage the same fallback
// (`DeveloperFlags.allowStageBelowShowRate`) so ordinary webcams can stand in
// for show cameras.
import Foundation

nonisolated enum CaptureProfilePolicy {
    enum Profile: Sendable, Equatable {
        case stage
        case webcam

        init(_ format: ShotComposer.Config.CinematicFormat) {
            self = format == .webcam ? .webcam : .stage
        }

        var title: String { self == .stage ? "Stage" : "Webcam" }

        /// Stable lowercase name stored in admission fingerprints and
        /// diagnostics manifests. Never change it: stored records match on it.
        var identifier: String { self == .stage ? "stage" : "webcam" }

        /// An actual built-in test fallback is a distinct measured setup.
        /// Merely enabling the option does not relabel a native-rate capture.
        func identifier(for selectionReason: Reason?) -> String {
            self == .stage && selectionReason == .builtInCameraTestBelowShowRate
                ? "stage-built-in-test" : identifier
        }

        var preferredSize: (width: Int, height: Int) {
            switch self {
            case .stage: return (3840, 2160)
            case .webcam: return (1920, 1080)
            }
        }
    }

    struct Candidate: Sendable {
        let width: Int
        let height: Int
        let frameRateRanges: [ClosedRange<Double>]

        func supports(_ rate: Double) -> Bool {
            frameRateRanges.contains { $0.lowerBound <= rate && $0.upperBound >= rate }
        }

        /// Fastest rate any of this format's ranges reaches.
        var maxFrameRate: Double {
            frameRateRanges.map(\.upperBound).max() ?? 0
        }

        /// 1080p-class or smaller: what Webcam mode treats as HD.
        var isHDOrSmaller: Bool { height <= 1080 && width <= 1920 }

        var isWidescreen: Bool {
            height > 0 && abs(Double(width) / Double(height) - 16.0 / 9.0) < 0.02
        }
    }

    enum Reason: Sendable, Equatable {
        case preferred
        case closestWidescreen
        case closestAspect
        /// Webcam only: nothing runs at the show rate, so the webcam's fastest
        /// HD format is used at its own rate.
        case webcamBelowShowRate
        /// Development only: the same fallback for a Stage camera.
        case stageBelowShowRate
        /// Explicit opt-in for a system-identified built-in camera used in tests.
        case builtInCameraTestBelowShowRate

        /// Legacy fallback category. For the actual rate relationship, use
        /// Selection.isBelowShowRate(_:) after selection.
        var isBelowShowRate: Bool {
            self == .webcamBelowShowRate || self == .stageBelowShowRate
                || self == .builtInCameraTestBelowShowRate
        }

        var description: String {
            switch self {
            case .preferred: return "preferred format"
            case .closestWidescreen: return "preferred size unavailable at show rate; using closest 16:9 format"
            case .closestAspect: return "16:9 unavailable at show rate; using closest compatible format"
            case .webcamBelowShowRate: return "webcam has no format at the show rate; using its fastest HD format"
            case .stageBelowShowRate: return "camera has no format at the show rate; development build is using its fastest HD format"
            case .builtInCameraTestBelowShowRate:
                return "built-in camera testing: using its fastest HD format instead of the show rate; output repeats frames when capture runs slower"
            }
        }
    }

    struct Selection: Sendable {
        let index: Int
        let reason: Reason
        /// Capture rate to configure. Equals the show rate except for
        /// a below-show-rate fallback.
        let frameRate: Double

        /// A fallback can also be a fixed rate above the show rate (for
        /// example, 60-only capture against 50). Report the actual comparison.
        func isBelowShowRate(_ showRate: Double) -> Bool { frameRate < showRate }

        func rateLabel(showRate: Double, showStandardTitle: String) -> String {
            frameRate == showRate ? showStandardTitle
                : String(format: "%g fps (show standard %@)", frameRate, showStandardTitle)
        }
    }

    static func select(_ candidates: [Candidate], profile: Profile, showRate: Double,
                       allowStageBelowShowRate: Bool = false,
                       builtInCameraTestEnabled: Bool = false,
                       isBuiltInCamera: Bool = false) -> Selection? {
        guard showRate.isFinite, showRate > 0 else { return nil }
        if let selection = selectAtShowRate(candidates, profile: profile, showRate: showRate) {
            return selection
        }
        switch profile {
        case .webcam:
            return selectFastestHD(candidates, reason: .webcamBelowShowRate)
        case .stage:
            if builtInCameraTestEnabled && isBuiltInCamera {
                return selectFastestHD(candidates, reason: .builtInCameraTestBelowShowRate)
            }
            return allowStageBelowShowRate ? selectFastestHD(candidates, reason: .stageBelowShowRate) : nil
        }
    }

    private static func selectAtShowRate(_ candidates: [Candidate], profile: Profile, showRate: Double) -> Selection? {
        let preferred = profile.preferredSize
        let compatible = candidates.indices.filter {
            candidates[$0].width > 0 && candidates[$0].height > 0 && candidates[$0].supports(showRate)
        }
        if let exact = compatible.first(where: {
            candidates[$0].width == preferred.width && candidates[$0].height == preferred.height
        }) {
            return Selection(index: exact, reason: .preferred, frameRate: showRate)
        }

        let widescreen = compatible.filter { candidates[$0].isWidescreen }
        let pool = widescreen.isEmpty ? compatible : widescreen
        guard let index = pool.min(by: { lhs, rhs in
            let a = candidates[lhs]
            let b = candidates[rhs]
            if profile == .stage {
                let aPixels = Int64(a.width) * Int64(a.height)
                let bPixels = Int64(b.width) * Int64(b.height)
                if aPixels != bPixels { return aPixels > bPixels }
            } else {
                let targetPixels = Double(preferred.width * preferred.height)
                let aDistance = abs(log(Double(a.width * a.height) / targetPixels))
                let bDistance = abs(log(Double(b.width * b.height) / targetPixels))
                if aDistance != bDistance { return aDistance < bDistance }
            }
            let targetAspect = 16.0 / 9.0
            let aAspect = abs(Double(a.width) / Double(a.height) - targetAspect)
            let bAspect = abs(Double(b.width) / Double(b.height) - targetAspect)
            if aAspect != bAspect { return aAspect < bAspect }
            return lhs < rhs
        }) else { return nil }
        return Selection(index: index, reason: widescreen.isEmpty ? .closestAspect : .closestWidescreen,
                         frameRate: showRate)
    }

    /// Fastest rate first (motion matters more than pixels on a call), then
    /// the size nearest 1080p, then 16:9. HD-class formats are preferred over
    /// larger ones whenever the webcam offers any.
    private static func selectFastestHD(_ candidates: [Candidate], reason: Reason) -> Selection? {
        let usable = candidates.indices.filter {
            candidates[$0].width > 0 && candidates[$0].height > 0 && candidates[$0].maxFrameRate > 0
        }
        let hd = usable.filter { candidates[$0].isHDOrSmaller }
        let sized = hd.isEmpty ? usable : hd
        let widescreen = sized.filter { candidates[$0].isWidescreen }
        let pool = widescreen.isEmpty ? sized : widescreen
        guard let bestRate = pool.map({ candidates[$0].maxFrameRate }).max() else { return nil }

        let fastest = pool.filter { abs(candidates[$0].maxFrameRate - bestRate) < 0.01 }
        let target = Double(Profile.webcam.preferredSize.width * Profile.webcam.preferredSize.height)
        guard let index = fastest.min(by: { lhs, rhs in
            let a = candidates[lhs]
            let b = candidates[rhs]
            let aDistance = abs(log(Double(a.width * a.height) / target))
            let bDistance = abs(log(Double(b.width * b.height) / target))
            if aDistance != bDistance { return aDistance < bDistance }
            return lhs < rhs
        }) else { return nil }
        return Selection(index: index, reason: reason, frameRate: bestRate)
    }
}
