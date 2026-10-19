//
//  FakeNextCutConsole.swift
//  CinematicCoreMacOS
//
//  Gallery stand-in so Esc can reach cancelNextCut before B-08 wires the
//  live controller. It never touches a camera.
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

    func cancelNextCut() {
        cancelCount += 1
        directorSection.nextCut = nil
    }

    func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .accepted }
    func handToAlfie() -> DirectorControlResult { .accepted }
    func takeOver() {}
    func advanceSegment() {}
    func overrideSubject(on channel: ChannelID, at point: CGPoint) {}
}
