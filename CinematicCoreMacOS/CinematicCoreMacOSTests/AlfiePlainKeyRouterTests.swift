import AppKit
import Testing
@testable import Alfie

@MainActor
struct AlfiePlainKeyRouterTests {
    private final class Focus {
        var window: NSWindow?
        var modal: NSWindow?
    }

    private final class Calls {
        var ids: [AlfieCommandCatalog.ID] = []
    }

    private final class KeyView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    /// A text client which is neither NSTextField nor NSTextView.
    private final class CustomTextClient: NSView, NSTextInputClient {
        override var acceptsFirstResponder: Bool { true }
        func insertText(_ string: Any, replacementRange: NSRange) {}
        func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
        func unmarkText() {}
        func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
        func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func hasMarkedText() -> Bool { false }
        func attributedSubstring(forProposedRange range: NSRange,
                                 actualRange: NSRangePointer?) -> NSAttributedString? { nil }
        func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
        func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
        func characterIndex(for point: NSPoint) -> Int { 0 }
    }

    private func fixture() -> (AlfiePlainKeyRouter, Focus, NSWindow, Calls) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let focus = Focus()
        focus.window = window
        let router = AlfiePlainKeyRouter(installMonitor: false,
                                        keyWindow: { focus.window }, modalWindow: { focus.modal })
        let calls = Calls()
        let ids: [AlfieCommandCatalog.ID] = [.cuePreview1, .cuePreview2, .cuePreview3, .cuePreview4]
        router.update(actions: AlfieCommandActions(actions: Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, AlfieCommandAction(title: nil, perform: { calls.ids.append(id) }))
        })))
        return (router, focus, window, calls)
    }

    private func event(_ characters: String = "1", window: NSWindow,
                       modifiers: NSEvent.ModifierFlags = [], repeated: Bool = false,
                       type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: repeated, keyCode: 18))
    }

    @Test func catalogBareCuesRouteOnlyWhenPublished() throws {
        let (router, _, window, calls) = fixture()
        let ids: [AlfieCommandCatalog.ID] = [.cuePreview1, .cuePreview2, .cuePreview3, .cuePreview4]
        for id in ids {
            let shortcut = try #require(AlfieCommandCatalog.definition(for: id).shortcut)
            guard case .character(let key) = shortcut.key else {
                Issue.record("Cue key must be a character")
                continue
            }
            #expect(router.route(try event(String(key), window: window)) == nil)
        }
        #expect(calls.ids == ids)
        router.update(actions: nil)
        let digit = try event(window: window)
        #expect(router.route(digit) === digit)
        #expect(calls.ids == ids)
    }

    @Test func missingIndividualActionDoesNotConsumeTheDigit() throws {
        let (router, _, window, calls) = fixture()
        router.update(actions: AlfieCommandActions(actions: [:]))
        let digit = try event(window: window)
        #expect(router.route(digit) === digit)
        #expect(calls.ids.isEmpty)
    }

    @Test func ordinaryAndSecureFieldEditorsKeepTheirTypingEvents() throws {
        for field in [NSTextField(), NSSecureTextField()] {
            let (router, _, window, calls) = fixture()
            field.frame = NSRect(x: 10, y: 10, width: 240, height: 30)
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
            window.contentView?.addSubview(field)
            #expect(window.makeFirstResponder(field))
            let editor = try #require(window.firstResponder as? NSTextView)
            #expect(editor.isFieldEditor)
            let digit = try event(window: window)
            #expect(router.route(digit) === digit)
            #expect(calls.ids.isEmpty)
            // Returning the original event leaves normal native text input
            // intact; the router must never manually re-dispatch this event.
            editor.keyDown(with: digit)
            #expect(editor.string == "1")
        }
    }

    @Test func textViewAndCustomTextClientKeepTheirEvents() throws {
        let responders: [NSView] = [NSTextView(), CustomTextClient()]
        for responder in responders {
            let (router, _, window, calls) = fixture()
            window.contentView = responder
            #expect(window.makeFirstResponder(responder))
            let digit = try event(window: window)
            #expect(router.route(digit) === digit)
            #expect(calls.ids.isEmpty)
        }
        #expect(AlfiePlainKeyRouter.ownsTextInput(NSTextField()))
    }

    @Test func firstResponderIsCheckedForEveryEventWithoutRefreshingCommands() throws {
        let (router, _, window, calls) = fixture()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        let editor = NSTextView(frame: root.bounds)
        let keyView = KeyView(frame: root.bounds)
        root.addSubview(editor)
        root.addSubview(keyView)
        window.contentView = root
        let digit = try event(window: window)
        #expect(window.makeFirstResponder(editor))
        #expect(router.route(digit) === digit)
        #expect(window.makeFirstResponder(keyView))
        #expect(router.route(digit) == nil)
        #expect(calls.ids == [.cuePreview1])
        #expect(window.makeFirstResponder(editor))
        #expect(router.route(digit) === digit)
        #expect(calls.ids == [.cuePreview1])
    }

    @Test func modifiedRepeatedAndUnrelatedEventsAreUntouched() throws {
        let (router, _, window, calls) = fixture()
        for modifier: NSEvent.ModifierFlags in [.command, .option, .shift, .control, .function, .help] {
            let modified = try event(window: window, modifiers: modifier)
            #expect(router.route(modified) === modified)
        }
        let repeated = try event(window: window, repeated: true)
        #expect(router.route(repeated) === repeated)
        let keyUp = try event(window: window, type: .keyUp)
        #expect(router.route(keyUp) === keyUp)
        for characters in ["", "5", "a", "12", "\u{1b}", "\r"] {
            let unrelated = try event(characters, window: window)
            #expect(router.route(unrelated) === unrelated)
        }
        #expect(calls.ids.isEmpty)
        #expect(router.route(try event(window: window, modifiers: [.capsLock, .numericPad])) == nil)
        #expect(calls.ids == [.cuePreview1])
    }

    @Test func missingModalOrChangedWindowsCannotUseTheCachedSceneActions() throws {
        let (router, focus, window, calls) = fixture()
        let digit = try event(window: window)
        focus.window = nil
        #expect(router.route(digit) === digit)
        focus.window = window
        focus.modal = window
        #expect(router.route(digit) === digit)
        focus.modal = nil
        let otherWindow = NSWindow(contentRect: window.frame, styleMask: [.titled],
                                   backing: .buffered, defer: false)
        focus.window = otherWindow
        let otherDigit = try event(window: otherWindow)
        #expect(router.route(otherDigit) === otherDigit)
        // Even an event naming a different window is not a cue for this one.
        focus.window = window
        #expect(router.route(otherDigit) === otherDigit)
        #expect(calls.ids.isEmpty)
    }
}
