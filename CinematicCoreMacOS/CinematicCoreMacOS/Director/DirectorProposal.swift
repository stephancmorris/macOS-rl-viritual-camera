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

    /// The operator's name for the shot, e.g. "Waist Up".
    var title: String {
        switch preset {
        case .stage(let shot): return shot.title
        case .webcam(let shot): return shot.title
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

/// What a channel's evidence says about the subject, in discrete terms. There
/// is no invented confidence number: these are the lock states the camera
/// already has (plan §5.2).
nonisolated enum IdentityEvidence: Equatable, Hashable, Sendable {
    /// Locked, face gallery ready, tracking owns framing, observation fresh.
    case confirmed
    /// Learning the face (lock not yet ready). A temporary gap.
    case acquiring
    /// Recovering a brief loss. A temporary gap.
    case holding
    /// The composer pulled back to wide: the subject has gone (N5).
    case lost
    /// More than one plausible person (a crossing, a panel). Use a wider shot (P2).
    case ambiguous
    /// No subject, the operator is framing manually, or observations are stale.
    case unavailable

    /// Classifies one sample. Fails closed: invalid ages read as unavailable.
    static func classify(_ sample: ChannelEvidenceSample,
                         maximumObservationAge: TimeInterval) -> IdentityEvidence {
        if sample.lockPhase == .wideWaiting { return .lost }
        guard sample.lockPhase != .inactive, sample.lockedTargetID != nil,
              sample.trackingOwnsControl else { return .unavailable }
        switch sample.lockPhase {
        case .acquiring: return .acquiring
        case .hold: return .holding
        case .inactive, .wideWaiting: return .unavailable
        case .tracking: break
        }
        guard sample.galleryReady else { return .acquiring }
        guard maximumObservationAge.isFinite, maximumObservationAge >= 0,
              let age = sample.observationAge, age.isFinite, age >= 0,
              age <= maximumObservationAge else { return .unavailable }
        return sample.observedPersonCount >= 2 ? .ambiguous : .confirmed
    }
}

/// One channel's evidence at one moment: the shared contract between the
/// engine (which reads the camera) and the Director's pure logic. Values only;
/// no camera, actor or clock access.
nonisolated struct ChannelEvidenceSample: Equatable, Sendable {
    let channel: ChannelID
    /// Host-clock time the sample was taken.
    let sampledAt: TimeInterval
    let lockPhase: RecoveryState.Phase
    let trackingOwnsControl: Bool
    let galleryReady: Bool
    let lockedTargetID: UUID?
    /// Seconds since the newest detection observation; nil if none yet.
    let observationAge: TimeInterval?
    /// Smoothed subject speed, normalized frame units per second.
    let subjectSpeed: Double
    /// The composer has concluded the subject settled and is holding.
    let holdingSteady: Bool
    /// The crop has reached its target (no interpolation or zoom move).
    let cropConverged: Bool
    /// The operator has a gesture in flight on this channel (inhibit only).
    let operatorGestureInProgress: Bool
    /// People in the newest fresh observation (the subject ROI while locked).
    let observedPersonCount: Int
}

/// Two bars (P1): prepare-ready lets the Director set up Preview; cut-ready is
/// stricter and is required before any automatic cut. Neither ever blocks an
/// operator Take.
nonisolated struct DirectorReadiness: Equatable, Sendable {
    enum Bar: Equatable, Sendable { case prepare, cut }
    struct Inputs: Sendable {
        let take: TakeAvailability
        let identity: IdentityEvidence
        let framingSettledFor: TimeInterval
        let motion: Double
        let cropConverged: Bool
    }
    /// Study parameters only; there are no defaults. The cut bar must be at
    /// least as strict as the prepare bar.
    struct Parameters: Sendable {
        let minimumSettledTime: TimeInterval
        let maximumMotion: Double
        let cutOnMotionAllowed: Bool
        let minimumCutSettledTime: TimeInterval
        let maximumCutMotion: Double

        var isValid: Bool {
            minimumSettledTime.isFinite && minimumSettledTime >= 0 &&
            maximumMotion.isFinite && maximumMotion >= 0 &&
            minimumCutSettledTime.isFinite && minimumCutSettledTime >= minimumSettledTime &&
            maximumCutMotion.isFinite && maximumCutMotion >= 0 && maximumCutMotion <= maximumMotion
        }
    }
    enum Reason: Hashable, Sendable {
        case compositionUnavailable, evidenceUnavailable, takeUnavailable, invalidParameters, invalidEvidence
        case identityUncertain, framingUnsettled, moving, cropMoving
    }
    let reasons: [Reason]
    var isReady: Bool { reasons.isEmpty }

    static func evaluate(_ input: Inputs, parameters: Parameters, bar: Bar = .prepare) -> DirectorReadiness {
        var reasons: [Reason] = []
        if !input.take.isEligible { reasons.append(.takeUnavailable) }
        guard parameters.isValid else {
            reasons.append(.invalidParameters)
            return .init(reasons: reasons)
        }
        guard input.framingSettledFor.isFinite, input.framingSettledFor >= 0,
              input.motion.isFinite, input.motion >= 0 else {
            reasons.append(.invalidEvidence)
            return .init(reasons: reasons)
        }
        if input.identity != .confirmed { reasons.append(.identityUncertain) }
        switch bar {
        case .prepare:
            if input.framingSettledFor < parameters.minimumSettledTime { reasons.append(.framingUnsettled) }
            if !parameters.cutOnMotionAllowed && input.motion > parameters.maximumMotion { reasons.append(.moving) }
        case .cut:
            // Not mid-stride and framing landed, whatever the prepare policy allows.
            if input.framingSettledFor < parameters.minimumCutSettledTime { reasons.append(.framingUnsettled) }
            if input.motion > parameters.maximumCutMotion { reasons.append(.moving) }
            if !input.cropConverged { reasons.append(.cropMoving) }
        }
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
                          parameters: DirectorReadiness.Parameters,
                          bar: DirectorReadiness.Bar = .prepare) -> DirectorReadiness {
        guard let prepared = composition,
              Self.contextValid(prepared.intent, revisions: prepared.revisions, live: live) else {
            composition = nil
            return .init(reasons: [.compositionUnavailable])
        }
        guard live.evidenceAvailable && live.authority.evidenceAvailable else {
            return .init(reasons: [.evidenceUnavailable])
        }
        return DirectorReadiness.evaluate(evidence, parameters: parameters, bar: bar)
    }
}
