import Foundation
import Testing
@testable import Alfie

/// A-06 (AI-1): a judge ranks or declines among rule-allowed shots; stale or
/// out-of-bounds judgements never reach preparation.
struct DirectorJudgeTests {
    private let program = DirectorShot(preset: .stage(.wide))
    private let parameters = DirectorShotPolicy.Parameters(minimumShotDuration: 8, maximumShotDuration: 35,
        wideCadence: 90, repetitionWindow: 20, maximumMovement: 0.1, cutOnMotionAllowed: false)

    private func candidate(_ preset: OperatorCommand.Preset, confidence: Double = 0.9,
                           channel: ChannelID = .b) -> DirectorShotPolicy.Candidate {
        .init(channel: channel, shot: DirectorShot(preset: preset), subjectConfidence: confidence,
              movement: 0, isWide: DirectorShot(preset: preset).isWide)
    }

    private func timeline(_ candidates: [DirectorShotPolicy.Candidate], now: TimeInterval = 10,
                          lastWide: TimeInterval = 0,
                          history: [DirectorShotPolicy.History] = []) -> DirectorShotPolicy.Timeline {
        .init(programShot: program, programStartedAt: 0, lastWideAt: lastWide, history: history,
              candidates: candidates, now: now)
    }

    private func context(_ timeline: DirectorShotPolicy.Timeline, revision: UInt64 = 1) -> DirectorJudgeContext {
        .init(timeline: timeline, preview: .b, parameters: parameters, evidenceRevision: revision, now: timeline.now)
    }

    // MARK: RuleJudge matches today's policy

    @Test func ruleJudgeTopMatchesChoosePreparationOnEveryFixture() {
        let full = candidate(.stage(.fullBody)), waist = candidate(.stage(.waistUp)),
            wide = candidate(.stage(.wide), confidence: 0.5)
        let fixtures: [DirectorShotPolicy.Timeline] = [
            timeline([full, waist]),
            timeline([waist, full], now: 100),
            timeline([full], history: [.init(shot: full.shot, endedAt: 5)]),
            timeline([candidate(.stage(.fullBody), channel: .a)]),
            timeline([], now: 10),
            timeline([full], now: .nan),
            timeline([candidate(.webcam(.tight)), candidate(.webcam(.wide))], now: 120, lastWide: 0),
            timeline([wide, waist], now: 50),
        ]
        for fixture in fixtures {
            let judgement = RuleJudge().judge(context(fixture))
            switch DirectorShotPolicy.choosePreparation(fixture, preview: .b, parameters: parameters) {
            case .chosen(let pick, let reason):
                #expect(judgement.top?.candidate == pick)
                #expect(judgement.top?.reason == reason)
                #expect(judgement.top?.probability == nil)
            case .abstain(let reason):
                #expect(judgement.outcome == .abstain(.policy(reason)))
            }
        }
    }

    // MARK: Staleness

    @Test func staleJudgementsAreRefused() {
        let fixture = timeline([candidate(.stage(.fullBody))])
        let judgement = RuleJudge().judge(context(fixture, revision: 4))
        let allowed = DirectorShotPolicy.rank(fixture, preview: .b, parameters: parameters)
        #expect(DirectorJudgeGate.accept(judgement, allowed: allowed, evidenceRevision: 5, now: 10, maximumAge: 1) == .stale)
        #expect(DirectorJudgeGate.accept(judgement, allowed: allowed, evidenceRevision: 4, now: 12, maximumAge: 1) == .stale)
        #expect(DirectorJudgeGate.accept(judgement, allowed: allowed, evidenceRevision: 4, now: 9, maximumAge: 1) == .stale)
        for age in [Double.nan, -1, .infinity] {
            #expect(DirectorJudgeGate.accept(judgement, allowed: allowed, evidenceRevision: 4, now: 10, maximumAge: age) == .stale)
        }
        guard case .accepted(let item) = DirectorJudgeGate.accept(judgement, allowed: allowed,
            evidenceRevision: 4, now: 10.5, maximumAge: 1) else { Issue.record("expected acceptance"); return }
        #expect(item.candidate.shot.preset == .stage(.fullBody))
    }

    // MARK: Rules dispose

