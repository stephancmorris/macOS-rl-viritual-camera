import Foundation

/// A-10: Assist recommendation policy. No dispatch, grant or Take capability.
/// The controller supplies the actual Preview tenure and marks only committed
/// preparations; N4 remains an explicitly supplied flag, not a product default.
nonisolated extension DirectorShotPolicy {
    enum InputFormat: Equatable, Sendable {
        case stage, webcam
        init(_ preset: OperatorCommand.Preset) {
            switch preset { case .stage: self = .stage; case .webcam: self = .webcam }
        }
        var ladder: [DirectorShot] {
            switch self {
            case .stage: ShotComposer.Config.ShotPreset.allCases.map { .init(preset: .stage($0)) }
            case .webcam: ShotComposer.Config.WebcamPreset.allCases.map { .init(preset: .webcam($0)) }
            }
        }
    }
    struct Input: Sendable {
        let channel: ChannelID
        let sourceGeneration: UInt64
        let sampledAt: TimeInterval
        let observationAge: TimeInterval?
        let hasNomination: Bool
        let format: InputFormat
        let identity: IdentityEvidence
        let operatorGestureInProgress: Bool
        /// Actual prepare-bar result. Wide-only suggestions are not assertions
        /// of single-subject readiness; the effect boundary still revalidates.
        let prepareReadiness: DirectorReadiness?
        /// Ranking scores supplied for measured preset candidates. Missing scores
        /// mean unavailable, never an invented zero or biometric probability.
        let presetScores: [DirectorShot: Double]
        let movement: Double
    }
    struct AssistParameters: Sendable {
        let policy: Parameters
        let onePreparationPerTenure: Bool
        let maximumSampleAge: TimeInterval
        let maximumObservationAge: TimeInterval
        let judgeMaximumAge: TimeInterval
        let minimumProbability: Double?
        var isValid: Bool {
            policy.isValid && maximumSampleAge.isFinite && maximumSampleAge >= 0 &&
                maximumObservationAge.isFinite && maximumObservationAge >= 0 && judgeMaximumAge.isFinite && judgeMaximumAge >= 0 &&
                (minimumProbability.map { $0.isFinite && (0...1).contains($0) } ?? true)
        }
    }
    struct PreviewTenure: Equatable, Sendable {
        /// Controller-owned session token, renewed when Preview tenure changes.
        /// Its generation rules are supplied by the integration, not guessed here.
        let id: UUID
        let preview: ChannelID
        let sourceGeneration: UInt64
        let routeGeneration: UInt64
    }
    struct PreparationHistory: Sendable {
        private(set) var currentTenure: PreviewTenure
        private var prepared = false
        private var lastReceiptID: UUID?
        var preparedTenure: PreviewTenure? { prepared ? currentTenure : nil }
        init(tenure: PreviewTenure) { currentTenure = tenure }
        /// Coordinator ingress only. Delayed effect callbacks use their captured
        /// tenure with recordCommittedPreparation, never advance this state.
        mutating func beginTenure(_ next: PreviewTenure) {
            if next != currentTenure { currentTenure = next; prepared = false; lastReceiptID = nil }
        }
        @discardableResult
        mutating func recordCommittedPreparation(_ receipt: DirectorPreparation.Receipt,
                                                 tenure: PreviewTenure) -> Bool {
            guard tenure == currentTenure, receipt.requestID != lastReceiptID, receipt.intent.target == tenure.preview,
                  receipt.intent.routeGeneration == tenure.routeGeneration,
                  receipt.intent.revisions.sourceGeneration == tenure.sourceGeneration,
                  receipt.postRevisions.sourceGeneration == tenure.sourceGeneration,
                  receipt.postRevisions.controlEpoch > receipt.intent.revisions.controlEpoch,
                  receipt.postRevisions.shotRevision > receipt.intent.revisions.shotRevision else { return false }
            prepared = true; lastReceiptID = receipt.requestID
            return true
        }
    }
    enum AssistAbstention: Equatable, Sendable {
        case invalidInput, noPreview, previewIsSafeWide, alreadyPrepared
        case operatorAdjusting, learningSubject, recoveringSubject, evidenceUnavailable
        case notReady([DirectorReadiness.Reason]), movement
        case policy(Abstention), judge(DirectorJudgement.Abstention), judgementStale
    }
    enum CandidateBuild: Equatable, Sendable {
        case candidates([Candidate]), abstain(AssistAbstention)
    }
    enum AssistDecision: Equatable, Sendable {
        case chosen(DirectorJudgement.Ranked), abstain(AssistAbstention)
    }

    static func candidates(for input: Input, parameters: Parameters, maximumObservationAge: TimeInterval, now: TimeInterval) -> CandidateBuild {
        let ladder = input.format.ladder
        guard now.isFinite, now >= 0, input.sampledAt.isFinite, input.sampledAt >= 0, now >= input.sampledAt,
              parameters.isValid, maximumObservationAge.isFinite, maximumObservationAge >= 0, input.movement.isFinite, input.movement >= 0,
              input.presetScores.allSatisfy({ ladder.contains($0.key) && $0.value.isFinite && (0...1).contains($0.value) }) else {
            return .abstain(.invalidInput)
        }
        guard !input.operatorGestureInProgress else { return .abstain(.operatorAdjusting) }
        let allowed: [DirectorShot]
        switch input.identity {
        case .acquiring: return .abstain(.learningSubject)
        case .holding: return .abstain(.recoveringSubject)
        case .confirmed:
            guard input.hasNomination, let age = input.observationAge,
                  age.isFinite, age >= 0, (age + (now - input.sampledAt)).isFinite,
                  age + (now - input.sampledAt) <= maximumObservationAge else { return .abstain(.evidenceUnavailable) }
            guard let ready = input.prepareReadiness else { return .abstain(.evidenceUnavailable) }
            guard ready.isReady else { return .abstain(.notReady(ready.reasons)) }
            guard parameters.cutOnMotionAllowed || input.movement <= parameters.maximumMovement else {
                return .abstain(.movement)
            }
            allowed = ladder
        case .ambiguous, .lost, .unavailable:
            // P2 / N5 / no nomination: never suggest a tight unidentified subject.
            // This does not make a wide preset a verified safe-wide input.
            if input.identity == .unavailable && input.hasNomination { return .abstain(.evidenceUnavailable) }
            allowed = ladder.filter(\.isWide)
        }
        let values = allowed.compactMap { shot -> Candidate? in
            guard let score = input.presetScores[shot] else { return nil }
            return .init(channel: input.channel, shot: shot, subjectConfidence: score,
                         movement: input.movement, isWide: shot.isWide)
        }
        return values.isEmpty ? .abstain(.evidenceUnavailable) : .candidates(values)
    }

    /// All recommendations pass the same rule-allowed set through the judge gate.
    /// Preview-only preparation can precede minimum Program dwell; cutting cannot.
    static func assistPreparation(_ timeline: Timeline, program: ChannelID, preview: ChannelID?,
                                  inputs: [Input], previewIsSafeWide: Bool, tenure: PreviewTenure,
                                  preparationHistory: PreparationHistory, parameters p: AssistParameters,
                                  evidenceRevision: UInt64, judge: any DirectorJudge) -> AssistDecision {
        guard p.isValid, timeline.now.isFinite, timeline.now >= 0,
              timeline.programStartedAt.isFinite, timeline.programStartedAt >= 0,
              timeline.lastWideAt.isFinite, timeline.lastWideAt >= 0,
              timeline.now >= timeline.programStartedAt, timeline.now >= timeline.lastWideAt,
              timeline.history.allSatisfy({ $0.endedAt.isFinite && $0.endedAt >= 0 && $0.endedAt <= timeline.now }),
              zip(timeline.history, timeline.history.dropFirst()).allSatisfy({ pair in pair.0.endedAt <= pair.1.endedAt }),
              Set(inputs.map(\.channel)).count == inputs.count else { return .abstain(.invalidInput) }
        guard let preview, preview != program, inputs.contains(where: { $0.channel == program }),
              let input = inputs.first(where: { $0.channel == preview }) else { return .abstain(.noPreview) }
        guard preparationHistory.currentTenure == tenure, tenure.preview == preview, tenure.sourceGeneration == input.sourceGeneration else { return .abstain(.invalidInput) }
        guard input.sampledAt.isFinite, input.sampledAt >= 0, timeline.now >= input.sampledAt,
              timeline.now - input.sampledAt <= p.maximumSampleAge else { return .abstain(.evidenceUnavailable) }
        guard !previewIsSafeWide else { return .abstain(.previewIsSafeWide) }
        guard !p.onePreparationPerTenure || preparationHistory.preparedTenure != tenure else { return .abstain(.alreadyPrepared) }
        let values: [Candidate]
        switch candidates(for: input, parameters: p.policy, maximumObservationAge: p.maximumObservationAge, now: timeline.now) {
        case .abstain(let reason): return .abstain(reason)
        case .candidates(let built): values = built
        }
        // The caller's legacy timeline candidates cannot bypass evidence/ladder filtering.
        let evaluated = Timeline(programShot: timeline.programShot, programStartedAt: timeline.programStartedAt,
            lastWideAt: timeline.lastWideAt, history: timeline.history, candidates: values, now: timeline.now)
        let allowed = rank(evaluated, preview: preview, parameters: p.policy)
        if case .abstain(let reason) = allowed { return .abstain(.policy(reason)) }
        let context = DirectorJudgeContext(timeline: evaluated, preview: preview, parameters: p.policy,
            evidenceRevision: evidenceRevision, now: evaluated.now)
        let judgement = judge.judge(context)
        // The existing gate rejects future clocks; this boundary also rejects
        // a negative origin, even when the age difference looks valid.
        guard judgement.computedAt.isFinite, judgement.computedAt >= 0 else { return .abstain(.judgementStale) }
        switch DirectorJudgeGate.accept(judgement, allowed: allowed, evidenceRevision: evidenceRevision,
            now: evaluated.now, maximumAge: p.judgeMaximumAge, minimumProbability: p.minimumProbability) {
        case .accepted(let choice): return .chosen(choice)
        case .abstain(let reason): return .abstain(.judge(reason))
        case .stale: return .abstain(.judgementStale)
        }
    }
}

