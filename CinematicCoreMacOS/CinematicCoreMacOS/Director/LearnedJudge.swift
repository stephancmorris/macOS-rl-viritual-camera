import Foundation

/// A-16's versioned, metadata-only scorer input. Values are raw, not normalized.
/// The one-hot entries describe existing presets; zero is not missing evidence.
nonisolated struct DirectorJudgeFeatures: Equatable, Sendable {
    static let schemaVersion = 1
    static let inputName = "directorFeatures"
    static let outputName = "probability"
    static let schemaMetadataKey = "alfie.director.featureSchema"
    static let modelMetadataKey = "alfie.director.modelVersion"
    static let names = [
        "subjectConfidence", "movement", "programDwellSeconds", "sinceWideSeconds",
        "historyCount", "sameShotHistoryCount", "candidateStageWide", "candidateStageFullBody",
        "candidateStageWaistUp", "candidateWebcamWide", "candidateWebcamTight", "programStageWide",
        "programStageFullBody", "programStageWaistUp", "programWebcamWide", "programWebcamTight"
    ]
    let values: [Float]

    private init(values: [Float]) { self.values = values }

    static func validContext(_ context: DirectorJudgeContext) -> Bool {
        let t = context.timeline
        return context.parameters.isValid && context.now.isFinite && context.now >= 0 &&
            context.now == t.now && t.programStartedAt.isFinite && t.programStartedAt >= 0 &&
            t.programStartedAt <= t.now && t.lastWideAt.isFinite && t.lastWideAt >= 0 &&
            t.lastWideAt <= t.now && t.history.allSatisfy {
                $0.endedAt.isFinite && $0.endedAt >= 0 && $0.endedAt <= t.now
            } && zip(t.history, t.history.dropFirst()).allSatisfy { pair in
                pair.0.endedAt <= pair.1.endedAt
            }
    }

    static func extract(_ candidate: DirectorShotPolicy.Candidate,
                        context: DirectorJudgeContext) -> Self? {
        guard validContext(context), candidate.channel == context.preview,
              candidate.shot != context.timeline.programShot,
              candidate.isWide == candidate.shot.isWide,
              candidate.subjectConfidence.isFinite, (0...1).contains(candidate.subjectConfidence),
              candidate.movement.isFinite, candidate.movement >= 0 else { return nil }
        let t = context.timeline
        let raw = [candidate.subjectConfidence, candidate.movement,
                   t.now - t.programStartedAt, t.now - t.lastWideAt,
                   Double(t.history.count), Double(t.history.filter { $0.shot == candidate.shot }.count)] +
            oneHot(candidate.shot) + oneHot(t.programShot)
        let values = raw.map(Float.init)
        guard values.count == names.count, values.allSatisfy(\.isFinite) else { return nil }
        return Self(values: values)
    }

    private static func oneHot(_ shot: DirectorShot) -> [Double] {
        let index: Int
        switch shot.preset {
        case .stage(.wide): index = 0
        case .stage(.fullBody): index = 1
        case .stage(.waistUp): index = 2
        case .webcam(.wide): index = 3
        case .webcam(.tight): index = 4
        }
        return (0..<5).map { $0 == index ? 1 : 0 }
    }
}

/// Implementations are immutable local scorers. A backend cannot return a shot.
nonisolated protocol DirectorScoringModel: Sendable {
    var featureSchemaVersion: Int { get }
    var modelVersion: String { get }
    func probability(for features: DirectorJudgeFeatures) throws -> Double
}

nonisolated enum DirectorScoringModelError: Error { case invalidOutput }

