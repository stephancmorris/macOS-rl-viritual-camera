import Foundation
import Testing
@testable import Alfie

/// B-06 (C16): qualification records bound to the admission fingerprint.
@MainActor struct DirectorQualificationStoreTests {
    private final class MemoryStorage: QualificationRecordStorage {
        var data: Data?
        var writes = 0
        init(_ data: Data? = nil) { self.data = data }
        func read() throws -> Data? { data }
        func write(_ data: Data) throws { self.data = data; writes += 1 }
    }

    nonisolated private static func fingerprint(mode: String = "track", device: String = "cam-1",
                                    policyVersion: Int = AdmissionPolicy.version) -> AdmissionFingerprint {
        AdmissionFingerprint(policyVersion: policyVersion, machineModel: "Mac15,3", osVersion: "26.0",
            showStandard: "1080p50", route: "Direct",
            inputs: [.init(channel: "A", deviceModelID: device, deliveredWidth: 1920, deliveredHeight: 1080,
                           captureFPS: 50, captureProfile: "hd", mode: mode),
                     .init(channel: "B", deviceModelID: "cam-2", deliveredWidth: 1920, deliveredHeight: 1080,
                           captureFPS: 50, captureProfile: "hd", mode: "wide")])
    }

    private let rig = Self.fingerprint()
    private let signedOff = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func emptyStoreQualifiesNothing() {
        let store = DirectorQualificationStore(storage: MemoryStorage(), acceptsInjectedRecords: false)
        #expect(store.state == .empty)
        #expect(store.qualifiedLevels(for: rig).isEmpty)
        #expect(store.consoleQualification(for: rig) == .none)
    }

    @Test func signOffQualifiesOnlyThatLevelOnThatRig() throws {
        let store = DirectorQualificationStore(storage: MemoryStorage(), acceptsInjectedRecords: false)
        try store.recordSignOff(.assist, for: rig, at: signedOff)
        #expect(store.qualifiedLevels(for: rig) == [.assist])
        #expect(store.consoleQualification(for: rig) == .init(assist: true, auto: false, backup: false))
        #expect(!store.qualifiedLevels(for: rig).contains(.suggest))
    }

    @Test(arguments: [fingerprint(mode: "wide"), fingerprint(device: "cam-9"),
                      fingerprint(policyVersion: AdmissionPolicy.version + 1)])
    func anyFingerprintChangeMakesTheLevelUnavailable(changed: AdmissionFingerprint) throws {
        let store = DirectorQualificationStore(storage: MemoryStorage(), acceptsInjectedRecords: false)
        try store.recordSignOff(.assist, for: rig, at: signedOff)
        #expect(changed.key != rig.key)
        #expect(store.qualifiedLevels(for: changed).isEmpty)
    }

    @Test func recordsSurviveRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-qualification-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = FileQualificationStorage(fileURL: folder.appendingPathComponent("DirectorQualification.json"))
        try DirectorQualificationStore(storage: storage, acceptsInjectedRecords: false)
            .recordSignOff(.auto, for: rig, at: signedOff)

        let relaunched = DirectorQualificationStore(storage: storage, acceptsInjectedRecords: false)
        #expect(relaunched.state == .loaded)
        #expect(relaunched.qualifiedLevels(for: rig) == [.auto])
    }

    @Test func unknownVersionFailsClosedAndIsNeverOverwritten() throws {
        let future = Data(#"{"version":2,"records":[{"level":"auto","fingerprintKey":"x","signedOffAt":"2026-10-10T00:00:00Z"}]}"#.utf8)
        let storage = MemoryStorage(future)
        let store = DirectorQualificationStore(storage: storage, acceptsInjectedRecords: false)
        #expect(store.state == .unreadable)
        #expect(store.qualifiedLevels(for: rig).isEmpty)
        #expect(throws: DirectorQualificationError.unreadable) {
            try store.recordSignOff(.assist, for: rig, at: signedOff)
        }
        #expect(storage.data == future && storage.writes == 0)
    }

    @Test func corruptFileFailsClosed() {
        let store = DirectorQualificationStore(storage: MemoryStorage(Data("not json".utf8)), acceptsInjectedRecords: false)
        #expect(store.state == .unreadable)
        #expect(store.qualifiedLevels(for: rig).isEmpty)
    }

    @Test func noStorageFailsClosed() {
        let store = DirectorQualificationStore(storage: nil, acceptsInjectedRecords: true)
        #expect(store.qualifiedLevels(for: rig).isEmpty)
        #expect(throws: DirectorQualificationError.noStorage) {
            try store.recordSignOff(.assist, for: rig, at: signedOff)
        }
    }

    @Test func releaseIgnoresInjectedRecords() {
        let release = DirectorQualificationStore(storage: MemoryStorage(), acceptsInjectedRecords: false)
        release.injectForTesting([.assist, .auto, .backup], for: rig)
        #expect(release.qualifiedLevels(for: rig).isEmpty)
    }

    @Test func debugInjectionIsNeverPersisted() {
        let storage = MemoryStorage()
        let debug = DirectorQualificationStore(storage: storage, acceptsInjectedRecords: true)
        debug.injectForTesting([.assist], for: rig)
        #expect(debug.qualifiedLevels(for: rig) == [.assist])
        #expect(storage.writes == 0 && storage.data == nil)
        #expect(DirectorQualificationStore(storage: storage, acceptsInjectedRecords: true)
            .qualifiedLevels(for: rig).isEmpty)
    }

    @Test func revokeRemovesOnlyThatLevel() throws {
        let store = DirectorQualificationStore(storage: MemoryStorage(), acceptsInjectedRecords: false)
        try store.recordSignOff(.assist, for: rig, at: signedOff)
        try store.recordSignOff(.auto, for: rig, at: signedOff)
        try store.revoke(.auto, for: rig)
        #expect(store.qualifiedLevels(for: rig) == [.assist])
    }

    @Test func fileHoldsSignOffsOnlyNeverASelectedLevel() throws {
        let storage = MemoryStorage()
        let store = DirectorQualificationStore(storage: storage, acceptsInjectedRecords: false)
        try store.recordSignOff(.backup, for: rig, at: signedOff)
        let data = try #require(storage.data)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["version", "records"])
        let record = try #require((json["records"] as? [[String: Any]])?.first)
        #expect(Set(record.keys) == ["level", "fingerprintKey", "signedOffAt"])
    }

    @Test func storeFeedsTheAuthorityGate() throws {
        let store = DirectorQualificationStore(storage: MemoryStorage(), acceptsInjectedRecords: false)
        try store.recordSignOff(.assist, for: rig, at: signedOff)
        func prerequisites(_ fingerprint: AdmissionFingerprint) -> DirectorAuthority.Prerequisites {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true,
                  admissionCurrent: true, qualifiedLevels: store.qualifiedLevels(for: fingerprint))
        }
        var authority = DirectorAuthority(reviewPolicy: .conservative)
        #expect(authority.apply(.enable(.auto), prerequisites: prerequisites(rig)).refusal == .notQualified)
        #expect(authority.level == .off)
        #expect(authority.apply(.enable(.assist), prerequisites: prerequisites(Self.fingerprint(mode: "wide")))
            .refusal == .notQualified)
        #expect(authority.apply(.enable(.assist), prerequisites: prerequisites(rig)).refusal == nil)
        #expect(authority.level == .assist)
    }
}
