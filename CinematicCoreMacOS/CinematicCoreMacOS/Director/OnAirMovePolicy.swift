import Foundation

/// A-15's isolated N2 study policy. No camera effect; B-09 must consume the
/// one-shot plan immediately before its approved slow-move sink, with no await.
/// N2 is open. The production controller does not call this policy.
nonisolated struct OnAirMovePolicy: Sendable {
    struct Context: Sendable {
        let authority: DirectorAuthority
        let prerequisites: DirectorAuthority.Prerequisites
        let program: ChannelID
        let programRevisions: ChannelRevisions
        let routeGeneration: UInt64
        let policyRevision: UInt64
        let nominationRevision: UInt64
        let currentShot: DirectorShot
        let targetShot: DirectorShot
        let runningInputs: Set<ChannelID>
        /// nil means the off-air assessment is unavailable, never "none ready".
        let betterInputCutReady: Bool?
        let readiness: DirectorReadiness
        let sourceHealthy: Bool
        let operatorGestureInProgress: Bool
        let programStartedAt: TimeInterval
        let sampledAt: TimeInterval
    }
    struct Plan: Equatable, Sendable {
        let id: UUID
        let epoch: UInt64
        let program: ChannelID
        let programRevisions: ChannelRevisions
        let routeGeneration: UInt64
        let policyRevision: UInt64
        let nominationRevision: UInt64
        let from: DirectorShot
        let to: DirectorShot
        let style: DirectorStyle
        let proposedAt: TimeInterval
        /// Ladder steps per second, supplied by the style, never a snap.
        var maximumRate: Double { style.onAirMoveRate }

        fileprivate init(_ c: Context, style: DirectorStyle, now: TimeInterval) {
            id = UUID(); epoch = c.authority.epoch; program = c.program
            programRevisions = c.programRevisions; routeGeneration = c.routeGeneration
            policyRevision = c.policyRevision; nominationRevision = c.nominationRevision
            from = c.currentShot; to = c.targetShot; self.style = style; proposedAt = now
        }
        fileprivate func matches(_ c: Context, style: DirectorStyle) -> Bool {
            epoch == c.authority.epoch && program == c.program && programRevisions == c.programRevisions &&
                routeGeneration == c.routeGeneration && policyRevision == c.policyRevision &&
                nominationRevision == c.nominationRevision && from == c.currentShot && to == c.targetShot && self.style == style
        }
    }
    enum Abstention: Equatable, Sendable {
        case invalidInput, authority, notReady, betterInputReady, alternativeEvidenceUnavailable
        case minimumDwell, moveHold, notOneStep
    }
    enum Decision: Equatable, Sendable { case move(Plan), abstain(Abstention) }
    private(set) var pending: Plan?
    /// Consumed attempts count even if the downstream move fails. A refusal
    /// must not be retried as an unintended later move.
    private(set) var lastMoveAt: TimeInterval?
    private var lastClock: TimeInterval?

    mutating func retire() { pending = nil }

    mutating func propose(_ c: Context, style: DirectorStyle, now: TimeInterval,
                          maximumSampleAge: TimeInterval) -> Decision {
        if let refusal = refusal(c, style: style, now: now, maximumSampleAge: maximumSampleAge) {
            pending = nil
            return .abstain(refusal)
        }
        lastClock = now
        if let pending, pending.matches(c, style: style), now - pending.proposedAt <= maximumSampleAge { return .move(pending) }
        let plan = Plan(c, style: style, now: now)
        pending = plan
        return .move(plan)
    }

    /// Matching attempts are terminal. Stale callbacks leave replacements
    /// alone. Fresh authority, readiness, roles and spacing are rechecked.
    mutating func consume(_ plan: Plan, live c: Context, style: DirectorStyle,
                          now: TimeInterval, maximumSampleAge: TimeInterval) -> Plan? {
        guard pending == plan else { return nil }
        pending = nil
        guard now >= plan.proposedAt, now - plan.proposedAt <= maximumSampleAge, plan.matches(c, style: style),
              refusal(c, style: style, now: now, maximumSampleAge: maximumSampleAge) == nil else { return nil }
        lastClock = now; lastMoveAt = now
        return plan
    }

    private func refusal(_ c: Context, style: DirectorStyle, now: TimeInterval,
                         maximumSampleAge: TimeInterval) -> Abstention? {
        guard (try? style.validated()) != nil, now.isFinite, now >= 0,
              lastClock.map({ now >= $0 }) ?? true,
              c.programStartedAt.isFinite, c.programStartedAt >= 0, now >= c.programStartedAt,
              c.sampledAt.isFinite, c.sampledAt >= 0, now >= c.sampledAt,
              maximumSampleAge.isFinite, maximumSampleAge >= 0,
              c.runningInputs.contains(c.program) else { return .invalidInput }
        guard c.authority.mayIssueTake(at: now), c.prerequisites.satisfied,
              c.prerequisites.qualifiedLevels.contains(c.authority.level) else { return .authority }
        guard c.sourceHealthy, c.readiness.isReady, !c.operatorGestureInProgress,
              now - c.sampledAt <= maximumSampleAge else { return .notReady }
        if c.runningInputs.count > 1 {
            guard let better = c.betterInputCutReady else { return .alternativeEvidenceUnavailable }
            if better { return .betterInputReady }
        }
        guard now - c.programStartedAt >= style.minimumShotDuration else { return .minimumDwell }
        if let lastMoveAt {
            guard now >= lastMoveAt, now - lastMoveAt >= style.minimumShotDuration else { return .moveHold }
        }
        let ladder = DirectorShotPolicy.InputFormat(c.currentShot.preset).ladder
        guard let from = ladder.firstIndex(of: c.currentShot), let to = ladder.firstIndex(of: c.targetShot),
              abs(from - to) == 1 else { return .notOneStep }
        return nil
    }
}
