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

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    // F-05: camera, display and device names can carry a person's name. They
    // may reach the unified log only as private. The Metal GPU name is a
    // hardware model and stays public.
    @Test func deviceNamesNeverReachTheUnifiedLogAsPublic() throws {
        let fileManager = FileManager.default
        let interpolation = try Regex(#"\\\(([^\\]*?),\s*privacy:\s*\.public"#)
        let identifying = try Regex(#"localizedName|uniqueID|deviceName|cameraName|modelID|\.name\b|\bsummary\b|\bdetail\b"#)
        var offenders: [String] = []
        var scanned = 0
        for folder in ["CinematicCoreMacOS", "Shared", "CinematicCoreExtension"] {
            let base = Self.projectRoot.appendingPathComponent(folder)
            guard let files = fileManager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files where url.pathExtension == "swift" {
                scanned += 1
                let text = try String(contentsOf: url, encoding: .utf8)
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where !line.contains("Metal device") {
                    for match in line.matches(of: interpolation)
                    where match.output[1].substring?.firstMatch(of: identifying) != nil {
                        offenders.append("\(url.lastPathComponent):\(index + 1)")
                    }
                }
            }
        }
        #expect(scanned > 50)
        #expect(offenders.isEmpty, "public device names at \(offenders)")
    }

    // F-05: the app and the extension are separate bundles, each with its own
    // manifest. No tracking and no collected data; only the required-reason
    // categories a source search found.
    // The extension's UserDefaults and file-timestamp calls come from the
    // shared files compiled into it (ShowStandard, ProgramOutputManager,
    // DiagnosticsLog, ProgramOutputDiagnostics).
    @Test(arguments: ["CinematicCoreMacOS", "CinematicCoreExtension"])
    func eachBundleHasAPrivacyManifest(folder: String) throws {
        let reasons = ["NSPrivacyAccessedAPICategoryUserDefaults": "CA92.1",
                       "NSPrivacyAccessedAPICategoryFileTimestamp": "C617.1",
                       "NSPrivacyAccessedAPICategorySystemBootTime": "35F9.1"]
        let url = Self.projectRoot.appendingPathComponent(folder).appendingPathComponent("PrivacyInfo.xcprivacy")
        let plist = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let accessed = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var declared: [String: [String]] = [:]
        for entry in accessed {
            let type = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            declared[type] = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
        }
        #expect(declared == reasons.mapValues { [$0] })
    }
}
