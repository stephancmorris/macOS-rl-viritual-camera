//
//  ProgramOutputDiagnostics.swift
//  CinematicCoreMacOS
//

import Foundation
import OSLog
import SwiftUI

enum AlfieDiagnosticsLog {
    private static let queue = DispatchQueue(label: "com.alfie.diagnostics-log")

    static var fileURL: URL {
        let logsDirectory = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Alfie", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Alfie", isDirectory: true)

        return logsDirectory.appendingPathComponent("alfie-diagnostics.log")
    }

    /// Size at which the log rolls over to `alfie-diagnostics.1.log`. One
    /// previous file is kept, so the pair never exceeds twice this (CR-012).
    nonisolated static let maxFileBytes: UInt64 = 2 * 1024 * 1024

    static func append(_ category: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"

        queue.async {
            do {
                try write(line, to: fileURL, maxBytes: maxFileBytes)
            } catch {
                Logger(subsystem: "com.alfie", category: "DiagnosticsFile")
                    .error("Failed to append diagnostics log: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The rotated copy of `url`: `name.log` → `name.1.log`.
    nonisolated static func rotatedURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("1").appendingPathExtension(url.pathExtension)
    }

    /// Append `line`, first rolling the file over when it has reached
    /// `maxBytes`. Synchronous; `append` calls it on the log queue.
    nonisolated static func write(_ line: String, to url: URL, maxBytes: UInt64) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size >= maxBytes {
            let rotated = rotatedURL(for: url)
            try? fileManager.removeItem(at: rotated)
            try fileManager.moveItem(at: url, to: rotated)
        }

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

enum OutputCheckLevel {
    case ok
    case info
    case warning
    case error

    var title: String {
        switch self {
        case .ok:
            return "OK"
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }

    var color: Color {
        switch self {
        case .ok:
            return .green
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct OutputBringUpCheck: Identifiable {
    let id: String
    let title: String
    let status: String
    let detail: String
    let level: OutputCheckLevel
}
