//
//  DiagnosticsLog.swift
//  CinematicCoreMacOS
//
//  Session diagnostics recorder for the progressive-lag investigation.
//
//  Writes one CSV row every ~5 s — the same cadence as the `[SOAK]` log line,
//  driven from the same accumulators, so it adds no per-frame work. The whole
//  point of this file is to answer "why does Alfie slow down at ~4:35?" from a
//  spreadsheet after a show, instead of from Console during one.
//
//  Deliberately NOT a per-frame logger. Per-frame logging is what Task 1
//  removed: at 50 Hz it backs up `logd` and becomes part of the problem it is
//  trying to measure. One buffered append per 5 s is ~700 KB over a ten-hour
//  day and costs nothing on the frame path.
//

import AppKit
import Foundation
import OSLog

// MARK: - Off-main file appender

/// Serial, off-MainActor file appender.
///
/// `@unchecked Sendable` is sound because `handle` is only ever read or written
/// inside `queue`, which is serial. Every closure is explicitly `@Sendable`:
/// with `NonisolatedNonsendingByDefault` a bare `DispatchQueue.async` closure
/// is `nonisolated nonsending`, which resolves to the wrong overload.
private final class DiagnosticsFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.alfie.diagnostics.write", qos: .utility)
    private var handle: FileHandle?

    /// Create the file (writing `header` if it is new) and seek to the end.
    func open(url: URL, header: String) {
        queue.async { @Sendable in
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                return
            }
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: Data(header.utf8))
            }
            self.handle = try? FileHandle(forWritingTo: url)
            _ = try? self.handle?.seekToEnd()
        }
    }

    func append(_ line: String) {
        queue.async { @Sendable in
            guard let handle = self.handle else { return }
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    func close() {
        queue.async { @Sendable in
            try? self.handle?.synchronize()
            try? self.handle?.close()
            self.handle = nil
        }
    }

    /// Delete diagnostics files older than `days`. Runs on the write queue so it
    /// never touches the MainActor.
    func prune(directory: URL, olderThan days: Int) {
        queue.async { @Sendable in
            let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            let fileManager = FileManager.default
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
            for url in urls where url.pathExtension == "csv" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let modified, modified < cutoff {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
}

// MARK: - Session recorder

/// Per-session diagnostics CSV. One row per `[SOAK]` window (~5 s).
///
/// Owned by `ProgramOutputManager`, which already computes every number in the
/// row — this class only formats and writes them.
@MainActor
final class DiagnosticsLog {
    private static let logger = Logger(subsystem: "com.alfie", category: "Diagnostics")

    /// Diagnostics live beside the training data, in the app's own Documents
    /// folder. The app is sandboxed (`com.apple.security.app-sandbox`), so this
    /// resolves inside the container rather than to `~/Documents` — reachable
    /// via `openInFinder()`, which is why the Output settings tab has a button.
    static var directory: URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("CinematicCore/Diagnostics", isDirectory: true)
    }

    static func openInFinder() {
        let directory = Self.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    /// Column order. `elapsed_s` is the column to sort by when hunting the
    /// onset; `thermal` is the column that confirms or kills the throttling
    /// hypothesis without needing `sudo powermetrics`.
    private static let header = """
        elapsed_s,clock,thermal,low_power,footprint_mb,\
        hop_mean_ms,hop_max_ms,queue_mean_ms,queue_max_ms,vision_mean_ms,vision_max_ms,\
        detections,frames_window,frames_total,out_drops_window,out_drops_total,\
        gate_drops_window,gate_drops_total,note

        """

    private let writer = DiagnosticsFileWriter()
    private var sessionStart: TimeInterval = 0
    private var isOpen = false

    /// Free-text markers recorded since the last row, emitted in that row's
    /// `note` column. Bounded: a runaway caller can't grow this unboundedly
    /// because it is cleared on every emit, and appends are capped per window.
    private var pendingNotes: [String] = []
    private static let maxNotesPerWindow = 8

    /// Filename of the session in progress, for display in Settings.
    private(set) var currentFileName: String?

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()

    // MARK: Session lifecycle

    func beginSession(note: String) {
        guard !isOpen else { return }
        let stamp = Self.fileStampFormatter.string(from: Date())
        let name = "alfie_soak_\(stamp).csv"
        let url = Self.directory.appendingPathComponent(name)

        writer.open(url: url, header: Self.header)
        writer.prune(directory: Self.directory, olderThan: 30)

        sessionStart = CACurrentMediaTime()
        isOpen = true
        currentFileName = name
        pendingNotes = []
        // Marker row up front so the file is never empty and never undated,
        // even if the session dies before the first 5 s window closes.
        appendMarkerRow(note)
        Self.logger.notice("Diagnostics session started: \(name, privacy: .public)")
    }

    func endSession(note: String) {
        guard isOpen else { return }
        // A closing marker row, so the file records exactly when capture
        // stopped rather than just running out of rows. Any notes still pending
        // from the last partial window ride along instead of being lost.
        let closing = (pendingNotes + [note]).joined(separator: "; ")
        pendingNotes = []
        appendMarkerRow(closing)
        isOpen = false
        currentFileName = nil
        writer.close()
    }

    /// A row carrying only the timing/thermal columns and a note. Measurement
    /// columns are left empty so these markers don't distort a chart of the
    /// real windows.
    private func appendMarkerRow(_ text: String) {
        let elapsed = CACurrentMediaTime() - sessionStart
        let processInfo = ProcessInfo.processInfo
        // 15 commas span the 14 empty measurement columns and land on `note`.
        let emptyMeasurements = String(repeating: ",", count: 15)
        let row = String(
            format: "%.1f,%@,%@,%@%@%@\n",
            elapsed,
            Self.clockFormatter.string(from: Date()),
            Self.thermalStateName(processInfo.thermalState),
            processInfo.isLowPowerModeEnabled ? "yes" : "no",
            emptyMeasurements,
            Self.csvEscaped(text)
        )
        writer.append(row)
    }

    /// Record a marker (capture start, lock acquired, route change) to appear in
    /// the next row's `note` column.
    func note(_ text: String) {
        guard isOpen, pendingNotes.count < Self.maxNotesPerWindow else { return }
        pendingNotes.append(text)
    }

    // MARK: Row emission

    /// One row per soak window. All values are already computed by
    /// `ProgramOutputManager.emitSoakLineIfDue` — nothing is measured here.
    func appendRow(
        footprintMB: Double,
        hopMeanMS: Double,
        hopMaxMS: Double,
        queueMeanMS: Double,
        queueMaxMS: Double,
        visionMeanMS: Double,
        visionMaxMS: Double,
        detections: Int,
        framesWindow: Int,
        framesTotal: Int,
        outDropsWindow: Int,
        outDropsTotal: Int,
        gateDropsWindow: UInt64,
        gateDropsTotal: UInt64
    ) {
        guard isOpen else { return }

        let elapsed = CACurrentMediaTime() - sessionStart
        let processInfo = ProcessInfo.processInfo
        let noteField = pendingNotes.isEmpty ? "" : pendingNotes.joined(separator: "; ")
        pendingNotes = []

        let row = String(
            format: "%.1f,%@,%@,%@,%.0f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%llu,%llu,%@\n",
            elapsed,
            Self.clockFormatter.string(from: Date()),
            Self.thermalStateName(processInfo.thermalState),
            processInfo.isLowPowerModeEnabled ? "yes" : "no",
            footprintMB,
            hopMeanMS, hopMaxMS,
            queueMeanMS, queueMaxMS,
            visionMeanMS, visionMaxMS,
            detections,
            framesWindow, framesTotal,
            outDropsWindow, outDropsTotal,
            gateDropsWindow, gateDropsTotal,
            Self.csvEscaped(noteField)
        )
        writer.append(row)
    }

    /// The decisive signal for the throttling hypothesis. macOS reports this
    /// without any privileged access: if it walks nominal → fair → serious
    /// around the onset, sustained thermal pressure is confirmed in-app and no
    /// `powermetrics` run is needed to establish it.
    nonisolated static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private nonisolated static func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
