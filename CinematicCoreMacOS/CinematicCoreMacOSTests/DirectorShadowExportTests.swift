import Foundation
import Testing
@testable import Alfie

nonisolated private final class ExportUTCClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

/// B-04 synthetic metadata export checks. Fixture evidence-class labels test
/// serialization only; no camera, consent, live study or qualification exists.
@MainActor
struct DirectorShadowExportTests {
    private var now: Date { DirectorShadowExportManifest.utcDate("2026-10-19T00:00:00.000Z")! }
    private var limits: DirectorShadowLog.Limits {
        .init(maximumRecordBytes: 4096, maximumQueuedBytes: 262144,
              maximumFileBytes: 65536, maximumStoreBytes: 262144)
    }
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("shadow-export-\(UUID().uuidString)", isDirectory: true)
    }
    private func source(_ log: DirectorShadowLog, session: UUID? = nil) -> URL {
        log.directory.appendingPathComponent("director_shadow_\((session ?? log.sessionID).uuidString).jsonl")
    }
    private func record(_ session: UUID, sequence: UInt64, date: Date,
                        evidence: DirectorShadowRecord.EvidenceClass = .synthetic,
                        id: UUID = UUID(), eventTime: Double = 10) throws -> DirectorShadowRecord {
        let object: [String: Any] = [
            "schemaVersion": 1, "recordID": id.uuidString, "sessionID": session.uuidString,
            "sequence": String(sequence), "recordedAtUTC": DirectorShadowLog.utcString(date),
            "eventTime": eventTime, "evidenceClass": evidence.rawValue, "executionMode": "shadow",
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
    private func append(_ records: [DirectorShadowRecord], to log: DirectorShadowLog) async {
        for row in records { #expect(log.append(row, provenance: [row.evidenceClass])) }
        await log.flush()
    }
    private func data(_ records: [DirectorShadowRecord]) throws -> Data {
        var result = Data()
        for row in records { result.append(try JSONEncoder().encode(row)); result.append(10) }
        return result
    }
    private func decoded(_ url: URL) throws -> [DirectorShadowRecord] {
        try Data(contentsOf: url).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }
    private func selection(_ ids: Set<UUID>, from: Date? = nil, through: Date? = nil) -> DirectorShadowExportSelection {
        .init(sessionIDs: ids, fromUTC: from ?? now.addingTimeInterval(-60), throughUTC: through ?? now)
    }
    private func noStaging(in base: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: base.path).allSatisfy { !$0.hasPrefix(".director-export-") }
    }

    @Test func inventoryIncludesRetainedSessionsRatherThanOnlyTheCurrentWriter() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now
        let first = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        await append([try record(first.sessionID, sequence: 0, date: utc.addingTimeInterval(-2)),
                      try record(first.sessionID, sequence: 1, date: utc.addingTimeInterval(-1))], to: first)
        let renewed = try first.renewed()
        await append([try record(renewed.sessionID, sequence: 0, date: utc)], to: renewed)
        let inventory = try await renewed.retainedSessions()
        #expect(inventory.sessions.map(\.id) == [first.sessionID, renewed.sessionID].sorted { $0.uuidString < $1.uuidString })
        #expect(inventory.sessions.first { $0.id == first.sessionID }?.recordCount == 2)
        #expect(inventory.sessions.first { $0.id == first.sessionID }?.firstUTC == utc.addingTimeInterval(-2))
        #expect(inventory.sessions.first { $0.id == first.sessionID }?.lastUTC == utc.addingTimeInterval(-1))
        #expect(inventory.excludedFiles == 0 && inventory.prunedFiles == 0)
    }

    @Test func multiSessionBundleUsesInclusiveUTCAndExactManifestWithoutChangingSources() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, directory = base.appendingPathComponent("logs", isDirectory: true)
        let first = try DirectorShadowLog(directory: directory, limits: limits, utcClock: { utc })
        let second = try first.renewed()
        await append(try [-3.0, -2, -1].enumerated().map {
            try record(first.sessionID, sequence: UInt64($0.offset), date: utc.addingTimeInterval($0.element))
        }, to: first)
        await append(try [-2.0, -1, 0].enumerated().map {
            try record(second.sessionID, sequence: UInt64($0.offset), date: utc.addingTimeInterval($0.element), evidence: .recorded)
        }, to: second)
        let firstBytes = try Data(contentsOf: source(first)), secondBytes = try Data(contentsOf: source(second))
        let destination = base.appendingPathComponent("chosen-bundle", isDirectory: true)
        let result = try await second.export(selection: selection([first.sessionID, second.sessionID],
            from: utc.addingTimeInterval(-2), through: utc.addingTimeInterval(-1)), toNewBundle: destination)
        #expect(result.manifest.recordCount == 4 && result.omittedOutsideSelection == 2)
        #expect(result.manifest.evidenceClasses == [.recorded, .synthetic])
        #expect(result.manifest.recordSchemaVersions == [1])
        #expect(result.manifest.sessionIDs == [first.sessionID, second.sessionID].sorted { $0.uuidString < $1.uuidString })
        #expect(result.manifest.exportedAtUTC == "2026-10-19T00:00:00.000Z")
        let members = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(Set(members) == ["manifest.json", "records.jsonl"])
        let records = try decoded(destination.appendingPathComponent("records.jsonl"))
        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.recordedAtUTC == "2026-10-18T23:59:58.000Z" || $0.recordedAtUTC == "2026-10-18T23:59:59.000Z" })
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("manifest.json"))) as? [String: Any])
        #expect(Set(object.keys) == ["exportSchemaVersion", "exportID", "exportedAtUTC", "sessionIDs", "recordCount", "evidenceClasses", "recordSchemaVersions", "retention"])
        #expect(object["retention"] as? String == "explicitExport")
        #expect(try Data(contentsOf: source(first)) == firstBytes)
        #expect(try Data(contentsOf: source(second)) == secondBytes)
        #expect(try noStaging(in: base))
    }

    @Test(arguments: ["noSessions", "backwards", "invalidClock", "noRows"])
    func invalidOrEmptySelectionsNeverPublishABundle(variant: String) async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await append([try record(log.sessionID, sequence: 0, date: utc)], to: log)
        let choice: DirectorShadowExportSelection
        switch variant {
        case "noSessions": choice = selection([])
        case "backwards": choice = selection([log.sessionID], from: utc, through: utc.addingTimeInterval(-1))
        case "invalidClock": choice = selection([log.sessionID], from: Date(timeIntervalSince1970: .nan))
        default: choice = selection([log.sessionID], from: utc.addingTimeInterval(-10), through: utc.addingTimeInterval(-5))
        }
        let destination = base.appendingPathComponent("none")
        await #expect(throws: (any Error).self) { try await log.export(selection: choice, toNewBundle: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try noStaging(in: base))
    }

    @Test func aSessionRemovedAfterInventoryRefusesTheEntireSelection() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, a = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        let b = try a.renewed()
        await append([try record(a.sessionID, sequence: 0, date: utc)], to: a)
        await append([try record(b.sessionID, sequence: 0, date: utc)], to: b)
        #expect(try await b.retainedSessions().sessions.count == 2)
        try FileManager.default.removeItem(at: source(a))
        let destination = base.appendingPathComponent("missing")
        await #expect(throws: DirectorShadowLog.Failure.invalidSource) {
            try await b.export(selection: selection([a.sessionID, b.sessionID]), toNewBundle: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func expiryAtThirtyDaysIsReportedAsFilesAndCannotBeRenewedByModificationTime() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let clock = ExportUTCClock(now), log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { clock.read() })
        await append([try record(log.sessionID, sequence: 0, date: now)], to: log)
        clock.advance(DirectorShadowLog.retention - 0.001)
        #expect(try await log.retainedSessions().sessions.count == 1)
        clock.advance(0.001)
        try FileManager.default.setAttributes([.modificationDate: clock.read()], ofItemAtPath: source(log).path)
        let inventory = try await log.retainedSessions()
        #expect(inventory.sessions.isEmpty && inventory.prunedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: source(log).path))
        await #expect(throws: (any Error).self) {
            try await log.export(selection: selection([log.sessionID]), toNewBundle: base.appendingPathComponent("expired"))
        }
    }

    @Test(arguments: ["corrupt", "duplicateKey", "unterminated", "unknownPrivateField", "emptyLine", "floatingInteger", "exponentInteger"])
    func corruptRetainedTailsAreExcludedAndNeverPartiallyExported(variant: String) async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await append([try record(log.sessionID, sequence: 0, date: utc)], to: log)
        var bad = try JSONEncoder().encode(record(log.sessionID, sequence: 1, date: utc))
        switch variant {
        case "duplicateKey": bad = Data(("{\"recordedAtUTC\":\"PRIVATE_VALUE\"," + String(decoding: bad, as: UTF8.self).dropFirst()).utf8)
        case "unknownPrivateField": bad = Data(("{\"frame\":\"PRIVATE_FRAME\"," + String(decoding: bad, as: UTF8.self).dropFirst()).utf8)
        case "floatingInteger": bad = Data(String(decoding: bad, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1.0").utf8)
        case "exponentInteger": bad = Data(String(decoding: bad, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1e0").utf8)
        case "emptyLine": bad = Data()
        case "corrupt": bad = Data("{}".utf8)
        default: break
        }
        if variant != "unterminated" { bad.append(10) }
        let handle = try FileHandle(forWritingTo: source(log)); try handle.seekToEnd(); try handle.write(contentsOf: bad); try handle.close()
        let before = try Data(contentsOf: source(log))
        let inventory = try await log.retainedSessions()
        #expect(inventory.sessions.isEmpty && inventory.excludedFiles == 1)
        let destination = base.appendingPathComponent("rejected")
        await #expect(throws: (any Error).self) { try await log.export(selection: selection([log.sessionID]), toNewBundle: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: source(log)) == before)
    }

    @Test(arguments: ["future", "utcReversal"])
    func invalidStoredUTCIsPrunedRatherThanExposedToAnalysis(variant: String) async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { utc })
        await log.flush()
        let rows = [try record(log.sessionID, sequence: 0, date: utc.addingTimeInterval(-2)),
                    try record(log.sessionID, sequence: 1, date: utc.addingTimeInterval(variant == "future" ? 1 : -3))]
        try data(rows).write(to: source(log))
        let inventory = try await log.retainedSessions()
        #expect(inventory.sessions.isEmpty && inventory.prunedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: source(log).path))
    }

    @Test func detectedWallClockRollbackDiscardsOwnedLogsAcrossRenewedSessions() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let clock = ExportUTCClock(now), first = try DirectorShadowLog(directory: base, limits: limits, utcClock: { clock.read() })
        await append([try record(first.sessionID, sequence: 0, date: now.addingTimeInterval(-20))], to: first)
        let renewed = try first.renewed(); await renewed.flush()
        let unrelated = base.appendingPathComponent("operator-note.txt"); try Data("keep".utf8).write(to: unrelated)
        clock.advance(-1)
        await #expect(throws: DirectorShadowLog.Failure.clockRollback) { try await renewed.retainedSessions() }
        #expect(!FileManager.default.fileExists(atPath: source(first).path))
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        await #expect(throws: DirectorShadowLog.Failure.clockRollback) { try await first.retainedSessions() }
    }

    @Test func duplicateRecordIDsAcrossSessionsRefuseTheBundle() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, a = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        let b = try a.renewed(), reusedID = UUID()
        await append([try record(a.sessionID, sequence: 0, date: utc, id: reusedID)], to: a)
        await append([try record(b.sessionID, sequence: 0, date: utc, id: reusedID)], to: b)
        let destination = base.appendingPathComponent("duplicate")
        await #expect(throws: DirectorShadowLog.Failure.invalidSource) {
            try await b.export(selection: selection([a.sessionID, b.sessionID]), toNewBundle: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(arguments: ["descendant", "sourceAlias", "existingFile", "existingDirectory", "danglingLink"])
    func destinationsCannotOverwriteOrEscapeThroughASourceAlias(variant: String) async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await append([try record(log.sessionID, sequence: 0, date: utc)], to: log)
        let before = try Data(contentsOf: source(log)), destination: URL
        switch variant {
        case "descendant":
            let subfolder = log.directory.appendingPathComponent("nested")
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
            destination = subfolder.appendingPathComponent("not-exported")
        case "sourceAlias":
            let alias = base.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: log.directory)
            destination = alias.appendingPathComponent("not-exported")
        default:
            destination = base.appendingPathComponent("existing")
            if variant == "existingFile" { try Data("keep".utf8).write(to: destination) }
            if variant == "existingDirectory" { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false) }
            if variant == "danglingLink" { try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: base.appendingPathComponent("absent")) }
        }
        await #expect(throws: (any Error).self) { try await log.export(selection: selection([log.sessionID]), toNewBundle: destination) }
        #expect(try Data(contentsOf: source(log)) == before)
        if variant == "existingFile" { #expect(try String(contentsOf: destination, encoding: .utf8) == "keep") }
        if variant == "existingDirectory" { #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty) }
        if variant == "danglingLink" { #expect(try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true) }
        #expect(try noStaging(in: base))
    }

    @Test func aSiblingWhoseNameSharesTheSourcePrefixIsAValidDestination() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await append([try record(log.sessionID, sequence: 0, date: utc)], to: log)
        let sibling = base.appendingPathComponent("logs-export-parent")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        let destination = sibling.appendingPathComponent("bundle")
        #expect(try await log.export(selection: selection([log.sessionID]), toNewBundle: destination).manifest.recordCount == 1)
    }

    @Test func sourceSymlinksAndNonregularEntriesAreNeverFollowed() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await log.flush()
        let id = UUID(), target = base.appendingPathComponent("unrelated.jsonl")
        let original = try data([record(id, sequence: 0, date: utc)])
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: source(log, session: id), withDestinationURL: target)
        let directoryID = UUID()
        try FileManager.default.createDirectory(at: source(log, session: directoryID), withIntermediateDirectories: false)
        #expect(try await log.retainedSessions().sessions.isEmpty)
        await #expect(throws: DirectorShadowLog.Failure.invalidSource) {
            try await log.export(selection: selection([id]), toNewBundle: base.appendingPathComponent("refused"))
        }
        #expect(try Data(contentsOf: target) == original)
        #expect(try source(log, session: directoryID).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    @Test func stagedWriteFailureLeavesNeitherBundleNorStagingAndPreservesTheSource() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await append([try record(log.sessionID, sequence: 0, date: utc)], to: log)
        let original = try Data(contentsOf: source(log)), destination = base.appendingPathComponent("failed")
        log.failBeforePublishingForTesting = true
        await #expect(throws: DirectorShadowLog.Failure.unavailable) {
            try await log.export(selection: selection([log.sessionID]), toNewBundle: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try noStaging(in: base))
        #expect(try Data(contentsOf: source(log)) == original)
    }

    @Test func exportedPassiveHostClockDiagnosticsArePreservedWithoutComparingSessions() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await append([try record(log.sessionID, sequence: 0, date: utc.addingTimeInterval(-1), eventTime: 100),
                      try record(log.sessionID, sequence: 1, date: utc, eventTime: 1)], to: log)
        let destination = base.appendingPathComponent("passive")
        _ = try await log.export(selection: selection([log.sessionID]), toNewBundle: destination)
        #expect(try decoded(destination.appendingPathComponent("records.jsonl")).map(\.eventTime) == [100, 1])
    }

    @Test func wireUTCMillisecondsNeverManufactureAFutureTimestamp() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let raw = now.addingTimeInterval(0.0009), log = try DirectorShadowLog(directory: base, limits: limits, utcClock: { raw })
        #expect(log.recordingUTC() == "2026-10-19T00:00:00.000Z")
        await append([try record(log.sessionID, sequence: 0, date: raw)], to: log)
        #expect(log.metrics.written == 1 && log.metrics.dropped == 0)
        let represented = try #require(DirectorShadowExportManifest.utcDate("2026-10-19T00:00:00.123Z"))
        #expect(DirectorShadowLog.utcString(represented) == "2026-10-19T00:00:00.123Z")
    }

    @Test func everyWireMillisecondRoundTripsAndRawSubmillisecondsStayInTheirMillisecond() throws {
        for millisecond in 0..<1_000 {
            let text = String(format: "2026-10-19T00:00:00.%03dZ", millisecond)
            let represented = try #require(DirectorShadowExportManifest.utcDate(text))
            #expect(DirectorShadowLog.utcString(represented) == text)
            for fraction in [0.0001, 0.0005, 0.0009] {
                #expect(DirectorShadowLog.utcString(represented.addingTimeInterval(fraction)) == text)
            }
        }
    }

    @Test func oversizedRetainedFilesAreExcludedBeforeAnUnboundedRead() async throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let utc = now, log = try DirectorShadowLog(directory: base.appendingPathComponent("logs"), limits: limits, utcClock: { utc })
        await log.flush()
        var oversized = try data([record(log.sessionID, sequence: 0, date: utc)])
        oversized.append(Data(repeating: 32, count: limits.maximumFileBytes + 1 - oversized.count))
        try oversized.write(to: source(log))
        let inventory = try await log.retainedSessions()
        #expect(inventory.sessions.isEmpty && inventory.excludedFiles == 1)
        let destination = base.appendingPathComponent("too-large")
        await #expect(throws: DirectorShadowLog.Failure.resourceLimit) {
            try await log.export(selection: selection([log.sessionID]), toNewBundle: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func swiftManifestMatchesTheSharedOfflineBundleFixture() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = project.appendingPathComponent("scripts/fixtures/director-shadow-synthetic-export")
        let records = try decoded(fixture.appendingPathComponent("records.jsonl"))
        let manifest = try DirectorShadowExportManifest(records: records,
            exportID: UUID(uuidString: "3C38781E-8078-4D22-912E-0FB9A9C50154")!, exportedAtUTC: now)
        let actual = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        let expected = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("manifest.json"))) as? [String: Any])
        #expect(NSDictionary(dictionary: actual).isEqual(to: expected))
    }
}
