//
//  FakeDirectorConsole.swift
//  CinematicCoreMacOS
//
//  Gallery stand-in for DirectorConsoleControlling. The live controller is
//  B-03. This one never touches a camera.
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class FakeDirectorConsole: ObservableObject, DirectorConsoleControlling {
    @Published private(set) var directorSection: NextShotStatus.DirectorSection
    /// Shown when setLevel or handToAlfie returns .refused. Nil after a success.
    @Published var refusalMessage: String?

    init(section: NextShotStatus.DirectorSection = .atLaunch(qualified: .none), refusalMessage: String? = nil) {
        self.directorSection = section
        self.refusalMessage = refusalMessage
    }

    @discardableResult
    func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult {
        guard directorSection.canSelect(level) else {
            let message = "\(level.title), \(NextShotStatus.DirectorSection.notQualifiedCaption)"
            refusalMessage = message
            return .refused(message)
        }
        directorSection.level = level
        if level == .manual {
            directorSection.handedToAlfie = false
            directorSection.activity = .paused(.manualMode)
        } else {
            directorSection.handedToAlfie = true
        }
        refusalMessage = nil
        return .accepted
    }

    @discardableResult
    func handToAlfie() -> DirectorControlResult {
        guard directorSection.level != .manual else {
            let message = "Choose Assist, Auto or Backup"
            refusalMessage = message
            return .refused(message)
        }
        directorSection.handedToAlfie = true
        if case .paused(.operatorTookOver) = directorSection.activity {
            directorSection.activity = .active(.watching)
        }
        refusalMessage = nil
        return .accepted
    }

    func takeOver() {
        directorSection.handedToAlfie = false
        directorSection.activity = .paused(.operatorTookOver)
        refusalMessage = nil
    }

    func cancelNextCut() {}
    func advanceSegment() {}
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {}
}
