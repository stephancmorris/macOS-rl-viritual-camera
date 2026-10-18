import Foundation

/// A-13's optional, operator-advanced run sheet. This value selects styles
/// only; it cannot issue commands or change Director authority. F3 remains
/// open, so this model is not wired into the live controller or preferences.
nonisolated struct RunSheet: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum PositionHint: String, CaseIterable, Codable, Sendable {
        case lectern, centre, left, right
    }

    struct Segment: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        /// Presenter, Panel, Performance or Video/Break. Live event is the
        /// fallback profile for an empty sheet, not an authored segment type.
        let type: SegmentType
        let name: String?
        let positionHint: PositionHint?

        init(id: UUID = UUID(), type: SegmentType, name: String? = nil, positionHint: PositionHint? = nil) {
            self.id = id; self.type = type; self.name = name; self.positionHint = positionHint
        }
    }

    enum ValidationError: Error, Equatable {
        case unsupportedVersion, duplicateSegmentID, invalidSegmentType, invalidCurrentSegment
    }

    let version: Int
    let segments: [Segment]
    private(set) var currentSegmentID: UUID?

    /// A newly authored sheet starts at its first segment. The caller can
    /// explicitly restore/select an existing segment by stable identity.
    init(segments: [Segment], currentSegmentID: UUID? = nil) throws {
        version = Self.currentVersion
        self.segments = segments
        self.currentSegmentID = currentSegmentID ?? segments.first?.id
        try validate()
    }

    private enum CodingKeys: String, CodingKey { case version, segments, currentSegmentID }

    /// Corrupt, unknown or inconsistent persisted sheets never silently select
    /// a different segment or restore an automatic operating level.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        segments = try values.decode([Segment].self, forKey: .segments)
        currentSegmentID = try values.decodeIfPresent(UUID.self, forKey: .currentSegmentID)
        try validate()
    }

    private func validate() throws {
        guard version == Self.currentVersion else { throw ValidationError.unsupportedVersion }
        guard Set(segments.map(\.id)).count == segments.count else { throw ValidationError.duplicateSegmentID }
        guard segments.allSatisfy({ $0.type != .liveEvent }) else { throw ValidationError.invalidSegmentType }
        guard segments.isEmpty ? currentSegmentID == nil : segments.contains(where: { $0.id == currentSegmentID }) else {
            throw ValidationError.invalidCurrentSegment
        }
    }

    var currentIndex: Int? { segments.firstIndex { $0.id == currentSegmentID } }
    var current: Segment? { currentIndex.map { segments[$0] } }
    var next: Segment? {
        guard let index = currentIndex, index + 1 < segments.count else { return nil }
        return segments[index + 1]
    }

    /// These are deliberate operator actions. Neither wraps at a boundary.
    @discardableResult mutating func advance() -> Bool {
        guard let next else { return false }
        currentSegmentID = next.id
        return true
    }

    @discardableResult mutating func back() -> Bool {
        guard let index = currentIndex, index > 0 else { return false }
        currentSegmentID = segments[index - 1].id
        return true
    }

    /// Reuse A-05's single parameter source. Missing per-segment styles fall
    /// back to Live event; invalid preferences fail closed with no profile.
    func style(in preferences: DirectorPreferences) -> DirectorStyle? {
        guard (try? preferences.validated()) != nil else { return nil }
        return preferences.style(for: current?.type ?? .liveEvent)
    }

    struct Evidence: Equatable, Sendable {
        let personCount: Int
        let sampledAt: TimeInterval
        /// How long this count has been stable at sampledAt.
        let stableFor: TimeInterval

        fileprivate var isValid: Bool {
            personCount >= 0 && sampledAt.isFinite && sampledAt >= 0 &&
                stableFor.isFinite && stableFor >= 0 && stableFor <= sampledAt
        }
    }

    struct SuggestionParameters: Sendable {
        let maximumEvidenceAge: TimeInterval
        let minimumStableDuration: TimeInterval
    }

    struct ChangeSuggestion: Equatable, Sendable {
        let segmentID: UUID
        let previousPersonCount: Int
        let currentPersonCount: Int
        let observedAt: TimeInterval
        var text: String { "Segment changed?" }
    }

    /// Advisory evidence only: it does not infer the next segment's type,
    /// select a subject, advance the sheet or grant authority. Debounce and
    /// freshness are supplied study parameters, with no production defaults.
    func segmentChangeSuggestion(previous: Evidence, current: Evidence, now: TimeInterval,
                                 parameters: SuggestionParameters) -> ChangeSuggestion? {
        guard let segment = self.current, previous.isValid, current.isValid,
              now.isFinite, now >= current.sampledAt, current.sampledAt > previous.sampledAt,
              parameters.maximumEvidenceAge.isFinite, parameters.maximumEvidenceAge >= 0,
              parameters.minimumStableDuration.isFinite, parameters.minimumStableDuration >= 0,
              now - previous.sampledAt <= parameters.maximumEvidenceAge,
              now - current.sampledAt <= parameters.maximumEvidenceAge,
              current.stableFor >= parameters.minimumStableDuration,
              current.sampledAt - current.stableFor >= previous.sampledAt,
              previous.personCount != current.personCount else { return nil }
        return .init(segmentID: segment.id, previousPersonCount: previous.personCount,
                     currentPersonCount: current.personCount, observedAt: current.sampledAt)
    }
}