    @Test func aJudgeCannotIntroduceAShotTheRulesDoNotAllow() {
        let fixture = timeline([candidate(.stage(.fullBody))])
        let allowed = DirectorShotPolicy.rank(fixture, preview: .b, parameters: parameters)
        // A learned judge "prefers" a Program-channel shot and a repeat: neither is allowed.
        let rogue = DirectorJudgement(outcome: .ranked([
            .init(candidate: candidate(.stage(.waistUp), channel: .a), probability: 0.99, reason: "model"),
            .init(candidate: candidate(.stage(.wide)), probability: 0.95, reason: "model")]),
            evidenceRevision: 1, computedAt: 10)
        #expect(DirectorJudgeGate.accept(rogue, allowed: allowed, evidenceRevision: 1, now: 10, maximumAge: 1)
                == .abstain(.nothingAllowed))
        let reordered = DirectorJudgement(outcome: .ranked([
            .init(candidate: candidate(.stage(.waistUp), channel: .a), probability: 0.99, reason: "model"),
            .init(candidate: candidate(.stage(.fullBody)), probability: 0.8, reason: "model")]),
            evidenceRevision: 1, computedAt: 10)
        guard case .accepted(let item) = DirectorJudgeGate.accept(reordered, allowed: allowed,
            evidenceRevision: 1, now: 10, maximumAge: 1) else { Issue.record("expected the allowed shot"); return }
        #expect(item.candidate.shot.preset == .stage(.fullBody) && item.probability == 0.8)
    }

    @Test func ruleAbstentionWinsOverAnyJudge() {
        let fixture = timeline([candidate(.stage(.fullBody))], now: .nan)
        let allowed = DirectorShotPolicy.rank(fixture, preview: .b, parameters: parameters)
        let eager = DirectorJudgement(outcome: .ranked([.init(candidate: candidate(.stage(.fullBody)),
            probability: 1, reason: "model")]), evidenceRevision: 1, computedAt: 10)
        #expect(DirectorJudgeGate.accept(eager, allowed: allowed, evidenceRevision: 1, now: 10, maximumAge: 1)
                == .abstain(.policy(.invalidInput)))
    }

    // MARK: Low confidence

    @Test func lowConfidenceAndInvalidProbabilitiesAbstain() {
        let fixture = timeline([candidate(.stage(.fullBody))])
        let allowed = DirectorShotPolicy.rank(fixture, preview: .b, parameters: parameters)
        func learned(_ p: Double) -> DirectorJudgement {
            .init(outcome: .ranked([.init(candidate: candidate(.stage(.fullBody)), probability: p, reason: "model")]),
                  evidenceRevision: 1, computedAt: 10)
        }
        #expect(DirectorJudgeGate.accept(learned(0.4), allowed: allowed, evidenceRevision: 1, now: 10,
            maximumAge: 1, minimumProbability: 0.6) == .abstain(.lowConfidence))
        for bad in [Double.nan, -0.1, 1.5] {
            #expect(DirectorJudgeGate.accept(learned(bad), allowed: allowed, evidenceRevision: 1, now: 10,
                maximumAge: 1, minimumProbability: 0.6) == .abstain(.invalidJudgement))
        }
        #expect(DirectorJudgeGate.accept(learned(0.7), allowed: allowed, evidenceRevision: 1, now: 10,
            maximumAge: 1, minimumProbability: .nan) == .abstain(.invalidJudgement))
        // Rules give no probability; asking for one fails closed rather than guessing.
        let rules = RuleJudge().judge(context(fixture))
        #expect(DirectorJudgeGate.accept(rules, allowed: allowed, evidenceRevision: 1, now: 10,
            maximumAge: 1, minimumProbability: 0.6) == .abstain(.invalidJudgement))
    }

    // MARK: Recorded judge

    @Test func recordedJudgeReplaysByEvidenceRevision() {
        let fixture = timeline([candidate(.stage(.fullBody))])
        let recorded = RuleJudge().judge(context(fixture, revision: 7)).outcome
        let judge = RecordedJudge(records: [7: recorded])
        #expect(judge.judge(context(fixture, revision: 7)).outcome == recorded)
        #expect(judge.judge(context(fixture, revision: 8)).outcome == .abstain(.notRecorded))
    }
}
