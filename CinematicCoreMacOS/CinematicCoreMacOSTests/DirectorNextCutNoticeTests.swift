//
//  DirectorNextCutNoticeTests.swift
//  CinematicCoreMacOSTests
//
//  C-06 software UI evidence only. Controllers are synthetic, and no test
//  opens capture, issues a permit or executes a real cut.
//

import AppKit
import Combine
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct DirectorNextCutNoticeTests {
    @Test func autoNoticeUsesTheFixtureCountdown() {
        #expect(DirectorNextCutGallery.auto.nextCut?.countdown == DirectorNextCutGallery.noticeExample)
        #expect(DirectorNextCutGallery.auto.nextCut?.line == "Next: Cam B · 2 s · Esc to cancel")
    }

    @Test func backupNamesTheNextCutWithoutACountdown() {
        #expect(DirectorNextCutGallery.backup.nextCut?.countdown == nil)
        #expect(DirectorNextCutGallery.backup.nextCut?.line == "Next: Cam B")
    }

    @MainActor private final class OtherController: ObservableObject, DirectorConsoleControlling {
        @Published var directorSection = DirectorNextCutGallery.auto
        var cancelledInputs: [ChannelID] = []
        func cancelNextCut() {
            if let notice = directorSection.nextCut, notice.cancellable {
                cancelledInputs.append(notice.input)
                directorSection.nextCut = nil
            }
        }
        func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult { .accepted }
        func handToAlfie() -> DirectorControlResult { .accepted }
        func takeOver() {}
        func advanceSegment() {}
        func overrideSubject(on channel: ChannelID, at point: CGPoint) {}
    }

    @Test func cancellationWorksWithAnotherControllerAndReadsTheCurrentNotice() {
        let controller = OtherController()
        let notice = DirectorNextCutNotice(controller: controller)
        #expect(notice.cancelCurrentCut())
        #expect(!notice.cancelCurrentCut())
        #expect(controller.cancelledInputs == [.b])

        controller.directorSection = DirectorNextCutGallery.backup
        #expect(!notice.cancelCurrentCut())
        // The same view action must cancel the current replacement, rather
        // than an old captured input or countdown from its earlier rendering.
        controller.directorSection.nextCut = .init(input: .a, countdown: 0.5, cancellable: true)
        #expect(notice.cancelCurrentCut())
        #expect(controller.cancelledInputs == [.b, .a])
    }

    @Test func theGalleryFakeRefusesNoncancellableAndDuplicateCancellation() {
        let controller = FakeNextCutConsole(section: DirectorNextCutGallery.backup)
        controller.cancelNextCut()
        #expect(controller.cancelCount == 0)
        #expect(controller.directorSection.nextCut != nil)
        controller.show(DirectorNextCutGallery.auto)
        controller.cancelNextCut()
        controller.cancelNextCut()
        #expect(controller.cancelCount == 1)
        #expect(controller.directorSection.nextCut == nil)
    }

    private func event(keyCode: UInt16 = 53, modifiers: NSEvent.ModifierFlags = [],
                       repeated: Bool = false, windowNumber: Int = 0) throws -> NSEvent {
        let characters = keyCode == 53 ? String(UnicodeScalar(0x1b)!) : "a"
        return try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: repeated, keyCode: keyCode))
    }

    private func host<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 680, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    @Test func escapeRoutesThroughTheHostedWindowAndCancelsOnlyOnce() throws {
        let controller = OtherController()
        let (host, window) = host(DirectorNextCutNotice(controller: controller))
        #expect(host.fittingSize.height > 0)
        let escape = try event(windowNumber: window.windowNumber)
        #expect(window.performKeyEquivalent(with: escape))
        #expect(controller.cancelledInputs == [.b])
        #expect(!window.performKeyEquivalent(with: escape))
        #expect(controller.cancelledInputs == [.b])
    }

    @Test func aStaleCatcherChecksRemovalAndReplacementBeforeConsumingEsc() throws {
        let controller = FakeNextCutConsole(section: DirectorNextCutGallery.auto)
        let (host, window) = host(DirectorNextCutNotice(controller: controller))
        let catcher = try #require(findEscapeKeyViews(host).first)
        let escape = try event(windowNumber: window.windowNumber)
        // Do not refresh the hosted view: this deliberately exercises its old
        // native callback after the controller's published state has changed.
        controller.removeNotice()
        #expect(!catcher.performKeyEquivalent(with: escape))
        controller.show(DirectorNextCutGallery.backup)
        #expect(!catcher.performKeyEquivalent(with: escape))
        #expect(controller.cancelCount == 0)
        controller.show(DirectorNextCutGallery.auto)
        #expect(catcher.performKeyEquivalent(with: escape))
        #expect(controller.cancelCount == 1)
        #expect(!catcher.performKeyEquivalent(with: escape))
    }

    @Test func onlyTheInteractiveCancellableNoticeInstallsEsc() {
        var absent = DirectorNextCutGallery.auto
        absent.nextCut = nil
        let view = VStack {
            DirectorNextCutNotice(controller: FakeNextCutConsole(section: DirectorNextCutGallery.auto))
            DirectorNextCutNotice(controller: FakeNextCutConsole(section: DirectorNextCutGallery.auto), ownsShortcut: false)
            DirectorNextCutNotice(controller: FakeNextCutConsole(section: DirectorNextCutGallery.backup))
            DirectorNextCutNotice(controller: FakeNextCutConsole(section: absent))
        }
        let (host, window) = host(view)
        #expect(findEscapeKeyViews(host).count == 1)
        #expect(window.contentView === host)
    }

    @Test func escapeDoesNotSwallowModifiedRepeatedOrUnrelatedKeys() throws {
        let catcher = DirectorEscapeKeyView()
        var cancellations = 0
        catcher.onEscape = { cancellations += 1; return true }
        let modifiers: [NSEvent.ModifierFlags] = [.command, .option, .shift, .control]
        for modifier in modifiers {
            #expect(!catcher.performKeyEquivalent(with: try event(modifiers: modifier)))
        }
        #expect(!catcher.performKeyEquivalent(with: try event(keyCode: 0)))
        #expect(!catcher.performKeyEquivalent(with: try event(repeated: true)))
        #expect(cancellations == 0)
        #expect(catcher.performKeyEquivalent(with: try event()))
        #expect(cancellations == 1)
        catcher.onEscape = nil
        #expect(!catcher.performKeyEquivalent(with: try event()))
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

private func findEscapeKeyViews(_ view: NSView) -> [DirectorEscapeKeyView] {
    var found = (view as? DirectorEscapeKeyView).map { [$0] } ?? []
    for child in view.subviews { found += findEscapeKeyViews(child) }
    return found
}

extension DirectorNextCutCard: CustomTestStringConvertible {
    public nonisolated var testDescription: String { id }
}
