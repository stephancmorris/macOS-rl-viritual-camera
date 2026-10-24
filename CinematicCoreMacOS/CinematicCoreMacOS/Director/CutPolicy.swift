import Foundation

nonisolated enum CutPolicy {
    /// This policy only evaluates the shot already prepared on Preview. A
    /// result grants no authority: the deadline must obtain a fresh permit.
    enum Reason: Equatable, Sendable { case preferredLength, programUncertain, wideDue }
    enum Abstention: Equatable, Sendable { case invalidInput, authority, minimumDwell, notReady, nothingBetter, judge }
    struct Plan: Equatable, Sendable {
        let candidate: DirectorShotPolicy.Candidate
        let reason: Reason
        let computedAt: TimeInterval
        let epoch: UInt64
        let program: ChannelID
        let preview: ChannelID
        let revisions: ChannelRevisions
        let routeGeneration: UInt64
        let policyRevision: UInt64
        let nominationRevision: UInt64
        fileprivate init(candidate: DirectorShotPolicy.Candidate, reason: Reason, live: DirectorTakeState, now: TimeInterval,
                         preview: ChannelID, revisions: ChannelRevisions) {
            self.candidate = candidate; self.reason = reason; computedAt = now
            epoch = live.world.authority.epoch; program = live.world.program; self.preview = preview
            self.revisions = revisions; routeGeneration = live.world.routeGeneration
            policyRevision = live.world.policyRevision; nominationRevision = live.world.nominationRevision
        }
        /// Observation confidence and movement can change during the notice;
        /// identity here is the prepared shot and input, bound by revisions.
        func hasSameShot(as other: Plan) -> Bool {
            candidate.channel == other.candidate.channel && candidate.shot == other.candidate.shot
        }
        func matches(_ live: DirectorTakeState) -> Bool {
            let w = live.world
            return epoch == w.authority.epoch && program == w.program && preview == w.preview &&
                revisions == w.revisions && routeGeneration == w.routeGeneration &&
                policyRevision == w.policyRevision && nominationRevision == w.nominationRevision
        }
    }
    enum Decision: Equatable, Sendable { case cut(Plan), abstain(Abstention) }

    /// Only the actual prepared Preview shot is a candidate for this cut.
    static func evaluate(live: DirectorTakeState, timeline: DirectorShotPolicy.Timeline,
                         prepared: DirectorShotPolicy.Candidate, programIdentity: IdentityEvidence,
                         style: DirectorStyle, evidenceRevision: UInt64, judge: any DirectorJudge,
                         judgeMaximumAge: TimeInterval, minimumProbability: Double?) -> Decision {
        let now = timeline.now
        guard (try? style.validated()) != nil, now.isFinite, now >= 0,
              timeline.programStartedAt.isFinite, timeline.programStartedAt >= 0,
              timeline.programStartedAt <= now, timeline.lastWideAt.isFinite, timeline.lastWideAt >= 0,
              timeline.lastWideAt <= now, timeline.history.allSatisfy({ $0.endedAt.isFinite && $0.endedAt >= 0 && $0.endedAt <= now }),
              judgeMaximumAge.isFinite, judgeMaximumAge >= 0,
              minimumProbability.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              prepared.isWide == prepared.shot.isWide, prepared.subjectConfidence.isFinite,
              (0...1).contains(prepared.subjectConfidence), prepared.movement.isFinite, prepared.movement >= 0 else { return .abstain(.invalidInput) }
        guard live.world.authority.mayIssueTake(at: now), live.prerequisites.satisfied,
              live.prerequisites.qualifiedLevels.contains(live.world.authority.level) else { return .abstain(.authority) }
        guard let preview = live.world.preview, preview != live.world.program,
              prepared.channel == preview, let revisions = live.world.revisions,
              !live.world.sourceMissing, live.world.evidenceAvailable,
              live.cutReadiness.isReady, !live.operatorGestureInProgress,
              style.cutOnMotionAllowed || prepared.movement <= style.maximumMovement else { return .abstain(.notReady) }
        let dwell = now - timeline.programStartedAt
        guard dwell >= style.minimumShotDuration else { return .abstain(.minimumDwell) }
        let reason: Reason
        if programIdentity != .confirmed { reason = .programUncertain }
        else if now - timeline.lastWideAt >= style.wideCadence && prepared.shot.isWide { reason = .wideDue }
        else if dwell >= style.preferredShotDuration { reason = .preferredLength }
        else { return .abstain(.nothingBetter) }
        let filtered = DirectorShotPolicy.Timeline(programShot: timeline.programShot,
            programStartedAt: timeline.programStartedAt, lastWideAt: timeline.lastWideAt,
            history: timeline.history, candidates: [prepared], now: now)
        let parameters = DirectorShotPolicy.Parameters(style)
        let allowed = DirectorShotPolicy.rank(filtered, preview: preview, parameters: parameters)
        let judgement = judge.judge(.init(timeline: filtered, preview: preview, parameters: parameters,
                                          evidenceRevision: evidenceRevision, now: now))
        guard judgement.computedAt.isFinite, judgement.computedAt >= 0,
              case .accepted(let selected) = DirectorJudgeGate.accept(judgement, allowed: allowed,
                  evidenceRevision: evidenceRevision, now: now, maximumAge: judgeMaximumAge,
                  minimumProbability: minimumProbability), selected.candidate == prepared else { return .abstain(.judge) }
        return .cut(.init(candidate: prepared, reason: reason, live: live, now: now, preview: preview, revisions: revisions))
    }
}

