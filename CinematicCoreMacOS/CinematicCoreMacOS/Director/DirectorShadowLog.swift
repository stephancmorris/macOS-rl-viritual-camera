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
    enum Failure: Error { case invalidLimits, unavailable, expired
        case invalidExport(String) }
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

    init(directory: URL, sessionID: UUID = UUID(), limits: Limits,
         utcClock: @escaping @Sendable () -> Date = { Date() }) throws {
        guard limits.isValid else { throw Failure.invalidLimits }
        self.directory = directory.standardizedFileURL; self.sessionID = sessionID
        self.limits = limits; self.utcClock = utcClock
        queue.async { @Sendable [self] in do { try prune() } catch { storageError() } }
    }

    @MainActor static func besideDiagnostics(limits: Limits) throws -> DirectorShadowLog {
        try .init(directory: DiagnosticsLog.directory, limits: limits)
    }

    var metrics: Metrics { lock.withLock { counters } }
    func recordingUTC() -> String { Self.utcString(utcClock()) }
    func renewed() throws -> DirectorShadowLog {
        try .init(directory: directory, limits: limits, utcClock: utcClock)
    }
    private var fileURL: URL { directory.appendingPathComponent(Self.name(sessionID)) }
    private static func name(_ id: UUID) -> String { "director_shadow_\(id.uuidString).jsonl" }
    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
    static func utcString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
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
    private func managedFiles() throws -> [(url: URL, size: Int, first: Date?)] {
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
                guard let record = try? JSONDecoder().decode(DirectorShadowRecord.self, from: prefix[..<end]) else { return nil }
                return Self.date(record.recordedAtUTC)
            }
            return (url, size, first)
        }
    }
    /// Only this writer's strict UUID filename namespace is managed. Corrupt
    /// owned headers have no defensible retention origin and are removed.
    private func prune() throws {
        let cutoff = utcClock().addingTimeInterval(-Self.retention)
        for entry in try managedFiles() where entry.first == nil || entry.first! <= cutoff || entry.first! > utcClock() {
            try FileManager.default.removeItem(at: entry.url)
            lock.withLock { counters.prunedFiles = Self.adding(counters.prunedFiles, 1) }
            if entry.url.lastPathComponent == Self.name(sessionID) { closed = true }
        }
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
        try prune()
        guard !closed, let date = Self.date(original.recordedAtUTC), date <= utcClock(),
              date > utcClock().addingTimeInterval(-Self.retention),
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
            queue.async { @Sendable [self] in do { try prune() } catch { storageError() }; continuation.resume() }
        }
    }
    func finish() async {
        await withCheckedContinuation { continuation in queue.async { @Sendable [self] in closed = true; continuation.resume() } }
    }

    /// Explicit local export only. Validate every retained line; preserve its
    /// original UTC/source class, and never overwrite a destination or upload.
    func export(session: UUID, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { @Sendable [self] in
                do {
                    try prune()
                    let source = directory.appendingPathComponent(Self.name(session))
                    guard destination.deletingLastPathComponent().resolvingSymlinksInPath().path != directory.resolvingSymlinksInPath().path,
                          let entry = try managedFiles().first(where: { $0.url.lastPathComponent == Self.name(session) }),
                          entry.size <= limits.maximumFileBytes else { throw Failure.invalidExport("source or destination") }
                    let data = try Data(contentsOf: source)
                    guard data.last == 10 else { throw Failure.invalidExport("unterminated record") }
                    var previous: UInt64?, ids = Set<UUID>()
                    for line in data.split(separator: 10, omittingEmptySubsequences: false).dropLast() {
                        let record = try JSONDecoder().decode(DirectorShadowRecord.self, from: Data(line))
                        guard record.sessionID.value == session, let date = Self.date(record.recordedAtUTC),
                              date > utcClock().addingTimeInterval(-Self.retention), date <= utcClock(),
                              previous.map({ record.sequence.value > $0 }) ?? true,
                              ids.insert(record.recordID.value).inserted else { throw Failure.invalidExport("record invariants") }
                        previous = record.sequence.value
                    }
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
              judgements: judgements, event: event, invalidFields: invalidFields, droppedRecordsBefore: .init(count))
    }
}
