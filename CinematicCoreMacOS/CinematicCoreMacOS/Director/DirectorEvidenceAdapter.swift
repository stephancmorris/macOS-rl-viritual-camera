import Foundation

/// S3 A-07: turns each channel's evidence samples over time into the facts
/// the Director needs: debounced identity, how long the subject has been
/// settled, readiness inputs, and authority events. Pure and deterministic;
/// time comes only from the samples.
///
/// A lock wobble (tracking → hold → tracking) bumps the channel's shot
/// revision on the frame path (plan F-D), so a short flicker must not also
/// churn evidence: a changed identity is published only after it persists for
/// `debounce`. A declared loss and a nomination change are never debounced.
/// Missing, stale or malformed evidence inhibits immediately; debounce never
/// extends observation freshness or preserves a settled subject through a gap.
nonisolated struct DirectorEvidenceAdapter: Sendable {
    struct Parameters: Equatable, Sendable {
        let maximumObservationAge: TimeInterval
        /// How long a changed identity must persist before it is published.
        let debounce: TimeInterval
        /// Subject speed at or below which the subject counts as still.
        let stillSpeed: Double

        var isValid: Bool {
            maximumObservationAge.isFinite && maximumObservationAge >= 0 &&
            debounce.isFinite && debounce >= 0 && stillSpeed.isFinite && stillSpeed >= 0
        }
    }

    struct ChannelState: Equatable, Sendable {
        /// The published (debounced) identity.
        var identity: IdentityEvidence = .unavailable
        var pendingIdentity: IdentityEvidence?
        var pendingSince: TimeInterval?
        var settledSince: TimeInterval?
        var lockedTargetID: UUID?
        var operatorGestureInProgress = false
        var subjectSpeed = 0.0
        var cropConverged = false
        var lastSampleAt: TimeInterval?

        /// Preparation-grade evidence: a confirmed subject and no operator gesture in flight.
        var evidenceAvailable: Bool { identity == .confirmed && !operatorGestureInProgress }
    }

    enum Event: Equatable, Sendable {
        /// A temporary gap opened or closed. Never revokes a grant.
        case evidenceAvailable(ChannelID, Bool)
        /// The subject has gone (N5): revoke and pause.
        case identityLost(ChannelID)
        /// The nominated subject changed or was cleared: revoke and pause.
        case nominationChanged(ChannelID)
    }

    let parameters: Parameters
    private(set) var channels: [ChannelID: ChannelState] = [:]

    init(parameters: Parameters) { self.parameters = parameters }

    func state(for channel: ChannelID) -> ChannelState? { channels[channel] }

    /// Seconds the subject has been settled, 0 if not settled or the clock is bad.
    func settledFor(_ channel: ChannelID, now: TimeInterval) -> TimeInterval {
        guard let since = channels[channel]?.settledSince, now.isFinite, now >= since else { return 0 }
        return now - since
    }

    /// Readiness inputs for a channel, or nil before its first sample.
    func readinessInputs(for channel: ChannelID, take: TakeAvailability, now: TimeInterval) -> DirectorReadiness.Inputs? {
        guard let state = channels[channel] else { return nil }
        return .init(take: take, identity: state.identity, framingSettledFor: settledFor(channel, now: now),
                     motion: state.subjectSpeed, cropConverged: state.cropConverged)
    }

    @discardableResult
    mutating func ingest(_ sample: ChannelEvidenceSample) -> [Event] {
        let now = sample.sampledAt
        var state = channels[sample.channel] ?? ChannelState()
        let wasAvailable = channels[sample.channel]?.evidenceAvailable ?? false
        // A bad current clock cannot support fresh evidence. Discard its payload
        // and inhibit without moving the last accepted timestamp or nomination.
        guard now.isFinite, now >= 0 else {
            guard channels[sample.channel] != nil else { return [] }
            if state.identity != .lost { state.identity = .unavailable }
            state.pendingIdentity = nil; state.pendingSince = nil; state.settledSince = nil
            channels[sample.channel] = state
            return wasAvailable ? [.evidenceAvailable(sample.channel, false)] : []
        }
        // A finite, nonnegative older sample is historical: ignore it completely.
        // It must neither rewind state nor revoke a newer accepted nomination.
        guard state.lastSampleAt.map({ now >= $0 }) ?? true else { return [] }
        var events: [Event] = []

        let raw = parameters.isValid
            ? IdentityEvidence.classify(sample, maximumObservationAge: parameters.maximumObservationAge)
            : .unavailable

        let observationIsFresh = sample.observationAge.map {
            $0.isFinite && $0 >= 0 && $0 <= parameters.maximumObservationAge
        } ?? false
        // Unavailable evidence is a real gap, not a brief lock wobble. Also do
        // not let hold/acquiring bypass freshness while retaining confirmation.
        // Keep their truthful category; only a fresh wobble uses debounce.
        // Declared wideWaiting loss still follows its ordinary revocation path.
        if raw != .lost, raw == .unavailable || !observationIsFresh {
            state.identity = raw
            state.pendingIdentity = nil; state.pendingSince = nil; state.settledSince = nil
        }

        // Nomination: a different subject, or a cleared one that wasn't a loss.
        let previousTarget = state.lockedTargetID
        let nominationChanged = previousTarget != nil && sample.lockedTargetID != previousTarget &&
            !(sample.lockedTargetID == nil && raw == .lost)
        if nominationChanged {
            events.append(.nominationChanged(sample.channel))
            state.identity = raw
            state.pendingIdentity = nil; state.pendingSince = nil; state.settledSince = nil
        }
        if sample.lockedTargetID != nil || raw == .lost || nominationChanged {
            state.lockedTargetID = sample.lockedTargetID
        }

        if raw == .lost {
            if state.identity != .lost { events.append(.identityLost(sample.channel)) }
            state.identity = .lost
            state.pendingIdentity = nil; state.pendingSince = nil
        } else if !nominationChanged {
            if raw == state.identity {
                state.pendingIdentity = nil; state.pendingSince = nil
            } else {
                if state.pendingIdentity != raw { state.pendingIdentity = raw; state.pendingSince = now }
                if let since = state.pendingSince, now - since >= parameters.debounce, parameters.isValid {
                    state.identity = raw
                    state.pendingIdentity = nil; state.pendingSince = nil
                }
            }
        }

        state.operatorGestureInProgress = sample.operatorGestureInProgress
        state.subjectSpeed = sample.subjectSpeed
        state.cropConverged = sample.cropConverged
        let still = sample.subjectSpeed.isFinite && sample.subjectSpeed >= 0 && sample.subjectSpeed <= parameters.stillSpeed
        if parameters.isValid, state.identity == .confirmed, sample.holdingSteady, still, sample.cropConverged {
            state.settledSince = state.settledSince ?? now
        } else {
            state.settledSince = nil
        }
        state.lastSampleAt = now
        channels[sample.channel] = state

        if state.evidenceAvailable != wasAvailable {
            events.append(.evidenceAvailable(sample.channel, state.evidenceAvailable))
        }
        return events
    }
}
