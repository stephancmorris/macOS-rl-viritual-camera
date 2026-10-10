//
//  DirectorSectionMirror.swift
//  CinematicCoreMacOS
//
//  Local stand-in for A-04's `NextShotStatus.DirectorSection` v2. The gallery
//  renders this until that type merges; then the demo should read the real
//  section and this mirror can go. Operator copy lives here as plain words.
//  Countdown length is a caller-supplied parameter (A4 is open). This type
//  never stores a level for the next launch.
//

import Foundation

/// One director status the operator can be shown.
nonisolated struct DirectorSectionMirror: Equatable, Sendable {

    enum Level: String, CaseIterable, Equatable, Sendable {
        case manual
        case assist
        case auto
        case backup

        var title: String {
            switch self {
            case .manual: "Manual"
            case .assist: "Assist"
            case .auto: "Auto"
            case .backup: "Backup"
            }
        }
    }

    /// Active, paused, inhibited or abstaining, each with the sentence the operator reads.
    enum Activity: Equatable, Sendable {
        case active(reason: String)
        case paused(reason: String)
        case inhibited(reason: String)
        case abstaining(reason: String)

        var reason: String {
            switch self {
            case .active(let reason), .paused(let reason), .inhibited(let reason), .abstaining(let reason):
                reason
            }
        }

        var kind: Kind {
            switch self {
            case .active: .active
            case .paused: .paused
            case .inhibited: .inhibited
            case .abstaining: .abstaining
            }
        }

        enum Kind: String, CaseIterable, Equatable, Sendable {
            case active, paused, inhibited, abstaining
        }
    }

    struct PreparedShot: Equatable, Sendable {
        var input: ChannelID
        /// Preset name, e.g. "Waist Up".
        var shotName: String
    }

    /// The cut Alfie will make. `countdown == nil` is the Backup notice: the
    /// next cut is named and no duration is shown.
    struct NextCut: Equatable, Sendable {
        var input: ChannelID
        var countdown: TimeInterval?
        var cancellable: Bool
    }

    /// Per-level qualification on this rig. Manual is always allowed.
    struct Qualification: Equatable, Sendable {
        var assist: Bool
        var auto: Bool
        var backup: Bool

        static let none = Qualification(assist: false, auto: false, backup: false)

        func allows(_ level: Level) -> Bool {
            switch level {
            case .manual: true
            case .assist: assist
            case .auto: auto
            case .backup: backup
            }
        }
    }

    /// Optional strip. The import format is still open (F3); these are display labels only.
    struct RunSheetStrip: Equatable, Sendable {
        var current: String
        var next: String?
    }

    struct ModeChip: Equatable, Sendable {
        var level: Level
        var title: String
        var selected: Bool
        /// Nil when the level can be chosen. Otherwise the greyed caption, "not qualified".
        var unqualifiedCaption: String?
        var accessibilityLabel: String
    }

    struct HandControl: Equatable, Sendable {
        var manualTitle: String
        var handTitle: String
        /// True when the operator is driving. False when Alfie has been handed the show.
        var manualSelected: Bool
        var accessibilityLabel: String
    }

    var level: Level
    var activity: Activity
    var prepared: PreparedShot?
    var nextCut: NextCut?
    /// Inputs whose current shot Alfie set. Those tiles show AUTO.
    var alfieSetShot: Set<ChannelID>
    var qualified: Qualification
    /// False on every launch, and after the operator takes over.
    var handedToAlfie: Bool
    var runSheet: RunSheetStrip?

    static let autoBadge = "AUTO"
    static let unqualifiedCaption = "not qualified"

    var preparedLine: String {
        guard let prepared else { return "No shot prepared" }
        return "\(prepared.input.cameraLabel) · \(prepared.shotName)"
    }

    /// Line the operator reads for what Alfie is doing.
    var statusLine: String { activity.reason }

    var nextCutLine: String? {
        guard let nextCut else { return nil }
        return Self.nextCutLine(input: nextCut.input, countdown: nextCut.countdown, cancellable: nextCut.cancellable)
    }

    var modeChips: [ModeChip] {
        Level.allCases.map { level in
            let allowed = qualified.allows(level)
            let caption = allowed ? nil : Self.unqualifiedCaption
            let access: String
            if level == self.level {
                access = "\(level.title), selected"
            } else if let caption {
                access = "\(level.title), \(caption)"
            } else {
                access = level.title
            }
            return ModeChip(
                level: level,
                title: level.title,
                selected: level == self.level,
                unqualifiedCaption: caption,
                accessibilityLabel: access)
        }
    }

    var handControl: HandControl {
        let manualSelected = !handedToAlfie
        let access = manualSelected ? "Manual, selected" : "Hand to Alfie, selected"
        return HandControl(
            manualTitle: "Manual",
            handTitle: "Hand to Alfie",
            manualSelected: manualSelected,
            accessibilityLabel: access)
    }

    var runSheetAccessibilityLabel: String? {
        guard let runSheet else { return nil }
        if let next = runSheet.next {
            return "Run sheet. Now \(runSheet.current). Next \(next). Advance."
        }
        return "Run sheet. Now \(runSheet.current). Advance."
    }

    func showsAutoBadge(on channel: ChannelID) -> Bool {
        alfieSetShot.contains(channel)
    }

    /// Channel the gallery tile uses when a badge is on screen.
    var badgeChannel: ChannelID? {
        if let prepared, alfieSetShot.contains(prepared.input) { return prepared.input }
        return alfieSetShot.sorted { $0.letter < $1.letter }.first
    }

    static func nextCutLine(input: ChannelID, countdown: TimeInterval?, cancellable: Bool) -> String {
        var parts = ["Next: \(input.cameraLabel)"]
        if let countdown {
            parts.append(secondsText(countdown))
            if cancellable {
                parts.append("Esc to cancel")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Whole seconds read as "2 s". The caller supplies the duration; there is no built-in length.
    static func secondsText(_ seconds: TimeInterval) -> String {
        let whole = seconds.rounded()
        if abs(seconds - whole) < 0.05 {
            return "\(Int(whole)) s"
        }
        let tenths = (seconds * 10).rounded() / 10
        return "\(tenths) s"
    }
}

/// One named row in the director gallery.
nonisolated struct DirectorGalleryCase: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var section: DirectorSectionMirror
}