nonisolated extension DirectorShotPolicy.Input {
    init(sample: ChannelEvidenceSample, sourceGeneration: UInt64, format: DirectorShotPolicy.InputFormat,
         identity: IdentityEvidence, prepareReadiness: DirectorReadiness?, presetScores: [DirectorShot: Double]) {
        channel = sample.channel; self.sourceGeneration = sourceGeneration
        sampledAt = sample.sampledAt; observationAge = sample.observationAge
        hasNomination = sample.lockedTargetID != nil; self.format = format; self.identity = identity
        operatorGestureInProgress = sample.operatorGestureInProgress
        self.prepareReadiness = prepareReadiness; self.presetScores = presetScores; movement = sample.subjectSpeed
    }
}

nonisolated extension DirectorShotPolicy.AssistAbstention {
    func activity(input: ChannelID) -> NextShotStatus.DirectorSection.Activity {
        switch self {
        case .noPreview, .policy(.noPreview): .abstaining(.noPreview)
        case .previewIsSafeWide: .abstaining(.previewIsSafeWide)
        case .alreadyPrepared: .abstaining(.previewAlreadyPrepared)
        case .operatorAdjusting: .inhibited(.operatorAdjusting(input))
        case .learningSubject: .inhibited(.learningSubject(input))
        case .recoveringSubject: .inhibited(.recoveringSubject(input))
        case .evidenceUnavailable: .inhibited(.noFreshView(input))
        case .movement, .policy(.movement): .abstaining(.subjectMoving)
        case .notReady(let reasons):
            reasons.contains(.moving) ? .abstaining(.subjectMoving) : .inhibited(.noFreshView(input))
        case .policy(.repetition): .abstaining(.justUsed)
        case .policy(.minimumDuration): .abstaining(.holdingCurrentShot)
        case .policy(.noEligibleCandidate), .judge(.nothingAllowed): .abstaining(.nothingBetter)
        case .judge(.lowConfidence): .abstaining(.notSureEnough)
        case .invalidInput, .policy(.invalidInput), .judge, .judgementStale: .abstaining(.cannotDecide)
        }
    }
}
