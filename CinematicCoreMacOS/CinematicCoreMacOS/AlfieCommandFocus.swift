import SwiftUI

/// A screen publishes only the actions that are valid for its current state.
/// For Escape, publish the matching label (Cancel Detect / Done Editing Live).
@MainActor
struct AlfieCommandAction {
    var title: String? = nil
    let perform: @MainActor () -> Void
}

/// A snapshot assembled by the command consumer, rather than a value that a
/// screen publishes. Independent focus keys let nested screens contribute
/// actions without replacing commands supplied by another UX track.
nonisolated struct AlfieCommandActions: Sendable {
    var actions: [AlfieCommandCatalog.ID: AlfieCommandAction] = [:]

    subscript(_ id: AlfieCommandCatalog.ID) -> AlfieCommandAction? { actions[id] }

    /// Pure resolution: no action runs here. Stop is the one app-wide safety
    /// command; the App supplies its fallback only while a channel is live.
    /// A scene's explicit Stop takes precedence, and every other command
    /// remains available only when that scene publishes it.
    static func resolve(focused: [AlfieCommandCatalog.ID: AlfieCommandAction],
                        fallbackStop: AlfieCommandAction?) -> Self {
        var resolved = focused
        if resolved[.stopSession] == nil { resolved[.stopSession] = fallbackStop }
        return Self(actions: resolved)
    }
}

private struct AlfieSingleCamKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieMultiCamKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieWebcamKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieDetectKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieCancelKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieStopSessionKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieWideKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieFullBodyKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieWaistUpKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfiePushInKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfiePullOutKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieCuePreview1Key: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieCuePreview2Key: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieCuePreview3Key: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieCuePreview4Key: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieTakeKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieShowInspectorKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieDirectorHandKey: FocusedValueKey { typealias Value = AlfieCommandAction }
private struct AlfieDirectorAdvanceKey: FocusedValueKey { typealias Value = AlfieCommandAction }

extension FocusedValues {
    // Publish with `.focusedSceneValue(\.alfieDetect, action)` (and the other
    // keys below), so commands follow the active scene while a control has
    // focus. Each key is independent: publishing Inspector does not replace
    // the console's cue commands or the stopped screen's mode commands.

    var alfieSingleCam: AlfieCommandAction? {
        get { self[AlfieSingleCamKey.self] }
        set { self[AlfieSingleCamKey.self] = newValue }
    }

    var alfieMultiCam: AlfieCommandAction? {
        get { self[AlfieMultiCamKey.self] }
        set { self[AlfieMultiCamKey.self] = newValue }
    }

    var alfieWebcam: AlfieCommandAction? {
        get { self[AlfieWebcamKey.self] }
        set { self[AlfieWebcamKey.self] = newValue }
    }

    var alfieDetect: AlfieCommandAction? {
        get { self[AlfieDetectKey.self] }
        set { self[AlfieDetectKey.self] = newValue }
    }

    /// One Escape action per active context, with its matching title. The
    /// publisher must follow the catalogue's Escape ownership contract:
    /// withdraw for text input, modal/transient UI and a cancellable Director
    /// notice, as well as when Detect/Edit or the active scene ends.
    var alfieCancel: AlfieCommandAction? {
        get { self[AlfieCancelKey.self] }
        set { self[AlfieCancelKey.self] = newValue }
    }

    var alfieStopSession: AlfieCommandAction? {
        get { self[AlfieStopSessionKey.self] }
        set { self[AlfieStopSessionKey.self] = newValue }
    }

    var alfieWide: AlfieCommandAction? {
        get { self[AlfieWideKey.self] }
        set { self[AlfieWideKey.self] = newValue }
    }

    var alfieFullBody: AlfieCommandAction? {
        get { self[AlfieFullBodyKey.self] }
        set { self[AlfieFullBodyKey.self] = newValue }
    }

    var alfieWaistUp: AlfieCommandAction? {
        get { self[AlfieWaistUpKey.self] }
        set { self[AlfieWaistUpKey.self] = newValue }
    }

    var alfiePushIn: AlfieCommandAction? {
        get { self[AlfiePushInKey.self] }
        set { self[AlfiePushInKey.self] = newValue }
    }

    var alfiePullOut: AlfieCommandAction? {
        get { self[AlfiePullOutKey.self] }
        set { self[AlfiePullOutKey.self] = newValue }
    }

    var alfieCuePreview1: AlfieCommandAction? {
        get { self[AlfieCuePreview1Key.self] }
        set { self[AlfieCuePreview1Key.self] = newValue }
    }

    var alfieCuePreview2: AlfieCommandAction? {
        get { self[AlfieCuePreview2Key.self] }
        set { self[AlfieCuePreview2Key.self] = newValue }
    }

    var alfieCuePreview3: AlfieCommandAction? {
        get { self[AlfieCuePreview3Key.self] }
        set { self[AlfieCuePreview3Key.self] = newValue }
    }

    var alfieCuePreview4: AlfieCommandAction? {
        get { self[AlfieCuePreview4Key.self] }
        set { self[AlfieCuePreview4Key.self] = newValue }
    }

    var alfieTake: AlfieCommandAction? {
        get { self[AlfieTakeKey.self] }
        set { self[AlfieTakeKey.self] = newValue }
    }

    var alfieShowInspector: AlfieCommandAction? {
        get { self[AlfieShowInspectorKey.self] }
        set { self[AlfieShowInspectorKey.self] = newValue }
    }

    var alfieDirectorHand: AlfieCommandAction? {
        get { self[AlfieDirectorHandKey.self] }
        set { self[AlfieDirectorHandKey.self] = newValue }
    }

    var alfieDirectorAdvance: AlfieCommandAction? {
        get { self[AlfieDirectorAdvanceKey.self] }
        set { self[AlfieDirectorAdvanceKey.self] = newValue }
    }
}
