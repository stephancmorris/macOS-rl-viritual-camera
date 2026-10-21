import Foundation
@preconcurrency import CoreML
import Testing
@testable import Alfie

/// Offline synthetic Python-fit -> CoreML -> actual CPU inference. The model
/// remains outside the application bundle and grants no runtime authority.
struct DirectorTrainedScorerInteropTests {
    private struct Parity: Decodable {
        let featureSchemaVersion: Int
        let evidenceClass: String
        let modelVersion: String
        let cases: [Case]
        struct Case: Decodable { let features: [Double]; let expectedProbability: Double }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_SCORER_INTEROP"] != nil,
                   "Requires an explicitly generated synthetic scorer export"))
    func actualPythonExportMatchesCoreMLCpuInferenceAndAdapterSchema() throws {
        let requested = try #require(ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_SCORER_INTEROP"])
        #expect(requested.hasPrefix("/"))
        let directory = URL(fileURLWithPath: requested)
        let data = try Data(contentsOf: directory.appendingPathComponent("parity.json"))
        let parity = try JSONDecoder().decode(Parity.self, from: data)
        #expect(parity.featureSchemaVersion == 1 && parity.evidenceClass == "synthetic" && !parity.cases.isEmpty)
        let compiled = try MLModel.compileModel(at: directory.appendingPathComponent("DirectorScorer.mlmodel"))
        defer { try? FileManager.default.removeItem(at: compiled) }
        // Exercise the real app adapter's strict loading contract. The public
        // CoreML call below allows parity vectors without adding an app import
        // seam or reconstructing missing history from metadata.
        let adapter = try CoreMLDirectorScoringModel(compiledModelURL: compiled)
        #expect(adapter.modelVersion == parity.modelVersion && adapter.featureSchemaVersion == 1)
        let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        for item in parity.cases {
            #expect(item.features.count == 16 && item.features.allSatisfy { $0.isFinite && Float($0).isFinite })
            #expect(item.expectedProbability.isFinite && (0...1).contains(item.expectedProbability))
            let array = try MLMultiArray(shape: [1, 16], dataType: .float32)
            for (index, feature) in item.features.enumerated() { array[index] = NSNumber(value: Float(feature)) }
            let input = try MLDictionaryFeatureProvider(dictionary: ["directorFeatures": array])
            let output = try model.prediction(from: input)
            let probability = try #require(output.featureValue(for: "probability")?.multiArrayValue)
            #expect(probability.shape.map(\.intValue) == [1, 1] && probability.dataType == .float32)
            // Numerical parity tolerance for authored Float32 CPU inference;
            // this is not an editorial threshold or a calibration claim.
            #expect(abs(probability[0].doubleValue - item.expectedProbability) <= 0.00001)
        }
    }
}
