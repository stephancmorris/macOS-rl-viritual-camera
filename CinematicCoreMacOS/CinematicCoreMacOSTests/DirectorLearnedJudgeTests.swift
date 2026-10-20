import Foundation
import Testing
@preconcurrency import CoreML
@testable import Alfie

/// Synthetic software evidence only. Scores in these fixtures are authored,
/// never trained, calibrated or a permission to run an autonomous level.
struct DirectorLearnedJudgeTests {
    private let parameters = DirectorShotPolicy.Parameters(minimumShotDuration: 8, maximumShotDuration: 35,
        wideCadence: 90, repetitionWindow: 20, maximumMovement: 0.1, cutOnMotionAllowed: false)

    private struct FixedModel: DirectorScoringModel {
        var featureSchemaVersion: Int = 1
        var modelVersion: String = "synthetic-1"
        let score: Double
        func probability(for features: DirectorJudgeFeatures) throws -> Double { score }
    }
    private struct ClosureModel: DirectorScoringModel {
        let featureSchemaVersion = 1
        let modelVersion = "synthetic-closure-1"
        let predict: @Sendable (DirectorJudgeFeatures) throws -> Double
        func probability(for features: DirectorJudgeFeatures) throws -> Double { try predict(features) }
    }
    private enum SyntheticError: Error { case refused }

    private func candidate(_ preset: OperatorCommand.Preset, channel: ChannelID = .b,
                           confidence: Double = 0.9, movement: Double = 0) -> DirectorShotPolicy.Candidate {
        let shot = DirectorShot(preset: preset)
        return .init(channel: channel, shot: shot, subjectConfidence: confidence,
                     movement: movement, isWide: shot.isWide)
    }
    private func context(_ candidates: [DirectorShotPolicy.Candidate]? = nil, now: Double = 10,
                         startedAt: Double = 0, lastWideAt: Double = 0,
                         history: [DirectorShotPolicy.History] = [], computedAt: Double? = nil) -> DirectorJudgeContext {
        .init(timeline: .init(programShot: .init(preset: .stage(.wide)), programStartedAt: startedAt,
            lastWideAt: lastWideAt, history: history,
            candidates: candidates ?? [candidate(.stage(.fullBody)), candidate(.stage(.waistUp))], now: now),
            preview: .b, parameters: parameters, evidenceRevision: 7, now: computedAt ?? now)
    }

    @Test func missingAndUnloadableModelReturnExactRules() {
        let c = context()
        let expected = RuleJudge().judge(c)
        let missing = LearnedJudge(model: nil, minimumProbability: 0.8).evaluate(c)
        #expect(missing.judgement == expected && missing.rules == expected)
        #expect(missing.source == .rules && missing.fallbackReason == .modelMissing && missing.modelVersion == nil)
        let unavailable = LearnedJudge.coreML(compiledModelURL: URL(fileURLWithPath: "/missing-director.mlmodelc"),
                                              minimumProbability: 0.8).evaluate(c)
        #expect(unavailable.judgement == expected && unavailable.fallbackReason == .modelLoadFailed)
    }

    @Test(arguments: [-0.1, 1.1, Double.nan, Double.infinity])
    func invalidThresholdAbstainsEvenWithoutModel(_ threshold: Double) {
        let evaluation = LearnedJudge(model: nil, minimumProbability: threshold).evaluate(context())
        #expect(evaluation.source == .invalid && evaluation.fallbackReason == nil)
        #expect(evaluation.judgement.outcome == .abstain(.invalidJudgement))
    }

    @Test func thresholdIsInclusiveAndLowConfidenceNeverFallsBack() {
        let accepted = LearnedJudge(model: FixedModel(score: 0.75), minimumProbability: 0.75).evaluate(context())
        #expect(accepted.source == .learned && accepted.judgement.top?.probability == 0.75)
        let declined = LearnedJudge(model: FixedModel(score: 0.74), minimumProbability: 0.75).evaluate(context())
        #expect(declined.source == .learned && declined.modelVersion == "synthetic-1")
        #expect(declined.judgement.outcome == .abstain(.lowConfidence) && declined.fallbackReason == nil)
    }

