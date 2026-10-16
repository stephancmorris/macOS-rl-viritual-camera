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

    // CR-001: the release script is public. It must not name the notary Apple ID or a
    // personal signing identity; both come from the keychain or ALFIE_DEV_ID.
    @Test func releaseScriptCarriesNoPersonalIdentity() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build_release.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        let email = try Regex(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
        #expect(text.firstMatch(of: email) == nil)
        let identity = try Regex(#"Developer ID Application: [^"(]+\("#)
        #expect(text.firstMatch(of: identity) == nil)
        #expect(text.contains(#"DEV_ID="${ALFIE_DEV_ID:-Developer ID Application}""#))
    }
}
