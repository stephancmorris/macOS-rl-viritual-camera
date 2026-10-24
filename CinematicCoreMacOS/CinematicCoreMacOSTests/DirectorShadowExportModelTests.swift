import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorShadowExportModelTests {
    private var now: Date { DirectorShadowExportModel.date("2026-10-20T00:00:00.000Z")! }
    private func record(_ log: DirectorShadowLog) throws -> DirectorShadowRecord {
        let object: [String: Any] = [
            "schemaVersion": 1, "recordID": UUID().uuidString, "sessionID": log.sessionID.uuidString,
            "sequence": "0", "recordedAtUTC": DirectorShadowLog.utcString(now),
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
    private func configured(_ root: URL) async throws -> DirectorShadowLog {
        let utc = now
        let log = try DirectorShadowLog(directory: root.appendingPathComponent("logs"),
            limits: .init(maximumRecordBytes: 4096, maximumQueuedBytes: 8192,
                          maximumFileBytes: 8192, maximumStoreBytes: 16384), utcClock: { utc })
        #expect(log.append(try record(log), provenance: [.synthetic]))
        await log.flush()
        return log
    }

    @Test func missingConfigurationDoesNotCreateStorageOrAllowExport() async {
        let model = DirectorShadowExportModel()
        #expect(!model.isConfigured && !model.canExport)
        await model.load()
        #expect(model.inventory == nil && model.selectedSessions.isEmpty)
        #expect(model.message == "Shadow logging is not configured.")
        #expect(!model.hasError)
    }

    @Test func exportRequiresExplicitSessionSelectionAndCanonicalBoundsAndNeverOverwrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let log = try await configured(root)
        let model = DirectorShadowExportModel(logProvider: { log })
        await model.load()
        #expect(model.inventory?.sessions.count == 1)
        #expect(model.selectedSessions.isEmpty && !model.canExport)
        model.selectedSessions = [log.sessionID]
        #expect(model.canExport)
        model.fromUTC = "2026-10-20T00:00:00Z"
        #expect(!model.canExport)
        model.fromUTC = "2026-10-20T00:00:00.000Z"
        model.throughUTC = "2026-10-19T23:59:59.999Z"
        #expect(!model.canExport)
        model.throughUTC = model.fromUTC
        #expect(model.canExport)
        let destination = root.appendingPathComponent("explicit.alfieshadow")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        await model.export(to: destination)
        #expect(!model.hasError && model.message.hasPrefix("Exported 1 records."))
        let manifest = try Data(contentsOf: destination.appendingPathComponent("manifest.json"))
        await model.export(to: destination)
        #expect(model.hasError)
        #expect(try Data(contentsOf: destination.appendingPathComponent("manifest.json")) == manifest)
        #expect(model.selectedSessions == [log.sessionID])
    }

    @Test func changedProviderRequiresReloadAndCannotUseOldSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await configured(root.appendingPathComponent("first"))
        let second = try await configured(root.appendingPathComponent("second"))
        var current = first
        let model = DirectorShadowExportModel(logProvider: { current })
        await model.load()
        model.selectedSessions = [first.sessionID]
        current = second
        #expect(!model.canExport)
        let destination = root.appendingPathComponent("must-not-exist")
        await model.export(to: destination)
        #expect(model.hasError && !FileManager.default.fileExists(atPath: destination.path))
        await model.load()
        #expect(model.selectedSessions.isEmpty && !model.canExport)
        #expect(model.inventory?.sessions.map(\.id) == [second.sessionID])
    }

    @Test func configurationChangedDuringLoadCannotPublishOldInventory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let log = try await configured(root)
        let release = DispatchSemaphore(value: 0)
        await log.holdWritesForTesting(until: release)
        var current: DirectorShadowLog? = log
        let model = DirectorShadowExportModel(logProvider: { current })
        let loading = Task { await model.load() }
        while !model.isBusy { await Task.yield() }
        current = nil
        release.signal()
        await loading.value
        #expect(model.inventory == nil && model.selectedSessions.isEmpty)
        #expect(model.hasError && !model.canExport)
        #expect(model.message == "Logging configuration changed. Reload retained sessions.")
    }

    @Test(arguments: ["2026-02-30T00:00:00.000Z", "2026-10-20T01:00:00.000+01:00", "2026-10-20T00:00:00Z", "NaN"])
    func noncanonicalUTCIsRefused(_ text: String) {
        #expect(DirectorShadowExportModel.date(text) == nil)
    }
}