    @Test func ranksOnlyRuleEligibleCandidatesAndPreservesBindings() {
        let full = candidate(.stage(.fullBody)), waist = candidate(.stage(.waistUp))
        let c = context([candidate(.stage(.wide)), candidate(.webcam(.tight), channel: .a), full, waist])
        let model = ClosureModel { $0.values[8] == 1 ? 0.95 : 0.4 }
        let result = LearnedJudge(model: model, minimumProbability: 0.7).evaluate(c)
        #expect(result.judgement.top?.candidate == waist)
        guard case .ranked(let items) = result.judgement.outcome else { Issue.record("Expected ranking"); return }
        #expect(items.map(\.candidate) == [waist, full])
        #expect(result.judgement.evidenceRevision == 7 && result.judgement.computedAt == 10)
        #expect(result.rules == RuleJudge().judge(c))
        let allowed = DirectorShotPolicy.rank(c.timeline, preview: c.preview, parameters: c.parameters)
        #expect(DirectorJudgeGate.accept(result.judgement, allowed: allowed,
            evidenceRevision: 8, now: 10, maximumAge: 1) == .stale)
    }

    @Test func equalScoresKeepDeterministicRuleOrderAcrossInputPermutations() {
        let full = candidate(.stage(.fullBody)), waist = candidate(.stage(.waistUp))
        let judge = LearnedJudge(model: FixedModel(score: 0.8), minimumProbability: 0.7)
        let a = judge.judge(context([full, waist])), b = judge.judge(context([waist, full]))
        #expect(a == b && a.top?.candidate == full)
    }

    @Test(arguments: [-0.1, 1.1, Double.nan, Double.infinity])
    func malformedProbabilityFallsBackWholeEvaluation(_ score: Double) {
        let c = context()
        let result = LearnedJudge(model: FixedModel(score: score), minimumProbability: 0.7).evaluate(c)
        #expect(result.judgement == RuleJudge().judge(c))
        #expect(result.source == .rules && result.fallbackReason == .invalidModelOutput)
    }

    @Test func predictionFailureDiscardsPreviouslyScoredCandidate() {
        let c = context()
        let model = ClosureModel {
            if $0.values[8] == 1 { throw SyntheticError.refused }
            return 0.99
        }
        let result = LearnedJudge(model: model, minimumProbability: 0.7).evaluate(c)
        #expect(result.judgement == RuleJudge().judge(c) && result.fallbackReason == .predictionFailed)
        #expect(result.modelVersion == "synthetic-closure-1")
    }

    @Test func incompatibleBackendAndVersionFallBack() {
        let c = context()
        for model in [FixedModel(featureSchemaVersion: 2, score: 0.9),
                      FixedModel(modelVersion: "private/path", score: 0.9),
                      FixedModel(modelVersion: "synthetic\n", score: 0.9),
                      FixedModel(modelVersion: "", score: 0.9)] {
            let result = LearnedJudge(model: model, minimumProbability: 0.7).evaluate(c)
            #expect(result.judgement == RuleJudge().judge(c) && result.fallbackReason == .invalidModel)
        }
    }

    @Test func ruleAbstentionDoesNotCallModel() {
        let model = ClosureModel { _ in Issue.record("No candidate may reach model"); throw SyntheticError.refused }
        let c = context([])
        let result = LearnedJudge(model: model, minimumProbability: 0.7).evaluate(c)
        #expect(result.judgement == RuleJudge().judge(c) && result.source == .rules && result.fallbackReason == nil)
    }

    @Test func featureContractIsExactAndContainsOnlyAvailableMetadata() throws {
        let c = context(now: 50, startedAt: 2, lastWideAt: 3,
            history: [.init(shot: .init(preset: .stage(.fullBody)), endedAt: 5)])
        let features = try #require(DirectorJudgeFeatures.extract(candidate(.stage(.fullBody), confidence: 0.75, movement: 0.1), context: c))
        #expect(features.values == [0.75, 0.1, 48, 47, 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0])
        #expect(DirectorJudgeFeatures.names.count == 16)
        let webcam = try #require(DirectorJudgeFeatures.extract(candidate(.webcam(.tight)), context: context()))
        #expect(Array(webcam.values[6...10]) == [0, 0, 0, 0, 1])
    }

    @Test func invalidClocksHistoryAndFloat32OverflowFailClosed() {
        let bad: [DirectorJudgeContext] = [context(now: -1), context(computedAt: 11),
            context(history: [.init(shot: .init(preset: .stage(.fullBody)), endedAt: 11)]),
            context(history: [.init(shot: .init(preset: .stage(.fullBody)), endedAt: 2),
                              .init(shot: .init(preset: .stage(.waistUp)), endedAt: 1)]),
            context(now: Double(Float.greatestFiniteMagnitude) * 2),
            context([candidate(.stage(.fullBody), movement: Double(Float.greatestFiniteMagnitude) * 2)])]
        for c in bad {
            let result = LearnedJudge(model: nil, minimumProbability: 0.7).evaluate(c)
            #expect(result.source == .invalid && result.judgement.outcome == .abstain(.invalidJudgement))
        }
    }

    @Test func fabricatedWideFlagIsRejected() {
        let value = DirectorShotPolicy.Candidate(channel: .b, shot: .init(preset: .stage(.fullBody)),
                                                 subjectConfidence: 0.9, movement: 0, isWide: true)
        #expect(LearnedJudge(model: FixedModel(score: 0.9), minimumProbability: 0.7)
            .judge(context([value])).outcome == .abstain(.invalidJudgement))
    }

    @Test func missingModelFallbackNeedsRulesCompatibleOuterGate() throws {
        let c = context()
        let result = LearnedJudge(model: nil, minimumProbability: 0.7).judge(c)
        let top = try #require(result.top)
        let allowed = DirectorShotPolicy.rank(c.timeline, preview: c.preview, parameters: c.parameters)
        #expect(DirectorJudgeGate.accept(result, allowed: allowed, evidenceRevision: 7,
                                        now: 10, maximumAge: 1) == .accepted(top))
        #expect(DirectorJudgeGate.accept(result, allowed: allowed, evidenceRevision: 7,
            now: 10, maximumAge: 1, minimumProbability: 0.7) == .abstain(.invalidJudgement))
    }

    @Test func actualCoreMLFixtureRepeatsAndEnforcesSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic.mlmodel")
        try DirectorScorerCoreMLFixture.model().write(to: source)
        let compiled = try MLModel.compileModel(at: source)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let model = try CoreMLDirectorScoringModel(compiledModelURL: compiled)
        let judge = LearnedJudge(model: model, minimumProbability: 0.7)
        let first = judge.evaluate(context())
        #expect(first.source == .learned && first.modelVersion == "synthetic-coreml-1")
        #expect(first.judgement.top?.probability == 0.75)
        for _ in 0..<4 { #expect(judge.evaluate(context()) == first) }

        try DirectorScorerCoreMLFixture.model(schemaVersion: "2").write(to: source)
        let incompatible = try MLModel.compileModel(at: source)
        defer { try? FileManager.default.removeItem(at: incompatible) }
        let fallback = LearnedJudge.coreML(compiledModelURL: incompatible, minimumProbability: 0.7).evaluate(context())
        #expect(fallback.source == .rules && fallback.fallbackReason == .modelLoadFailed)
        #expect(fallback.judgement == RuleJudge().judge(context()))
    }
}

