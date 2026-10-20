import Combine
import CoreGraphics
import Foundation

/// UI refresh is bounded by LiveConsoleModel. Actions and Esc read the current
/// attached controller again, so an old painted notice cannot cancel a later
/// Backup notice or consume Escape after the real notice was removed.
final class LiveDirectorConsoleProxy: ObservableObject, DirectorConsoleControlling {
    typealias Section = NextShotStatus.DirectorSection
    @Published private var sampledSection: Section?
    private let enabled: Bool
    private let readController: () -> (any DirectorConsoleControlling)?

    init(enabled: Bool, controller: @escaping () -> (any DirectorConsoleControlling)?) {
        self.enabled = enabled
        self.readController = controller
    }

    private var current: (any DirectorConsoleControlling)? { enabled ? readController() : nil }
    var directorSection: Section { current?.directorSection ?? .atLaunch(qualified: .none) }

    func sample(_ section: Section?) {
        if section != sampledSection { sampledSection = section }
    }

    @discardableResult
    func setLevel(_ level: Section.Level) -> DirectorControlResult {
        guard let current else { return .refused("Alfie controls are unavailable") }
        let result = current.setLevel(level)
        sample(current.directorSection)
        return result
    }

    @discardableResult
    func handToAlfie() -> DirectorControlResult {
        guard let current else { return .refused("Alfie controls are unavailable") }
        let result = current.handToAlfie()
        sample(current.directorSection)
        return result
    }

    func takeOver() { current?.takeOver(); sample(current?.directorSection) }
    func cancelNextCut() {
        guard let current, current.directorSection.nextCut?.cancellable == true else { return }
        current.cancelNextCut()
        sample(current.directorSection)
    }
    func advanceSegment() { current?.advanceSegment(); sample(current?.directorSection) }
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {
        current?.overrideSubject(on: channel, at: point)
        sample(current?.directorSection)
    }

    @discardableResult
    func overrideSubject(_ request: DirectorSubjectOverrideRequest) -> DirectorControlResult {
        guard let current else { return .refused("Subject selection is unavailable") }
        // Reject a stale painted request before forwarding. The real controller
        // still rechecks roles, route and camera generations at its effect boundary.
        guard let pick = current.directorSection.subjectPicks[request.channel], request.matches(pick) else {
            return .refused("The subject view changed. Choose again.")
        }
        let result = current.overrideSubject(request)
        sample(current.directorSection)
        return result
    }
}
