#if DEBUG
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import Alfie

/// Runtime regression coverage for the existing view shortcuts while Wave 1's
/// focused Director menu has no publisher. These fixtures never start capture,
/// attach a Director, change flags, or write qualification records.
@Suite(.serialized)
@MainActor
struct DirectorShortcutMenuIntegrationTests {
    private final class HostedScene {
        let window: NSWindow
        private let controller: NSViewController

        init(window: NSWindow, controller: NSViewController) {
            self.window = window
            self.controller = controller
        }
    }

    private func disabledDirectorItems() throws -> [NSMenuItem] {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let menu = try #require(NSApp.mainMenu?.items.first(where: { $0.title == "Director" })?.submenu)
        menu.update()
        let handTitle = AlfieCommandCatalog.definition(for: .directorHand).title
        let advanceTitle = AlfieCommandCatalog.definition(for: .directorAdvance).title
        let hand = try #require(menu.items.first(where: { $0.title == handTitle }))
        let advance = try #require(menu.items.first(where: { $0.title == advanceTitle }))
        #expect(!hand.isEnabled)
        #expect(!advance.isEnabled)
        #expect(hand.keyEquivalent.lowercased() == "h")
        #expect(hand.keyEquivalentModifierMask.intersection([.command, .shift]) == [.command, .shift])
        #expect(advance.keyEquivalent == "\r")
        #expect(advance.keyEquivalentModifierMask.intersection([.command, .shift]) == [.command, .shift])
        return [hand, advance]
    }

    private func host<V: View>(_ view: V) throws -> HostedScene {
        let controller = NSHostingController(rootView: view.frame(width: 1000, height: 260))
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 260)
        controller.view.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return HostedScene(window: window, controller: controller)
    }

    @discardableResult
    private func dispatch(_ id: AlfieCommandCatalog.ID, into window: NSWindow) throws -> Bool {
        let isHand = id == .directorHand
        let keyCode: CGKeyCode = isHand ? 4 : 36
        // Derive text from an unposted hardware-key event so this fixture
        // follows the system keyboard layout and Shift interpretation.
        let hardwareEvent = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        hardwareEvent.flags = [.maskCommand, .maskShift]
        let nativeEvent = try #require(NSEvent(cgEvent: hardwareEvent))
        let characters = try #require(nativeEvent.characters)
        let unmodifiedCharacters = try #require(nativeEvent.charactersIgnoringModifiers)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: unmodifiedCharacters,
            isARepeat: false, keyCode: keyCode))
        // Exercise each native stage once in its normal order. Hosted tests
        // cannot always obtain foreground activation, so do not make a nil
        // application keyWindow look like a swallowed shortcut.
        let handledByWindow = window.performKeyEquivalent(with: event)
        let handledByMenu: Bool
        if handledByWindow {
            handledByMenu = false
        } else {
            let menu = try #require(NSApp.mainMenu)
            handledByMenu = menu.performKeyEquivalent(with: event)
        }
        #expect(handledByWindow || handledByMenu,
                "Native shortcut trace: window=\(handledByWindow), menu=\(handledByMenu)")
        return handledByWindow
    }

    private func pausedSyntheticController() -> FakeDirectorConsole {
        let controller = FakeDirectorConsole(section: .atLaunch(
            qualified: .init(assist: true, auto: false, backup: false)))
        controller.setLevel(.assist)
        controller.takeOver()
        return controller
    }

    @Test(arguments: [false, true])
    func disabledHandMenuLeavesActualDirectorControlsWorking(liveBar: Bool) throws {
        let controller = pausedSyntheticController()
        let fixture: HostedScene
        if liveBar {
            fixture = try host(LiveDirectorControlBar(controller: controller))
        } else {
            // This is the same view and shortcut owner as gallery C-02.
            fixture = try host(DirectorModeControl(controller: controller))
        }
        let window = fixture.window
        defer { window.close(); withExtendedLifetime(fixture) {} }
        let items = try disabledDirectorItems()
        #expect(!controller.directorSection.handedToAlfie)
        try dispatch(.directorHand, into: window)
        #expect(controller.directorSection.handedToAlfie)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        try dispatch(.directorHand, into: window)
        #expect(!controller.directorSection.handedToAlfie)
        #expect(items.allSatisfy { !$0.isEnabled })
    }

    @Test func disabledAdvanceMenuLeavesActualRunSheetStripWorking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("director-key-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let editor = RunSheetEditor(store: RunSheetStore(directory: directory), showID: UUID())
        editor.add(type: .presenter, name: "Opening")
        editor.add(type: .panel, name: "Discussion")
        let first = editor.sheet.currentSegmentID
        let second = try #require(editor.sheet.next?.id)
        let fixture = try host(RunSheetStrip(editor: editor))
        let window = fixture.window
        defer { window.close(); withExtendedLifetime(fixture) {} }
        let items = try disabledDirectorItems()
        #expect(editor.sheet.currentSegmentID == first)
        try dispatch(.directorAdvance, into: window)
        #expect(editor.sheet.currentSegmentID == second)
        #expect(items.allSatisfy { !$0.isEnabled })
    }

    @Test func disabledAdvanceMenuDoesNotPreemptTheActualLiveConsoleHeader() throws {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        var section = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
        section.runSheet = .init(current: "Opening", next: "Discussion")
        let model = LiveConsoleModel(show: show, directorStatusEnabled: true, directorStatus: { section })
        let fixture = try host(LiveConsoleHeader(model: model))
        let window = fixture.window
        defer { window.close(); withExtendedLifetime(fixture) {} }
        let items = try disabledDirectorItems()
        // The real header's shortcut must handle the event. Its show-level
        // action remains inert here because no Director was attached.
        let handledByWindow = try dispatch(.directorAdvance, into: window)
        #expect(handledByWindow)
        #expect(items.allSatisfy { !$0.isEnabled })
        #expect(show.directorCurrentSegmentID == nil)
        #expect(show.directorSectionForConsole == nil)
    }
}
#endif
