import Foundation

/// An explicit operator choice, in UTC. Both endpoints are inclusive; the
/// interval never compares monotonic event times from different sessions.
nonisolated struct DirectorShadowExportSelection: Equatable, Sendable {
    let sessionIDs: Set<UUID>
    let fromUTC: Date
    let throughUTC: Date

    var isValid: Bool {
        !sessionIDs.isEmpty && fromUTC.timeIntervalSince1970.isFinite &&
            throughUTC.timeIntervalSince1970.isFinite && fromUTC <= throughUTC
    }
}

nonisolated struct DirectorShadowSessionSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let firstUTC: Date
    let lastUTC: Date
    let recordCount: Int
    let evidenceClasses: [DirectorShadowRecord.EvidenceClass]
}

nonisolated struct DirectorShadowInventory: Equatable, Sendable {
    let sessions: [DirectorShadowSessionSummary]
    /// Retained files that failed validation; their contents are never shown.
    let excludedFiles: Int
    /// Expired/invalid-header files removed before the inventory was read.
    /// File counts are not invented counts of missing records.
    let prunedFiles: Int

    init(sessions: [DirectorShadowSessionSummary], excludedFiles: Int = 0, prunedFiles: Int = 0) {
        self.sessions = sessions; self.excludedFiles = excludedFiles; self.prunedFiles = prunedFiles
    }
}

/// The exact eight-key schema-1 companion. Generated only from validated
/// exported records; there is deliberately no manifest-import/authority API.
/// The offline reader is responsible for strict external-bundle decoding.
nonisolated struct DirectorShadowExportManifest: Encodable, Equatable, Sendable {
    let exportSchemaVersion = 1
    let exportID: UUID
    let exportedAtUTC: String
    let sessionIDs: [UUID]
    let recordCount: Int
    let evidenceClasses: [DirectorShadowRecord.EvidenceClass]
    let recordSchemaVersions: [Int]
    let retention = "explicitExport"

    init(records: [DirectorShadowRecord], exportID: UUID = UUID(), exportedAtUTC: Date) throws {
        let stamp = Self.utcString(exportedAtUTC)
        guard let reference = Self.utcDate(stamp) else { throw DirectorShadowLog.Failure.invalidClock }
        for record in records {
            _ = try record.validated(provenance: [record.evidenceClass])
            guard let date = Self.utcDate(record.recordedAtUTC), date <= reference,
                  date > reference.addingTimeInterval(-DirectorShadowLog.retention) else {
                throw DirectorShadowLog.Failure.invalidSourceClock
            }
        }
        self.exportID = exportID
        self.exportedAtUTC = stamp
        sessionIDs = Set(records.map(\.sessionID.value)).sorted { $0.uuidString < $1.uuidString }
        recordCount = records.count
        let classes = Set(records.map { $0.evidenceClass.rawValue })
        evidenceClasses = DirectorShadowRecord.EvidenceClass.allCases.filter { classes.contains($0.rawValue) }
            .sorted { $0.rawValue < $1.rawValue }
        recordSchemaVersions = Set(records.map(\.schemaVersion)).sorted()
    }

    /// Milliseconds are the schema's UTC precision. Floor rather than round
    /// so recording the current clock can never manufacture a future UTC.
    static func utcString(_ date: Date) -> String {
        guard date.timeIntervalSince1970.isFinite else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rounded = formatter.string(from: date)
        guard let represented = formatter.date(from: rounded) else { return "" }
        // Preserve an already-representable wire millisecond exactly; binary
        // multiplication/floor can otherwise move it into the previous one.
        // Step back from the rounded wire millisecond, not the raw clock:
        // a half-millisecond raw value can otherwise round back twice.
        return represented > date ? formatter.string(from: represented.addingTimeInterval(-0.001)) : rounded
    }

    static func utcDate(_ text: String) -> Date? {
        guard text.range(of: "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z\\z",
                         options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
}

nonisolated struct DirectorShadowExportResult: Equatable, Sendable {
    let manifest: DirectorShadowExportManifest
    let omittedOutsideSelection: Int
    let excludedFiles: Int
    let prunedFiles: Int

    init(manifest: DirectorShadowExportManifest, omittedOutsideSelection: Int,
         excludedFiles: Int = 0, prunedFiles: Int = 0) {
        self.manifest = manifest; self.omittedOutsideSelection = omittedOutsideSelection
        self.excludedFiles = excludedFiles; self.prunedFiles = prunedFiles
    }
}
