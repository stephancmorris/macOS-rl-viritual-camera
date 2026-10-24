import CoreGraphics
import Foundation
import Testing
@testable import Alfie

/// Counts and row indices are checked against actual synthetic JSONL files.
@MainActor struct TrainingDataPersistenceTests {
    private struct Fixture {
        let recorder: TrainingDataRecorder
        let writer: PersistenceTestWriter
        let root: URL
        let defaults: UserDefaults
        let suite: String
    }

    private func fixture(bufferSize: Int, gated: Bool = false, failingWrites: Set<Int> = []) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-persistence-" + UUID().uuidString)
        let suite = "alfie-persistence-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        var writer: PersistenceTestWriter?
        let recorder = TrainingDataRecorder(defaults: defaults, outputDirectory: root) { handle in
            let result = PersistenceTestWriter(handle: handle, gated: gated, failingWrites: failingWrites)
            writer = result
            return result
        }
        recorder.config.bufferSize = bufferSize
        recorder.setTrainingDataConsent(true)
        recorder.startRecording(cameraName: "synthetic", resolution: CGSize(width: 16, height: 16),
            composerConfig: .init(), detectorConfig: .init())
        return Fixture(recorder: recorder, writer: try #require(writer), root: root, defaults: defaults, suite: suite)
    }

    private func cleanUp(_ fixture: Fixture) {
        fixture.defaults.removePersistentDomain(forName: fixture.suite)
        try? FileManager.default.removeItem(at: fixture.root)
    }

    private func frame(_ recorder: TrainingDataRecorder, _ index: Int) {
        recorder.recordFrame(timestamp: Double(index), persons: [], currentCrop: .fullFrame,
            idealCrop: nil, isInterpolating: false)
    }

