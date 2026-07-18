//
//  ShowStandard.swift
//  CinematicCoreMacOS
//
//  The output video standard the show runs at. This drives two things that
//  must always agree: the capture-side target frame rate and the
//  frame-rate-match bring-up check. Persisted so the operator's choice
//  survives relaunch.
//

import Foundation

enum ShowStandard: String, CaseIterable, Identifiable {
    case p50
    case p5994
    case p60

    var id: String { rawValue }

    /// UserDefaults key the selection is persisted under.
    static let userDefaultsKey = "showStandard"

    /// Human-readable label for the settings picker.
    var title: String {
        switch self {
        case .p50:
            return "1080p50"
        case .p5994:
            return "1080p59.94"
        case .p60:
            return "1080p60"
        }
    }

    /// Exact playout frame rate. 59.94 is 60000/1001, never approximated.
    var frameRate: Double {
        switch self {
        case .p50:
            return 50.0
        case .p5994:
            return 60000.0 / 1001.0
        case .p60:
            return 60.0
        }
    }

    /// The persisted selection, defaulting to 1080p50 (the historical default,
    /// which the running show depends on).
    static var current: ShowStandard {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let standard = ShowStandard(rawValue: raw) {
            return standard
        }
        return .p50
    }
}