/// Optional local ranking only. It grants no authority and installs no model.
nonisolated struct LearnedJudge: DirectorJudge {
    enum Source: Equatable, Sendable { case rules, learned, invalid }
    enum FallbackReason: Equatable, Sendable {
        case modelMissing, modelLoadFailed, invalidModel, predictionFailed, invalidModelOutput
    }
    struct Evaluation: Equatable, Sendable {
        let judgement: DirectorJudgement
        let rules: DirectorJudgement
        let source: Source
        /// The attempted model's opaque version, if a valid model was consulted.
        let modelVersion: String?
        let fallbackReason: FallbackReason?
    }

    let minimumProbability: Double
    private let model: (any DirectorScoringModel)?
    private let unavailableReason: FallbackReason

    init(model: (any DirectorScoringModel)?, minimumProbability: Double,
         unavailableReason: FallbackReason = .modelMissing) {
        self.model = model
        self.minimumProbability = minimumProbability
        self.unavailableReason = unavailableReason
    }

    func judge(_ context: DirectorJudgeContext) -> DirectorJudgement { evaluate(context).judgement }

    func judgeWithAttribution(_ context: DirectorJudgeContext) -> DirectorJudgeEvaluation {
        let evaluation = evaluate(context)
        let attribution: DirectorJudgeAttribution?
        switch evaluation.source {
        case .rules: attribution = .rules
        case .learned: attribution = evaluation.modelVersion.map { .learned(modelVersion: $0) }
        case .invalid: attribution = nil
        }
        return .init(judgement: evaluation.judgement, attribution: attribution)
    }

    /// Both outputs use precisely the same evidence/timestamp. Failed prediction
    /// of any candidate discards the whole learned ranking, never a partial list.
    func evaluate(_ context: DirectorJudgeContext) -> Evaluation {
        let rules = RuleJudge().judge(context)
        func result(_ outcome: DirectorJudgement.Outcome, source: Source,
                    version: String? = nil, fallback: FallbackReason? = nil) -> Evaluation {
            .init(judgement: .init(outcome: outcome, evidenceRevision: context.evidenceRevision,
                                  computedAt: context.now), rules: rules, source: source,
                  modelVersion: version, fallbackReason: fallback)
        }
        func fallback(_ reason: FallbackReason, version: String? = nil) -> Evaluation {
            result(rules.outcome, source: .rules, version: version, fallback: reason)
        }
        guard minimumProbability.isFinite, (0...1).contains(minimumProbability),
              DirectorJudgeFeatures.validContext(context) else {
            return result(.abstain(.invalidJudgement), source: .invalid)
        }
        guard case .ranked(let permitted) = rules.outcome else {
            return result(rules.outcome, source: .rules)
        }
        var inputs: [DirectorJudgeFeatures] = []
        for allowed in permitted {
            guard let features = DirectorJudgeFeatures.extract(allowed.candidate, context: context) else {
                return result(.abstain(.invalidJudgement), source: .invalid)
            }
            inputs.append(features)
        }
        guard let model else { return fallback(unavailableReason) }
        guard model.featureSchemaVersion == DirectorJudgeFeatures.schemaVersion,
              Self.validModelVersion(model.modelVersion) else { return fallback(.invalidModel) }
        let version = model.modelVersion
        var scored: [(index: Int, item: DirectorJudgement.Ranked)] = []
        for (index, allowed) in permitted.enumerated() {
            let probability: Double
            do { probability = try model.probability(for: inputs[index]) }
            catch DirectorScoringModelError.invalidOutput { return fallback(.invalidModelOutput, version: version) }
            catch { return fallback(.predictionFailed, version: version) }
            guard probability.isFinite, (0...1).contains(probability) else {
                return fallback(.invalidModelOutput, version: version)
            }
            scored.append((index, .init(candidate: allowed.candidate, probability: probability,
                                        reason: allowed.reason)))
        }
        let ranked = scored.sorted {
            if $0.item.probability != $1.item.probability {
                return ($0.item.probability ?? 0) > ($1.item.probability ?? 0)
            }
            return $0.index < $1.index
        }.map(\.item)
        guard let top = ranked.first, let probability = top.probability else {
            return fallback(.invalidModelOutput, version: version)
        }
        return result(probability < minimumProbability ? .abstain(.lowConfidence) : .ranked(ranked),
                      source: .learned, version: version)
    }

    static func validModelVersion(_ token: String) -> Bool {
        func alphanumeric(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
        }
        let bytes = Array(token.utf8)
        guard let first = bytes.first, alphanumeric(first) else { return false }
        return bytes.allSatisfy { alphanumeric($0) || $0 == 46 || $0 == 95 || $0 == 45 }
    }
}
