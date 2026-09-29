import Foundation

nonisolated struct DirectorPreferences: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let minimumShotDuration: TimeInterval
    let maximumShotDuration: TimeInterval
    let wideCadence: TimeInterval
    let repetitionWindow: TimeInterval
    let maximumMovement: Double
    let cutOnMotionAllowed: Bool

    // PROPOSED — pending AD-PREFS and AD-STYLE decisions.
    static let safeDefaults = DirectorPreferences(version: currentVersion,
        minimumShotDuration: 8, maximumShotDuration: 35, wideCadence: 90,
        repetitionWindow: 20, maximumMovement: 0.1, cutOnMotionAllowed: false)

    enum ValidationError: Error, Equatable {
        case unsupportedVersion, invalidDuration, invalidMovement, conflictingConstraints
    }
    func validated() throws -> DirectorPreferences {
        guard version == Self.currentVersion else { throw ValidationError.unsupportedVersion }
        guard minimumShotDuration.isFinite, maximumShotDuration.isFinite,
              wideCadence.isFinite, repetitionWindow.isFinite,
              minimumShotDuration >= 0, maximumShotDuration >= minimumShotDuration,
              wideCadence > 0, repetitionWindow >= 0 else { throw ValidationError.invalidDuration }
        guard maximumMovement.isFinite, maximumMovement >= 0 else { throw ValidationError.invalidMovement }
        return self
    }

    /// Migration hook. Unknown future schemas fail closed; prior schemas can be added here.
    static func migrate(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> DirectorPreferences {
        try decoder.decode(Self.self, from: data).validated()
    }

    /// Safety wins conflicts; duration limits resolve to the more conservative bound.
    static func resolve(_ a: Self, _ b: Self) throws -> Self {
        let a = try a.validated(), b = try b.validated()
        let minimum = max(a.minimumShotDuration, b.minimumShotDuration)
        let maximum = min(a.maximumShotDuration, b.maximumShotDuration)
        guard minimum <= maximum else { throw ValidationError.conflictingConstraints }
        return Self(version: currentVersion, minimumShotDuration: minimum,
            maximumShotDuration: maximum, wideCadence: min(a.wideCadence, b.wideCadence),
            repetitionWindow: max(a.repetitionWindow, b.repetitionWindow),
            maximumMovement: min(a.maximumMovement, b.maximumMovement),
            cutOnMotionAllowed: a.cutOnMotionAllowed && b.cutOnMotionAllowed)
    }
}
