import Foundation

/// Synchronous effect boundary. The caller supplies the current world in the
/// same turn; implementations revalidate the one-shot request immediately
/// before applying an off-air preset, without an await or deferred retry.
/// Take and on-air moves deliberately have no entry point until their permit
/// and policy contracts land. This protocol itself grants no authority.
nonisolated protocol DirectorEffectSink {
    mutating func prepare(_ request: DirectorPreparation.Request,
                          preparation: inout DirectorPreparation,
                          live: DirectorLiveState, now: TimeInterval) -> DirectorPreparationEffect
}

nonisolated enum DirectorPreparationEffect: Equatable, Sendable {
    case committed(DirectorPreparation.Receipt)
    case rejected([DirectorProposalValidator.StaleReason])
    case failed
}

/// Synthetic preset mutation only. No camera, output, I/O or qualification.
/// The injected outcome models a command refusing to apply; it is not a retry.
nonisolated struct SimulatedDirectorEffectSink: DirectorEffectSink {
    let succeeds: Bool
    private(set) var appliedReceipts: [DirectorPreparation.Receipt] = []

    init(succeeds: Bool) { self.succeeds = succeeds }

    mutating func prepare(_ request: DirectorPreparation.Request,
                          preparation: inout DirectorPreparation,
                          live: DirectorLiveState, now: TimeInterval) -> DirectorPreparationEffect {
        guard now.isFinite, now >= 0, request.issuedAt.isFinite, request.issuedAt >= 0,
              request.intent.createdAt.isFinite, request.intent.createdAt >= 0,
              request.maximumAge.isFinite, request.maximumAge >= 0 else {
            preparation.discard(request)
            return .rejected([.expired])
        }
        if case .stale(let reasons) = preparation.validate(request, live: live, now: now) {
            preparation.discard(request)
            return .rejected(reasons)
        }
        guard succeeds, var revisions = live.revisions,
              revisions.controlEpoch < UInt64.max, revisions.shotRevision < UInt64.max else {
            preparation.discard(request)
            return .failed
        }
        revisions.controlEpoch += 1
        revisions.shotRevision += 1
        guard let receipt = preparation.commit(request, live: live, now: now, postRevisions: revisions) else {
            // No suspension occurs above, so a refused commit is terminal.
            preparation.discard(request)
            return .failed
        }
        appliedReceipts.append(receipt)
        return .committed(receipt)
    }
}
