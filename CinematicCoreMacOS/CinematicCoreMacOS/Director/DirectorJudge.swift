import Foundation

/// The seam where shot judgement plugs in (AI-1). A judge ranks Preview
/// candidates or declines. It never creates a shot, targets Program, extends a
/// lease or skips a check: the gate below admits only candidates the rules
/// already allow, and authority, staleness and permits stay elsewhere.
nonisolated protocol DirectorJudge: Sendable {
    func judge(_ context: DirectorJudgeContext) -> DirectorJudgement
}

nonisolated struct DirectorJudgeContext: Sendable {
    let timeline: DirectorShotPolicy.Timeline
    let preview: ChannelID
    let parameters: DirectorShotPolicy.Parameters
    /// Increments whenever the evidence behind the timeline changes.
    let evidenceRevision: UInt64
    let now: TimeInterval
}

nonisolated struct DirectorJudgement: Equatable, Sendable {
    struct Ranked: Equatable, Sendable {
        let candidate: DirectorShotPolicy.Candidate
        /// nil for rules; 0...1 for a calibrated learned judge.
        let probability: Double?
        let reason: String
    }
    enum Abstention: Equatable, Sendable {
        case policy(DirectorShotPolicy.Abstention)
        case lowConfidence, notRecorded, nothingAllowed, invalidJudgement
    }
    enum Outcome: Equatable, Sendable {
        case ranked([Ranked])
        case abstain(Abstention)
    }

    let outcome: Outcome
    /// The evidence this judgement was computed from.
    let evidenceRevision: UInt64
    let computedAt: TimeInterval

    var top: Ranked? {
        if case .ranked(let list) = outcome { return list.first }
        return nil
    }

    /// Bound to the evidence it saw: a judgement for older evidence, from the
    /// future, or older than `maximumAge` is stale. Fails closed on bad clocks.
    func isCurrent(evidenceRevision current: UInt64, now: TimeInterval, maximumAge: TimeInterval) -> Bool {
        evidenceRevision == current && now.isFinite && computedAt.isFinite && maximumAge.isFinite &&
            maximumAge >= 0 && now >= computedAt && now - computedAt <= maximumAge
    }
}

/// Today's deterministic rules as a judge: the baseline and the fallback.
nonisolated struct RuleJudge: DirectorJudge {
    func judge(_ context: DirectorJudgeContext) -> DirectorJudgement {
        let outcome: DirectorJudgement.Outcome
        switch DirectorShotPolicy.rank(context.timeline, preview: context.preview, parameters: context.parameters) {
        case .abstain(let reason):
            outcome = .abstain(.policy(reason))
        case .ranked(let sorted, let dueWide):
            outcome = sorted.isEmpty ? .abstain(.policy(.noEligibleCandidate)) : .ranked(sorted.map {
                .init(candidate: $0, probability: nil, reason: DirectorShotPolicy.reason(for: $0,
                    dueWide: dueWide, timeline: context.timeline, parameters: context.parameters))
            })
        }
        return DirectorJudgement(outcome: outcome, evidenceRevision: context.evidenceRevision, computedAt: context.now)
    }
}

/// Replays judgements logged in shadow mode, keyed by evidence revision, so a
/// replay with any judge plugged in stays deterministic.
nonisolated struct RecordedJudge: DirectorJudge {
    let records: [UInt64: DirectorJudgement.Outcome]

    func judge(_ context: DirectorJudgeContext) -> DirectorJudgement {
        DirectorJudgement(outcome: records[context.evidenceRevision] ?? .abstain(.notRecorded),
                          evidenceRevision: context.evidenceRevision, computedAt: context.now)
    }
}

/// AI proposes, rules dispose: the only way a judgement reaches preparation.
nonisolated enum DirectorJudgeGate {
    enum Result: Equatable, Sendable {
        case accepted(DirectorJudgement.Ranked)
        case abstain(DirectorJudgement.Abstention)
        case stale
    }

    /// - Parameters:
    ///   - allowed: the rules' ranking for the same timeline; nothing outside it is admitted.
    ///   - minimumProbability: below this, a probabilistic judge abstains. nil for rules-only.
    static func accept(_ judgement: DirectorJudgement, allowed: DirectorShotPolicy.Ranking,
                       evidenceRevision: UInt64, now: TimeInterval, maximumAge: TimeInterval,
                       minimumProbability: Double? = nil) -> Result {
        guard judgement.isCurrent(evidenceRevision: evidenceRevision, now: now, maximumAge: maximumAge) else {
            return .stale
        }
        let ranked: [DirectorJudgement.Ranked]
        switch judgement.outcome {
        case .abstain(let reason): return .abstain(reason)
        case .ranked(let list): ranked = list
        }
        guard case .ranked(let permitted, _) = allowed else {
            if case .abstain(let reason) = allowed { return .abstain(.policy(reason)) }
            return .abstain(.nothingAllowed)
        }
        let admitted = ranked.filter { item in permitted.contains(item.candidate) }
        guard let top = admitted.first else { return .abstain(.nothingAllowed) }
        if let probability = top.probability {
            guard probability.isFinite, (0...1).contains(probability) else { return .abstain(.invalidJudgement) }
            if let minimumProbability {
                guard minimumProbability.isFinite, (0...1).contains(minimumProbability) else {
                    return .abstain(.invalidJudgement)
                }
                if probability < minimumProbability { return .abstain(.lowConfidence) }
            }
        } else if minimumProbability != nil {
            // A probability threshold was required but the judge gave none.
            return .abstain(.invalidJudgement)
        }
        return .accepted(top)
    }
}
