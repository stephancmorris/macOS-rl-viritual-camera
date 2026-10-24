import Foundation
import Testing
@testable import Alfie

/// Synthetic observations only; these fixtures confer no operating qualification.
nonisolated struct DirectorCutJudgementCaptureTests {
    private typealias P = DirectorShotPolicy
    private let wide = DirectorShot(preset: .stage(.wide))
    private let tight = DirectorShot(preset: .stage(.waistUp))

    private final class CountingJudge: DirectorJudge, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        let value: DirectorJudgement
        init(_ value: DirectorJudgement) { self.value = value }
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
        func judge(_ context: DirectorJudgeContext) -> DirectorJudgement {
            lock.lock(); count += 1; lock.unlock()
            return value
        }
    }
    private final class CountingModel: DirectorScoringModel, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        let featureSchemaVersion = DirectorJudgeFeatures.schemaVersion
        let modelVersion: String
        let fails: Bool
        init(version: String = "trial-v1", fails: Bool = false) {
            modelVersion = version; self.fails = fails
        }
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
        func probability(for features: DirectorJudgeFeatures) throws -> Double {
            lock.lock(); count += 1; lock.unlock()
            if fails { throw DirectorScoringModelError.invalidOutput }
            return 0.9
        }
    }
    private func style() -> DirectorStyle {
        .init(minimumShotDuration: 5, preferredShotDuration: 10, softMaximumShotDuration: 30,
              wideCadence: 20, repetitionWindow: 4, maximumMovement: 0.2,
              settleTime: 1, onAirMoveRate: 0.1, cutOnMotionAllowed: false)
    }
    private func candidate(channel: ChannelID = .b) -> P.Candidate {
        .init(channel: channel, shot: tight, subjectConfidence: 0.9, movement: 0, isWide: false)
    }
    private func state(ready: Bool = true) -> DirectorTakeState {
        let prerequisites = DirectorAuthority.Prerequisites(nominationsCurrent: true, previewAvailable: true,
            sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.auto])
        var authority = DirectorAuthority()
        authority.apply(.enable(.auto), prerequisites: prerequisites)
        return .init(world: .init(authority: authority, program: .a, preview: .b,
            revisions: .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3), routeGeneration: 1,
            sourceMissing: false, policyRevision: 1, nominationRevision: 1, evidenceAvailable: true),
            prerequisites: prerequisites, cutReadiness: .init(reasons: ready ? [] : [.identityUncertain]),
            operatorGestureInProgress: false)
    }
    private func timeline(now: Double = 10) -> P.Timeline {
        .init(programShot: wide, programStartedAt: 0, lastWideAt: 0,
              history: [], candidates: [candidate(channel: .a), candidate()], now: now)
    }
    private func evaluate(_ judge: any DirectorJudge, now: Double = 10, ready: Bool = true,
                          maximumAge: Double = 1, probability: Double? = nil,
                          observe: ((CutPolicy.JudgeObservation) -> Void)? = nil) -> CutPolicy.Decision {
        CutPolicy.evaluate(live: state(ready: ready), timeline: timeline(now: now), prepared: candidate(),
            programIdentity: .confirmed, style: style(), evidenceRevision: 7, judge: judge,
            judgeMaximumAge: maximumAge, minimumProbability: probability, observeJudge: observe)
    }
    private func judgement(probability: Double? = 0.9, revision: UInt64 = 7,
                           computedAt: Double = 9.75) -> DirectorJudgement {
        .init(outcome: .ranked([
            .init(candidate: candidate(channel: .a), probability: 0.99, reason: "synthetic first"),
            .init(candidate: candidate(), probability: probability, reason: "synthetic second")
        ]), evidenceRevision: revision, computedAt: computedAt)
    }

    @Test func arbitraryJudgeRunsOnceAndPreservesExactCallAndOriginalRank() throws {
        let raw = judgement(), plain = CountingJudge(raw), observed = CountingJudge(raw)
        let baseline = evaluate(plain)
        var snapshot: CutPolicy.JudgeObservation?
        let result = evaluate(observed) { snapshot = $0 }
        let captured = try #require(snapshot)
        #expect(plain.calls == 1 && observed.calls == 1 && result == baseline)
        guard case .cut = result else { Issue.record("Expected eligible prepared shot"); return }
        #expect(captured.judgement == raw && captured.attribution == nil)
        #expect(captured.context.timeline.candidates == [candidate()])
        #expect(captured.context.timeline.history == timeline().history)
        #expect(captured.context.timeline.programShot == wide)
        #expect(captured.context.timeline.programStartedAt == 0 && captured.context.timeline.lastWideAt == 0)
        #expect(captured.context.parameters == .init(style()))
        #expect(captured.context.preview == .b && captured.context.evidenceRevision == 7)
        #expect(captured.context.now == 10 && captured.context.timeline.now == 10)
        guard case .ranked(let ranked) = raw.outcome else {
            Issue.record("Expected ranked fixture"); return
        }
        #expect(captured.gate == .accepted(ranked[1]))
    }

    @Test(arguments: ["minimumDwell", "nothingBetter", "notReady", "invalidInput"])
    func preJudgeRefusalsHaveNoInvocationOrObservation(_ refusal: String) {
        let judge = CountingJudge(judgement())
        var snapshot: CutPolicy.JudgeObservation?
        let now: Double = refusal == "minimumDwell" ? 4 : (refusal == "nothingBetter" ? 6 : 10)
        let result = evaluate(judge, now: now, ready: refusal != "notReady",
            maximumAge: refusal == "invalidInput" ? -1 : 1) { snapshot = $0 }
        let expected: CutPolicy.Abstention
        switch refusal {
        case "minimumDwell": expected = .minimumDwell
        case "nothingBetter": expected = .nothingBetter
        case "notReady": expected = .notReady
        default: expected = .invalidInput
        }
        #expect(result == .abstain(expected) && judge.calls == 0 && snapshot == nil)
    }

    @Test(arguments: ["revision", "age", "probability", "missingProbability", "negativeTime", "nonfiniteTime"])
    func refusedJudgementsKeepTheirActualGateAndDecision(_ refusal: String) throws {
        let raw = judgement(probability: refusal == "missingProbability" ? nil : (refusal == "probability" ? 0.2 : 0.9),
            revision: refusal == "revision" ? 6 : 7,
            computedAt: refusal == "age" ? 8 : (refusal == "negativeTime" ? -1 : (refusal == "nonfiniteTime" ? .nan : 9.75)))
        let observed = CountingJudge(raw), plain = CountingJudge(raw)
        var snapshot: CutPolicy.JudgeObservation?
        let result = evaluate(observed, probability: 0.8) { snapshot = $0 }
        #expect(result == evaluate(plain, probability: 0.8) && result == .abstain(.judge))
        #expect(observed.calls == 1 && plain.calls == 1)
        let captured = try #require(snapshot)
        #expect(captured.attribution == nil && captured.judgement.evidenceRevision == raw.evidenceRevision)
        #expect(captured.judgement.outcome == raw.outcome)
        switch refusal {
        case "revision", "age": #expect(captured.gate == .stale)
        case "probability": #expect(captured.gate == .abstain(.lowConfidence))
        case "missingProbability": #expect(captured.gate == .abstain(.invalidJudgement))
        case "negativeTime": #expect(captured.gate == nil && captured.judgement.computedAt == -1)
        default: #expect(captured.gate == nil && captured.judgement.computedAt.isNaN)
        }
    }

    @Test func builtInRulesAndRecordedJudgesSupplyExplicitIdentity() throws {
        var rules: CutPolicy.JudgeObservation?, recorded: CutPolicy.JudgeObservation?
        _ = evaluate(RuleJudge()) { rules = $0 }
        _ = evaluate(RecordedJudge(records: [7: judgement().outcome])) { recorded = $0 }
        #expect(try #require(rules).attribution == .rules)
        #expect(try #require(recorded).attribution == .recorded)
    }

    @Test(arguments: ["learned", "predictionFallback", "invalidModelFallback", "missingModelFallback"])
    func learnedJudgeReportsActualSingleEvaluationSource(_ source: String) throws {
        let version = source == "invalidModelFallback" ? "/Users/private/model" : "trial-v1"
        let observedModel = CountingModel(version: version, fails: source == "predictionFallback")
        let plainModel = CountingModel(version: version, fails: source == "predictionFallback")
        let missing = source == "missingModelFallback"
        let observed = LearnedJudge(model: missing ? nil : observedModel, minimumProbability: 0.8)
        let plain = LearnedJudge(model: missing ? nil : plainModel, minimumProbability: 0.8)
        var snapshot: CutPolicy.JudgeObservation?
        let result = evaluate(observed) { snapshot = $0 }
        #expect(result == evaluate(plain))
        let captured = try #require(snapshot)
        #expect(captured.attribution == (source == "learned" ? .learned(modelVersion: "trial-v1") : .rules))
        let calls = source == "learned" || source == "predictionFallback" ? 1 : 0
        #expect(observedModel.calls == calls && plainModel.calls == calls)
        if source != "learned" { #expect(captured.judgement.top?.probability == nil) }
    }

    @Test func invalidLearnedEvaluationDoesNotAcquireAnIdentity() throws {
        var snapshot: CutPolicy.JudgeObservation?
        let result = evaluate(LearnedJudge(model: nil, minimumProbability: -1)) { snapshot = $0 }
        let captured = try #require(snapshot)
        #expect(result == .abstain(.judge) && captured.attribution == nil)
        #expect(captured.judgement.outcome == .abstain(.invalidJudgement))
    }
}
