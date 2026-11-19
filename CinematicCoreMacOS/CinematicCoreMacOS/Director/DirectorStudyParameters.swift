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
}
