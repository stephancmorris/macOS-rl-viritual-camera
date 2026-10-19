import Foundation

/// A-17, isolated R1/R2 proposal. Only B-12 may integrate this exceptional
/// source-loss permit with the existing synchronous technical Take checks.
/// No production caller exists while fallback decisions remain open.
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
    private(set) var pending: Permit?
    private var lastClock: TimeInterval?
    mutating func retire() { pending = nil }

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
        pending = nil
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
