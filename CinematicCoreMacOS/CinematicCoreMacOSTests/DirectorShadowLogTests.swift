import Foundation
import CoreVideo
import Testing
@testable import Alfie

nonisolated private final class ShadowUTCClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

@MainActor struct DirectorShadowLogTests {
    private var date: Date { ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z")! }
    private var limits: DirectorShadowLog.Limits {
        .init(maximumRecordBytes: 4096, maximumQueuedBytes: 262144, maximumFileBytes: 8192, maximumStoreBytes: 8192)
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("b04-\(UUID())") }
    private func file(_ log: DirectorShadowLog) -> URL {
        log.directory.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl")
    }
    private func record(_ log: DirectorShadowLog, sequence: UInt64, date: Date? = nil) throws -> DirectorShadowRecord {
        let object: [String: Any] = [
            "schemaVersion": 1, "recordID": UUID().uuidString, "sessionID": log.sessionID.uuidString,
            "sequence": String(sequence), "recordedAtUTC": DirectorShadowLog.utcString(date ?? self.date),
            "eventTime": 10.0, "evidenceClass": "synthetic", "executionMode": "shadow",
            "context": ["inputs": ["input-1"], "program": "input-1", "level": "off", "paused": false,
                "editLive": false, "running": true, "healthy": true, "evidenceAvailable": false,
                "mayPropose": false, "mayPrepare": false, "mayTake": false, "authorityEpoch": "0",
                "routeGeneration": "0", "policyRevision": "0", "nominationRevision": "0", "evidenceRevision": "0",
                "segmentType": "liveEvent"], "parameters": ["status": "unavailable"], "evidence": [], "judgements": [],
            "event": ["kind": "abstention", "decisionID": UUID().uuidString, "stage": "cut",
                "reasons": [["domain": "observation", "code": "cutPolicyUnavailable"]]],
            "invalidFields": [], "droppedRecordsBefore": "0"]
        return try JSONDecoder().decode(DirectorShadowRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func records(_ url: URL) throws -> [DirectorShadowRecord] {
        try Data(contentsOf: url).split(separator: 10).map { try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0)) }
    }

    @Test func typedJSONLAndExplicitExportPreserveOriginalProvenanceAndNeverOverwrite() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        for sequence in 0..<3 { #expect(log.append(try record(log, sequence: UInt64(sequence)), provenance: [.synthetic])) }
        await log.flush()
        #expect(log.metrics.written == 3 && log.metrics.dropped == 0 && log.metrics.queuedBytes == 0)
        let source = try records(file(log))
        #expect(source.map(\.sequence.value) == [0, 1, 2] && source.allSatisfy { $0.evidenceClass == .synthetic })
        let destination = base.appendingPathComponent("explicit-export.jsonl")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try await log.export(session: log.sessionID, to: destination)
        #expect(try Data(contentsOf: destination) == Data(contentsOf: file(log)))
        await #expect(throws: (any Error).self) { try await log.export(session: log.sessionID, to: destination) }
        #expect(try records(destination).map(\.recordedAtUTC) == source.map(\.recordedAtUTC))
    }
    @Test func queueLossIsReportedOnTheLaterSequenceRatherThanAnEarlierQueuedRecord() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date
        let log = try DirectorShadowLog(directory: base, limits: .init(maximumRecordBytes: 4096,
            maximumQueuedBytes: 4096, maximumFileBytes: 8192, maximumStoreBytes: 8192), utcClock: { utc })
        let release = DispatchSemaphore(value: 0); defer { release.signal() }
        await log.holdWritesForTesting(until: release)
        #expect(log.append(try record(log, sequence: 0), provenance: [.synthetic]))
        #expect(!log.append(try record(log, sequence: 1), provenance: [.synthetic]))
        #expect(log.metrics.queuedBytes == 4096)
        release.signal(); await log.flush()
        #expect(log.append(try record(log, sequence: 2), provenance: [.synthetic]))
        await log.flush()
        let rows = try records(file(log))
        #expect(rows.map(\.sequence.value) == [0, 2])
        #expect(rows.map(\.droppedRecordsBefore.value) == [0, 1])
    }
    @Test func validationProvenanceAndFailedWritesCarryLossWithoutReusingSequence() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date, log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        #expect(!log.append(try record(log, sequence: 0), provenance: [.live, .synthetic]))
        #expect(log.append(try record(log, sequence: 1), provenance: [.synthetic]))
        await log.flush()
        #expect(log.append(try record(log, sequence: 1), provenance: [.synthetic]))
        #expect(log.append(try record(log, sequence: 2), provenance: [.synthetic]))
        await log.flush()
        let rows = try records(file(log))
        #expect(rows.map(\.sequence.value) == [1, 2] && rows.map(\.droppedRecordsBefore.value) == [1, 1])
        #expect(log.metrics.written == 2 && log.metrics.dropped == 2)
    }
    @Test func expiryUsesOriginalRecordTimeEvenWhenFileModificationTimeIsRefreshed() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let clock = ShadowUTCClock(date)
        let log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { clock.read() })
        log.append(try record(log, sequence: 0), provenance: [.synthetic]); await log.flush()
        let unrelated = log.directory.appendingPathComponent("operator-notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let target = base.appendingPathComponent("keep-target.txt"); try Data("keep".utf8).write(to: target)
        let link = log.directory.appendingPathComponent("director_shadow_\(UUID().uuidString).jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        clock.advance(31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: clock.read()], ofItemAtPath: file(log).path)
        await log.maintain()
        #expect(!FileManager.default.fileExists(atPath: file(log).path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path) && FileManager.default.fileExists(atPath: target.path))
        #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        await #expect(throws: (any Error).self) { try await log.export(session: log.sessionID, to: base.appendingPathComponent("expired.jsonl")) }
    }
    @Test func fileAndStoreBudgetsRemainBoundedAndOnlyOwnedLogsAreEvicted() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date, a = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        for sequence in 0..<8 { a.append(try record(a, sequence: UInt64(sequence)), provenance: [.synthetic]) }
        await a.flush()
        let unrelated = base.appendingPathComponent("keep.jsonl"); try Data("keep".utf8).write(to: unrelated)
        let b = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        for sequence in 0..<30 { b.append(try record(b, sequence: UInt64(sequence)), provenance: [.synthetic]) }
        await b.flush()
        #expect(!FileManager.default.fileExists(atPath: file(a).path))
        #expect(b.metrics.written > 0 && b.metrics.dropped > 0 && b.metrics.prunedFiles > 0)
        #expect(try Data(contentsOf: file(b)).count <= limits.maximumFileBytes)
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    }
    @Test func oversizeRecordsAndCorruptExportFailClosed() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date
        let tiny = try DirectorShadowLog(directory: base, limits: .init(maximumRecordBytes: 1,
            maximumQueuedBytes: 1, maximumFileBytes: 1, maximumStoreBytes: 1), utcClock: { utc })
        #expect(!tiny.append(try record(tiny, sequence: 0), provenance: [.synthetic]))
        #expect(tiny.metrics.queuedBytes == 0)
        let log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        log.append(try record(log, sequence: 0), provenance: [.synthetic]); await log.flush()
        let handle = try FileHandle(forWritingTo: file(log)); try handle.seekToEnd(); try handle.write(contentsOf: Data("{}\n".utf8)); try handle.close()
        await #expect(throws: (any Error).self) { try await log.export(session: log.sessionID, to: base.deletingLastPathComponent().appendingPathComponent("bad-\(UUID()).jsonl")) }
    }
    @Test func controllerLogsManualTakeAttemptAndRefusalWithOneActionIDWithoutEffects() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date, log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false), directorShadowLog: log)
        show.clock = { 100 }
        show.director.shadowRecorder?.provenanceForTesting = [.synthetic]
        show.director.attach()
        #expect(show.take() == .rejected(.noPreview))
        show.director.detach()
        await log.flush()
        let rows = try records(file(log))
        #expect(rows.count == 2 && rows[0].event.phase == .attempt && rows[1].event.outcome == .refused)
        #expect(rows[0].event.actionID == rows[1].event.actionID && rows.allSatisfy { $0.context.level == .off })
        #expect(show.programChannel == .a && show.director.authority.level == .off)
        #expect(rows.allSatisfy { $0.evidence.isEmpty && $0.judgements.isEmpty && $0.evidenceClass == .synthetic })
        let oldID = show.director.shadowRecorder?.log.sessionID
        show.director.attach()
        show.prepareForNewShow()
        show.director.detach()
        #expect(show.director.shadowRecorder?.log.sessionID != oldID)
        await show.director.shadowRecorder?.log.flush()
    }
    @Test func automaticSafetyPauseIsNotLabelledAsAnOperatorTakeover() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date, log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false), directorShadowLog: log)
        show.clock = { 100 }
        let b = show.addChannel(.b)
        show.channelA.setRunningForTesting(true); b.setRunningForTesting(true)
        b.shotComposer.lockTarget(UUID()); b.setOperationMode(.autoTracking)
        show.director.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        show.director.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                  outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])
        }
        show.director.attach()
        #expect(show.director.setLevel(.assist) == .accepted)
        show.director.assistPreparation.readinessForTesting = .init(reasons: [])
        show.director.assistPreparation.dispatchForTesting = { _, _ in .rejected("synthetic refusal") }
        let configuration = DirectorAssistPreparation.Configuration(readiness: .init(minimumSettledTime: 0,
            maximumMotion: 0.2, cutOnMotionAllowed: false, minimumCutSettledTime: 1, maximumCutMotion: 0.1),
            maximumRequestAge: 1, onePreparationPerTenure: true)
        #expect(show.director.preparePreview(.init(preset: .stage(.fullBody)), configuration: configuration) == .failed)
        show.director.detach()
        await log.flush()
        #expect(try records(file(log)).allSatisfy { $0.event.action != .takeOver })
        show.director.takeOver(); await log.flush()
        #expect(try records(file(log)).filter { $0.event.action == .takeOver }.count == 1)
    }

    private final class AcceptedSink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var isAvailable: Bool { true }
        var summary: String { "synthetic" }
        var detail: String { "synthetic" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
    }
    @Test func completedTakeRecordsActualRoleSwapWithoutCallingAnAttemptACompletedCut() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = date, log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [AcceptedSink()]),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false), directorShadowLog: log)
        show.clock = { 100 }; show.router.clock = { 100 }
        let b = show.addChannel(.b)
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        b.setLatestRenderedFrameForTesting(.init(channelID: .b, revisions: b.revisions, sourceTimestamp: 1,
            processingStartedAt: 100, renderedAt: 100, crop: .fullFrame,
            outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
        show.director.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        show.director.attach()
        #expect(show.take() == .committed(newProgram: .b))
        show.director.detach(); await log.flush()
        let rows = try records(file(log))
        #expect(rows.count == 2 && rows[0].event.phase == .attempt && rows[0].event.outcome == nil)
        #expect(rows[0].context.program == "input-1" && rows[0].context.preview == "input-2")
        #expect(rows[1].event.outcome == .completed && rows[1].event.programAfter == "input-2")
        #expect(rows[1].context.program == "input-2" && rows[1].context.preview == "input-1")
        #expect(rows[0].event.actionID == rows[1].event.actionID)
    }

}
