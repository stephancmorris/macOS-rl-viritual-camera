import Foundation
import Testing
@testable import Alfie

nonisolated struct DirectorAssistPolicyTests {
    private typealias P = DirectorShotPolicy
    private let wide = DirectorShot(preset: .stage(.wide))
    private let full = DirectorShot(preset: .stage(.fullBody))
    private let tight = DirectorShot(preset: .stage(.waistUp))
    private func parameters(one: Bool = true) -> P.AssistParameters {
        .init(policy: .init(minimumShotDuration: 8, maximumShotDuration: 30,
            wideCadence: 60, repetitionWindow: 10, maximumMovement: 0.2, cutOnMotionAllowed: false),
            onePreparationPerTenure: one, maximumSampleAge: 3, maximumObservationAge: 2,
            judgeMaximumAge: 1, minimumProbability: nil)
    }
    private func tenure(preview: ChannelID = .b, route: UInt64 = 1) -> P.PreviewTenure {
        .init(id: UUID(), preview: preview, sourceGeneration: 1, routeGeneration: route)
    }
    private func input(channel: ChannelID = .b, identity: IdentityEvidence = .confirmed,
                       ready: DirectorReadiness? = .init(reasons: []), gesture: Bool = false,
                       sampledAt: Double = 9, age: Double? = 0, nominated: Bool = true,
                       movement: Double = 0, scores: [DirectorShot: Double]? = nil,
                       format: P.InputFormat = .stage) -> P.Input {
        .init(channel: channel, sourceGeneration: 1, sampledAt: sampledAt, observationAge: age,
            hasNomination: nominated, format: format, identity: identity,
            operatorGestureInProgress: gesture, prepareReadiness: ready,
            presetScores: scores ?? [wide: 0.2, full: 0.6, tight: 0.9], movement: movement)
    }
    private func timeline(now: Double = 10, history: [P.History] = []) -> P.Timeline {
        .init(programShot: full, programStartedAt: 8, lastWideAt: 8, history: history,
            candidates: [], now: now)
    }
    private func decide(_ i: P.Input, safe: Bool = false, one: Bool = true,
                        now: Double = 10, judge: any DirectorJudge = RuleJudge()) -> P.AssistDecision {
        let t = tenure()
        return P.assistPreparation(timeline(now: now), program: .a, preview: .b,
            inputs: [input(channel: .a), i], previewIsSafeWide: safe, tenure: t,
            preparationHistory: .init(tenure: t), parameters: parameters(one: one),
            evidenceRevision: 4, judge: judge)
    }
    @Test(arguments: ["confirmed", "acquiring", "holding", "lost", "ambiguous", "noNomination", "gesture", "unsettled", "moving", "stale", "noReadiness"])
    func everyEvidenceRowHasAnExplicitDecision(row: String) {
        let i: P.Input
        switch row {
        case "acquiring": i = input(identity: .acquiring)
        case "holding": i = input(identity: .holding)
        case "lost": i = input(identity: .lost)
        case "ambiguous": i = input(identity: .ambiguous)
        case "noNomination": i = input(identity: .unavailable, nominated: false)
        case "gesture": i = input(gesture: true)
        case "unsettled": i = input(ready: .init(reasons: [.framingUnsettled]))
        case "moving": i = input(movement: 0.3)
        case "stale": i = input(age: 3)
        case "noReadiness": i = input(ready: nil)
        default: i = input()
        }
        let result = decide(i)
        switch row {
        case "confirmed": guard case .chosen(let pick) = result else { Issue.record("expected prepared candidate"); return }; #expect(pick.candidate.shot == tight)
        case "lost", "ambiguous", "noNomination": guard case .chosen(let pick) = result else { Issue.record("expected wide suggestion"); return }; #expect(pick.candidate.shot == wide)
        case "acquiring": #expect(result == .abstain(.learningSubject))
        case "holding": #expect(result == .abstain(.recoveringSubject))
        case "gesture": #expect(result == .abstain(.operatorAdjusting))
        case "unsettled": #expect(result == .abstain(.notReady([.framingUnsettled])))
        case "moving": #expect(result == .abstain(.movement))
        default: #expect(result == .abstain(.evidenceUnavailable))
        }
    }
    @Test func candidatesComeFromEachInputsActualPresetLadder() {
        let webcam = DirectorShot(preset: .webcam(.tight)), webcamWide = DirectorShot(preset: .webcam(.wide))
        guard case .candidates(let stage) = P.candidates(for: input(), parameters: parameters().policy, maximumObservationAge: 2),
              case .candidates(let web) = P.candidates(for: input(scores: [webcam: 0.8, webcamWide: 0.2], format: .webcam), parameters: parameters().policy, maximumObservationAge: 2) else { Issue.record("expected ladders"); return }
        #expect(stage.map(\.shot) == [wide, full, tight] && web.map(\.shot) == [webcamWide, webcam])
        #expect(stage.allSatisfy { $0.channel == .b && $0.isWide == $0.shot.isWide })
        #expect(P.candidates(for: input(scores: [webcam: 0.8]), parameters: parameters().policy, maximumObservationAge: 2) == .abstain(.invalidInput))
        #expect(P.candidates(for: input(scores: [:]), parameters: parameters().policy, maximumObservationAge: 2) == .abstain(.evidenceUnavailable))
    }
    @Test func protectedWideAndMissingPreviewAlwaysAbstain() {
        #expect(decide(input(), safe: true) == .abstain(.previewIsSafeWide))
        let t = tenure()
        #expect(P.assistPreparation(timeline(), program: .a, preview: nil, inputs: [input(channel: .a)],
            previewIsSafeWide: false, tenure: t, preparationHistory: .init(tenure: t),
            parameters: parameters(), evidenceRevision: 4, judge: RuleJudge()) == .abstain(.noPreview))
        #expect(P.assistPreparation(timeline(), program: .b, preview: .b, inputs: [input()],
            previewIsSafeWide: false, tenure: t, preparationHistory: .init(tenure: t),
            parameters: parameters(), evidenceRevision: 4, judge: RuleJudge()) == .abstain(.noPreview))
    }
    private func receipt(_ t: P.PreviewTenure) throws -> DirectorPreparation.Receipt {
        let proposal = try #require(DirectorProposal(target: t.preview, preview: t.preview, shot: tight,
            reason: "synthetic", authorityEpoch: 2, revisions: .init(sourceGeneration: t.sourceGeneration, controlEpoch: 3, shotRevision: 4), routeGeneration: t.routeGeneration, createdAt: 9))
        return .init(requestID: UUID(), intent: proposal, postRevisions: .init(sourceGeneration: t.sourceGeneration, controlEpoch: 4, shotRevision: 5))
    }
    @Test func n4FlagOnlySuppressesACommittedPreparationInTheCurrentTenure() throws {
        let t = tenure(); var h = P.PreparationHistory(tenure: t)
        func choose(_ h: P.PreparationHistory, one: Bool) -> P.AssistDecision {
            P.assistPreparation(timeline(), program: .a, preview: .b, inputs: [input(channel: .a), input()],
                previewIsSafeWide: false, tenure: t, preparationHistory: h, parameters: parameters(one: one), evidenceRevision: 4, judge: RuleJudge())
        }
        guard case .chosen = choose(h, one: true) else { Issue.record("fresh tenure must choose"); return }
        #expect(h.preparedTenure == nil) // suggestions do not consume N4
        let r = try receipt(t)
        let first = h.recordCommittedPreparation(r, tenure: t)
        let duplicate = h.recordCommittedPreparation(r, tenure: t)
        #expect(first && !duplicate)
        #expect(choose(h, one: true) == .abstain(.alreadyPrepared))
        guard case .chosen = choose(h, one: false) else { Issue.record("disabled N4 flag must allow another recommendation"); return }
        let second = h.recordCommittedPreparation(try receipt(t), tenure: t)
        #expect(second)
        let next = tenure(route: 2); h.beginTenure(next)
        #expect(h.preparedTenure == nil)
        let old = h.recordCommittedPreparation(r, tenure: t)
        #expect(!old)
        #expect(h.currentTenure == next && h.preparedTenure == nil)
        let replacement = h.recordCommittedPreparation(try receipt(next), tenure: next)
        let stale = h.recordCommittedPreparation(r, tenure: t)
        #expect(replacement && !stale && h.preparedTenure == next)
    }
    private struct FixedJudge: DirectorJudge {
        let result: DirectorJudgement
        func judge(_ context: DirectorJudgeContext) -> DirectorJudgement { result }
    }
    @Test(arguments: ["program", "tightAmbiguity", "staleRevision", "future", "negative", "invalidProbability", "valid"])
    func judgeOutputCannotBypassRulesOrFreshness(fault: String) {
        let candidate = P.Candidate(channel: fault == "program" ? .a : .b,
            shot: tight, subjectConfidence: 0.9, movement: 0, isWide: false)
        let value = DirectorJudgement(outcome: .ranked([.init(candidate: candidate,
            probability: fault == "invalidProbability" ? .nan : nil, reason: "synthetic")]),
            evidenceRevision: fault == "staleRevision" ? 3 : 4,
            computedAt: fault == "future" ? 11 : fault == "negative" ? -1 : 10)
        let result = decide(input(identity: fault == "tightAmbiguity" ? .ambiguous : .confirmed), judge: FixedJudge(result: value))
        switch fault {
        case "program", "tightAmbiguity": #expect(result == .abstain(.judge(.nothingAllowed)))
        case "staleRevision", "future", "negative": #expect(result == .abstain(.judgementStale))
        case "invalidProbability": #expect(result == .abstain(.judge(.invalidJudgement)))
        default: guard case .chosen(let pick) = result else { Issue.record("rule-allowed item should pass"); return }; #expect(pick.candidate == candidate)
        }
    }
    @Test(arguments: [Double.nan, Double.infinity, -1, 11, 5])
    func badFutureAndExpiredSampleClocksFailClosed(time: Double) {
        #expect(decide(input(sampledAt: time)) == .abstain(.evidenceUnavailable))
    }
    @Test(arguments: [Double.nan, Double.infinity, -1])
    func invalidRankingNumbersFailClosed(value: Double) {
        #expect(decide(input(scores: [wide: value])) == .abstain(.invalidInput))
        #expect(decide(input(movement: value)) == .abstain(.invalidInput))
        #expect(decide(input(age: value)) == .abstain(.evidenceUnavailable))
        #expect(decide(input(), now: value) == .abstain(.invalidInput))
    }
    @Test func consoleReasonsUsePlainWordsAndNeverGrantAuthority() {
        #expect(P.AssistAbstention.alreadyPrepared.activity(input: .b).text == "Preview is prepared · keeping its shot")
        #expect(P.AssistAbstention.previewIsSafeWide.activity(input: .b).text == "Preview is the wide camera · nothing to prepare")
        #expect(P.AssistAbstention.learningSubject.activity(input: .b).text.contains("learning the subject"))
        #expect(P.AssistAbstention.judge(.lowConfidence).activity(input: .b) == .abstaining(.notSureEnough))
        let authority = DirectorAuthority(reviewPolicy: .conservative)
        #expect(!authority.mayPrepare && !authority.mayTake)
    }
    @Test(arguments: ["negativeHistory", "futureHistory", "reorderedHistory", "duplicateInput", "wrongTenure"])
    func invalidTimelineAndTenureBindingsFailClosed(fault: String) {
        let t = tenure()
        let history: [P.History] = fault == "negativeHistory" ? [.init(shot: wide, endedAt: -1)] :
            fault == "futureHistory" ? [.init(shot: wide, endedAt: 11)] :
            fault == "reorderedHistory" ? [.init(shot: wide, endedAt: 9), .init(shot: full, endedAt: 8)] : []
        let inputs = fault == "duplicateInput" ? [input(channel: .a), input(), input()] : [input(channel: .a), input()]
        let h = P.PreparationHistory(tenure: fault == "wrongTenure" ? tenure() : t)
        #expect(P.assistPreparation(timeline(history: history), program: .a, preview: .b, inputs: inputs,
            previewIsSafeWide: false, tenure: t, preparationHistory: h, parameters: parameters(),
            evidenceRevision: 4, judge: RuleJudge()) == .abstain(.invalidInput))
    }

    @Test(arguments: ["missing", "low", "boundary"])
    func suppliedProbabilityThresholdIsEnforced(fault: String) {
        let base = parameters(), t = tenure()
        let p = P.AssistParameters(policy: base.policy, onePreparationPerTenure: base.onePreparationPerTenure,
            maximumSampleAge: base.maximumSampleAge, maximumObservationAge: base.maximumObservationAge,
            judgeMaximumAge: base.judgeMaximumAge, minimumProbability: 0.8)
        let candidate = P.Candidate(channel: .b, shot: tight, subjectConfidence: 0.9, movement: 0, isWide: false)
        let judge = FixedJudge(result: .init(outcome: .ranked([.init(candidate: candidate,
            probability: fault == "missing" ? nil : fault == "low" ? 0.7 : 0.8, reason: "synthetic")]), evidenceRevision: 4, computedAt: 10))
        let result = P.assistPreparation(timeline(), program: .a, preview: .b, inputs: [input(channel: .a), input()],
            previewIsSafeWide: false, tenure: t, preparationHistory: .init(tenure: t), parameters: p,
            evidenceRevision: 4, judge: judge)
        switch fault {
        case "missing": #expect(result == .abstain(.judge(.invalidJudgement)))
        case "low": #expect(result == .abstain(.judge(.lowConfidence)))
        default: guard case .chosen = result else { Issue.record("probability boundary should pass"); return }
        }
    }

    @Test func malformedReceiptCannotConsumeTheTenure() throws {
        let t = tenure(); var h = P.PreparationHistory(tenure: t)
        let good = try receipt(t)
        let invalid = DirectorPreparation.Receipt(requestID: good.requestID, intent: good.intent,
            postRevisions: good.intent.revisions)
        let applied = h.recordCommittedPreparation(invalid, tenure: t)
        #expect(!applied && h.preparedTenure == nil)
        let valid = h.recordCommittedPreparation(good, tenure: t)
        #expect(valid && h.preparedTenure == t)
    }

    @Test func replayJudgeRefusalNeverReachesTheEffectSink() {
        let fixture = DirectorReplay.Fixture(name: "synthetic judge refusal", duration: 3, events: [
            .init(at: 1, action: .render(channel: .b)),
            .init(at: 1, action: .subject(channel: .b, present: true, identity: .confirmed,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 2, action: .directorAttempt(id: "refused", delay: 0, succeeds: true))])
        var sinkCalls = 0
        let judge = FixedJudge(result: .init(outcome: .abstain(.nothingAllowed), evidenceRevision: 1, computedAt: 1))
        let report = DirectorReplay.run(fixture, parameters: .policyStudy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy,
            sinkFactory: { outcome in sinkCalls += 1; return SimulatedDirectorEffectSink(succeeds: outcome) }, judge: judge)
        #expect(report.proposalCount == 0 && report.preparationsCommitted == 0 && sinkCalls == 0)
        #expect(report.directorCuts == 0 && report.evidence == .synthetic)
    }

}
