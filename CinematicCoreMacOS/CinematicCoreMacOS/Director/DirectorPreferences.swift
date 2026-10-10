import Foundation

/// Run-sheet segment types (F3). Each selects a style; none grants authority.
/// `liveEvent` is the profile used when there is no run sheet.
nonisolated enum SegmentType: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
    case presenter, panel, performance, videoBreak, liveEvent
}

/// How Alfie paces and frames one kind of segment. Every value is a study
/// parameter supplied by the owner or by tests; this type has no defaults.
nonisolated struct DirectorStyle: Codable, Equatable, Sendable {
    let minimumShotDuration: TimeInterval
    let preferredShotDuration: TimeInterval
    let softMaximumShotDuration: TimeInterval
    let wideCadence: TimeInterval
    let repetitionWindow: TimeInterval
    /// Subject speed (normalized units per second) above which a shot is "moving".
    let maximumMovement: Double
    let settleTime: TimeInterval
    /// Fastest on-air shot move, in shot-ladder steps per second (N2).
    let onAirMoveRate: Double
    let cutOnMotionAllowed: Bool

    func validated() throws -> DirectorStyle {
        guard [minimumShotDuration, preferredShotDuration, softMaximumShotDuration,
               wideCadence, repetitionWindow, settleTime].allSatisfy({ $0.isFinite && $0 >= 0 }),
              wideCadence > 0 else { throw DirectorPreferences.ValidationError.invalidDuration }
        guard minimumShotDuration <= preferredShotDuration,
              preferredShotDuration <= softMaximumShotDuration else {
            throw DirectorPreferences.ValidationError.invalidDuration
        }
        guard maximumMovement.isFinite, maximumMovement >= 0,
              onAirMoveRate.isFinite, onAirMoveRate > 0 else {
            throw DirectorPreferences.ValidationError.invalidMovement
        }
        return self
    }

    /// Safety wins conflicts: the result is never looser than either input.
    static func resolve(_ a: DirectorStyle, _ b: DirectorStyle) throws -> DirectorStyle {
        let a = try a.validated(), b = try b.validated()
        let minimum = max(a.minimumShotDuration, b.minimumShotDuration)
        let softMaximum = min(a.softMaximumShotDuration, b.softMaximumShotDuration)
        guard minimum <= softMaximum else { throw DirectorPreferences.ValidationError.conflictingConstraints }
        let preferred = min(max(a.preferredShotDuration, b.preferredShotDuration, minimum), softMaximum)
        return try DirectorStyle(minimumShotDuration: minimum, preferredShotDuration: preferred,
            softMaximumShotDuration: softMaximum,
            wideCadence: min(a.wideCadence, b.wideCadence),
            repetitionWindow: max(a.repetitionWindow, b.repetitionWindow),
            maximumMovement: min(a.maximumMovement, b.maximumMovement),
            settleTime: max(a.settleTime, b.settleTime),
            onAirMoveRate: min(a.onAirMoveRate, b.onAirMoveRate),
            cutOnMotionAllowed: a.cutOnMotionAllowed && b.cutOnMotionAllowed).validated()
    }
}

/// The one source of Director pacing parameters: a versioned style per
/// segment type. Persisted by the console (C-04); never stores or restores an
/// authority level, so every launch still starts in Manual.
nonisolated struct DirectorPreferences: Codable, Equatable, Sendable {
    static let currentVersion = 2
    let version: Int
    let styles: [SegmentType: DirectorStyle]

    init(version: Int = DirectorPreferences.currentVersion, styles: [SegmentType: DirectorStyle]) {
        self.version = version
        self.styles = styles
    }

    enum ValidationError: Error, Equatable {
        case unsupportedVersion, invalidDuration, invalidMovement, conflictingConstraints, missingLiveEventStyle
    }

    func validated() throws -> DirectorPreferences {
        guard version == Self.currentVersion else { throw ValidationError.unsupportedVersion }
        guard styles[.liveEvent] != nil else { throw ValidationError.missingLiveEventStyle }
        for style in styles.values { _ = try style.validated() }
        return self
    }

    /// The style for a segment; segments without their own style use Live event.
    func style(for segment: SegmentType) -> DirectorStyle? {
        styles[segment] ?? styles[.liveEvent]
    }

    /// Reads stored preferences. Only the current schema is accepted: v1 was
    /// never persisted, and unknown or future schemas fail closed.
    static func migrate(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> DirectorPreferences {
        struct Header: Decodable { let version: Int }
        guard let header = try? decoder.decode(Header.self, from: data),
              header.version == currentVersion else { throw ValidationError.unsupportedVersion }
        return try decoder.decode(Self.self, from: data).validated()
    }

    /// Conservative merge per segment. A segment styled on only one side keeps
    /// that style; one styled on both resolves to the stricter values.
    static func resolve(_ a: Self, _ b: Self) throws -> Self {
        let a = try a.validated(), b = try b.validated()
        var merged = a.styles
        for (segment, style) in b.styles {
            merged[segment] = try merged[segment].map { try DirectorStyle.resolve($0, style) } ?? style
        }
        return try Self(styles: merged).validated()
    }
}
