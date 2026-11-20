//
//  DiagnosticsFilesSettingTests.swift
//  CinematicCoreMacOSTests
//
//  F-05: a saved switch for the soak CSV, memory CSV and session manifest.
//  Default on. Read at each session start. Off creates no file. Every
//  artifact stays in a new temporary root.
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct DiagnosticsFilesSettingTests {
    private let now = Date(timeIntervalSince1970: 1_600_000_000)

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-diagnostics-switch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "f05-switch-" + UUID().uuidString
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private var identity: DiagnosticsSessionIdentity {
        .init(build: .init(appVersion: "synthetic", buildNumber: "0", sourceFingerprint: "synthetic",
                           osVersion: "synthetic", machineModel: "synthetic"),
              source: .init(inputKind: "Live camera", deviceName: "Synthetic Person's Camera",
                            belowShowRate: false),
              output: .init(route: nil, showStandard: "1080p50", showFPS: 50,
                            presentation: "synthetic handoff only"))
    }

    private func contents(_ root: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
    }

    private func runSession(_ log: DiagnosticsLog) async {
        log.beginSession(note: "synthetic start", identity: identity)
        log.note("synthetic marker")
        log.appendMemoryRow(latencySamples: 1, dropTimestamps: 0, inputTimestamps: 1,
                            detectedPersons: 0, framesTotal: 1)
        log.endSession(note: "synthetic stop")
        await log.waitForPendingFileOperations()
    }

    @Test func theSavedSettingDefaultsToOnAndFollowsTheSwitch() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        #expect(DiagnosticsFilesSetting.isEnabled(in: store))
        store.set(false, forKey: DiagnosticsFilesSetting.key)
        #expect(!DiagnosticsFilesSetting.isEnabled(in: store))
        store.set(true, forKey: DiagnosticsFilesSetting.key)
        #expect(DiagnosticsFilesSetting.isEnabled(in: store))
    }

    @Test func offCreatesNoSoakMemoryOrManifestFile() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixedNow = now
        let log = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, wallClock: { fixedNow },
                                 filesEnabled: { false })
        await runSession(log)
        #expect(log.currentFileName == nil)
        #expect(log.filesOffForLastSession)
        #expect(try contents(root).isEmpty)
    }

    @Test func offDoesNotCreateTheDiagnosticsFolder() async throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("Diagnostics", isDirectory: true)
        let log = DiagnosticsLog(directory: root, filesEnabled: { false })
        await runSession(log)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    /// Turning files off does not keep expired files longer: they are still
    /// removed at session start.
    @Test func offStillRemovesExpiredFilesAtSessionStart() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("alfie_session_old.json")
        try Data("synthetic fixture".utf8).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-31 * 24 * 60 * 60)], ofItemAtPath: old.path)
        let fixedNow = now
        let log = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, filesEnabled: { false })
        await runSession(log)
        #expect(try contents(root).isEmpty)
    }

    @Test func theSwitchIsReadAtEachSessionStart() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var enabled = false
        let fixedNow = now
        let log = DiagnosticsLog(directory: root, cleanupClock: { fixedNow }, wallClock: { fixedNow },
                                 filesEnabled: { enabled })
        await runSession(log)
        #expect(try contents(root).isEmpty)

        enabled = true
        log.beginSession(note: "synthetic start", identity: identity)
        let name = try #require(log.currentFileName)
        #expect(!log.filesOffForLastSession)
        // Turning the switch off mid-session does not close the open session.
        enabled = false
        log.endSession(note: "synthetic stop")
        await log.waitForPendingFileOperations()
        let recorded = try contents(root)
        #expect(recorded.count == 3)
        #expect(recorded.contains(name))

        await runSession(log)
        #expect(try contents(root) == recorded)
    }

    @Test func theOutputManagerShowsOffAndStopsAskingUntilTheNextCapture() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var enabled = false
        let log = DiagnosticsLog(directory: root, filesEnabled: { enabled })
        let output = ProgramOutputManager(diagnosticsLog: log)

        output.start()
        #expect(output.diagnosticsFileName == nil)
        output.beginDiagnosticsSessionIfNeeded(note: "synthetic start")
        #expect(output.diagnosticsFileName == DiagnosticsFilesSetting.offStatus)
        // Non-nil, so the frame path's `diagnosticsFileName == nil` guard
        // stops calling in. Turning the switch on mid-capture changes nothing.
        enabled = true
        output.beginDiagnosticsSessionIfNeeded(note: "synthetic again")
        output.noteDetectionStartIfNeeded()
        #expect(output.diagnosticsFileName == DiagnosticsFilesSetting.offStatus)
        output.stop()
        await log.waitForPendingFileOperations()
        #expect(output.diagnosticsFileName == nil)
        #expect(try contents(root).isEmpty)

        // The next capture reads the switch again.
        output.start()
        output.beginDiagnosticsSessionIfNeeded(note: "synthetic start")
        let name = try #require(output.diagnosticsFileName)
        #expect(name.hasPrefix("alfie_soak_"))
        output.stop()
        await log.waitForPendingFileOperations()
        #expect(try contents(root).contains(name))
    }
}
