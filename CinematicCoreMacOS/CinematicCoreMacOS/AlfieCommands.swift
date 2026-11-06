import SwiftUI

/// Wave 1 defines the menus; Wave 2 screens publish their focused actions.
/// Stop also has an app-owned fallback, so it works from Settings/Inspector
/// and before any screen publishes commands.
struct AlfieCommands: Commands {
    private let fallbackStop: AlfieCommandAction?
    @FocusedValue(\.alfieSingleCam) private var singleCam
    @FocusedValue(\.alfieMultiCam) private var multiCam
    @FocusedValue(\.alfieWebcam) private var webcam
    @FocusedValue(\.alfieDetect) private var detect
    @FocusedValue(\.alfieCancel) private var cancel
    @FocusedValue(\.alfieStopSession) private var stopSession
    @FocusedValue(\.alfieWide) private var wide
    @FocusedValue(\.alfieFullBody) private var fullBody
    @FocusedValue(\.alfieWaistUp) private var waistUp
    @FocusedValue(\.alfiePushIn) private var pushIn
    @FocusedValue(\.alfiePullOut) private var pullOut
    @FocusedValue(\.alfieCuePreview1) private var cuePreview1
    @FocusedValue(\.alfieCuePreview2) private var cuePreview2
    @FocusedValue(\.alfieCuePreview3) private var cuePreview3
    @FocusedValue(\.alfieCuePreview4) private var cuePreview4
    @FocusedValue(\.alfieTake) private var take
    @FocusedValue(\.alfieShowInspector) private var showInspector
    @FocusedValue(\.alfieDirectorHand) private var directorHand
    @FocusedValue(\.alfieDirectorAdvance) private var directorAdvance
    @StateObject private var plainKeys = AlfiePlainKeyRouter()

    init(fallbackStop: AlfieCommandAction? = nil) {
        self.fallbackStop = fallbackStop
    }

    /// Independent keys let Track B's console and Track C's Inspector publish
    /// from their own views without one replacing the other's action set.
    private var actions: AlfieCommandActions {
        let entries: [(AlfieCommandCatalog.ID, AlfieCommandAction?)] = [
            (.singleCam, singleCam), (.multiCam, multiCam), (.webcam, webcam),
            (.detect, detect), (.cancel, cancel), (.stopSession, stopSession),
            (.wide, wide), (.fullBody, fullBody), (.waistUp, waistUp),
            (.pushIn, pushIn), (.pullOut, pullOut),
            (.cuePreview1, cuePreview1), (.cuePreview2, cuePreview2),
            (.cuePreview3, cuePreview3), (.cuePreview4, cuePreview4), (.take, take),
            (.showInspector, showInspector), (.directorHand, directorHand),
            (.directorAdvance, directorAdvance)
        ]
        let available = entries.compactMap { id, action in action.map { (id, $0) } }
        return AlfieCommandActions.resolve(focused: Dictionary(uniqueKeysWithValues: available),
                                           fallbackStop: fallbackStop)
    }

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
        let action = actions[id]
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
        // App Shortcuts rebinding uses this exact, stable menu title.
        let title = definition.id == .stopSession ? definition.title : action?.title ?? definition.title
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
