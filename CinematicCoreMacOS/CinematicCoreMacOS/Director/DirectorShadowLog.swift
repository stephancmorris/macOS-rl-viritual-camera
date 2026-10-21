import Darwin
import Foundation

/// B-04: typed metadata only. Mutable file/session state belongs exclusively
/// to queue; queued-byte and loss counters belong to lock. No frame-path I/O.
nonisolated final class DirectorShadowLog: @unchecked Sendable {
    struct Limits: Sendable {
        let maximumRecordBytes: Int
        let maximumQueuedBytes: Int
        let maximumFileBytes: Int
        let maximumStoreBytes: Int
        var isValid: Bool {
            maximumRecordBytes > 0 && maximumQueuedBytes >= maximumRecordBytes &&
                maximumFileBytes >= maximumRecordBytes && maximumStoreBytes >= maximumFileBytes
        }
    }
    struct Metrics: Sendable { var queuedBytes = 0; var written: UInt64 = 0; var dropped: UInt64 = 0; var prunedFiles: UInt64 = 0; var storageErrors: UInt64 = 0 }
    enum Failure: Error, Equatable {
        case invalidLimits, unavailable, expired, invalidSelection, invalidClock, clockRollback
        case invalidSource, invalidSourceClock, invalidDestination, emptySelection, resourceLimit
        case invalidExport(String)
    }
    /// Recorded C3 policy, not an E3 media-retention default.
    static let retention: TimeInterval = 30 * 24 * 60 * 60
    let sessionID: UUID
    let directory: URL
    private let limits: Limits
    private let utcClock: @Sendable () -> Date
    private static let storageQueue = DispatchQueue(label: "com.alfie.director-shadow", qos: .utility)
    private let queue = DirectorShadowLog.storageQueue
    private let lock = NSLock()
    private var counters = Metrics()
    private var pendingLoss: UInt64 = 0
    // Queue-confined state below.
    private var writeLoss: UInt64 = 0
    private var created = false
    private var closed = false
    private var lastDate: Date?
    private var lastSequence: UInt64?
    private var recordIDs = Set<UUID>()
    private var fileBytes = 0
    private final class ClockHistory { var latest: Date? }
    private let clockHistory: ClockHistory

    convenience init(directory: URL, sessionID: UUID = UUID(), limits: Limits,
         utcClock: @escaping @Sendable () -> Date = { Date() }) throws {
        try self.init(directory: directory, sessionID: sessionID, limits: limits,
                      utcClock: utcClock, clockHistory: ClockHistory())
    }

    private init(directory: URL, sessionID: UUID, limits: Limits,
                 utcClock: @escaping @Sendable () -> Date, clockHistory: ClockHistory) throws {
        guard limits.isValid, directory.isFileURL else { throw Failure.invalidLimits }
        self.directory = directory.standardizedFileURL; self.sessionID = sessionID
        self.limits = limits; self.utcClock = utcClock; self.clockHistory = clockHistory
        queue.async { @Sendable [self] in do { _ = try prune() } catch { storageError() } }
    }

    @MainActor static func besideDiagnostics(limits: Limits) throws -> DirectorShadowLog {
        try .init(directory: DiagnosticsLog.directory, limits: limits)
    }

    var metrics: Metrics { lock.withLock { counters } }
    func recordingUTC() -> String { Self.utcString(utcClock()) }
    func renewed() throws -> DirectorShadowLog {
        try .init(directory: directory, sessionID: UUID(), limits: limits,
                  utcClock: utcClock, clockHistory: clockHistory)
    }
    private var fileURL: URL { directory.appendingPathComponent(Self.name(sessionID)) }
    private static func name(_ id: UUID) -> String { "director_shadow_\(id.uuidString).jsonl" }
    private static func date(_ text: String) -> Date? { DirectorShadowExportManifest.utcDate(text) }
    static func utcString(_ date: Date) -> String { DirectorShadowExportManifest.utcString(date) }
    private static func adding(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let result = a.addingReportingOverflow(b); return result.overflow ? .max : result.partialValue
    }
    func noteDropped() { drop() }
    private func drop() {
        lock.withLock { counters.dropped = Self.adding(counters.dropped, 1); pendingLoss = Self.adding(pendingLoss, 1) }
    }

    private func storageError() { lock.withLock { counters.storageErrors = Self.adding(counters.storageErrors, 1) } }

    /// One producer submits records in sequence order. Returns queue admission, never a disk-success claim. Encoding is bounded
    /// metadata work on the caller's Director tick; all filesystem work is queued.
    @discardableResult func append(_ record: DirectorShadowRecord,
                                   provenance: [DirectorShadowRecord.EvidenceClass]) -> Bool {
        let loss = lock.withLock { () -> UInt64? in
            guard counters.queuedBytes <= limits.maximumQueuedBytes - limits.maximumRecordBytes else { return nil }
            counters.queuedBytes += limits.maximumRecordBytes
            let loss = pendingLoss; pendingLoss = 0
            return loss
        }
        guard let loss else { drop(); return false }
        do {
            guard record.sessionID.value == sessionID else { throw Failure.unavailable }
            _ = try record.validated(provenance: provenance)
            guard try JSONEncoder().encode(record).count + 1 <= limits.maximumRecordBytes else { throw Failure.unavailable }
        } catch {
            lock.withLock {
                counters.queuedBytes -= limits.maximumRecordBytes
                counters.dropped = Self.adding(counters.dropped, 1)
                pendingLoss = Self.adding(pendingLoss, Self.adding(loss, 1))
            }
            return false
        }
        queue.async { @Sendable [self] in
            defer { lock.withLock { counters.queuedBytes -= limits.maximumRecordBytes } }
            do { try write(record, queuedLoss: loss) }
            catch {
                writeLoss = Self.adding(writeLoss, Self.adding(loss, 1))
                lock.withLock { counters.dropped = Self.adding(counters.dropped, 1) }
                storageError()
            }
        }
        return true
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.unavailable }
    }
    private struct ManagedFile { let id: UUID; let url: URL; let size: Int; let first: Date? }
    private func managedFiles() throws -> [ManagedFile] {
        try ensureDirectory()
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]).compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("director_shadow_"), name.hasSuffix(".jsonl"),
                  let id = UUID(uuidString: String(name.dropFirst(16).dropLast(6))), Self.name(id) == name else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { return nil }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let prefix = try handle.read(upToCount: limits.maximumRecordBytes) ?? Data()
            let first = prefix.firstIndex(of: 10).flatMap { end -> Date? in
                let line = Data(prefix[..<end])
                guard (try? Self.rejectDuplicateKeys(in: line)) != nil,
                      let record = try? JSONDecoder().decode(DirectorShadowRecord.self, from: line) else { return nil }
                return Self.date(record.recordedAtUTC)
            }
            return ManagedFile(id: id, url: url, size: size, first: first)
        }
    }
    /// UTC rollback cannot extend retention. History is shared with renewed
    /// sessions in this process; after restart, future stored UTC still fails
    /// validation. This is not a trusted wall-clock or durable clock ledger.
    private func referenceUTC() throws -> Date {
        let now = utcClock()
        guard now.timeIntervalSince1970.isFinite,
              let canonical = Self.date(Self.utcString(now)) else { throw Failure.invalidClock }
        if let previous = clockHistory.latest, now < previous {
            for entry in try managedFiles() { try removeManaged(entry) }
            closed = true
            throw Failure.clockRollback
        }
        clockHistory.latest = now
        return canonical
    }

    private func removeManaged(_ entry: ManagedFile) throws {
        try FileManager.default.removeItem(at: entry.url)
        lock.withLock { counters.prunedFiles = Self.adding(counters.prunedFiles, 1) }
        if entry.id == sessionID { closed = true }
    }

    /// Only this writer's strict UUID filename namespace is managed. Corrupt
    /// owned headers have no defensible retention origin and are removed.
    @discardableResult private func prune(at reference: Date? = nil) throws -> Int {
        let now: Date
        if let reference { now = reference } else { now = try referenceUTC() }
        let cutoff = now.addingTimeInterval(-Self.retention)
        var removed = 0
        for entry in try managedFiles() where entry.first == nil || entry.first! <= cutoff || entry.first! > now {
            try removeManaged(entry)
            removed += 1
        }
        return removed
    }
    private func makeSpace(for bytes: Int) throws {
        var files = try managedFiles()
        var total = files.reduce(0) { sum, entry in
            sum > Int.max - entry.size ? Int.max : sum + entry.size
        }
        files.sort { ($0.first ?? .distantPast, $0.url.lastPathComponent) < ($1.first ?? .distantPast, $1.url.lastPathComponent) }
        for entry in files where total > limits.maximumStoreBytes - bytes && entry.url.lastPathComponent != Self.name(sessionID) {
            try FileManager.default.removeItem(at: entry.url); total -= entry.size
            lock.withLock { counters.prunedFiles = Self.adding(counters.prunedFiles, 1) }
        }
        guard total <= limits.maximumStoreBytes - bytes else { throw Failure.unavailable }
    }
    private func write(_ original: DirectorShadowRecord, queuedLoss: UInt64) throws {
        let now = try referenceUTC()
        try prune(at: now)
        guard !closed, let date = Self.date(original.recordedAtUTC), date <= now,
              date > now.addingTimeInterval(-Self.retention),
              lastDate.map({ date >= $0 }) ?? true,
              lastSequence.map({ original.sequence.value > $0 }) ?? true,
              !recordIDs.contains(original.recordID.value) else { throw Failure.unavailable }
        let loss = Self.adding(queuedLoss, writeLoss)
        let record = original.withDroppedRecords(Self.adding(original.droppedRecordsBefore.value, loss))
        var data = try JSONEncoder().encode(record); data.append(10)
        guard data.count <= limits.maximumRecordBytes, fileBytes <= limits.maximumFileBytes - data.count else { throw Failure.unavailable }
        try makeSpace(for: data.count)
        if !created {
            try data.write(to: fileURL, options: .withoutOverwriting)
            created = true
        } else {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unavailable }
            let handle = try FileHandle(forWritingTo: fileURL); defer { try? handle.close() }
            guard try handle.seekToEnd() == UInt64(fileBytes) else { throw Failure.unavailable }
            do { try handle.write(contentsOf: data) }
            catch { try? handle.truncate(atOffset: UInt64(fileBytes)); closed = true; throw error }
        }
        fileBytes += data.count; lastDate = date; lastSequence = original.sequence.value
        recordIDs.insert(original.recordID.value)
        writeLoss = 0
        lock.withLock { counters.written = Self.adding(counters.written, 1) }
    }

    #if DEBUG
    func holdWritesForTesting(until release: DispatchSemaphore) async {
        await withCheckedContinuation { continuation in
            queue.async { @Sendable in continuation.resume(); release.wait() }
        }
    }
    #endif

    /// FIFO barrier for tests/owner-requested flush; no physical durability claim.
    func flush() async {
        await withCheckedContinuation { continuation in queue.async { @Sendable in continuation.resume() } }
    }
    func maintain() async {
        await withCheckedContinuation { continuation in
            queue.async { @Sendable [self] in do { _ = try prune() } catch { storageError() }; continuation.resume() }
        }
    }
    func finish() async {
        await withCheckedContinuation { continuation in queue.async { @Sendable [self] in closed = true; continuation.resume() } }
    }

    private struct RetainedRecord {
        let value: DirectorShadowRecord
        let utc: Date
        let line: Data
    }

    /// Open a regular source without following a substituted final symlink,
    /// and bound the read before allocating an unbounded Data value.
    private func readSession(_ entry: ManagedFile, at now: Date) throws -> [RetainedRecord] {
        guard entry.size > 0, entry.size <= limits.maximumFileBytes else { throw Failure.resourceLimit }
        let descriptor = Darwin.open(entry.url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.invalidSource }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_size >= 0, metadata.st_size <= Int64(limits.maximumFileBytes) else { throw Failure.resourceLimit }
        var data = Data()
        while data.count < limits.maximumFileBytes {
            let part = try handle.read(upToCount: limits.maximumFileBytes - data.count) ?? Data()
            if part.isEmpty { break }
            data.append(part)
        }
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw Failure.resourceLimit }
        guard data.last == 10 else { throw Failure.invalidSource }
        var previousSequence: UInt64?, previousUTC: Date?, ids = Set<UUID>()
        var records: [RetainedRecord] = []
        for line in data.split(separator: 10, omittingEmptySubsequences: false).dropLast() {
            guard !line.isEmpty, line.count < limits.maximumRecordBytes else { throw Failure.resourceLimit }
            try Self.rejectDuplicateKeys(in: Data(line))
            let record = try JSONDecoder().decode(DirectorShadowRecord.self, from: Data(line))
            guard record.sessionID.value == entry.id,
                  previousSequence.map({ record.sequence.value > $0 }) ?? true,
                  ids.insert(record.recordID.value).inserted else { throw Failure.invalidSource }
            guard let date = Self.date(record.recordedAtUTC), date <= now,
                  date > now.addingTimeInterval(-Self.retention),
                  previousUTC.map({ date >= $0 }) ?? true else { throw Failure.invalidSourceClock }
            previousSequence = record.sequence.value; previousUTC = date
            var original = Data(line); original.append(10)
            records.append(.init(value: record, utc: date, line: original))
        }
        guard !records.isEmpty else { throw Failure.invalidSource }
        return records
    }

    /// Codable containers discard duplicate keys. Check the original JSON
    /// spelling (including escaped keys) and schema integer tokens before
    /// copying any original bytes; an ignored duplicate value must never
    /// carry private text into export.
    private static func rejectDuplicateKeys(in data: Data) throws {
        let bytes = Array(data)
        var objects: [Set<String>] = [], index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123: objects.append([]); index += 1 // {
            case 125: // }
                guard !objects.isEmpty else { throw Failure.invalidSource }
                objects.removeLast(); index += 1
            case 34: // JSON string; escaped quotes stay inside this token.
                let start = index
                index += 1
                var closed = false
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { index += 1; closed = true; break }
                    index += 1
                }
                guard closed else { throw Failure.invalidSource }
                var next = index
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == 58 {
                    guard !objects.isEmpty else { throw Failure.invalidSource }
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                    guard objects[objects.count - 1].insert(key).inserted else { throw Failure.invalidSource }
                    // Foundation can decode 1.0/1e0 as Int; the strict offline
                    // reader requires an integer JSON token for these fields.
                    // UInt64 counters remain strings and are not inspected here.
                    if ["schemaVersion", "preferencesVersion", "observedPersonCount", "acceptedRank", "judgementIndex", "featureSchemaVersion", "candidateRank"].contains(key) {
                        var value = next + 1
                        while value < bytes.count && [9, 10, 13, 32].contains(bytes[value]) { value += 1 }
                        var end = value
                        while end < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[end]) { end += 1 }
                        guard !bytes[value..<end].contains(where: { [46, 69, 101].contains($0) }) else { throw Failure.invalidSource }
                    }
                }
            default: index += 1
            }
        }
        guard objects.isEmpty else { throw Failure.invalidSource }
    }

    private func boundedFiles() throws -> [ManagedFile] {
        let files = try managedFiles().sorted { $0.id.uuidString < $1.id.uuidString }
        var total = 0
        for file in files {
            guard file.size >= 0, file.size <= limits.maximumStoreBytes - total else { throw Failure.resourceLimit }
            total += file.size
        }
        return files
    }

    /// A bounded, validated inventory after pending writes and expiry cleanup.
    /// Excluded/pruned file counts never pretend to count unknown lost rows.
    func retainedSessions() async throws -> DirectorShadowInventory {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { @Sendable [self] in
                do {
                    let now = try referenceUTC()
                    var pruned = try prune(at: now), excluded = 0
                    var summaries: [DirectorShadowSessionSummary] = []
                    for file in try boundedFiles() {
                        do {
                            let rows = try readSession(file, at: now)
                            let classes = Set(rows.map { $0.value.evidenceClass.rawValue })
                            summaries.append(.init(id: file.id, firstUTC: rows[0].utc, lastUTC: rows[rows.count - 1].utc,
                                recordCount: rows.count, evidenceClasses: DirectorShadowRecord.EvidenceClass.allCases
                                    .filter { classes.contains($0.rawValue) }.sorted { $0.rawValue < $1.rawValue }))
                        } catch Failure.invalidSourceClock {
                            try removeManaged(file); pruned += 1
                        } catch {
                            excluded += 1
                        }
                    }
                    continuation.resume(returning: .init(sessions: summaries, excludedFiles: excluded, prunedFiles: pruned))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Refuse source descendants/aliases and every existing destination,
    /// including dangling symlinks. The chosen parent must already exist.
    private func validateDestination(_ proposed: URL) throws -> URL {
        guard proposed.isFileURL else { throw Failure.invalidDestination }
        let destination = proposed.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let sourceParts = directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard !resolvedParent.pathComponents.starts(with: sourceParts),
              try resolvedParent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw Failure.invalidDestination
        }
        do {
            _ = try FileManager.default.attributesOfItem(atPath: destination.path)
            throw Failure.invalidDestination
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            // A genuinely absent final path is the only admissible target.
        }
        return destination
    }

    /// Publish both fixed members together. renamex_np(RENAME_EXCL) refuses
    /// even a destination that appears after validation; an unsuccessful
    /// operation removes its private staging directory and leaves no bundle.
    private func publish(records: Data, manifest: Data, to destination: URL) throws {
        let stage = destination.deletingLastPathComponent()
            .appendingPathComponent(".director-export-\(UUID().uuidString).tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        try records.write(to: stage.appendingPathComponent("records.jsonl"), options: .withoutOverwriting)
        try manifest.write(to: stage.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        #if DEBUG
        if failBeforePublishingForTesting { throw Failure.unavailable }
        #endif
        guard renamex_np(stage.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw Failure.invalidDestination }
    }

    #if DEBUG
    /// Deterministic failure after both staging members exist. No live UI sets it.
    var failBeforePublishingForTesting = false
    #endif

    /// Explicit operator export. Session inventory is advisory: selected
    /// sources are revalidated now, and a missing/corrupt one refuses the
    /// whole bundle rather than silently exporting a plausible subset.
    func export(selection: DirectorShadowExportSelection, toNewBundle proposed: URL) async throws -> DirectorShadowExportResult {
        guard selection.isValid else { throw Failure.invalidSelection }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { @Sendable [self] in
                do {
                    let now = try referenceUTC(), pruned = try prune(at: now)
                    let destination = try validateDestination(proposed)
                    let files = try boundedFiles().filter { selection.sessionIDs.contains($0.id) }
                    guard Set(files.map(\.id)) == selection.sessionIDs else { throw Failure.invalidSource }
                    var selected: [DirectorShadowRecord] = [], data = Data(), ids = Set<UUID>(), omitted = 0
                    for file in files {
                        let rows: [RetainedRecord]
                        do { rows = try readSession(file, at: now) }
                        catch Failure.invalidSourceClock { try removeManaged(file); throw Failure.invalidSourceClock }
                        for row in rows {
                            guard ids.insert(row.value.recordID.value).inserted else { throw Failure.invalidSource }
                            guard row.utc >= selection.fromUTC, row.utc <= selection.throughUTC else { omitted += 1; continue }
                            guard row.line.count <= limits.maximumStoreBytes - data.count else { throw Failure.resourceLimit }
                            data.append(row.line); selected.append(row.value)
                        }
                    }
                    guard !selected.isEmpty else { throw Failure.emptySelection }
                    let manifest = try DirectorShadowExportManifest(records: selected, exportedAtUTC: now)
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try publish(records: data, manifest: encoder.encode(manifest), to: destination)
                    continuation.resume(returning: .init(manifest: manifest, omittedOutsideSelection: omitted,
                                                         excludedFiles: 0, prunedFiles: pruned))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Legacy unbundled JSONL export. It has no companion manifest or visible
    /// selection; operator-facing export uses the explicit bundle API above.
    func export(session: UUID, to proposed: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { @Sendable [self] in
                do {
                    let now = try referenceUTC(); try prune(at: now)
                    let destination = try validateDestination(proposed)
                    guard let file = try boundedFiles().first(where: { $0.id == session }) else { throw Failure.invalidSource }
                    let rows = try readSession(file, at: now)
                    var data = Data()
                    for row in rows { data.append(row.line) }
                    try data.write(to: destination, options: .withoutOverwriting)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

}

nonisolated private extension DirectorShadowRecord {
    func withDroppedRecords(_ count: UInt64) -> Self {
        .init(schemaVersion: schemaVersion, recordID: recordID, sessionID: sessionID, sequence: sequence,
              recordedAtUTC: recordedAtUTC, eventTime: eventTime, evidenceClass: evidenceClass,
              executionMode: executionMode, context: context, parameters: parameters, evidence: evidence,
              judgements: judgements, event: event, invalidFields: invalidFields, droppedRecordsBefore: .init(count), scorerInputs: scorerInputs)
    }
}
