// Capture selection is a pure policy so advertised formats can be tested without
// opening a camera. The chosen format is applied only during session setup.
import Foundation

nonisolated enum CaptureProfilePolicy {
    enum Profile: Sendable, Equatable {
        case stage
        case webcam

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

        var isWidescreen: Bool {
            height > 0 && abs(Double(width) / Double(height) - 16.0 / 9.0) < 0.02
        }
    }

    enum Reason: Sendable, Equatable {
        case preferred
        case closestWidescreen
        case closestAspect

        var description: String {
            switch self {
            case .preferred: return "preferred format"
            case .closestWidescreen: return "preferred size unavailable at show rate; using closest 16:9 format"
            case .closestAspect: return "16:9 unavailable at show rate; using closest compatible format"
            }
        }
    }

    struct Selection: Sendable {
        let index: Int
        let reason: Reason
    }

    static func select(_ candidates: [Candidate], profile: Profile, showRate: Double) -> Selection? {
        guard showRate.isFinite, showRate > 0 else { return nil }
        let preferred = profile.preferredSize
        let compatible = candidates.indices.filter {
            candidates[$0].width > 0 && candidates[$0].height > 0 && candidates[$0].supports(showRate)
        }
        if let exact = compatible.first(where: {
            candidates[$0].width == preferred.width && candidates[$0].height == preferred.height
        }) {
            return Selection(index: exact, reason: .preferred)
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
        return Selection(index: index, reason: widescreen.isEmpty ? .closestAspect : .closestWidescreen)
    }
}
