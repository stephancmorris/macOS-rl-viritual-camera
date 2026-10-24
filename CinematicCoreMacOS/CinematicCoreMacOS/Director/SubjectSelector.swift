import Foundation

/// E1/P2: a visible, per-input discovery choice, not confirmed identity or a
/// camera command. The selected person must still pass normal acquire/lock.
nonisolated enum SubjectSelector {
    /// Normalized Vision coordinates. The caller resolves run-sheet hints
    /// (lectern/centre/left/right) to calibrated zones; no geometry is invented.
    struct Zone: Equatable, Sendable {
        let minX: Double, minY: Double, maxX: Double, maxY: Double
        var isValid: Bool {
            [minX, minY, maxX, maxY].allSatisfy { $0.isFinite && (0...1).contains($0) } &&
                minX < maxX && minY < maxY
        }
        func contains(_ person: Observation) -> Bool {
            (minX...maxX).contains(person.x) && (minY...maxY).contains(person.y)
        }
    }
    struct Observation: Equatable, Sendable {
        /// Local discovery identity, never a cross-camera/person name match.
        let id: UUID
        let x: Double, y: Double
        let stableFor: TimeInterval
        /// Detection age at Snapshot.sampledAt, not at the later decision time.
        let observationAge: TimeInterval
        var isValid: Bool {
            [x, y].allSatisfy { $0.isFinite && (0...1).contains($0) } &&
                stableFor.isFinite && stableFor >= 0 && observationAge.isFinite && observationAge >= 0
        }
    }
    struct Snapshot: Sendable {
        let channel: ChannelID
        let sourceGeneration: UInt64
        let sampledAt: TimeInterval
        let observations: [Observation]
    }
    struct Parameters: Sendable {
        let lecternZone: Zone
        /// Horizontal distance from this zone's centre, in normalized units.
        let maximumCentreDistance: Double
        let minimumStableDuration: TimeInterval
        let maximumObservationAge: TimeInterval
        let maximumSampleAge: TimeInterval
        var isValid: Bool {
            lecternZone.isValid && maximumCentreDistance.isFinite && (0...1).contains(maximumCentreDistance) &&
                [minimumStableDuration, maximumObservationAge, maximumSampleAge].allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }
    enum Reason: Equatable, Sendable { case operatorNomination, positionHint, centralPresenter }
    struct Selection: Equatable, Sendable {
        let channel: ChannelID
        let sourceGeneration: UInt64
        let subject: UUID
        let reason: Reason
        let sampledAt: TimeInterval
    }
    enum Abstention: Equatable, Sendable { case invalidInput, evidenceUnavailable, noPlausibleSubject }
    enum Decision: Equatable, Sendable {
        case selected(Selection)
        /// Keep the operator's intent; never substitute a different person.
        case awaitingNomination(UUID)
        case ambiguous([UUID])
        case abstain(Abstention)
    }

    static func select(_ snapshot: Snapshot, nomination: UUID?, positionHint: Zone?,
                       now: TimeInterval, parameters p: Parameters) -> Decision {
        guard p.isValid, positionHint.map(\.isValid) ?? true, now.isFinite, now >= 0,
              snapshot.sampledAt.isFinite, snapshot.sampledAt >= 0,
              Set(snapshot.observations.map(\.id)).count == snapshot.observations.count,
              snapshot.observations.allSatisfy(\.isValid) else { return .abstain(.invalidInput) }
        let elapsed = now - snapshot.sampledAt
        guard elapsed >= 0, elapsed <= p.maximumSampleAge else { return .abstain(.evidenceUnavailable) }
        let fresh = snapshot.observations.filter {
            let age = $0.observationAge + elapsed
            return age.isFinite && age <= p.maximumObservationAge
        }
        func pick(_ person: Observation, reason: Reason) -> Decision {
            .selected(.init(channel: snapshot.channel, sourceGeneration: snapshot.sourceGeneration,
                            subject: person.id, reason: reason, sampledAt: snapshot.sampledAt))
        }
        if let nomination {
            guard let person = fresh.first(where: { $0.id == nomination }) else { return .awaitingNomination(nomination) }
            // Operator priority does not require stability or a stage position.
            return pick(person, reason: .operatorNomination)
        }
        guard !fresh.isEmpty else { return .abstain(.evidenceUnavailable) }
        let stable = fresh.filter { $0.stableFor >= p.minimumStableDuration }
        func resolve(_ plausible: [Observation], reason: Reason) -> Decision? {
            guard let person = plausible.first else { return nil }
            guard plausible.count == 1 else {
                return .ambiguous(plausible.map(\.id).sorted { $0.uuidString < $1.uuidString })
            }
            return pick(person, reason: reason)
        }
        if let positionHint, let result = resolve(stable.filter { positionHint.contains($0) }, reason: .positionHint) {
            return result
        }
        let centre = (p.lecternZone.minX + p.lecternZone.maxX) / 2
        let plausible = stable.filter {
            p.lecternZone.contains($0) && abs($0.x - centre) <= p.maximumCentreDistance
        }
        return resolve(plausible, reason: .centralPresenter) ?? .abstain(.noPlausibleSubject)
    }
}
