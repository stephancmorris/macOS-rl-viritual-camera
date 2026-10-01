// Safe source-audit regression: no capture, consent grant, real recording or cleanup.
import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor struct PrivacyAuditTests {
    @Test func recordingWithoutConsentRejectsBeforeOpeningAWriter() throws {
        let suite = "alfie-privacy-audit-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = TrainingDataRecorder(defaults: defaults)
        #expect(!recorder.hasUserConsentedToTrainingData)
        recorder.startRecording(cameraName: "synthetic", resolution: CGSize(width: 16, height: 16),
            composerConfig: .init(), detectorConfig: .init())
        #expect(!recorder.isRecording)
        #expect(recorder.lastErrorDescription?.contains("consent") == true)
    }

    @Test func observationExportContainsOnlyReviewedFields() throws {
        let crop = TrainingDataRecorder.CropData(x: 0, y: 0, w: 1, h: 1, zoom: 1)
        let observation = TrainingDataRecorder.FrameObservation(t: 0, frameIdx: 0,
            speaker: .init(x: 0.5, y: 0.5, z: 1, bbox: [0, 0, 1, 1], confidence: 1),
            keypoints: .init(headX: 0.5, headY: 0.8, waistX: 0.5, waistY: 0.4, poseConfidence: 1),
            currentCrop: crop, idealCrop: .init(x: 0, y: 0, w: 1, h: 1, zoom: 1, source: "synthetic"),
            interpolating: false)
        let data = try JSONEncoder().encode(observation)
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == Set(["t", "frameIdx", "speaker", "keypoints", "currentCrop", "idealCrop", "interpolating"]))
        let speaker = try #require(fields["speaker"] as? [String: Any])
        #expect(Set(speaker.keys) == Set(["x", "y", "z", "bbox", "confidence"]))
        let pose = try #require(fields["keypoints"] as? [String: Any])
        #expect(Set(pose.keys) == Set(["headX", "headY", "waistX", "waistY", "poseConfidence"]))
    }
}
