import Foundation
@preconcurrency import CoreML

/// Owns one explicitly loaded, immutable CPU model. Apple requires serial use
/// of an MLModel instance; the private lock protects every prediction and its
/// output. The model reference never escapes this unchecked Sendable boundary.
nonisolated final class CoreMLDirectorScoringModel: DirectorScoringModel, @unchecked Sendable {
    enum ModelError: Error { case invalidURL, schemaMismatch }
    let featureSchemaVersion = DirectorJudgeFeatures.schemaVersion
    let modelVersion: String
    private let model: MLModel
    private let lock = NSLock()

    /// Loading is explicit configuration work, never performed by judge().
    /// Accepts only already compiled local models; no discovery or compilation.
    init(compiledModelURL: URL) throws {
        guard compiledModelURL.isFileURL, compiledModelURL.pathExtension == "mlmodelc" else {
            throw ModelError.invalidURL
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        let description = model.modelDescription
        guard Set(description.inputDescriptionsByName.keys) == [DirectorJudgeFeatures.inputName],
              Set(description.outputDescriptionsByName.keys) == [DirectorJudgeFeatures.outputName],
              description.stateDescriptionsByName.isEmpty, !description.isUpdatable,
              description.trainingInputDescriptionsByName.isEmpty,
              let input = description.inputDescriptionsByName[DirectorJudgeFeatures.inputName],
              let output = description.outputDescriptionsByName[DirectorJudgeFeatures.outputName],
              Self.matches(input, shape: [1, DirectorJudgeFeatures.names.count]),
              Self.matches(output, shape: [1, 1]),
              let metadata = description.metadata[.creatorDefinedKey] as? [String: String],
              metadata[DirectorJudgeFeatures.schemaMetadataKey] == String(DirectorJudgeFeatures.schemaVersion),
              let version = metadata[DirectorJudgeFeatures.modelMetadataKey],
              LearnedJudge.validModelVersion(version) else { throw ModelError.schemaMismatch }
        self.model = model
        self.modelVersion = version
    }

    func probability(for features: DirectorJudgeFeatures) throws -> Double {
        guard features.values.count == DirectorJudgeFeatures.names.count,
              features.values.allSatisfy(\.isFinite) else { throw ModelError.schemaMismatch }
        lock.lock()
        defer { lock.unlock() }
        let input = try MLMultiArray(shape: [1, NSNumber(value: DirectorJudgeFeatures.names.count)], dataType: .float32)
        for (index, value) in features.values.enumerated() { input[index] = NSNumber(value: value) }
        let provider = try MLDictionaryFeatureProvider(dictionary: [DirectorJudgeFeatures.inputName: input])
        let prediction = try model.prediction(from: provider)
        guard prediction.featureNames == [DirectorJudgeFeatures.outputName],
              let output = prediction.featureValue(for: DirectorJudgeFeatures.outputName)?.multiArrayValue,
              output.dataType == .float32, output.shape.map(\.intValue) == [1, 1], output.count == 1 else {
            throw DirectorScoringModelError.invalidOutput
        }
        let probability = output[0].doubleValue
        guard probability.isFinite, (0...1).contains(probability) else { throw DirectorScoringModelError.invalidOutput }
        return probability
    }

    private static func matches(_ feature: MLFeatureDescription, shape: [Int]) -> Bool {
        guard feature.type == .multiArray, !feature.isOptional, let constraint = feature.multiArrayConstraint else {
            return false
        }
        guard constraint.dataType == .float32, constraint.shape.map(\.intValue) == shape else { return false }
        // CoreML represents fixed shapes as a singleton enumeration on this
        // runtime. Admit only that exact shape, never a second allowed shape.
        switch constraint.shapeConstraint.type {
        case .unspecified: return true
        case .enumerated:
            let shapes = constraint.shapeConstraint.enumeratedShapes
            return shapes.count == 1 && shapes[0].map(\.intValue) == shape
        case .range: return false
        @unknown default: return false
        }
    }
}

nonisolated extension LearnedJudge {
    /// Explicit optional loading. An absent/unloadable/incompatible model keeps
    /// the rules baseline; nothing searches the application bundle or promotes it.
    static func coreML(compiledModelURL: URL?, minimumProbability: Double) -> Self {
        guard minimumProbability.isFinite, (0...1).contains(minimumProbability) else {
            return Self(model: nil, minimumProbability: minimumProbability)
        }
        guard let compiledModelURL else { return Self(model: nil, minimumProbability: minimumProbability) }
        do {
            return Self(model: try CoreMLDirectorScoringModel(compiledModelURL: compiledModelURL),
                        minimumProbability: minimumProbability)
        } catch {
            return Self(model: nil, minimumProbability: minimumProbability, unavailableReason: .modelLoadFailed)
        }
    }
}
