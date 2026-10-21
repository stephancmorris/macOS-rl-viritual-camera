import Foundation
import Testing
@testable import Alfie

/// Actual queued cleanup and session writes in disposable synthetic storage only.
@MainActor struct DiagnosticsCleanupTests {
    private let now = Date(timeIntervalSince1970: 1_600_000_000)
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-diagnostics-cleanup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixture(_ name: String, in root: URL, modified: Date) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("synthetic fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func session(_ log: DiagnosticsLog) async {
        log.beginSession(note: "synthetic start")
        log.endSession(note: "synthetic stop")
        await log.waitForPendingFileOperations()
    }

    @Test(arguments: ["alfie_soak_fixture.csv", "alfie_memory_fixture.csv", "alfie_session_fixture.json"])
    func actualCleanupUsesStrictModificationDateBoundary(name: String) async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let cutoff = now.addingTimeInterval(-retention)
        let old = try fixture(name, in: root, modified: cutoff.addingTimeInterval(-1))
        let boundary = try fixture("boundary_" + name, in: root, modified: cutoff)
        // Session manifests require their prefix, including at the boundary.
        let boundaryURL: URL
        if name.hasSuffix(".json") {
            boundaryURL = root.appendingPathComponent("alfie_session_boundary.json")
            try FileManager.default.moveItem(at: boundary, to: boundaryURL)
        } else { boundaryURL = boundary }
        let recentName = name.hasSuffix(".json") ? "alfie_session_2000.json" : "recent_" + name
        let recent = try fixture(recentName, in: root, modified: cutoff.addingTimeInterval(1))
        let unrelated = try fixture("director_style.json", in: root, modified: cutoff.addingTimeInterval(-1))
        let outside = try folder()
        defer { try? FileManager.default.removeItem(at: outside) }
        let outsideOld = try fixture(name, in: outside, modified: cutoff.addingTimeInterval(-1))
        let fixedNow = now
        await session(DiagnosticsLog(directory: root, cleanupClock: { fixedNow }))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        for preserved in [boundaryURL, recent, unrelated, outsideOld] {
            #expect(try Data(contentsOf: preserved) == Data("synthetic fixture".utf8))
        }
    }

    @Test func nextSessionRechecksAgeUsingTheInjectedClock() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let boundary = try fixture("alfie_session_boundary.json", in: root,
                                   modified: now.addingTimeInterval(-retention))
        let firstNow = now
        await session(DiagnosticsLog(directory: root, cleanupClock: { firstNow }))
        #expect(FileManager.default.fileExists(atPath: boundary.path))
        let nextNow = now.addingTimeInterval(1)
        await session(DiagnosticsLog(directory: root, cleanupClock: { nextNow }))
        #expect(!FileManager.default.fileExists(atPath: boundary.path))
    }

    @Test func sessionCSVMemoryAndManifestUseTheIsolatedDirectory() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixedNow = now
        let log = DiagnosticsLog(directory: root, cleanupClock: { fixedNow })
        let identity = DiagnosticsSessionIdentity(
            build: .init(appVersion: "synthetic", buildNumber: "0", sourceFingerprint: "synthetic",
                         osVersion: "synthetic", machineModel: "synthetic"),
            source: .unrecorded,
            output: .init(route: nil, showStandard: "1080p50", showFPS: 50,
                          presentation: "synthetic handoff only"))
        log.beginSession(note: "synthetic start", identity: identity)
        let name = try #require(log.currentFileName)
        log.endSession(note: "synthetic stop")
        await log.waitForPendingFileOperations()
        let memoryName = name.replacingOccurrences(of: "alfie_soak_", with: "alfie_memory_")
        let manifestName = name.replacingOccurrences(of: "alfie_soak_", with: "alfie_session_")
            .replacingOccurrences(of: ".csv", with: ".json")
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) ==
                Set([name, memoryName, manifestName]))
        let csv = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        #expect(csv.hasPrefix(DiagnosticsLog.header))
        #expect(csv.contains("synthetic start") && csv.contains("synthetic stop"))
        let manifest = try JSONDecoder().decode(DiagnosticsManifest.self,
            from: Data(contentsOf: root.appendingPathComponent(manifestName)))
        #expect(manifest.identity == identity)
        #expect(manifest.closing?.note == "synthetic stop")
        #expect(try String(contentsOf: root.appendingPathComponent(memoryName), encoding: .utf8)
            .hasPrefix("elapsed_s,clock,footprint_mb"))
    }
}
