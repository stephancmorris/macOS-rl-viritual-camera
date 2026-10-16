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

    init(section: NextShotStatus.DirectorSection = .atLaunch(qualified: .none)) {
        self.directorSection = section
    }

    @discardableResult
    func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult {
        guard directorSection.canSelect(level) else {
            return .refused("\(level.title), \(NextShotStatus.DirectorSection.notQualifiedCaption)")
        }
        directorSection.level = level
        if level == .manual {
            directorSection.handedToAlfie = false
            directorSection.activity = .paused(.manualMode)
        } else {
            directorSection.handedToAlfie = true
        }
        return .accepted
    }

    @discardableResult
    func handToAlfie() -> DirectorControlResult {
        guard directorSection.level != .manual else {
            return .refused("Choose Assist, Auto or Backup")
        }
        directorSection.handedToAlfie = true
        if case .paused(.operatorTookOver) = directorSection.activity {
            directorSection.activity = .active(.watching)
        }
        return .accepted
    }

    func takeOver() {
        directorSection.handedToAlfie = false
        directorSection.activity = .paused(.operatorTookOver)
    }

    func cancelNextCut() {}
    func advanceSegment() {}
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {}
}
