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
import CoreMedia

nonisolated enum ShowStandard: String, CaseIterable, Identifiable {
    case p50
    case p5994
    case p60

    var id: String { rawValue }

    /// UserDefaults key the selection is persisted under.
    static let userDefaultsKey = "showStandard"

    /// Capture sessions must not follow preference changes live: the camera is
    /// configured once at start, while the picker explicitly says changes apply
    /// to the next capture. Keep that selected standard stable until output
    /// stops, including if the virtual-camera XPC link reconnects.
    private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var sessionStandard: ShowStandard?

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

    var frameDuration: CMTime {
        switch self {
        case .p50: return CMTime(value: 1200, timescale: 60000)
        case .p5994: return CMTime(value: 1001, timescale: 60000)
        case .p60: return CMTime(value: 1000, timescale: 60000)
        }
    }

    static func matching(frameRate: Double) -> ShowStandard? {
        allCases.first { frameRate.isFinite && abs($0.frameRate - frameRate) < 0.001 }
    }

    /// Exact selection within a supported device range, not its endpoints.
    ///
    /// Pass the range's own durations when you have them: rounding 1/rate
    /// can land just outside a single-rate range (a Brio's "30 fps" is
    /// 30.00003, and 1/30.00003 at timescale 60000 rounds to 30.015 fps), and
    /// AVFoundation raises an exception rather than an error for that. The
    /// result is clamped into [minDuration, maxDuration].
    static func captureDuration(target: Double, minimum: Double, maximum: Double,
                                minDuration: CMTime? = nil, maxDuration: CMTime? = nil) -> CMTime {
        let rate = min(max(target, minimum), maximum)
        var duration = matching(frameRate: rate)?.frameDuration ?? CMTime(seconds: 1 / rate, preferredTimescale: 60000)
        if let minDuration, minDuration.isValid, CMTimeCompare(duration, minDuration) < 0 { duration = minDuration }
        if let maxDuration, maxDuration.isValid, CMTimeCompare(duration, maxDuration) > 0 { duration = maxDuration }
        return duration
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

    /// The standard frozen at `ProgramOutputManager.start()`, if any.
    static var activeSession: ShowStandard? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return sessionStandard
    }

    /// Use the active capture selection while running; otherwise reflect the
    /// persisted operator preference for preflight UI.
    static var activeOrCurrent: ShowStandard {
        activeSession ?? current
    }

    static func beginSession(standard: ShowStandard = ShowStandard.current) {
        sessionLock.lock()
        sessionStandard = standard
        sessionLock.unlock()
    }

    static func endSession() {
        sessionLock.lock()
        sessionStandard = nil
        sessionLock.unlock()
    }
}

/// Connection-scoped acknowledgement; a reply from a retired connection cannot
/// authorize frames on a new one.
struct PlayoutRateHandshake {
    private(set) var generation: UInt64 = 0
    private(set) var acknowledgedRate: Double?
    private var pendingRate: Double?

    mutating func begin(rate: Double, generation: UInt64) -> Bool {
        if self.generation != generation {
            self.generation = generation
            acknowledgedRate = nil
            pendingRate = nil
        }
        guard acknowledgedRate != rate, pendingRate == nil else { return false }
        pendingRate = rate
        return true
    }

    mutating func complete(rate: Double, generation: UInt64, accepted: Bool) {
        guard generation == self.generation, pendingRate == rate else { return }
        pendingRate = nil
        acknowledgedRate = accepted ? rate : nil
    }

    func isReady(rate: Double, generation: UInt64) -> Bool {
        self.generation == generation && acknowledgedRate == rate
    }
}
