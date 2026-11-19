import Foundation

/// Named sets of study parameters the app's Director runs with. Each set is a
/// value the shadow can name, so a record says which numbers produced it.
nonisolated struct DirectorStudyParameters: Sendable {
    let name: String
    let adapter: DirectorEvidenceAdapter.Parameters
    let readiness: DirectorReadiness.Parameters
    /// The shadow judge's own settings (decision core, stage 3).
    /// The oldest sample and judgement it acts on, in seconds.
    let maximumSampleAge: TimeInterval
    let judgeMaximumAge: TimeInterval
    /// nil: the rule judge gives no probability, so none is required.
    let minimumProbability: Double?
    let onePreparationPerTenure: Bool
    /// Decision core, stage 7: the second rule judge. nil runs the existing
    /// rule judge alone.
    var judgeTwo: DirectorJudgeTwo.Parameters? = nil

    /// The judge this set runs against one scene.
    func judge(for scene: DirectorScene) -> any DirectorJudge {
        judgeTwo.map { DirectorJudgeTwo(scene: scene, parameters: $0) } ?? RuleJudge()
    }

    /// Assist settings for this set under a segment's style.
    func assist(_ policy: DirectorShotPolicy.Parameters) -> DirectorShotPolicy.AssistParameters {
        .init(policy: policy, onePreparationPerTenure: onePreparationPerTenure, maximumSampleAge: maximumSampleAge,
              maximumObservationAge: adapter.maximumObservationAge, judgeMaximumAge: judgeMaximumAge,
              minimumProbability: minimumProbability)
    }

    /// PROVISIONAL (decision DC-6, 16 November 2026). Not measured on a rig.
    /// These switch the evidence adapter on for the shadow run only; they are
    /// to be replaced by values measured from real services.
    /// - adapter: the adapter tests' own fixture values
    ///   (`DirectorEvidenceAdapterTests`).
    /// - readiness: the replay study's values (`DirectorReplayTests.replayStudy`).
    /// - judge: samples and judgements are made on the same tick, so 0.5 s
    ///   (two ticks) is a margin, not a measured value.
    static let shadowV1 = DirectorStudyParameters(
        name: "shadowV1",
        adapter: .init(maximumObservationAge: 0.5, debounce: 0.5, stillSpeed: 0.05),
        readiness: .init(minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false,
                         minimumCutSettledTime: 0.2, maximumCutMotion: 0.1),
        maximumSampleAge: 0.5, judgeMaximumAge: 0.5, minimumProbability: nil, onePreparationPerTenure: true)

    /// shadowV1 with the second rule judge (stage 7). PROVISIONAL: the span
    /// is a guess at a waist-up shot's half-width in subject widths, and the
    /// age matches the typed commands' 0.5 s. Neither is measured. The app
    /// runs it only when `DeveloperFlags.judgeTwo` is on, which it is not;
    /// it replaces shadowV1 only if the shadow measures from real services
    /// do not get worse.
    static let shadowV2: DirectorStudyParameters = {
        var set = DirectorStudyParameters(name: "shadowV2", adapter: shadowV1.adapter, readiness: shadowV1.readiness,
            maximumSampleAge: shadowV1.maximumSampleAge, judgeMaximumAge: shadowV1.judgeMaximumAge,
            minimumProbability: shadowV1.minimumProbability, onePreparationPerTenure: shadowV1.onePreparationPerTenure)
        set.judgeTwo = .init(peopleFitSpan: 1.5, peopleMaximumAge: 0.5)
        return set
    }()
}
