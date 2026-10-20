import Foundation

/// A-17 / B-12: an exceptional, one-shot source-loss grant. A loss may be
/// reserved before the router detects its hold, but a permit exists only
/// inside the actual hold window. Qualification and live trials remain open.
nonisolated struct BackupFallbackPolicy: Sendable {
    struct Snapshot: Sendable {
        let live: DirectorLiveState
        let prerequisites: DirectorAuthority.Prerequisites
        /// Separate current qualification for the fault-fallback capability.
        let fallbackQualified: Bool
        /// Verified against this Preview source generation and current shot.
        let verifiedSafeWide: Bool
        let previewShot: DirectorShot
        let previewFrameAt: TimeInterval?
        let technicalTakeEligible: Bool
        let operatorGestureInProgress: Bool
        let programStillMissing: Bool
        let routerHolding: Bool
        /// Actual absolute deadline from the router; never restart its window
        /// when a delayed fault callback arrives. Standby starts at this time.
        let holdDeadline: TimeInterval
    }
    struct Permit: Equatable, Sendable {
        let id: UUID
        let epoch: UInt64
        let program: ChannelID
        let preview: ChannelID
        let previewRevisions: ChannelRevisions
        let routeGeneration: UInt64
        let policyRevision: UInt64
        let nominationRevision: UInt64
        let issuedAt: TimeInterval
        let expiresAt: TimeInterval
        let maximumFrameAge: TimeInterval
        fileprivate init(_ s: Snapshot, epoch: UInt64, preview: ChannelID,
                         revisions: ChannelRevisions, now: TimeInterval, maximumFrameAge: TimeInterval) {
            id = UUID(); self.epoch = epoch; program = s.live.program; self.preview = preview
            previewRevisions = revisions; routeGeneration = s.live.routeGeneration
            policyRevision = s.live.policyRevision; nominationRevision = s.live.nominationRevision
            issuedAt = now; expiresAt = s.holdDeadline
            self.maximumFrameAge = maximumFrameAge
        }
    }
    /// Captures permission immediately before the ordinary fault transition.
    /// It grants no effect and contains no invented router deadline.
    struct Reservation: Equatable, Sendable {
        let id: UUID
        let authority: DirectorAuthority
        let program: ChannelID
        let preview: ChannelID
        let previewRevisions: ChannelRevisions
        let routeGeneration: UInt64
        let policyRevision: UInt64
        let nominationRevision: UInt64
        let createdAt: TimeInterval
        let maximumFrameAge: TimeInterval
    }
    private(set) var pending: Permit?
    private(set) var reservation: Reservation?
    private var lastClock: TimeInterval?
    mutating func retire() { pending = nil; reservation = nil }

    /// B-12's split ingress: the controller first cancels/pauses using its
    /// normal sourceLoss transition, then reserves the exact resulting state.
    /// No stale pre-fault snapshot can grant after an intervening event.
    mutating func reserveSourceLoss(_ channel: ChannelID, before: DirectorLiveState,
                                   after: DirectorAuthority, now: TimeInterval,
                                   maximumFrameAge: TimeInterval) -> Reservation? {
        guard now.isFinite, now >= 0, lastClock.map({ now >= $0 }) ?? true,
              maximumFrameAge.isFinite, maximumFrameAge >= 0,
              channel == before.program, before.authority.level == .backup,
              before.authority.mayIssueTake(at: now), let preview = before.preview,
              preview != before.program, let revisions = before.revisions else { return nil }
        var expected = before.authority
        expected.apply(.sourceLoss(channel))
        guard after == expected, !after.exhausted, after.epoch > before.authority.epoch else { return nil }
        let next = Reservation(id: UUID(), authority: after, program: before.program,
            preview: preview, previewRevisions: revisions, routeGeneration: before.routeGeneration,
            policyRevision: before.policyRevision, nominationRevision: before.nominationRevision,
            createdAt: now, maximumFrameAge: maximumFrameAge)
        retire()
        reservation = next
        lastClock = now
        return next
    }

    /// First actual hold callback only. A matching failed attempt is terminal;
    /// later fresh frames or repeated fault callbacks never renew the chance.
    mutating func issueReserved(_ candidate: Reservation, snapshot s: Snapshot,
                               now: TimeInterval, maximumFrameAge: TimeInterval) -> Permit? {
        guard reservation == candidate else { return nil }
        reservation = nil
        guard maximumFrameAge == candidate.maximumFrameAge, now >= candidate.createdAt,
              eligible(s, now: now, maximumFrameAge: maximumFrameAge),
              s.live.authority == candidate.authority,
              s.live.program == candidate.program, s.live.preview == candidate.preview,
              s.live.revisions == candidate.previewRevisions,
              s.live.routeGeneration == candidate.routeGeneration,
              s.live.policyRevision == candidate.policyRevision,
              s.live.nominationRevision == candidate.nominationRevision else { return nil }
        let permit = Permit(s, epoch: candidate.authority.epoch, preview: candidate.preview,
                            revisions: candidate.previewRevisions, now: now, maximumFrameAge: maximumFrameAge)
        pending = permit
        lastClock = now
        return permit
    }

    /// Call once at source-loss ingress, before the ordinary authority handler.
    /// Every level receives exactly its existing sourceLoss transition. Backup
    /// may retain one narrowly bound exception after that transition; authority
    /// remains paused throughout and never grants a normal Take permit.
    mutating func sourceLoss(_ channel: ChannelID, authority: inout DirectorAuthority,
                             snapshot s: Snapshot, now: TimeInterval,
                             maximumFrameAge: TimeInterval) -> Permit? {
        // A delayed event from an older authority/source binding cannot
        // revoke newer work. Validate before touching the pending exception.
        guard authority == s.live.authority else { return nil }
        retire()
        let prior = authority
        authority.apply(.sourceLoss(channel))
        guard channel == s.live.program,
              prior.level == .backup, prior.mayIssueTake(at: now),
              authority.epoch > prior.epoch, !authority.exhausted,
              eligible(s, now: now, maximumFrameAge: maximumFrameAge),
              let preview = s.live.preview, let revisions = s.live.revisions else { return nil }
        lastClock = now
        let permit = Permit(s, epoch: authority.epoch, preview: preview, revisions: revisions, now: now,
                            maximumFrameAge: maximumFrameAge)
        pending = permit
        return permit
    }

    /// A matching attempt is terminal, including technical refusal. No reissue
    /// on a repeated fault: authority is already paused. A stale callback can
    /// never consume a newer fault's permit.
    mutating func consume(_ permit: Permit, snapshot s: Snapshot, now: TimeInterval,
                          maximumFrameAge: TimeInterval) -> Permit? {
        guard pending == permit else { return nil }
        pending = nil
        let a = s.live.authority
        guard maximumFrameAge == permit.maximumFrameAge,
              eligible(s, now: now, maximumFrameAge: maximumFrameAge), now >= permit.issuedAt,
              now < permit.expiresAt, s.holdDeadline == permit.expiresAt,
              a.epoch == permit.epoch, a.level == .backup, a.running, a.paused, !a.healthy,
              !a.exhausted, !a.editLive, a.pinnedShot == nil,
              s.live.program == permit.program, s.live.preview == permit.preview,
              s.live.revisions == permit.previewRevisions,
              s.live.routeGeneration == permit.routeGeneration,
              s.live.policyRevision == permit.policyRevision,
              s.live.nominationRevision == permit.nominationRevision else { return nil }
        lastClock = now
        return permit
    }

    private func eligible(_ s: Snapshot, now: TimeInterval, maximumFrameAge: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, lastClock.map({ now >= $0 }) ?? true,
              maximumFrameAge.isFinite, maximumFrameAge >= 0,
              s.holdDeadline.isFinite, now < s.holdDeadline, s.routerHolding,
              s.programStillMissing, s.fallbackQualified, s.verifiedSafeWide, s.previewShot.isWide,
              let frameAt = s.previewFrameAt, frameAt.isFinite, frameAt >= 0,
              now >= frameAt, now - frameAt <= maximumFrameAge,
              s.live.preview != nil, s.live.preview != s.live.program,
              s.live.revisions != nil, !s.live.sourceMissing,
              s.technicalTakeEligible, !s.operatorGestureInProgress else { return false }
        let p = s.prerequisites
        // Program loss is the one allowed source fault. Preview freshness and
        // availability above stay mandatory; output/admission faults never do.
        return p.nominationsCurrent && p.previewAvailable && p.outputHealthy && p.admissionCurrent &&
            p.qualifiedLevels.contains(.backup)
    }
}
