import Foundation

/// Decision core, stage 3: runs the existing rules against one `DirectorScene`
/// and returns what they would do. Values only. It holds no reference to the
/// show, sends no command, prepares nothing and never Takes; the controller
/// records the outcome in the shadow.
///
/// - Prepare: the Assist rules (`DirectorShotPolicy.assistPreparation`) for
///   the shot to set up on Preview. Every allowed preset scores 1, because the
///   composer never refuses a preset; it widens to the quality floor instead.
/// - Cut: the cut rules without authority (`CutPolicy.editorialDecision`) for
///   Preview as it stands now.
nonisolated struct DirectorDecisionCore: Sendable {
    struct Outcome: Equatable, Sendable {
        let prepare: DirectorShotPolicy.AssistDecision
        /// nil when there is no Preview to cut to.
        let cut: CutPolicy.Decision?
        /// The rule judge's view of the cut, when the cut rules asked it.
        var cutJudgeObservation: CutPolicy.JudgeObservation? = nil

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.prepare == rhs.prepare && lhs.cut == rhs.cut }
    }

    /// The Preview tenure. A tenure begins when Preview or its source changes.
    private(set) var tenure: DirectorShotPolicy.PreviewTenure?
    private var preparationHistory: DirectorShotPolicy.PreparationHistory?
    /// Owned only to give a would-prepare record its proposal and request.
    /// It is never committed: the shadow prepares nothing.
    private var shadowPreparation = DirectorPreparation()

    init() {}

    mutating func evaluate(_ scene: DirectorScene, live: DirectorTakeState,
                           parameters: DirectorStudyParameters, judge: any DirectorJudge) -> Outcome {
        let previewInput = scene.preview.flatMap { scene.input($0) }
        guard let style = scene.style, (try? style.validated()) != nil, let programShot = scene.programShot else {
            return .init(prepare: .abstain(.invalidInput), cut: previewInput == nil ? nil : .abstain(.invalidInput))
        }
        let policy = DirectorShotPolicy.Parameters(style)
        let timeline = DirectorShotPolicy.Timeline(programShot: programShot, programStartedAt: scene.programStartedAt,
            lastWideAt: scene.lastWideAt, history: scene.history, candidates: [], now: scene.now)

        let prepare: DirectorShotPolicy.AssistDecision
        if let preview = scene.preview, let previewInput {
            if tenure?.preview != preview || tenure?.sourceGeneration != previewInput.sourceGeneration {
                let next = DirectorShotPolicy.PreviewTenure(id: UUID(), preview: preview,
                    sourceGeneration: previewInput.sourceGeneration, routeGeneration: scene.routeGeneration)
                tenure = next
                preparationHistory = .init(tenure: next)
            }
            if let tenure, let preparationHistory {
                prepare = DirectorShotPolicy.assistPreparation(timeline, program: scene.program, preview: preview,
                    inputs: Self.shotInputs(scene, readiness: parameters.readiness), previewIsSafeWide: false,
                    tenure: tenure, preparationHistory: preparationHistory, parameters: parameters.assist(policy),
                    evidenceRevision: scene.evidenceRevision, judge: judge)
            } else { prepare = .abstain(.noPreview) }
        } else {
            prepare = .abstain(.noPreview)
        }

        guard let previewInput else { return .init(prepare: prepare, cut: nil) }
        let prepared = Self.prepared(previewInput)
        let cutTimeline = DirectorShotPolicy.Timeline(programShot: programShot, programStartedAt: scene.programStartedAt,
            lastWideAt: scene.lastWideAt, history: scene.history, candidates: [prepared], now: scene.now)
        var observation: CutPolicy.JudgeObservation?
        let cut = CutPolicy.editorialDecision(live: live, timeline: cutTimeline, prepared: prepared,
            programIdentity: scene.input(scene.program)?.state?.identity ?? .unavailable,
            style: style, evidenceRevision: scene.evidenceRevision, judge: judge,
            judgeMaximumAge: parameters.judgeMaximumAge, minimumProbability: parameters.minimumProbability,
            observeJudge: { observation = $0 })
        return .init(prepare: prepare, cut: cut, cutJudgeObservation: observation)
    }

    /// The proposal and request a would-prepare record carries. The request is
    /// never committed and grants nothing.
    mutating func shadowRequest(for chosen: DirectorJudgement.Ranked, scene: DirectorScene, authorityEpoch: UInt64,
                                policyRevision: UInt64, nominationRevision: UInt64) -> DirectorPreparation.Request? {
        guard let preview = scene.preview, let input = scene.input(preview),
              let proposal = DirectorProposal(target: chosen.candidate.channel, preview: preview,
                shot: chosen.candidate.shot, reason: chosen.reason, authorityEpoch: authorityEpoch,
                revisions: input.revisions, routeGeneration: scene.routeGeneration, createdAt: scene.now,
                policyRevision: policyRevision, nominationRevision: nominationRevision) else { return nil }
        let request = shadowPreparation.propose(proposal, maximumAge: 0, now: scene.now)
        shadowPreparation.retire()
        return request
    }

    // MARK: Inputs, as the existing rules take them

    /// One Assist input per scene input. Preview's prepare readiness comes from
    /// the adapter's state and Preview's Take availability; other inputs have none.
    static func shotInputs(_ scene: DirectorScene, readiness: DirectorReadiness.Parameters) -> [DirectorShotPolicy.Input] {
        scene.inputs.map { input in
            .init(sample: input.sample, sourceGeneration: input.sourceGeneration, format: input.format,
                  identity: input.state?.identity ?? .unavailable,
                  prepareReadiness: input.channel == scene.preview
                    ? prepareReadiness(input, take: scene.previewTake, readiness: readiness) : nil,
                  presetScores: Dictionary(uniqueKeysWithValues: input.format.ladder.map { ($0, 1.0) }))
        }
    }

    static func prepareReadiness(_ input: DirectorScene.Input, take: TakeAvailability?,
                                 readiness: DirectorReadiness.Parameters) -> DirectorReadiness? {
        guard let state = input.state, let take else { return nil }
        return DirectorReadiness.evaluate(.init(take: take, identity: state.identity,
            framingSettledFor: input.settledFor, motion: state.subjectSpeed, cropConverged: state.cropConverged),
            parameters: readiness, bar: .prepare)
    }

    /// Preview as it stands now is the shot a cut would go to.
    static func prepared(_ input: DirectorScene.Input) -> DirectorShotPolicy.Candidate {
        .init(channel: input.channel, shot: input.shot,
              subjectConfidence: input.state?.identity == .confirmed ? 1 : 0,
              movement: input.sample.subjectSpeed, isWide: input.shot.isWide)
    }
}
