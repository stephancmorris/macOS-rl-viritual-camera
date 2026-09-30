import Foundation

nonisolated struct DirectorShot: Equatable, Hashable, Sendable {
    enum Preset: String, Sendable { case wide, waistUp, medium, closeUp, custom }
    enum Mode: String, Sendable { case manualCrop, autoTracking, autoPan }
    let preset: Preset
    let mode: Mode
    let zoomRung: Int
}

nonisolated struct DirectorProposal: Equatable, Sendable {
    let target: ChannelID
    let shot: DirectorShot
    let reason: String
    let authorityEpoch: UInt64
    let revisions: ChannelRevisions
    let routeGeneration: UInt64
    let createdAt: TimeInterval

    init(target: ChannelID, preview: ChannelID, shot: DirectorShot, reason: String,
         authorityEpoch: UInt64, revisions: ChannelRevisions,
         routeGeneration: UInt64, createdAt: TimeInterval) {
        precondition(target == preview, "Director proposals may target Preview only")
        self.target = target; self.shot = shot; self.reason = reason
        self.authorityEpoch = authorityEpoch; self.revisions = revisions
        self.routeGeneration = routeGeneration; self.createdAt = createdAt
    }
}

nonisolated struct DirectorLiveState: Sendable {
    let authority: DirectorAuthority
    let program: ChannelID
    let preview: ChannelID?
    let revisions: ChannelRevisions?
    let routeGeneration: UInt64
    let sourceMissing: Bool
}

nonisolated protocol DirectorWorld {
    func directorState() -> DirectorLiveState
}

/// Main-actor boundary over R2's existing observable state. Authority is injected
/// because ShowCoordinator intentionally has no director field yet.
@MainActor final class ShowDirectorWorld: DirectorWorld {
    let show: ShowCoordinator
    var authority: DirectorAuthority
    init(show: ShowCoordinator, authority: DirectorAuthority) {
        self.show = show; self.authority = authority
    }
    func directorState() -> DirectorLiveState {
        let preview = show.previewChannel
        let channel = preview.flatMap(show.channel)
        return DirectorLiveState(authority: authority, program: show.programChannel,
            preview: preview, revisions: channel?.revisions,
            routeGeneration: show.router.routeGeneration,
            sourceMissing: channel?.sourceMissing ?? true)
    }
}

nonisolated enum DirectorProposalValidator {
    enum StaleReason: Hashable, Sendable {
        case authorityRevoked, routeChanged, sourceRestarted, shotChangedByOperator
        case targetBecameProgram, sourceMissing, expired
    }
    enum Result: Equatable, Sendable { case valid, stale([StaleReason]) }

    static func validate(_ proposal: DirectorProposal, against live: DirectorLiveState,
                         now: TimeInterval, maximumAge: TimeInterval) -> Result {
        var reasons: [StaleReason] = []
        if !live.authority.admits(proposal.authorityEpoch) { reasons.append(.authorityRevoked) }
        if live.routeGeneration != proposal.routeGeneration { reasons.append(.routeChanged) }
        if proposal.target == live.program || proposal.target != live.preview { reasons.append(.targetBecameProgram) }
        if live.sourceMissing || live.revisions == nil { reasons.append(.sourceMissing) }
        if let current = live.revisions {
            if current.sourceGeneration != proposal.revisions.sourceGeneration { reasons.append(.sourceRestarted) }
            if current.controlEpoch != proposal.revisions.controlEpoch || current.shotRevision != proposal.revisions.shotRevision {
                reasons.append(.shotChangedByOperator)
            }
        }
        if !now.isFinite || !proposal.createdAt.isFinite || !maximumAge.isFinite || maximumAge < 0 ||
            now < proposal.createdAt || now - proposal.createdAt > maximumAge {
            reasons.append(.expired)
        }
        return reasons.isEmpty ? .valid : .stale(reasons)
    }
}

nonisolated struct DirectorReadiness: Equatable, Sendable {
    struct Inputs: Sendable {
        let take: TakeAvailability
        let identityConfidence: Double
        let framingSettledFor: TimeInterval
        let motion: Double
    }
    struct Parameters: Sendable {
        let minimumIdentityConfidence: Double
        let minimumSettledTime: TimeInterval
        let maximumMotion: Double
        let cutOnMotionAllowed: Bool
    }
    enum Reason: Hashable, Sendable {
        case takeUnavailable, invalidParameters, invalidEvidence, identityUncertain, framingUnsettled, moving
    }
    let reasons: [Reason]
    var isReady: Bool { reasons.isEmpty }
    static func evaluate(_ input: Inputs, parameters: Parameters) -> DirectorReadiness {
        var reasons: [Reason] = []
        if !input.take.isEligible { reasons.append(.takeUnavailable) }
        guard parameters.minimumIdentityConfidence.isFinite,
              (0...1).contains(parameters.minimumIdentityConfidence),
              parameters.minimumSettledTime.isFinite, parameters.minimumSettledTime >= 0,
              parameters.maximumMotion.isFinite, parameters.maximumMotion >= 0 else {
            reasons.append(.invalidParameters)
            return .init(reasons: reasons)
        }
        guard input.identityConfidence.isFinite, (0...1).contains(input.identityConfidence),
              input.framingSettledFor.isFinite, input.framingSettledFor >= 0,
              input.motion.isFinite, input.motion >= 0 else {
            reasons.append(.invalidEvidence)
            return .init(reasons: reasons)
        }
        if input.identityConfidence < parameters.minimumIdentityConfidence { reasons.append(.identityUncertain) }
        if input.framingSettledFor < parameters.minimumSettledTime { reasons.append(.framingUnsettled) }
        if !parameters.cutOnMotionAllowed && input.motion > parameters.maximumMotion { reasons.append(.moving) }
        return .init(reasons: reasons)
    }
}
