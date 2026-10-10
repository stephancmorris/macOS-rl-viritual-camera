import Foundation

/// The B-07 boundary: dispatch requires consumption immediately before the
/// effect, using a fresh snapshot, with no suspension between check and Take.
/// This value is deliberately not Codable and cannot be restored from a log.
nonisolated struct TakePermit: Equatable, Sendable {
    let id: UUID
    let epoch: UInt64
    let level: DirectorAuthority.Level
    let program: ChannelID
    let preview: ChannelID
    let routeGeneration: UInt64
    let previewRevisions: ChannelRevisions
    let policyRevision: UInt64
    let nominationRevision: UInt64
    let issuedAt: TimeInterval
    let expiresAt: TimeInterval
    fileprivate init(id: UUID, live: DirectorTakeState, preview: ChannelID,
                     revisions: ChannelRevisions, now: TimeInterval, expiresAt: TimeInterval) {
        self.id = id; epoch = live.world.authority.epoch; level = live.world.authority.level
        program = live.world.program; self.preview = preview
        routeGeneration = live.world.routeGeneration; previewRevisions = revisions
        policyRevision = live.world.policyRevision; nominationRevision = live.world.nominationRevision
        issuedAt = now; self.expiresAt = expiresAt
    }
}

nonisolated struct DirectorTakeState: Sendable {
    let world: DirectorLiveState
    /// Re-read qualification/admission at issuance and the final effect.
    let prerequisites: DirectorAuthority.Prerequisites
    let cutReadiness: DirectorReadiness
    let operatorGestureInProgress: Bool
}

nonisolated struct TakePermitIssuer: Sendable {
    enum Refusal: Equatable, Sendable {
        case replacedOrConsumed, invalidClock, expired, authority, qualification
        case prerequisites, roles, source, route, revisions, policy, nomination, readiness, gesture
    }
    enum Consumption: Equatable, Sendable { case admitted(TakePermit), refused(Refusal) }
    private(set) var pending: TakePermit?
    private var lastClock: TimeInterval?

    mutating func retire() { pending = nil }
    /// A stale notice may retire its own lease, never a replacement.
    mutating func discard(_ candidate: TakePermit) { if pending == candidate { pending = nil } }

    mutating func issue(live: DirectorTakeState, now: TimeInterval,
                        validity: TimeInterval) -> TakePermit? {
        guard clockIsValid(now), validity.isFinite, validity >= 0,
              (now + validity).isFinite, refusal(live, now: now) == nil,
              let preview = live.world.preview, let revisions = live.world.revisions else { return nil }
        lastClock = now
        let permit = TakePermit(id: UUID(), live: live, preview: preview,
                                revisions: revisions, now: now, expiresAt: now + validity)
        pending = permit
        return permit
    }

    mutating func consume(_ candidate: TakePermit, live: DirectorTakeState,
                         now: TimeInterval) -> Consumption {
        guard pending == candidate else { return .refused(.replacedOrConsumed) }
        // A matching attempt is terminal even if the world is currently stale.
        pending = nil
        guard clockIsValid(now), now >= candidate.issuedAt else { return .refused(.invalidClock) }
        lastClock = now
        guard now <= candidate.expiresAt else { return .refused(.expired) }
        if let reason = refusal(live, now: now) { return .refused(reason) }
        let world = live.world
        guard world.authority.epoch == candidate.epoch, world.authority.level == candidate.level else { return .refused(.authority) }
        guard world.program == candidate.program, world.preview == candidate.preview else { return .refused(.roles) }
        guard world.routeGeneration == candidate.routeGeneration else { return .refused(.route) }
        guard world.revisions == candidate.previewRevisions else { return .refused(.revisions) }
        guard world.policyRevision == candidate.policyRevision else { return .refused(.policy) }
        guard world.nominationRevision == candidate.nominationRevision else { return .refused(.nomination) }
        return .admitted(candidate)
    }

    private func clockIsValid(_ now: TimeInterval) -> Bool {
        now.isFinite && now >= 0 && (lastClock.map { now >= $0 } ?? true)
    }
    private func refusal(_ live: DirectorTakeState, now: TimeInterval) -> Refusal? {
        let world = live.world
        guard world.authority.mayIssueTake(at: now) else { return .authority }
        guard live.prerequisites.qualifiedLevels.contains(world.authority.level) else { return .qualification }
        guard live.prerequisites.satisfied else { return .prerequisites }
        guard let preview = world.preview, preview != world.program else { return .roles }
        guard !world.sourceMissing, world.revisions != nil else { return .source }
        guard world.evidenceAvailable, live.cutReadiness.isReady else { return .readiness }
        guard !live.operatorGestureInProgress else { return .gesture }
        return nil
    }
}