    private func stored(_ fixture: Fixture) throws -> (indices: [Int], total: Int, bytes: Int64) {
        let sessions = try FileManager.default.contentsOfDirectory(at: fixture.root, includingPropertiesForKeys: nil)
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        let data = try Data(contentsOf: session.appendingPathComponent("frames.jsonl"))
        let indices = try data.split(separator: 0x0A).map { line in
            let row = try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            return try #require(row["frame_idx"] as? Int)
        }
        let metadata = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: session.appendingPathComponent("metadata.json"))) as? [String: Any])
        return (indices, try #require(metadata["total_frames"] as? Int), Int64(data.count))
    }

    @Test func saturatedWriterCountsOnlyEightPersistedRows() async throws {
        let fixture = try fixture(bufferSize: 1, gated: true)
        defer { cleanUp(fixture) }
        let recorder = fixture.recorder
        for index in 0..<10 { frame(recorder, index) }
        await fixture.writer.waitUntilBlocked()
        #expect(recorder.stats.framesRecorded == 0)
        #expect(recorder.stats.fileSizeBytes == 0)
        #expect(recorder.stats.droppedFrames == 2)
        await fixture.writer.release()
        await recorder.stopRecording()

        let result = try stored(fixture)
        #expect(result.indices == Array(0..<8))
        #expect(result.total == 8 && recorder.stats.framesRecorded == 8)
        #expect(recorder.stats.droppedFrames == 2)
        #expect(recorder.stats.fileSizeBytes == result.bytes)
        #expect(await fixture.writer.writeCount == 8)
        #expect(await fixture.writer.closeCount == 1)
    }

    @Test func failedWritesDoNotCountAsPersistedRowsOrBytes() async throws {
        let fixture = try fixture(bufferSize: 1, failingWrites: [1, 2])
        defer { cleanUp(fixture) }
        frame(fixture.recorder, 0)
        frame(fixture.recorder, 1)
        await fixture.recorder.stopRecording()

        let result = try stored(fixture)
        #expect(result.indices.isEmpty && result.total == 0 && result.bytes == 0)
        #expect(fixture.recorder.stats.framesRecorded == 0)
        #expect(fixture.recorder.stats.fileSizeBytes == 0)
        #expect(fixture.recorder.stats.droppedFrames == 2)
        #expect(fixture.recorder.lastErrorDescription?.contains("Failed") == true)
    }

    @Test func successfulBatchAfterFailureKeepsItsProducerIndex() async throws {
        let fixture = try fixture(bufferSize: 1, failingWrites: [1])
        defer { cleanUp(fixture) }
        frame(fixture.recorder, 0)
        frame(fixture.recorder, 1)
        await fixture.recorder.stopRecording()

        let result = try stored(fixture)
        #expect(result.indices == [1])
        #expect(result.total == 1 && fixture.recorder.stats.framesRecorded == 1)
        #expect(fixture.recorder.stats.droppedFrames == 1)
        #expect(fixture.recorder.stats.fileSizeBytes == result.bytes)
    }

    @Test(arguments: [false, true])
    func shutdownPreservesTailBehindEightBlockedBatches(revoke: Bool) async throws {
        let fixture = try fixture(bufferSize: 100, gated: true)
        defer { cleanUp(fixture) }
        let recorder = fixture.recorder
        for index in 0..<801 { frame(recorder, index) }
        await fixture.writer.waitUntilBlocked()
        #expect(recorder.stats.framesRecorded == 0 && recorder.stats.droppedFrames == 0)

        if revoke { recorder.setTrainingDataConsent(false) }
        let stop = Task { await recorder.stopRecording() }
        for _ in 0..<1_000 {
            if recorder.isStopping { break }
            await Task.yield()
        }
        try #require(recorder.isStopping)
        #expect(!recorder.isRecording)
        frame(recorder, 801) // Admission is already closed while writes drain.
        recorder.setTrainingDataConsent(false)
        recorder.setTrainingDataConsent(true)
        recorder.startRecording(cameraName: "too early", resolution: CGSize(width: 16, height: 16),
            composerConfig: .init(), detectorConfig: .init())
        #expect(!recorder.isRecording)
        let secondStop = Task { await recorder.stopRecording() }
        await fixture.writer.release()
        await stop.value
        await secondStop.value
        await recorder.stopRecording()

        let result = try stored(fixture)
        #expect(result.indices == Array(0..<801))
        #expect(result.total == 801 && recorder.stats.framesRecorded == 801)
        #expect(recorder.stats.droppedFrames == 0)
        #expect(recorder.stats.fileSizeBytes == result.bytes)
        #expect(await fixture.writer.writeCount == 9)
        #expect(await fixture.writer.closeCount == 1)
        #expect(!recorder.isStopping)
    }

    @Test func partialFileWriteRollsBackBeforeNextBatch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-rollback-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("kept\n".utf8).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let writer = TrainingDataSessionWriter(fileHandle: handle) { handle, data in
            if data.starts(with: Data("fail".utf8)) {
                try handle.write(contentsOf: data.prefix(3))
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try handle.write(contentsOf: data)
        }
        await #expect(throws: (any Error).self) { try await writer.write(Data("failed row\n".utf8)) }
        #expect(try Data(contentsOf: url) == Data("kept\n".utf8))
        #expect(try await writer.write(Data("next\n".utf8)) == 5)
        try await writer.close()
        #expect(try Data(contentsOf: url) == Data("kept\nnext\n".utf8))
    }

    @Test func rollbackFailureClosesWriterToFurtherBatches() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alfie-rollback-failure-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        let writer = TrainingDataSessionWriter(fileHandle: handle) { handle, data in
            try handle.write(contentsOf: data.prefix(3))
            try handle.close() // Forces rollback itself to fail.
            throw CocoaError(.fileWriteOutOfSpace)
        }
        do {
            _ = try await writer.write(Data("failed row\n".utf8))
            Issue.record("Expected the partial write and rollback to fail")
        } catch {
            #expect(error.localizedDescription.contains("writer was closed"))
        }
        do {
            _ = try await writer.write(Data("later row\n".utf8))
            Issue.record("Expected the closed writer to reject a later batch")
        } catch {
            #expect((error as NSError).code == CocoaError.fileWriteUnknown.rawValue)
        }
        try await writer.close()
    }
}

private actor PersistenceTestWriter: TrainingDataWriting {
    private let handle: FileHandle
    private let gated: Bool
    private let failingWrites: Set<Int>
    private var released = false
    private var blocked = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private(set) var writeCount = 0
    private(set) var closeCount = 0

    init(handle: FileHandle, gated: Bool, failingWrites: Set<Int>) {
        self.handle = handle
        self.gated = gated
        self.failingWrites = failingWrites
    }

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { entryContinuation = $0 }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func write(_ data: Data) async throws -> Int64 {
        writeCount += 1
        if gated && !released {
            blocked = true
            entryContinuation?.resume()
            entryContinuation = nil
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        if failingWrites.contains(writeCount) { throw CocoaError(.fileWriteOutOfSpace) }
        try handle.write(contentsOf: data)
        return Int64(data.count)
    }

    func close() throws {
        try handle.close()
        closeCount += 1
    }
}