/// Reviewable protobuf encoder for an authored y = x·0 + 0.75 network, not a
/// trained/bundled model. Field numbers follow Apple's published Model.proto,
/// FeatureTypes.proto and NeuralNetwork.proto; links are in learned-judge.md.
private nonisolated enum DirectorScorerCoreMLFixture {
    static func model(schemaVersion: String = "1") -> Data {
        func feature(_ name: String, shape: [UInt64]) -> Data {
            // FeatureDescription.name=1/type=3; FeatureType.multiArrayType=5.
            let array = packed(1, shape) + integer(2, 65568) // ArrayFeatureType FLOAT32.
            return string(1, name) + message(3, message(5, array))
        }
        func metadata(_ key: String, _ value: String) -> Data {
            message(100, string(1, key) + string(2, value)) // Metadata.userDefined map.
        }
        let creator = metadata("alfie.director.featureSchema", schemaVersion) +
            metadata("alfie.director.modelVersion", "synthetic-coreml-1")
        let description = message(1, feature("directorFeatures", shape: [1, 16])) +
            message(10, feature("probability", shape: [1, 1])) + message(100, creator)
        // BatchedMatMul: matrix dimensions=5/6, hasBias=7, weights=8, bias=9.
        let weights = message(1, floatBytes(Array(repeating: 0, count: 16)))
        let bias = message(1, floatBytes([0.75])) // WeightParams.floatValue=1, packed FP32.
        let multiply = integer(5, 16) + integer(6, 1) + integer(7, 1) + message(8, weights) + message(9, bias)
        let layer = string(1, "authored-constant") + string(2, "directorFeatures") +
            string(3, "probability") + message(1045, multiply)
        let network = message(1, layer) + integer(5, 1) // EXACT_ARRAY_MAPPING.
        return integer(1, 4) + message(2, description) + message(500, network)
    }

    private static func varint(_ value: UInt64) -> Data {
        var value = value, bytes: [UInt8] = []
        while value >= 128 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }
        bytes.append(UInt8(value))
        return Data(bytes)
    }
    private static func integer(_ field: UInt64, _ value: UInt64) -> Data { varint(field << 3) + varint(value) }
    private static func message(_ field: UInt64, _ bytes: Data) -> Data {
        varint((field << 3) | 2) + varint(UInt64(bytes.count)) + bytes
    }
    private static func string(_ field: UInt64, _ value: String) -> Data { message(field, Data(value.utf8)) }
    private static func packed(_ field: UInt64, _ values: [UInt64]) -> Data {
        message(field, values.reduce(into: Data()) { $0.append(varint($1)) })
    }
    private static func floatBytes(_ values: [Float]) -> Data {
        values.reduce(into: Data()) { data, value in
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }
}
