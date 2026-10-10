//
//  DirectorModeControlTests.swift
//  CinematicCoreMacOSTests
//
//  C-02: launch is Manual, unqualified levels refuse without changing the
//  level, and Hand to Alfie / take over are the toggle's only calls.
//  Set ALFIE_GALLERY_SNAPSHOTS=1 to write the state PNGs.
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct DirectorModeControlTests {
    @Test func everyLaunchIsManual() {
        let controller = FakeDirectorConsole()
        #expect(controller.directorSection == .atLaunch(qualified: .none))
        #expect(controller.directorSection.level == .manual)
        #expect(controller.directorSection.handedToAlfie == false)
        #expect(controller.directorSection.statusLine == "Manual · Alfie is not directing")
    }

    @Test func aQualifiedRigStillLaunchesInManual() {
        let controller = FakeDirectorConsole(
            section: .atLaunch(qualified: .init(assist: true, auto: true, backup: true)))
        #expect(controller.directorSection.level == .manual)
        #expect(controller.directorSection.handedToAlfie == false)
    }

    @Test func unqualifiedLevelIsRefusedAndTheLevelStays() {
        let controller = FakeDirectorConsole()
        let result = controller.setLevel(.auto)
        #expect(result == .refused("Auto, not qualified"))
        #expect(controller.directorSection.level == .manual)
    }

    @Test func choosingAssistHandsControlToAlfie() {
        let controller = FakeDirectorConsole(
            section: .atLaunch(qualified: .init(assist: true, auto: false, backup: false)))
        #expect(controller.setLevel(.assist) == .accepted)
        #expect(controller.directorSection.level == .assist)
        #expect(controller.directorSection.handedToAlfie)
    }

    @Test func takeOverStopsAlfieWithoutChangingTheLevel() {
        let controller = FakeDirectorConsole(
            section: .atLaunch(qualified: .init(assist: true, auto: false, backup: false)))
        controller.setLevel(.assist)
        controller.takeOver()
        #expect(controller.directorSection.level == .assist)
        #expect(controller.directorSection.handedToAlfie == false)
        #expect(controller.directorSection.statusLine == "Paused: you took over")
    }

    @Test func handToAlfieResumesAndManualRefuses() {
        let controller = FakeDirectorConsole()
        #expect(controller.handToAlfie() == .refused("Choose Assist, Auto or Backup"))
        #expect(controller.directorSection.level == .manual)
        let resumed = FakeDirectorConsole(section: NextShotStatus.DirectorSection(
            level: .assist,
            activity: .paused(.operatorTookOver),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: .init(assist: true, auto: false, backup: false),
            handedToAlfie: false,
            runSheet: nil))
        #expect(resumed.handToAlfie() == .accepted)
        #expect(resumed.directorSection.handedToAlfie)
        #expect(resumed.directorSection.statusLine == "Watching · Alfie is not changing shots")
    }

    /// A controller that is not the gallery fake: the view must work with any
    /// `DirectorConsoleControlling` (the live Director is B-03's).
    @MainActor private final class OtherController: ObservableObject, DirectorConsoleControlling {
        @Published var directorSection = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
        func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .refused("not qualified") }
        func handToAlfie() -> DirectorControlResult { .refused("not qualified") }
        func takeOver() {}
        func cancelNextCut() {}
        func advanceSegment() {}
        func overrideSubject(on channel: ChannelID, at point: CGPoint) {}
    }

    @Test func worksWithAnyControllerAndTheLiveDirector() throws {
        _ = DirectorModeControl(controller: OtherController())
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        let live = DirectorModeControl(controller: show.director, ownsShortcut: false)
        let host = NSHostingView(rootView: live.frame(width: 800))
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 0)
    }

    @Test func shortcutIsCommandShiftHAndNotTheStopShortcut() {
        #expect(DirectorHandShortcut.title == "Command Shift H")
        #expect(DirectorHandShortcut.key == KeyEquivalent("h"))
        #expect(DirectorHandShortcut.modifiers == [.command, .shift])
    }

    @Test(arguments: DirectorControlGallery.cards)
    func rendersEachControlState(card: DirectorControlCard) throws {
        let cardView = VStack(alignment: .leading, spacing: 8) {
            Text(card.title.uppercased())
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.7))
            DirectorModeControl(controller: card.controller, ownsShortcut: false, refusal: card.refusal)
        }
        .padding(24)
        .frame(width: 800, alignment: .topLeading)
        .background(ConsoleStyle.background)
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: cardView)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let height = min(max(host.fittingSize.height, 120), 400)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: height)
        window.setContentSize(NSSize(width: 800, height: height))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 800)

        guard ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" else { return }
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOT_DIR"] ?? "", isDirectory: true)
        guard dir.path != "/" else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try data.write(to: dir.appendingPathComponent("control-\(card.id).png"))
    }
}

extension DirectorControlCard: CustomTestStringConvertible {
    public nonisolated var testDescription: String { id }
}
