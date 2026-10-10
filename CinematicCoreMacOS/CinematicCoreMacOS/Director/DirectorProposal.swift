import Foundation

/// A shot the Director may prepare, in the app's own vocabulary (N3): the
/// Stage and Webcam presets an operator can already pick. There are no
/// Director-only shot names, modes or zoom rungs.
nonisolated struct DirectorShot: Equatable, Hashable, Sendable {
    let preset: OperatorCommand.Preset

    init(preset: OperatorCommand.Preset) { self.preset = preset }

    var isWide: Bool {
        switch preset {
        case .stage(.wide), .webcam(.wide): return true
        default: return false
        }
    }

    /// Total, deterministic order: Stage before Webcam, then each format's
    /// ladder from widest to tightest.
    var order: Int {
        switch preset {
        case .stage(let shot):
            return ShotComposer.Config.ShotPreset.allCases.firstIndex(of: shot) ?? 0
        case .webcam(let shot):
            return 100 + (ShotComposer.Config.WebcamPreset.allCases.firstIndex(of: shot) ?? 0)
        }
    }
}

nonisolated struct DirectorProposal: Equatable, Sendable {
    let id: UUID
    let policyRevision: UInt64
    let nominationRevision: UInt64
    let target: ChannelID
    let shot: DirectorShot
    let reason: String
    let authorityEpoch: UInt64
    let revisions: ChannelRevisions
    let routeGeneration: UInt64
    let createdAt: TimeInterval

    /// nil unless `target` is the Preview channel: a proposal for Program (or
    /// any non-Preview input) is refused, never a crash in a live show.
    init?(target: ChannelID, preview: ChannelID, shot: DirectorShot, reason: String,
          authorityEpoch: UInt64, revisions: ChannelRevisions,
          routeGeneration: UInt64, createdAt: TimeInterval, id: UUID = UUID(),
          policyRevision: UInt64 = 0, nominationRevision: UInt64 = 0) {
        guard target == preview else { return nil }
        self.id = id; self.policyRevision = policyRevision; self.nominationRevision = nominationRevision
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
    var policyRevision: UInt64 = 0
    var nominationRevision: UInt64 = 0
    var evidenceAvailable: Bool = false
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
        case targetBecameProgram, sourceMissing, expired, requestReplaced, policyChanged, nominationChanged, evidenceUnavailable
    }
    enum Result: Equatable, Sendable { case valid, stale([StaleReason]) }

    static func validate(_ proposal: DirectorProposal, against live: DirectorLiveState,
                         now: TimeInterval, maximumAge: TimeInterval, action: DirectorAuthority.Action) -> Result {
        var reasons: [StaleReason] = []
        if !live.authority.authorizes(proposal.authorityEpoch, action: action) { reasons.append(.authorityRevoked) }
        if live.policyRevision != proposal.policyRevision { reasons.append(.policyChanged) }
        if live.nominationRevision != proposal.nominationRevision { reasons.append(.nominationChanged) }
        if action == .prepare && !live.evidenceAvailable { reasons.append(.evidenceUnavailable) }
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
        case compositionUnavailable, evidenceUnavailable, takeUnavailable, invalidParameters, invalidEvidence, identityUncertain, framingUnsettled, moving
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


/// A request lease authorizes dispatch once; the resulting composition has no timer lease.
nonisolated struct DirectorPreparation {
    struct Request: Equatable, Sendable {
        let id: UUID
        let intent: DirectorProposal
        let maximumAge: TimeInterval
        let issuedAt: TimeInterval
    }
    struct Receipt: Equatable, Sendable {
        let requestID: UUID
        let intent: DirectorProposal
        let postRevisions: ChannelRevisions
    }
    struct Composition: Equatable, Sendable {
        let requestID: UUID
        let intent: DirectorProposal
        let revisions: ChannelRevisions
    }
    private(set) var intent: DirectorProposal?
    private(set) var request: Request?
    private(set) var receipt: Receipt?
    private(set) var composition: Composition?

    mutating func propose(_ proposal: DirectorProposal, maximumAge: TimeInterval, now: TimeInterval) -> Request? {
        // Replacement retires both pending callbacks and the previous composition.
        retire()
        intent = proposal
        guard maximumAge.isFinite, maximumAge >= 0, proposal.createdAt.isFinite, now.isFinite, now >= proposal.createdAt else { return nil }
        let next = Request(id: UUID(), intent: proposal, maximumAge: maximumAge, issuedAt: now)
        request = next
        return next
    }
    mutating func retire() { intent = nil; request = nil; receipt = nil; composition = nil }

    /// Discard only this request; a stale/failed callback cannot cancel replacement work.
    mutating func discard(_ candidate: Request) {
        if request == candidate { request = nil }
    }

    /// A scheduler may discard an expired request without selecting/reissuing it.
    mutating func discardExpiredRequest(now: TimeInterval) {
        guard let pending = request else { return }
        if !now.isFinite || now < pending.issuedAt || now - pending.issuedAt > pending.maximumAge {
            request = nil
        }
    }

    /// Shared enqueue/final-effect validation. Intent age is not the dispatch lease.
    func validate(_ candidate: Request, live: DirectorLiveState, now: TimeInterval) -> DirectorProposalValidator.Result {
        var reasons: [DirectorProposalValidator.StaleReason] = []
        if case .stale(let context) = DirectorProposalValidator.validate(candidate.intent,
            against: live, now: candidate.intent.createdAt, maximumAge: 0, action: .prepare) {
            reasons = context
        }
        if request != candidate { reasons.append(.requestReplaced) }
        if !now.isFinite || now < candidate.issuedAt || now - candidate.issuedAt > candidate.maximumAge {
            if !reasons.contains(.expired) { reasons.append(.expired) }
        }
        return reasons.isEmpty ? .valid : .stale(reasons)
    }

    /// Call immediately at the simulated effect, with no suspension before applying
    /// the preset. postRevisions are the sink's expected accepted result, not a late lookup.
    mutating func commit(_ candidate: Request, live: DirectorLiveState, now: TimeInterval,
                         postRevisions: ChannelRevisions) -> Receipt? {
        guard request == candidate else { return nil }
        guard validate(candidate, live: live, now: now) == .valid else {
            request = nil // Discard; never renew this lease.
            return nil
        }
        guard let before = live.revisions,
              before.sourceGeneration == postRevisions.sourceGeneration,
              before.controlEpoch < postRevisions.controlEpoch,
              before.shotRevision < postRevisions.shotRevision else { request = nil; return nil }
        request = nil
        let accepted = Receipt(requestID: candidate.id, intent: candidate.intent, postRevisions: postRevisions)
        receipt = accepted
        return accepted
    }
    private static func contextValid(_ proposal: DirectorProposal, revisions: ChannelRevisions,
                                     live: DirectorLiveState) -> Bool {
        live.authority.authorizes(proposal.authorityEpoch, action: .propose) &&
        live.preview == proposal.target && live.program != proposal.target && !live.sourceMissing &&
        live.revisions == revisions && live.routeGeneration == proposal.routeGeneration &&
        live.policyRevision == proposal.policyRevision && live.nominationRevision == proposal.nominationRevision
    }
    mutating func acknowledge(_ accepted: Receipt, live: DirectorLiveState) -> Bool {
        guard receipt == accepted else { return false }
        receipt = nil // One shot, even if invalid.
        guard Self.contextValid(accepted.intent, revisions: accepted.postRevisions, live: live) else { return false }
        composition = Composition(requestID: accepted.requestID, intent: accepted.intent, revisions: accepted.postRevisions)
        return true
    }
    mutating func refresh(live: DirectorLiveState, evidence: DirectorReadiness.Inputs,
                          parameters: DirectorReadiness.Parameters) -> DirectorReadiness {
        guard let prepared = composition,
              Self.contextValid(prepared.intent, revisions: prepared.revisions, live: live) else {
            composition = nil
            return .init(reasons: [.compositionUnavailable])
        }
        guard live.evidenceAvailable && live.authority.evidenceAvailable else {
            return .init(reasons: [.evidenceUnavailable])
        }
        return DirectorReadiness.evaluate(evidence, parameters: parameters)
    }
}
