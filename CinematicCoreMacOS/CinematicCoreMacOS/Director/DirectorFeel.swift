//
//  DirectorFeel.swift
//  CinematicCoreMacOS
//
//  SU-1/SU-2 (AD-STYLE-UX). Operators describe a segment with three plain
//  choices instead of nine numbers. A versioned feel table maps each feel to
//  a `DirectorStyle`; the feel is derived from a stored style by matching, so
//  `DirectorPreferences` keeps schema v2. Table values are provisional study
//  parameters (DECISIONS.md SU-2), not qualification evidence.
//

import Foundation

nonisolated struct DirectorFeel: Hashable, Sendable {
    enum Pace: String, CaseIterable, Identifiable, Sendable {
        case calm, balanced, lively
        var id: String { rawValue }

        var title: String {
            switch self {
            case .calm: "Calm"
            case .balanced: "Balanced"
            case .lively: "Lively"
            }
        }

        var detail: String {
            switch self {
            case .calm: "Long, settled shots"
            case .balanced: "Changes when it helps"
            case .lively: "Frequent cuts, more energy"
            }
        }
    }

    enum WideShots: String, CaseIterable, Identifiable, Sendable {
        case rarely, sometimes, often
        var id: String { rawValue }

        var title: String {
            switch self {
            case .rarely: "Rarely"
            case .sometimes: "Sometimes"
            case .often: "Often"
            }
        }

        var detail: String {
            switch self {
            case .rarely: "Stay close on the subject"
            case .sometimes: "Show the room now and then"
            case .often: "Keep the whole stage in view"
            }
        }
    }

    enum Movement: String, CaseIterable, Identifiable, Sendable {
        case waitUntilSettled, cutWhileMoving
        var id: String { rawValue }

        var title: String {
            switch self {
            case .waitUntilSettled: "Wait until they settle"
            case .cutWhileMoving: "Cut while moving"
            }
        }

        var detail: String {
            switch self {
            case .waitUntilSettled: "Never cut to a moving shot. Safest."
            case .cutWhileMoving: "For performers who rarely stand still"
            }
        }
    }

    var pace: Pace
    var wideShots: WideShots
    var movement: Movement

    /// SU-1: Live event's style when nothing has been saved.
    static let liveEventDefault = DirectorFeel(pace: .balanced, wideShots: .sometimes, movement: .waitUntilSettled)

    /// Every combination, in table order.
    static let all: [DirectorFeel] = Pace.allCases.flatMap { pace in
        WideShots.allCases.flatMap { wide in
            Movement.allCases.map { DirectorFeel(pace: pace, wideShots: wide, movement: $0) }
        }
    }

    /// "Calm · wide sometimes", for lists.
    var summary: String {
        "\(pace.title) · wide \(wideShots.title.lowercased())"
    }

    /// The feel whose table style equals `style`, or nil when the values were
    /// edited by hand ("Custom").
    static func matching(_ style: DirectorStyle, table: DirectorFeelTable = .v1) -> DirectorFeel? {
        all.first { table.style(for: $0) == style }
    }
}

/// A frozen, versioned mapping from feels to styles. A new set of values is a
/// new version, never an edit of an old one, so shadow evidence can name it.
nonisolated struct DirectorFeelTable: Sendable {
    let version: Int
    /// Minimum, preferred and soft maximum shot length per pace, in seconds.
    let shotLengths: [DirectorFeel.Pace: (minimum: TimeInterval, preferred: TimeInterval, softMaximum: TimeInterval)]
    let onAirMoveRate: [DirectorFeel.Pace: Double]
    let wideCadence: [DirectorFeel.WideShots: TimeInterval]
    let maximumMovement: [DirectorFeel.Movement: Double]
    let settleTime: [DirectorFeel.Movement: TimeInterval]

    /// SU-2, recorded 2026-10-25. Movement values are placeholders until they
    /// are checked against shadow evidence.
    static let v1 = DirectorFeelTable(
        version: 1,
        shotLengths: [.calm: (12, 30, 60), .balanced: (8, 20, 40), .lively: (5, 12, 25)],
        onAirMoveRate: [.calm: 0.25, .balanced: 0.35, .lively: 0.5],
        wideCadence: [.rarely: 120, .sometimes: 75, .often: 40],
        maximumMovement: [.waitUntilSettled: 0.05, .cutWhileMoving: 0.15],
        settleTime: [.waitUntilSettled: 1.0, .cutWhileMoving: 0.5])

    func style(for feel: DirectorFeel) -> DirectorStyle {
        let lengths = shotLengths[feel.pace]!
        return DirectorStyle(
            minimumShotDuration: lengths.minimum,
            preferredShotDuration: lengths.preferred,
            softMaximumShotDuration: lengths.softMaximum,
            wideCadence: wideCadence[feel.wideShots]!,
            repetitionWindow: lengths.preferred * 2,
            maximumMovement: maximumMovement[feel.movement]!,
            settleTime: settleTime[feel.movement]!,
            onAirMoveRate: onAirMoveRate[feel.pace]!,
            cutOnMotionAllowed: feel.movement == .cutWhileMoving)
    }
}

extension DirectorPreferences {
    /// SU-1: what the Director uses when no styles have been saved.
    nonisolated static var builtInDefault: DirectorPreferences {
        DirectorPreferences(styles: [.liveEvent: DirectorFeelTable.v1.style(for: .liveEventDefault)])
    }

    /// The styles the Director starts with (SU-01, SU-04). A saved file wins;
    /// with none saved, the built-in table applies. An unreadable file gives
    /// no styles at all: it is kept for the operator, never silently replaced.
    static func forLaunch(_ result: DirectorPreferencesStore.LoadResult) -> DirectorPreferences? {
        switch result {
        case .empty: return builtInDefault
        case .loaded(let preferences): return preferences
        case .unreadable: return nil
        }
    }
}
