import Foundation

/// C-07 local authoring storage. A show is an opaque UUID, never a show name
/// or arbitrary filename. This stores only A-13's versioned run-sheet value;
/// it cannot restore a Director level, qualification or runtime authority.
nonisolated struct RunSheetStore: Sendable {
    let directory: URL

    init(directory: URL) { self.directory = directory.standardizedFileURL }

    enum LoadResult: Equatable {
        case empty
        case loaded(RunSheet)
        case unreadable(String)
    }

    enum Failure: Error, Equatable { case unreadableExistingFile, invalidFile }

    static let unreadableMessage = "This show's run sheet can't be read. Alfie is not using it, and the saved file has been kept."

    func fileURL(for showID: UUID) -> URL {
        directory.appendingPathComponent("run-sheet-\(showID.uuidString).json", isDirectory: false)
    }

    func load(showID: UUID) -> LoadResult {
        let file = fileURL(for: showID)
        do {
            guard try directoryExists() else { return .empty }
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
                return .empty
            }
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidFile }
            return .loaded(try Self.decode(Data(contentsOf: file)))
        } catch {
            return .unreadable(Self.unreadableMessage)
        }
    }

    /// Validate before touching disk, and refuse to replace an unreadable or
    /// future file. An operator may repair/remove that file separately, then
    /// reload. Save never silently clears it or stores an authority value.
    func save(_ sheet: RunSheet, showID: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sheet)
        _ = try Self.decode(data)
        if case .unreadable = load(showID: showID) { throw Failure.unreadableExistingFile }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directoryExists() else { throw Failure.invalidFile }
        try data.write(to: fileURL(for: showID), options: .atomic)
    }

    private func directoryExists() throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: directory.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return false
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidFile }
        return true
    }

    /// The underlying model validates version, IDs, current selection and
    /// authored types. Refuse unknown storage keys too, so a newer payload or
    /// unrelated authority data is not silently accepted and then discarded.
    private static func decode(_ data: Data) throws -> RunSheet {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "segments", "currentSegmentID"]),
              let segments = object["segments"] as? [[String: Any]],
              segments.allSatisfy({ Set($0.keys).isSubset(of: ["id", "type", "name", "positionHint"]) }) else {
            throw Failure.invalidFile
        }
        return try JSONDecoder().decode(RunSheet.self, from: data)
    }
}
