//
//  DirectorPreferencesStore.swift
//  CinematicCoreMacOS
//
//  C-04. Versioned style JSON in Application Support. Reads go through
//  DirectorPreferences.migrate, so an unknown or old file fails closed.
//  The file never stores an authority level.
//

import Foundation

struct DirectorPreferencesStore: Equatable, Sendable {
    var fileURL: URL

    static func applicationSupportFile() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("Alfie", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("DirectorPreferences.json")
    }

    enum LoadResult: Equatable {
        case empty
        case loaded(DirectorPreferences)
        /// Plain words for the settings screen. The stored file is not used.
        case unreadable(String)
    }

    static let unreadableMessage = "This style file can't be read. Alfie is not using it."

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: fileURL)
            return .loaded(try DirectorPreferences.migrate(data))
        } catch {
            return .unreadable(Self.unreadableMessage)
        }
    }

    func save(_ preferences: DirectorPreferences) throws {
        let validated = try preferences.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
