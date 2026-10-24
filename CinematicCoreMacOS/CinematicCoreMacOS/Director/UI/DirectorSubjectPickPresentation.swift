import CoreGraphics
import Foundation

/// Pure C-08 display projection. Selection and lock facts never imply identity
/// confidence, editorial readiness or permission to Take.
nonisolated struct DirectorSubjectPickPresentation: Equatable, Sendable {
    let pick: DirectorSubjectPick

    var candidates: [DirectorSubjectPick.Candidate] { pick.isValid ? pick.candidates : [] }
    var canOverride: Bool { pick.isValid && pick.canOverride }

    var owner: String {
        switch pick.provenance {
        case .operatorNomination: return "Your subject"
        case .alfie: return "Alfie's pick"
        case nil: return "Selected subject"
        }
    }

    var line: String {
        guard pick.isValid else { return "Subject view unavailable" }
        switch pick.phase {
        case .unavailable: return "No current subject view"
        case .ambiguous: return "More than one possible subject"
        case .lost: return "Subject lost"
        case .recovering:
            return pick.selectedCandidate != nil ? "Recovering subject · last position" : "Recovering subject"
        case .suggested:
            return pick.selectedCandidate != nil ? "\(owner) · select to acquire" : "No current subject view"
        case .acquiring:
            return pick.selectedCandidate != nil ? "\(owner) · acquiring" : "Acquiring subject"
        case .tracking:
            return pick.selectedCandidate != nil ? "\(owner) · tracking" : "No current subject view"
        }
    }

    var reason: String? {
        guard pick.isValid, pick.selectedCandidate != nil else { return nil }
        switch pick.provenance {
        case .alfie(.positionHint): return "Position hint"
        case .alfie(.centralPresenter): return "Central presenter"
        case .operatorNomination, nil: return nil
        }
    }

    var instruction: String {
        canOverride ? "Click a person to choose your subject" : "Subject selection is read-only"
    }

    func candidateLabel(_ candidate: DirectorSubjectPick.Candidate, index: Int) -> String {
        if candidate.id == pick.selectedCandidateID {
            return "\(owner), \(phaseLabel)"
        }
        return "Person \(index + 1)"
    }

    private var phaseLabel: String {
        switch pick.phase {
        case .suggested: return "suggested, select to acquire"
        case .acquiring: return "acquiring"
        case .tracking: return "tracking"
        case .recovering: return "last position, recovering"
        case .lost: return "lost"
        case .ambiguous: return "ambiguous"
        case .unavailable: return "unavailable"
        }
    }
}

/// The same source-space transform serves camera taps, subject rectangles and
/// the synthetic gallery. Letterbox margins are never selectable pixels.
nonisolated enum DirectorSourceCoordinates {
    static func normalizedPoint(_ location: CGPoint, viewSize: CGSize, imageSize: CGSize,
                                aspectFill: Bool = false) -> CGPoint? {
        guard let display = displayRect(viewSize: viewSize, imageSize: imageSize, aspectFill: aspectFill),
              location.x.isFinite, location.y.isFinite else { return nil }
        let point = CGPoint(x: (location.x - display.minX) / display.width,
                            y: 1 - (location.y - display.minY) / display.height)
        return DirectorSubjectOverrideRequest.isValid(point) ? point : nil
    }

    static func rect(_ bounds: CGRect, viewSize: CGSize, imageSize: CGSize,
                     aspectFill: Bool = false) -> CGRect? {
        guard DirectorSubjectPick.Candidate.validBounds(bounds),
              let display = displayRect(viewSize: viewSize, imageSize: imageSize, aspectFill: aspectFill) else { return nil }
        return CGRect(x: display.minX + bounds.minX * display.width,
                      y: display.minY + (1 - bounds.maxY) * display.height,
                      width: bounds.width * display.width, height: bounds.height * display.height)
    }

    private static func displayRect(viewSize: CGSize, imageSize: CGSize, aspectFill: Bool) -> CGRect? {
        guard [viewSize.width, viewSize.height, imageSize.width, imageSize.height].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return nil
        }
        let scale = aspectFill
            ? max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
            : min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        guard [size.width, size.height].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return CGRect(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
