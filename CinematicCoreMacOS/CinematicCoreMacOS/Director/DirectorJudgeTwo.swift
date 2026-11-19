import CoreGraphics
import Foundation

/// Decision core, stage 7: the second rule judge. Two rules narrow the shots
/// the existing rules allow, then the existing rule judge ranks what is left.
/// It is a fixed order, not a weighted sum, so one rule always decides and
/// says which. It reads only the scene, and only ever removes options.
///
/// - People fit: a tight shot is not offered on an input whose newest scan
///   shows another person inside the subject's framed region, or whose view
///   is partial, old or unknown. The wide stays on offer.
/// - Segment fit: a panel or a performance offers only the wide; a video or
///   a break holds. A presenter needs a nominated subject, which the existing
///   rules already require for any tight shot. The segment never grants a cut.
nonisolated struct DirectorJudgeTwo: DirectorJudge {
    struct Parameters: Equatable, Sendable {
        /// Half the width of a tight shot's framed region, in subject widths.
        let peopleFitSpan: Double
        /// The oldest world-model scan people fit acts on.
        let peopleMaximumAge: TimeInterval
        var isValid: Bool {
            peopleFitSpan.isFinite && peopleFitSpan > 0 && peopleMaximumAge.isFinite && peopleMaximumAge >= 0
        }
    }
    enum Fit: Equatable, Sendable { case clear, crowded, unknown }

    let fits: [ChannelID: Fit]
    let segment: SegmentType

    init(fits: [ChannelID: Fit], segment: SegmentType) { self.fits = fits; self.segment = segment }

    init(scene: DirectorScene, parameters: Parameters) {
        self.init(fits: Dictionary(uniqueKeysWithValues: scene.inputs.map {
            ($0.channel, Self.peopleFit($0.people, now: scene.now, parameters: parameters))
        }), segment: scene.segmentType)
    }

    /// Whether a tight shot around the subject would hold only the subject.
    static func peopleFit(_ people: DirectorScene.People?, now: TimeInterval, parameters: Parameters) -> Fit {
        guard parameters.isValid, now.isFinite, let people, case .fullFrame = people.coverage,
              let observedAt = people.observedAt else { return .unknown }
        let age = now - observedAt
        guard age.isFinite, age >= 0, age <= parameters.peopleMaximumAge,
              let rank = people.subjectRank, people.positions.indices.contains(rank),
              let width = people.subjectWidth, width.isFinite, width > 0 else { return .unknown }
        let subject = Double(people.positions[rank]), reach = Double(width) * parameters.peopleFitSpan
        let crowded = people.positions.enumerated().contains { index, x in
            index != rank && abs(Double(x) - subject) <= reach
        }
        return crowded ? .crowded : .clear
    }

    func judgeWithAttribution(_ context: DirectorJudgeContext) -> DirectorJudgeEvaluation {
        .init(judgement: judge(context), attribution: .rules)
    }

    func judge(_ context: DirectorJudgeContext) -> DirectorJudgement {
        func abstain(_ reason: DirectorJudgement.Abstention) -> DirectorJudgement {
            .init(outcome: .abstain(reason), evidenceRevision: context.evidenceRevision, computedAt: context.now)
        }
        // Segment fit, first half: a video or a break holds.
        if segment == .videoBreak { return abstain(.segmentHolds) }
        let timeline = context.timeline
        var kept = timeline.candidates
        // People fit.
        let fitted = kept.filter { $0.isWide || fits[$0.channel] == .clear }
        if fitted.isEmpty, !kept.isEmpty {
            return abstain(kept.contains { fits[$0.channel] == .crowded } ? .peopleFit : .peopleUnknown)
        }
        kept = fitted
        // Segment fit, second half: a panel or a performance prefers the wide.
        if segment == .panel || segment == .performance {
            let wide = kept.filter(\.isWide)
            if wide.isEmpty, !kept.isEmpty { return abstain(.segmentPrefersWide) }
            kept = wide
        }
        // Then the existing rules, in their own order, on what is left.
        let narrowed = DirectorShotPolicy.Timeline(programShot: timeline.programShot,
            programStartedAt: timeline.programStartedAt, lastWideAt: timeline.lastWideAt,
            history: timeline.history, candidates: kept, now: timeline.now)
        return RuleJudge().judge(.init(timeline: narrowed, preview: context.preview, parameters: context.parameters,
                                       evidenceRevision: context.evidenceRevision, now: context.now))
    }
}
