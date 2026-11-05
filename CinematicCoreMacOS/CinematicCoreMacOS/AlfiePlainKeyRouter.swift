import AppKit
import Combine

/// Bare character keys deliberately have no SwiftUI menu key equivalent: an
/// equivalent can consume a digit before a text editor gets to insert it.
/// The menu lists the keys, while this monitor either cues or returns the
/// original event untouched for normal AppKit dispatch.
@MainActor
final class AlfiePlainKeyRouter: ObservableObject {
    private let keyWindow: @MainActor () -> NSWindow?
    private let modalWindow: @MainActor () -> NSWindow?
    private var actions: AlfieCommandActions?
    private weak var actionsWindow: NSWindow?
    private var monitor: Any?

    init(installMonitor: Bool = true,
         keyWindow: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow },
         modalWindow: @escaping @MainActor () -> NSWindow? = { NSApp.modalWindow }) {
        self.keyWindow = keyWindow
        self.modalWindow = modalWindow
        if installMonitor {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.route(event) == nil
                }
                return consumed ? nil : event
            }
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Called from Commands whenever its FocusedValue is evaluated. Keeping
    /// this cache unpublished avoids causing another Commands update.
    func update(actions: AlfieCommandActions?) {
        self.actions = actions
        actionsWindow = actions == nil ? nil : keyWindow()
    }

    /// The same path used by the native monitor is directly testable without
    /// installing an application-wide monitor or changing the real key window.
    func route(_ event: NSEvent) -> NSEvent? {
        let permittedFlags: NSEvent.ModifierFlags = [.capsLock, .numericPad]
        guard event.type == .keyDown, !event.isARepeat,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(permittedFlags).isEmpty,
              let window = keyWindow(), window === actionsWindow,
              event.windowNumber == window.windowNumber,
              modalWindow() == nil, !window.isSheet, window.attachedSheet == nil,
              !Self.ownsTextInput(window.firstResponder),
              let characters = event.charactersIgnoringModifiers,
              let definition = AlfieCommandCatalog.definitions.first(where: { definition in
                  let shortcut = definition.shortcut
                  guard let shortcut, shortcut.modifiers.isEmpty,
                        case .character(let character) = shortcut.key else { return false }
                  return characters == String(character)
              }),
              let action = actions?[definition.id] else { return event }

        action.perform()
        return nil
    }

    static func ownsTextInput(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        // NSTextField normally installs an NSTextView field editor as first
        // responder. Cover the control itself, secure editors, TextEditor,
        // and custom text clients without relying on private SwiftUI classes.
        if responder is NSText || responder is NSTextField || responder is any NSTextInputClient {
            return true
        }
        // A compound native text control may focus one of its child views.
        var parent = (responder as? NSView)?.superview
        while let view = parent {
            if view is NSText || view is NSTextField { return true }
            parent = view.superview
        }
        return false
    }
}
