/// One table for menu titles and key equivalents. Keys are interim until
/// docs/ux/2026-11-05/keyboard-map.md lands; unspecified keys stay unset.
/// This value layer has no dependency on a focused scene or SwiftUI.
nonisolated enum AlfieCommandCatalog {
    enum ID: String, CaseIterable, Hashable, Sendable {
        case singleCam, multiCam, webcam
        case detect, cancel, stopSession
        case wide, fullBody, waistUp, pushIn, pullOut
        case cuePreview1, cuePreview2, cuePreview3, cuePreview4, take
        case showInspector
        case directorHand, directorAdvance
    }

    enum Category: String, CaseIterable, Equatable, Sendable {
        case session = "Session"
        case shot = "Shot"
        case multiCam = "Multi Cam"
        case view = "View"
        case director = "Director"
    }

    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: UInt8

        static let command = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let shift = Self(rawValue: 1 << 2)
        static let control = Self(rawValue: 1 << 3)
    }

    enum Key: Hashable, Sendable {
        case character(Character)
        case escape
        case returnKey
    }

    struct Shortcut: Hashable, Sendable {
        let key: Key
        let modifiers: Modifiers
    }

    struct Definition: Identifiable, Equatable, Sendable {
        let id: ID
        let title: String
        let category: Category
        let shortcut: Shortcut?
        /// A missing key here is awaiting the spec, rather than a decision
        /// that the action should never have a key (as with TAKE).
        var keysPending = false
    }

    struct Reservation: Equatable, Sendable {
        let shortcut: Shortcut
        /// Only an existing Alfie command may retain these three shortcuts.
        /// Standard macOS reservations have no permitted Alfie owner.
        var allowedOwner: ID? = nil
    }

    static let definitions: [Definition] = [
        .init(id: .singleCam, title: "Single Cam", category: .session,
              shortcut: .init(key: .character("1"), modifiers: .command)),
        .init(id: .multiCam, title: "Multi Cam", category: .session,
              shortcut: .init(key: .character("2"), modifiers: .command)),
        .init(id: .webcam, title: "Webcam", category: .session,
              shortcut: .init(key: .character("3"), modifiers: .command)),
        .init(id: .detect, title: "Detect", category: .session,
              shortcut: nil, keysPending: true),
        // A screen publishes either Cancel Detect or Done Editing Live here.
        // Sharing one slot keeps Escape unambiguous in the active scene.
        // Escape remains a native menu equivalent. Publish alfieCancel ONLY
        // while that operator scene is active and its Detect/Edit action is
        // valid, with no text/field/secure/custom text client owning focus,
        // no sheet, alert, modal, popover or other transient UI owning Escape,
        // and no cancellable Director notice using its own Escape handler.
        // Withdraw it before presenting such UI and whenever focus, scene or
        // action validity changes. The callback must recheck validity too.
        .init(id: .cancel, title: "Cancel Detect", category: .session,
              shortcut: .init(key: .escape, modifiers: [])),
        .init(id: .stopSession, title: "Stop Session", category: .session,
              shortcut: .init(key: .character("s"), modifiers: [.command, .option, .shift])),
        .init(id: .wide, title: "Wide", category: .shot, shortcut: nil, keysPending: true),
        .init(id: .fullBody, title: "Full Body", category: .shot, shortcut: nil, keysPending: true),
        .init(id: .waistUp, title: "Waist Up", category: .shot, shortcut: nil, keysPending: true),
        .init(id: .pushIn, title: "Push In", category: .shot, shortcut: nil, keysPending: true),
        .init(id: .pullOut, title: "Pull Out", category: .shot, shortcut: nil, keysPending: true),
        .init(id: .cuePreview1, title: "Cue Preview 1", category: .multiCam,
              shortcut: .init(key: .character("1"), modifiers: [])),
        .init(id: .cuePreview2, title: "Cue Preview 2", category: .multiCam,
              shortcut: .init(key: .character("2"), modifiers: [])),
        .init(id: .cuePreview3, title: "Cue Preview 3", category: .multiCam,
              shortcut: .init(key: .character("3"), modifiers: [])),
        .init(id: .cuePreview4, title: "Cue Preview 4", category: .multiCam,
              shortcut: .init(key: .character("4"), modifiers: [])),
        // Owner decision D4: cueing is reversible; TAKE deliberately has no key.
        .init(id: .take, title: "TAKE", category: .multiCam, shortcut: nil),
        .init(id: .showInspector, title: "Show Inspector", category: .view,
              shortcut: .init(key: .character("i"), modifiers: [.command, .option])),
        .init(id: .directorHand, title: "Hand to Alfie", category: .director,
              shortcut: .init(key: .character("h"), modifiers: [.command, .shift])),
        .init(id: .directorAdvance, title: "Advance Run Sheet", category: .director,
              shortcut: .init(key: .returnKey, modifiers: [.command, .shift])),
    ]

    static func definition(for id: ID) -> Definition {
        // The coverage test requires exactly one definition for every ID.
        guard let definition = definitions.first(where: { $0.id == id }) else {
            preconditionFailure("Missing command definition: \(id.rawValue)")
        }
        return definition
    }

    /// Platform editing, window, application and system shortcuts. Keep these
    /// reserved even while Alfie's corresponding focused actions are absent.
    static let reservations: [Reservation] = {
        let commandKeys: [Character] = [
            "q", "w", ",", "h", "m", "n", "o", "s", "p", "f", "g",
            "a", "c", "v", "x", "z", " ", "\t", "\u{8}"
        ]
        let commandShiftKeys: [Character] = ["z", "g", "p", "s", "n", "/", "\t"]
        let commandOptionKeys: [Character] = ["h", "w", "m", " "]
        return commandKeys.map { Reservation(shortcut: .init(key: .character($0), modifiers: .command)) }
            + commandShiftKeys.map {
                Reservation(shortcut: .init(key: .character($0), modifiers: [.command, .shift]))
            }
            + commandOptionKeys.map {
                Reservation(shortcut: .init(key: .character($0), modifiers: [.command, .option]))
            }
            + [
                .init(shortcut: .init(key: .escape, modifiers: [.command, .option])),
                .init(shortcut: .init(key: .character("q"), modifiers: [.command, .control])),
                .init(shortcut: .init(key: .character("f"), modifiers: [.command, .control])),
                .init(shortcut: .init(key: .character("s"), modifiers: [.command, .option, .shift]),
                      allowedOwner: .stopSession),
                .init(shortcut: .init(key: .character("h"), modifiers: [.command, .shift]),
                      allowedOwner: .directorHand),
                .init(shortcut: .init(key: .returnKey, modifiers: [.command, .shift]),
                      allowedOwner: .directorAdvance),
            ]
    }()
}
