//
//  DirectorCapabilities.swift
//  CinematicCoreMacOS
//
//  What the Director may do in this build (C-04). Watching and recording
//  need no capability. Acting does: Assist's preset command needs `assist`;
//  automatic Take, Backup and on-air moves need `auto`.
//
//  The compile-time flags stay the outer lock. A value built here can only
//  be as permissive as `DeveloperFlags` allows, so a Release build is
//  shadow-only whatever is asked for. A test can ask for less, to prove what
//  a shadow-only build does.
//

import Foundation

nonisolated struct DirectorCapabilities: Equatable, Sendable {
    let assist: Bool
    let auto: Bool

    init(assist: Bool, auto: Bool) {
        self.assist = assist && DeveloperFlags.allowDirectorAssist
        self.auto = auto && DeveloperFlags.allowDirectorAuto
    }

    /// Everything this build permits: all of it in Debug, nothing in Release.
    static let full = DirectorCapabilities(assist: true, auto: true)
    /// Watch and record only. What a Release build gets.
    static let shadowOnly = DirectorCapabilities(assist: false, auto: false)

    /// Whether the Director may hold this level at all in this build.
    func permits(_ level: DirectorAuthority.Level) -> Bool {
        switch level {
        case .off, .suggest: return true
        case .assist: return assist
        case .auto, .backup: return auto
        }
    }

    /// The level ceiling: a sign-off record cannot qualify a level this
    /// build cannot run.
    func ceiling(_ levels: Set<DirectorAuthority.Level>) -> Set<DirectorAuthority.Level> {
        levels.filter(permits)
    }
}

extension NextShotStatus.DirectorSection.Level {
    /// The modes the operator may be offered in this build.
    static func selectable(with capabilities: DirectorCapabilities = .full) -> [Self] {
        allCases.filter { level in
            switch level {
            case .manual: return true
            case .assist: return capabilities.assist
            case .auto, .backup: return capabilities.auto
            }
        }
    }
}