/// A deadline is a one-shot notice, never a Take lease. A fresh policy decision
/// and a fresh permit are required at the deadline; refusal retires the notice.
nonisolated struct CutNotice: Sendable {
    struct Token: Equatable, Sendable {
        let id: UUID
        let plan: CutPolicy.Plan
        let issuedAt: TimeInterval
        let deadline: TimeInterval
        let expiresAt: TimeInterval
        let level: DirectorAuthority.Level
    }
    private(set) var pending: Token?
    private var lastClock: TimeInterval?
    mutating func retire() { pending = nil }

    mutating func begin(_ decision: CutPolicy.Decision, live: DirectorTakeState, now: TimeInterval,
                        autoNoticeLength: TimeInterval, maximumLateness: TimeInterval) -> Token? {
        guard clockValid(now), autoNoticeLength.isFinite, autoNoticeLength >= 0,
              maximumLateness.isFinite, maximumLateness >= 0,
              case .cut(let plan) = decision, plan.computedAt == now, plan.matches(live),
              live.world.authority.mayIssueTake(at: now), live.prerequisites.satisfied,
              live.prerequisites.qualifiedLevels.contains(live.world.authority.level),
              !live.world.sourceMissing, live.world.evidenceAvailable,
              live.cutReadiness.isReady, !live.operatorGestureInProgress else { return nil }
        let length = live.world.authority.level == .backup ? 0 : autoNoticeLength
        let deadline = now + length, expiry = deadline + maximumLateness
        guard deadline.isFinite, expiry.isFinite else { return nil }
        // Re-evaluation must not continually move the same cut's deadline.
        if let current = pending, current.plan.matches(live), current.level == live.world.authority.level,
           current.plan.hasSameShot(as: plan), now <= current.expiresAt {
            lastClock = now
            return current
        }
        lastClock = now
        let token = Token(id: UUID(), plan: plan, issuedAt: now, deadline: deadline,
                          expiresAt: expiry, level: live.world.authority.level)
        pending = token
        return token
    }

    /// Cancel wins against its pending deadline, including the exact deadline.
    /// Stale cancel tokens cannot retire a replacement or create a hold.
    @discardableResult mutating func cancel(_ token: Token, authority: inout DirectorAuthority,
                                           now: TimeInterval, minimumShotDuration: TimeInterval) -> Bool {
        guard pending == token else { return false }
        pending = nil
        guard authority.epoch == token.plan.epoch else { return true }
        let validClock = clockValid(now) && now >= token.issuedAt
        // A malformed/backward cancellation still revokes the cut, but cannot
        // shorten the hold by supplying an earlier timestamp.
        authority.holdAfterCutCancellation(.init(now: validClock ? now : .nan,
                                                minimumShotDuration: minimumShotDuration))
        if validClock { lastClock = now }
        return true
    }

    /// B-08 calls policy again, then obtains and consumes this permit in the
    /// same turn before the technical Take. No delayed retry on any refusal.
    mutating func fire(_ token: Token, decision: CutPolicy.Decision, live: DirectorTakeState,
                       now: TimeInterval, permitValidity: TimeInterval,
                       issuer: inout TakePermitIssuer) -> TakePermit? {
        guard pending == token else { return nil }
        guard clockValid(now), now >= token.issuedAt else { pending = nil; return nil }
        lastClock = now
        if now < token.deadline { return nil }
        pending = nil
        guard now <= token.expiresAt, token.plan.matches(live), token.level == live.world.authority.level,
              case .cut(let fresh) = decision, fresh.computedAt == now, fresh.matches(live),
              fresh.hasSameShot(as: token.plan) else { return nil }
        return issuer.issue(live: live, now: now, validity: permitValidity)
    }
    func consoleNextCut(now: TimeInterval) -> NextShotStatus.DirectorSection.NextCut? {
        guard let token = pending, now.isFinite, now >= token.issuedAt, now <= token.expiresAt, clockValid(now) else { return nil }
        return .init(input: token.plan.preview,
                     countdown: token.level == .backup ? nil : max(0, token.deadline - now), cancellable: true)
    }
    private func clockValid(_ now: TimeInterval) -> Bool {
        now.isFinite && now >= 0 && (lastClock.map { now >= $0 } ?? true)
    }
}
