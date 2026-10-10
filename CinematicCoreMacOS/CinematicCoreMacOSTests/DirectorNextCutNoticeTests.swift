//
//  DirectorNextCutNoticeTests.swift
//  CinematicCoreMacOSTests
//
//  C-06: Auto shows the countdown and Esc. Backup shows the next cut with
//  no duration. Esc calls cancelNextCut on the gallery controller.
//

import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct DirectorNextCutNoticeTests {
    @Test func autoNoticeUsesTheFixtureCountdown() {
        let line = DirectorNextCutGallery.auto.nextCut?.line
        #expect(DirectorNextCutGallery.auto.nextCut?.countdown == DirectorNextCutGallery.noticeExample)
        #expect(line == "Next: Cam B · 2 s · Esc to cancel")
    }

    @Test func backupNamesTheNextCutWithoutACountdown() {
        let line = DirectorNextCutGallery.backup.nextCut?.line
        #expect(DirectorNextCutGallery.backup.nextCut?.countdown == nil)
        #expect(line == "Next: Cam B")
        #expect(line?.contains("Esc") == false)
    }

    @Test func escapeCallsCancelNextCut() throws {
        let controller = FakeNextCutConsole(section: DirectorNextCutGallery.auto)
        let catcher = DirectorEscapeKeyView()
        catcher.onEscape = { controller.cancelNextCut() }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: String(UnicodeScalar(0x1b)!),
            charactersIgnoringModifiers: String(UnicodeScalar(0x1b)!),
            isARepeat: false,
            keyCode: 53))
        #expect(catcher.performKeyEquivalent(with: event))
        #expect(controller.cancelCount == 1)
        #expect(controller.directorSection.nextCut == nil)

        let other = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0))
        #expect(catcher.performKeyEquivalent(with: other) == false)
        #expect(controller.cancelCount == 1)
    }

    @Test func onlyACancellableNoticeInstallsEsc() {
        let auto = NSHostingView(rootView: DirectorNextCutNotice(
            controller: FakeNextCutConsole(section: DirectorNextCutGallery.auto)))
        let backup = NSHostingView(rootView: DirectorNextCutNotice(
            controller: FakeNextCutConsole(section: DirectorNextCutGallery.backup)))
        let autoWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 48), styleMask: [.borderless], backing: .buffered, defer: false)
        let backupWindow = NSWindow(contentRect: autoWindow.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        auto.frame = autoWindow.frame
        backup.frame = autoWindow.frame
        autoWindow.contentView = auto
        backupWindow.contentView = backup
        auto.layoutSubtreeIfNeeded()
        backup.layoutSubtreeIfNeeded()
        #expect(findEscapeKeyView(auto) != nil)
        #expect(findEscapeKeyView(backup) == nil)
    }

    @Test(arguments: DirectorNextCutGallery.cards)
    func rendersEachNotice(card: DirectorNextCutCard) throws {
        let view = VStack(alignment: .leading, spacing: 8) {
            Text(card.title.uppercased())
                .font(ConsoleStyle.label(11))
                .foregroundStyle(.white.opacity(0.7))
            DirectorNextCutNotice(controller: card.controller, ownsShortcut: false)
        }
        .padding(24)
        .frame(width: 680, alignment: .topLeading)
        .background(ConsoleStyle.background)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 680, height: 160)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 680)
        guard ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1",
              let path = ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try data.write(to: dir.appendingPathComponent("notice-\(card.id).png"))
    }
}

private func findEscapeKeyView(_ view: NSView) -> DirectorEscapeKeyView? {
    if let found = view as? DirectorEscapeKeyView { return found }
    for subview in view.subviews {
        if let found = findEscapeKeyView(subview) { return found }
    }
    return nil
}

extension DirectorNextCutCard: CustomTestStringConvertible {
    public nonisolated var testDescription: String { id }
}
