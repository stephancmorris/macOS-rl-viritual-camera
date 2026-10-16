import Foundation

/// S3 B-06 (C16): per-level sign-off records bound to the rig's admission
/// fingerprint. A level is selectable only on a rig with a current record;
/// any change to the fingerprint (devices, formats, rates, modes, show
/// standard, route, admission policy version) makes the level unavailable.
///
/// The store only answers *availability*. It never stores the selected
/// authority level and never grants one: every launch still starts Manual.
///
/// The sign-off fields beyond level, fingerprint and time are AWAITING OWNER
/// (Q1–Q3, D-04 memo). Adding them is a new file version, not a guess here.

/// The levels that need a sign-off. Suggest is the internal shadow level and
/// needs none; Manual is always available.
nonisolated enum QualifiableLevel: String, Codable, CaseIterable, Sendable {
    case assist, auto, backup

    var authorityLevel: DirectorAuthority.Level {
        switch self {
        case .assist: .assist
        case .auto: .auto
        case .backup: .backup
        }
    }
}

nonisolated struct QualificationRecord: Codable, Equatable, Sendable {
    let level: QualifiableLevel
    /// `AdmissionFingerprint.key` at sign-off.
    let fingerprintKey: String
    let signedOffAt: Date
}

/// Answers which levels this rig may select. `DirectorAuthority.Prerequisites
/// .qualifiedLevels` is fed from here.
nonisolated protocol DirectorQualificationLookup {
    func qualifiedLevels(for fingerprint: AdmissionFingerprint) -> Set<DirectorAuthority.Level>
}

/// Where the record file lives. Injected so tests never touch the real one.
nonisolated protocol QualificationRecordStorage {
    /// Nil when nothing has been stored yet.
    func read() throws -> Data?
    func write(_ data: Data) throws
}

nonisolated struct FileQualificationStorage: QualificationRecordStorage {
    let fileURL: URL

    /// `~/Library/Application Support/Alfie/DirectorQualification.json`. The
    /// folder is created on first write, not on read.
    static func applicationSupport() -> FileQualificationStorage? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return FileQualificationStorage(fileURL: base
            .appendingPathComponent("Alfie", isDirectory: true)
            .appendingPathComponent("DirectorQualification.json"))
    }

    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

nonisolated struct DirectorQualificationFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let records: [QualificationRecord]

    /// Only the current version is read; anything else fails closed.
    static func decode(_ data: Data) throws -> DirectorQualificationFile {
        let file = try JSONDecoder.qualification.decode(DirectorQualificationFile.self, from: data)
        guard file.version == currentVersion else { throw DirectorQualificationError.unsupportedVersion }
        return file
    }
}

nonisolated enum DirectorQualificationError: Error, Equatable {
    /// The stored file is from another version or can't be read. It is not
    /// used and is never overwritten.
    case unsupportedVersion, unreadable
    case noStorage
}

final class DirectorQualificationStore: DirectorQualificationLookup {
    enum State: Equatable {
        case empty, loaded, unreadable
    }

    private let storage: QualificationRecordStorage?
    /// Debug builds may inject in-memory records for testing. Release never does.
    private let acceptsInjectedRecords: Bool
    private(set) var state: State = .empty
    private var records: [QualificationRecord] = []
    private var injected: [QualificationRecord] = []

    init(storage: QualificationRecordStorage?,
         acceptsInjectedRecords: Bool = DeveloperFlags.allowInjectedQualification) {
        self.storage = storage
        self.acceptsInjectedRecords = acceptsInjectedRecords
        reload()
    }

    /// The owner's real record file.
    static func applicationSupport() -> DirectorQualificationStore {
        DirectorQualificationStore(storage: FileQualificationStorage.applicationSupport())
    }

    func reload() {
        records = []
        guard let storage else { state = .unreadable; return }
        do {
            guard let data = try storage.read() else { state = .empty; return }
            records = try DirectorQualificationFile.decode(data).records
            state = .loaded
        } catch {
            state = .unreadable
        }
    }

    func qualifiedLevels(for fingerprint: AdmissionFingerprint) -> Set<DirectorAuthority.Level> {
        let key = fingerprint.key
        let real = state == .loaded ? records : []
        return Set((real + injected).filter { $0.fingerprintKey == key }.map(\.level.authorityLevel))
    }

    /// The same answer in the console's terms.
    func consoleQualification(for fingerprint: AdmissionFingerprint) -> NextShotStatus.DirectorSection.Qualification {
        let levels = qualifiedLevels(for: fingerprint)
        return .init(assist: levels.contains(.assist), auto: levels.contains(.auto), backup: levels.contains(.backup))
    }

    /// Sign-off entry point (G-03 / G-05 / G-07). Replaces any earlier record
    /// for the same level and fingerprint. Refuses to write over a file it
    /// couldn't read, so a newer Alfie's records are never destroyed.
    func recordSignOff(_ level: QualifiableLevel, for fingerprint: AdmissionFingerprint, at date: Date) throws {
        try mutate { all in
            all.removeAll { $0.level == level && $0.fingerprintKey == fingerprint.key }
            all.append(QualificationRecord(level: level, fingerprintKey: fingerprint.key, signedOffAt: date))
        }
    }

    func revoke(_ level: QualifiableLevel, for fingerprint: AdmissionFingerprint) throws {
        try mutate { all in all.removeAll { $0.level == level && $0.fingerprintKey == fingerprint.key } }
    }

    /// Debug-only test seam: never persisted, ignored when injection is off.
    func injectForTesting(_ levels: Set<QualifiableLevel>, for fingerprint: AdmissionFingerprint) {
        guard acceptsInjectedRecords else { return }
        injected = levels.sorted { $0.rawValue < $1.rawValue }.map {
            QualificationRecord(level: $0, fingerprintKey: fingerprint.key, signedOffAt: .distantPast)
        }
    }

    private func mutate(_ change: (inout [QualificationRecord]) -> Void) throws {
        guard let storage else { throw DirectorQualificationError.noStorage }
        guard state != .unreadable else { throw DirectorQualificationError.unreadable }
        var all = records
        change(&all)
        let data = try JSONEncoder.qualification.encode(
            DirectorQualificationFile(version: DirectorQualificationFile.currentVersion, records: all))
        try storage.write(data)
        records = all
        state = .loaded
    }
}

private extension JSONEncoder {
    nonisolated static var qualification: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var qualification: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
