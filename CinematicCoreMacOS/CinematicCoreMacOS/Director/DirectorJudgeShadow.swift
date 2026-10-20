import Foundation

/// Explicit A-16 shadow trial. The producer supplies actual timeline/history;
/// this layer never manufactures missing evidence or sends camera commands.
final class DirectorJudgeShadow {
    struct Configuration {
        let judge: LearnedJudge
        let maximumAge: TimeInterval
        var isValid: Bool { maximumAge.isFinite && maximumAge >= 0 &&
            judge.minimumProbability.isFinite && (0...1).contains(judge.minimumProbability) }
    }
    struct Sample {
        let context: DirectorJudgeContext
        /// Every contributing timeline/history/candidate input, not model training.
        let provenance: [DirectorShadowRecord.EvidenceClass]
    }
    typealias ContextProvider = (_ now: TimeInterval, _ evidenceRevision: UInt64) -> Sample?
    struct Observation {
        let context: DirectorJudgeContext
        let provenance: [DirectorShadowRecord.EvidenceClass]
        let evaluation: LearnedJudge.Evaluation
        let style: DirectorStyle
        let parametersVersion: UInt64
        let maximumAge: TimeInterval
        let minimumProbability: Double
    }
    private struct Binding: Equatable {
        let program: ChannelID
        let preview: ChannelID
        let programRevisions: ChannelRevisions
        let previewRevisions: ChannelRevisions
        let route: UInt64
    }
    private var configuration: Configuration?
    private var provider: ContextProvider?

    func configure(_ configuration: Configuration?, context: ContextProvider?) {
        self.configuration = configuration?.isValid == true ? configuration : nil
        self.provider = context
    }

    func observe(show: ShowCoordinator, now: TimeInterval, evidenceRevision: UInt64,
                 style: DirectorStyle?, policyRevision: UInt64) -> Observation? {
        #if DEBUG
        guard DeveloperFlags.runDirectorShadow, let configuration, let provider, let style,
              (try? style.validated()) != nil, now.isFinite, now >= 0,
              let preview = show.previewChannel, let program = show.channel(show.programChannel),
              let offAir = show.channel(preview), program.isRunning, offAir.isRunning,
              !program.sourceMissing, !offAir.sourceMissing else { return nil }
        let before = Binding(program: show.programChannel, preview: preview,
            programRevisions: program.revisions, previewRevisions: offAir.revisions, route: show.router.routeGeneration)
        guard let sample = provider(now, evidenceRevision), !sample.provenance.isEmpty,
              sample.provenance.allSatisfy({ $0 == sample.provenance.first }),
              sample.context.preview == preview else { return nil }
        let context = sample.context
        guard
              context.evidenceRevision == evidenceRevision, context.now == now,
              context.timeline.programShot == program.directorShot,
              context.parameters == .init(style), DirectorJudgeFeatures.validContext(context) else { return nil }
        let evaluation = configuration.judge.evaluate(context)
        guard evaluation.source != .invalid else { return nil }
        let finished = show.clock()
        let after = Binding(program: show.programChannel, preview: show.previewChannel ?? show.programChannel,
            programRevisions: program.revisions, previewRevisions: offAir.revisions, route: show.router.routeGeneration)
        guard before == after, program.isRunning, offAir.isRunning, !program.sourceMissing, !offAir.sourceMissing,
              evaluation.judgement.isCurrent(evidenceRevision: evidenceRevision, now: finished,
                                             maximumAge: configuration.maximumAge) else { return nil }
        return .init(context: context, provenance: sample.provenance, evaluation: evaluation, style: style, parametersVersion: policyRevision,
                     maximumAge: configuration.maximumAge, minimumProbability: configuration.judge.minimumProbability)
        #else
        return nil
        #endif
    }
}
