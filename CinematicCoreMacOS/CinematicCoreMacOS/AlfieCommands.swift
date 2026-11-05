import SwiftUI

/// A screen publishes only the actions that are valid for its current state.
/// For Escape, publish the matching label (Cancel Detect / Done Editing Live).
@MainActor
struct AlfieCommandAction {
    var title: String? = nil
    let perform: @MainActor () -> Void
}

@MainActor
struct AlfieCommandActions {
    var actions: [AlfieCommandCatalog.ID: AlfieCommandAction] = [:]

    subscript(_ id: AlfieCommandCatalog.ID) -> AlfieCommandAction? { actions[id] }
}

private struct AlfieCommandActionsKey: FocusedValueKey {
    typealias Value = AlfieCommandActions
}

extension FocusedValues {
    /// Publish with `.focusedSceneValue(\.alfieCommands, actions)` so commands
    /// follow the active scene, including while a control inside it has focus.
    var alfieCommands: AlfieCommandActions? {
        get { self[AlfieCommandActionsKey.self] }
        set { self[AlfieCommandActionsKey.self] = newValue }
    }
}

/// Wave 1 defines the menus; Wave 2 screens publish their focused actions.
/// With no publisher every item is disabled, including the retained Stop key.
struct AlfieCommands: Commands {
    @FocusedValue(\.alfieCommands) private var actions
    @StateObject private var plainKeys = AlfiePlainKeyRouter()

    var body: some Commands {
        // This is plain routing storage, not a published state mutation.
        // Native digit events use the same focused action set as the menus.
        let _ = plainKeys.update(actions: actions)

        CommandMenu("Session") {
            command(.singleCam)
            command(.multiCam)
            command(.webcam)
            Divider()
            command(.detect)
            command(.cancel)
            Divider()
            command(.stopSession)
        }
        CommandMenu("Shot") {
            command(.wide)
            command(.fullBody)
            command(.waistUp)
            Divider()
            command(.pushIn)
            command(.pullOut)
        }
        CommandMenu("Multi Cam") {
            command(.cuePreview1)
            command(.cuePreview2)
            command(.cuePreview3)
            command(.cuePreview4)
            Divider()
            command(.take)
        }
        CommandGroup(after: .sidebar) {
            command(.showInspector)
        }
        #if DEBUG
        CommandMenu("Director") {
            command(.directorHand)
            command(.directorAdvance)
        }
        #endif
    }

    private func command(_ id: AlfieCommandCatalog.ID) -> some View {
        let definition = AlfieCommandCatalog.definition(for: id)
        let action = actions?[id]
        return Button(Self.menuTitle(for: definition, action: action)) {
            action?.perform()
        }
        .disabled(action == nil)
        .keyboardShortcut(Self.menuShortcut(for: definition))
    }

    /// Plain digits are listed explicitly and dispatched by the native
    /// responder-aware router. Registering them with keyboardShortcut would
    /// let a menu consume typing before a text field can receive the event.
    static func menuTitle(for definition: AlfieCommandCatalog.Definition,
                          action: AlfieCommandAction?) -> String {
        let title = action?.title ?? definition.title
        if let shortcut = definition.shortcut, shortcut.modifiers.isEmpty,
           case .character(let character) = shortcut.key {
            return "\(title) (key \(character))"
        }
        return title
    }

    static func menuShortcut(for definition: AlfieCommandCatalog.Definition) -> KeyboardShortcut? {
        guard let shortcut = definition.shortcut else { return nil }
        // Unmodified character shortcuts must preserve text input.
        if shortcut.modifiers.isEmpty, case .character = shortcut.key { return nil }
        let key: KeyEquivalent
        switch shortcut.key {
        case .character(let character): key = KeyEquivalent(character)
        case .escape: key = .escape
        case .returnKey: key = .return
        }
        var modifiers: EventModifiers = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}
