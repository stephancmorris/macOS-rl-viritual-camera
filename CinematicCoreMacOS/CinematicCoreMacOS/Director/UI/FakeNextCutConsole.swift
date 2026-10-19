//
//  FakeNextCutConsole.swift
//  CinematicCoreMacOS
//
//  Synthetic C-06 gallery controller. It never opens capture, issues permits
//  or cuts. Replacing the supplied section is an explicit rehearsal action.
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class FakeNextCutConsole: ObservableObject, DirectorConsoleControlling {
    @Published private(set) var directorSection: NextShotStatus.DirectorSection
    private(set) var cancelCount = 0

    init(section: NextShotStatus.DirectorSection) {
        directorSection = section
    }

    func show(_ section: NextShotStatus.DirectorSection) {
        directorSection = section
    }

    func removeNotice() {
        directorSection.nextCut = nil
    }

    func cancelNextCut() {
        guard directorSection.nextCut?.cancellable == true else { return }
        cancelCount += 1
        directorSection.nextCut = nil
    }

    func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .accepted }
    func handToAlfie() -> DirectorControlResult { .accepted }
    func takeOver() {}
    func advanceSegment() {}
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {}
}
