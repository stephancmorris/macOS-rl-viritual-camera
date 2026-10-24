import Foundation
import Testing
@testable import Alfie

/// Synthetic session ownership checks; every artifact stays in a new temporary root.
@MainActor struct DiagnosticsSessionIsolationTests {
    private let now = Date(timeIntervalSince1970: 1_600_000_000)

    private var localStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: now)
    }

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-diagnostics-sessions-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func identity(_ label: String) -> DiagnosticsSessionIdentity {
        .init(build: .init(appVersion: "synthetic", buildNumber: "0", sourceFingerprint: label,
                           osVersion: "synthetic", machineModel: "synthetic"),
              source: .unrecorded,
              output: .init(route: nil, showStandard: "1080p50", showFPS: 50,
                            presentation: "synthetic handoff only"))
    }

    private func begin(_ log: DiagnosticsLog, label: String) throws -> String {
        log.beginSession(note: label + " start", identity: identity(label))
        let name = try #require(log.currentFileName)
        log.appendMemoryRow(latencySamples: 1, dropTimestamps: 0, inputTimestamps: 1,
                            detectedPersons: 0, framesTotal: 1)
        return name
    }

    private func verify(_ name: String, label: String, excluding other: String, root: URL) throws {
        let soak = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        #expect(soak.hasPrefix(DiagnosticsLog.header))
        #expect(soak.contains(label + " start") && soak.contains(label + " stop"))
        #expect(!soak.contains(other + " start") && !soak.contains(other + " stop"))
        let memoryName = name.replacingOccurrences(of: "alfie_soak_", with: "alfie_memory_")
        let memory = try String(contentsOf: root.appendingPathComponent(memoryName), encoding: .utf8)
        #expect(memory.hasPrefix("elapsed_s,clock,footprint_mb"))
        #expect(memory.split(separator: "\n").count == 2)
        let manifestName = name.replacingOccurrences(of: "alfie_soak_", with: "alfie_session_")
            .replacingOccurrences(of: ".csv", with: ".json")
        let manifest = try JSONDecoder().decode(DiagnosticsManifest.self,
            from: Data(contentsOf: root.appendingPathComponent(manifestName)))
        #expect(manifest.csvFile == name && manifest.memoryFile == memoryName)
        #expect(manifest.identity == identity(label))
        #expect(manifest.closing?.note == label + " stop")
    }

    @Test func rapidRestartAtOneFixedWallClockKeepsBothTripletsAndIdentities() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixedNow = now
        let log = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, wallClock: { fixedNow })
        let first = try begin(log, label: "first")
        log.endSession(note: "first stop")
        // Deliberately restart before draining the queued close and manifest update.
        let second = try begin(log, label: "second")
        log.endSession(note: "second stop")
        await log.waitForPendingFileOperations()
        #expect(first != second)
        #expect(first.hasPrefix("alfie_soak_" + localStamp + "_"))
        #expect(second.hasPrefix("alfie_soak_" + localStamp + "_"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 6)
        try verify(first, label: "first", excluding: "second", root: root)
        try verify(second, label: "second", excluding: "first", root: root)
    }

    @Test func twoInstancesAtOneFixedWallClockKeepIndependentTriplets() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixedNow = now
        let firstLog = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, wallClock: { fixedNow })
        let secondLog = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, wallClock: { fixedNow })
        let first = try begin(firstLog, label: "first")
        let second = try begin(secondLog, label: "second")
        firstLog.endSession(note: "first stop")
        secondLog.endSession(note: "second stop")
        await firstLog.waitForPendingFileOperations()
        await secondLog.waitForPendingFileOperations()
        #expect(first != second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 6)
        try verify(first, label: "first", excluding: "second", root: root)
        try verify(second, label: "second", excluding: "first", root: root)
    }

    @Test(arguments: ["soak", "memory", "session"])
    func existingMemberRefusesWholeAllocationWithoutOverwritingOrLeavingPartialFiles(kind: String) async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixedNow = now
        let fixedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let token = localStamp + "_" + fixedID.uuidString
        let name = "alfie_" + kind + "_" + token + (kind == "session" ? ".json" : ".csv")
        let existing = root.appendingPathComponent(name)
        let original = Data("unrelated pre-existing artifact".utf8)
        try original.write(to: existing)
        let log = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, wallClock: { fixedNow },
                                 sessionID: { fixedID })
        _ = try begin(log, label: "refused")
        log.endSession(note: "refused stop")
        await log.waitForPendingFileOperations()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [name])
        #expect(try Data(contentsOf: existing) == original)
    }
}
