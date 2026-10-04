import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Alfie

/// Synthetic observations in fresh temporary storage; no operator data or camera.
@MainActor struct TrainingDataRecorderTests {
    private func fixture(writerFactory: @escaping (FileHandle) -> any TrainingDataWriting = {
        TrainingDataSessionWriter(fileHandle: $0)
    }) throws -> (TrainingDataRecorder, URL, UserDefaults, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-consent-" + UUID().uuidString)
        let suite = "alfie-consent-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (TrainingDataRecorder(defaults: defaults, outputDirectory: root, writerFactory: writerFactory), root, defaults, suite)
    }

    private func start(_ recorder: TrainingDataRecorder) {
        recorder.startRecording(cameraName: "synthetic camera", resolution: CGSize(width: 16, height: 16),
            composerConfig: .init(), detectorConfig: .init())
    }

    private func frame(_ recorder: TrainingDataRecorder, _ timestamp: Double) {
        let person = PersonDetector.DetectedPerson(id: UUID(), boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.8),
            confidence: 0.9, timestamp: timestamp,
            poseKeypoints: .init(head: CGPoint(x: 0.4, y: 0.8), waist: CGPoint(x: 0.4, y: 0.4), confidence: 0.8),
            faceBoundingBox: nil, faceLandmarkRatios: nil)
        recorder.recordFrame(timestamp: timestamp, persons: [person], currentCrop: .fullFrame,
            idealCrop: nil, isInterpolating: false)
    }

    private func sessions(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("session_") }
    }

    private func observations(_ session: URL) throws -> [[String: Any]] {
        try Data(contentsOf: session.appendingPathComponent("frames.jsonl"))
            .split(separator: 0x0A).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
    }

    @Test func consentUsesInjectedDefaultsAndRefusesWriterWithoutGrant() async throws {
        var opened = false
        let (recorder, root, defaults, suite) = try fixture { handle in
            opened = true
            return TrainingDataSessionWriter(fileHandle: handle)
        }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        start(recorder)
        #expect(!opened && !FileManager.default.fileExists(atPath: root.path))
        recorder.setTrainingDataConsent(true)
        #expect(defaults.bool(forKey: "alfie.trainingDataRecorder.hasConsent"))
        recorder.setTrainingDataConsent(false)
        #expect(!defaults.bool(forKey: "alfie.trainingDataRecorder.hasConsent"))
        start(recorder)
        #expect(!opened && !recorder.isRecording)
    }

    @Test(arguments: [false, true]) func revokeAndStopShareDrainAndRejectQueuedFrames(stopFirst: Bool) async throws {
        var gate: GatedTrainingWriter?
        let (recorder, root, defaults, suite) = try fixture { handle in
            let writer = GatedTrainingWriter(handle: handle)
            gate = writer
            return writer
        }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        recorder.config.bufferSize = 1
        recorder.setTrainingDataConsent(true)
        start(recorder)
        frame(recorder, 1)
        let writer = try #require(gate)
        await writer.waitForWrite()
        frame(recorder, 2) // Accepted batch queued behind the paused first write.
        recorder.config.bufferSize = 100
        frame(recorder, 3) // Accepted in-memory observation must also be preserved.
        let queuedFrame = Task { @MainActor in frame(recorder, 4) }
        let stop = Task { await recorder.stopRecording() }
        if stopFirst {
            for _ in 0..<1_000 {
                if recorder.isStopping { break }
                await Task.yield()
            }
            try #require(recorder.isStopping) // Prove Stop entered before revoke.
            // queuedFrame was posted earlier, so it can be admitted before Stop.
        }
        let acceptedAtBoundary = recorder.stats.framesRecorded
        recorder.setTrainingDataConsent(false)
        #expect(!recorder.isRecording && recorder.isStopping)
        let lateFrame = Task { @MainActor in frame(recorder, 5) }
        await queuedFrame.value
        await lateFrame.value
        #expect(recorder.stats.framesRecorded == acceptedAtBoundary)
        start(recorder)
        #expect(!recorder.isRecording)
        recorder.setTrainingDataConsent(true)
        start(recorder) // Renewed consent cannot bypass the pending close.
        #expect(!recorder.isRecording)
        recorder.setTrainingDataConsent(false)
        await writer.release()
        await stop.value
        await recorder.stopRecording()
        #expect(!recorder.isStopping)
        let stored = try sessions(root)
        #expect(stored.count == 1)
        let rows = try observations(try #require(stored.first))
        #expect(rows.count == acceptedAtBoundary)
        #expect(rows.compactMap { $0["t"] as? Double } == Array(1...acceptedAtBoundary).map(Double.init))
        #expect(await writer.closeCount == 1)
        #expect(recorder.stats.droppedFrames == 0)
        start(recorder)
        #expect(!recorder.isRecording && recorder.lastErrorDescription?.contains("consent") == true)
    }

    @Test func shutdownNotificationsCannotReenterAdmissionOrRestart() async throws {
        let (recorder, root, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        recorder.setTrainingDataConsent(true)
        start(recorder)
        frame(recorder, 1)
        let recordingObserver = recorder.$isRecording.dropFirst().sink { recording in
            if !recording { frame(recorder, 2) }
        }
        let stoppingObserver = recorder.$isStopping.dropFirst().sink { stopping in
            if stopping { start(recorder); frame(recorder, 3) }
        }
        await recorder.stopRecording()
        withExtendedLifetime((recordingObserver, stoppingObserver)) {}
        #expect(recorder.stats.framesRecorded == 1)
        #expect(try sessions(root).count == 1)
        #expect(try observations(try #require(try sessions(root).first)).count == 1)
    }

    @Test func stopPersistsActualSchemaAndAllowsDistinctRenewedSession() async throws {
        let (recorder, root, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        recorder.setTrainingDataConsent(true)
        start(recorder)
        frame(recorder, 1)
        frame(recorder, 2)
        await recorder.stopRecording()
        let first = try #require(try sessions(root).first)
        let rows = try observations(first)
        #expect(rows.count == 2)
        let row = try #require(rows.first)
        #expect(Set(row.keys) == Set(["t", "frame_idx", "speaker", "keypoints", "current_crop", "ideal_crop", "interpolating"]))
        let pose = try #require(row["keypoints"] as? [String: Any])
        #expect(Set(pose.keys) == Set(["head_x", "head_y", "waist_x", "waist_y", "pose_confidence"]))
        let speaker = try #require(row["speaker"] as? [String: Any])
        #expect(Set(speaker.keys) == Set(["x", "y", "z", "bbox", "confidence"]))
        let metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: first.appendingPathComponent("metadata.json"))) as? [String: Any])
        #expect(metadata["total_frames"] as? Int == 2)
        #expect(metadata["camera_name"] as? String == "synthetic camera")
        #expect(recorder.stats.fileSizeBytes == Int64(try Data(contentsOf: first.appendingPathComponent("frames.jsonl")).count))
        recorder.setTrainingDataConsent(false)
        #expect(try observations(first).count == 2)
        recorder.setTrainingDataConsent(true)
        start(recorder)
        frame(recorder, 3)
        await recorder.stopRecording()
        #expect(try sessions(root).count == 2)
        #expect(try observations(first).count == 2)
        #expect(recorder.stats.framesRecorded == 1)
    }
}

private actor GatedTrainingWriter: TrainingDataWriting {
    let handle: FileHandle
    var entered = false
    var releaseContinuation: CheckedContinuation<Void, Never>?
    var entryContinuation: CheckedContinuation<Void, Never>?
    private(set) var closeCount = 0

    init(handle: FileHandle) { self.handle = handle }
    func waitForWrite() async {
        if entered { return }
        await withCheckedContinuation { entryContinuation = $0 }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
    func write(_ data: Data) async throws -> Int64 {
        if !entered {
            entered = true
            entryContinuation?.resume(); entryContinuation = nil
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        try handle.write(contentsOf: data)
        return Int64(data.count)
    }
    func close() throws { try handle.close(); closeCount += 1 }
}
