//
//  DirectorShadowWiringTests.swift
//  CinematicCoreMacOSTests
//
//  C-04 stage 2: the app gives a show its shadow log, inside a storage
//  budget, and a show never depends on it.
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct DirectorShadowWiringTests {
    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("c04-shadow-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func theShowBudgetIsValidAndBounded() {
        let limits = DirectorShadowLog.showLimits
        #expect(limits.isValid)
        #expect(limits.maximumRecordBytes <= limits.maximumQueuedBytes)
        #expect(limits.maximumFileBytes <= limits.maximumStoreBytes)
        // A whole store stays well under a gigabyte.
        #expect(limits.maximumStoreBytes <= 1024 * 1024 * 1024)
    }

    @Test func noLogIsMadeWhereTheShadowDoesNotRun() {
        let directory = scratch()
        #expect(DirectorShadowLog.forShow(enabled: false, directory: directory) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func aLogIsMadeWhereTheShadowRunsAndReachesTheShow() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = try #require(DirectorShadowLog.forShow(enabled: true, directory: directory))
        #expect(log.directory == directory.standardizedFileURL)
        let show = TestHardware.makeShow(directorShadowLog: log)
        #expect(show.shadowLogForExport === log)
        await log.flush()
        #expect(log.metrics.storageErrors == 0)
    }

    @Test func unusableStorageLeavesTheShowWithoutALogInsteadOfFailing() {
        let notAFile = try! #require(URL(string: "https://example.invalid/shadow"))
        #expect(DirectorShadowLog.forShow(enabled: true, directory: notAFile) == nil)
        let bad = DirectorShadowLog.Limits(maximumRecordBytes: 0, maximumQueuedBytes: 0, maximumFileBytes: 0, maximumStoreBytes: 0)
        #expect(DirectorShadowLog.forShow(enabled: true, directory: scratch(), limits: bad) == nil)
        // A show built without a log is an ordinary show.
        #expect(TestHardware.makeShow().shadowLogForExport == nil)
    }
}
