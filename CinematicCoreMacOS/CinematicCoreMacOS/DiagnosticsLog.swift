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

// MARK: - Metric definitions
//
// Every number Alfie records names the pipeline stage it measures, its unit,
// the window it covers and where it comes from. The CSV header and every row
// are generated from `DiagnosticsLog.columns`, so a column cannot exist
// without a definition, and the per-session manifest carries the same table.
//
// These types live in this file (not a new one) because DiagnosticsLog.swift
// is also compiled into the CMIO extension target alongside
// ProgramOutputManager.swift; nothing here may reference app-only types.

/// Pipeline stage a metric belongs to, in frame order.
nonisolated enum MetricStage: String, Codable, Sendable, CaseIterable {
    /// Row bookkeeping: time, window length, window kind.
    case session
    /// Process-wide: thermal, CPU, threads, memory.
    case system
    /// AVCapture dropped the frame before Alfie's delegate received it.
    case captureUpstream = "capture_upstream"
    /// The capture delegate received the frame (admitted + gate-skipped).
    case delivered
    /// The frame passed the one-frame processing gate and entered processFrame.
    case admitted
    /// Vision detection work and observation freshness.
    case detection
    /// Crop render on the admitted frame.
    case render
    /// What the crop is sampling (picture-quality context).
    case picture
    /// A program frame was offered to the output manager.
    case routed
    /// The active route's sink accepted (or refused) the frame.
    case handoff
    /// An accepted handoff that re-sent the last good render (HOLD).
    case repeated
    /// Physical or consumer presentation. Not observable from the app.
    case presented
    /// Cost of the diagnostics themselves.
    case instrumentation
}

/// Definition of one recorded number.
nonisolated struct MetricColumn: Codable, Equatable, Sendable {
    let name: String
    let stage: MetricStage
    let unit: String
    let window: String
    let provenance: String
}

/// Kind of CSV row. `partial` is the window Stop flushed early.
nonisolated enum DiagnosticsWindowKind: String, Codable, Sendable {
    case full
    case partial
    case marker
}

/// Session-relative frame counts per stage. Plain value type: the frame path
/// increments fields on a stored copy; a window is the difference of two
/// snapshots.
nonisolated struct PipelineCounters: Equatable, Sendable {
    var admitted = 0
    var gateSkipped: UInt64 = 0
    var captureDropped = 0
    var renderFailed = 0
    var routed = 0
    var noRoute = 0
    var handoffAccepted = 0
    var handoffRefused = 0
    var repeated = 0

    /// Frames the capture delegate received: admitted plus gate-skipped.
    var delivered: UInt64 { UInt64(admitted) &+ gateSkipped }

    /// Field-wise difference, for one window. Counters only grow within a
    /// session, so a smaller later value means a reset; report it as zero.
    func since(_ earlier: PipelineCounters) -> PipelineCounters {
        func diff(_ now: Int, _ then: Int) -> Int { max(0, now - then) }
        return PipelineCounters(
            admitted: diff(admitted, earlier.admitted),
            gateSkipped: gateSkipped >= earlier.gateSkipped ? gateSkipped - earlier.gateSkipped : 0,
            captureDropped: diff(captureDropped, earlier.captureDropped),
            renderFailed: diff(renderFailed, earlier.renderFailed),
            routed: diff(routed, earlier.routed),
            noRoute: diff(noRoute, earlier.noRoute),
            handoffAccepted: diff(handoffAccepted, earlier.handoffAccepted),
            handoffRefused: diff(handoffRefused, earlier.handoffRefused),
            repeated: diff(repeated, earlier.repeated))
    }
}

/// Everything ProgramOutputManager measured for one window. System columns
/// (thermal, CPU, threads) are sampled by DiagnosticsLog when the row is
/// written.
nonisolated struct DiagnosticsWindow: Equatable, Sendable {
    var kind: DiagnosticsWindowKind = .full
    var windowSeconds: Double = 0
    var footprintMB: Double = 0
    var sourceHeight = 0
    var cropHeightFraction: Double = 0
    var upscale: Double = 0
    var hopMeanMS: Double = 0
    var hopMaxMS: Double = 0
    var queueMeanMS: Double = 0
    var queueMaxMS: Double = 0
    var visionMeanMS: Double = 0
    var visionMaxMS: Double = 0
    var frameMeanMS: Double = 0
    var frameMaxMS: Double = 0
    var detections = 0
    var mainMeanMS: Double = 0
    var mainMaxMS: Double = 0
    var observationMeanMS: Double = 0
    var observationMaxMS: Double = 0
    var processedInputFPS: Double = 0
    var window = PipelineCounters()
    var totals = PipelineCounters()
    var emitMS: Double = 0

    var detectorFPS: Double { windowSeconds > 0 ? Double(detections) / windowSeconds : 0 }
    var handoffFPS: Double { windowSeconds > 0 ? Double(window.handoffAccepted) / windowSeconds : 0 }
}

/// Process-wide sample taken when a row is written.
nonisolated struct DiagnosticsSystemSample: Equatable, Sendable {
    var thermal: String
    var lowPower: Bool
    var cpuCores: Double
    var threads: Int
}

/// Who and what a diagnostics session measured. Written into the session
/// manifest so every number can be traced to a build, a source and a route.
nonisolated struct DiagnosticsSessionIdentity: Codable, Equatable, Sendable {
    struct Build: Codable, Equatable, Sendable {
        var appVersion: String
        var buildNumber: String
        var sourceFingerprint: String
        var osVersion: String
        var machineModel: String
    }

    struct Source: Codable, Equatable, Sendable {
        /// "Live camera" or "Validation clip".
        var inputKind: String
        var deviceName: String?
        var deviceModelID: String?
        /// "stage" or "webcam" (CaptureProfilePolicy profile).
        var captureProfile: String?
        var requestedWidth: Int?
        var requestedHeight: Int?
        /// Capture rate Alfie configured on the device.
        var configuredCaptureFPS: Double?
        /// CaptureProfilePolicy selection reason, as text.
        var captureSelectionReason: String?
        /// Webcam mode running below the show rate (`webcamBelowShowRate`).
        var belowShowRate: Bool
        /// Dimensions of the frames actually delivered (may differ from requested).
        var deliveredWidth: Int?
        var deliveredHeight: Int?

        static let unrecorded = Source(inputKind: "unrecorded", belowShowRate: false)
    }

    struct Output: Codable, Equatable, Sendable {
        var route: String?
        var showStandard: String
        var showFPS: Double
        /// The route's own playout clock, if it has one.
        var playoutFPS: Double?
        /// What "handoff" means on this route and why presentation is unknown.
        var presentation: String
    }

    var build: Build
    var source: Source
    var output: Output
}

/// Sidecar JSON written next to each session's CSVs.
nonisolated struct DiagnosticsManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    struct Closing: Codable, Equatable, Sendable {
        var endedAt: String
        var note: String
        var windowsWritten: Int
        var partialWindowFlushed: Bool
        /// MainActor time spent aggregating rows (excludes the async file write).
        var emitMeanMS: Double
        var emitMaxMS: Double
    }

    var schemaVersion = currentSchemaVersion
    var csvFile: String
    var memoryFile: String
    var startedAt: String
    var identity: DiagnosticsSessionIdentity
    var columns: [MetricColumn]
    /// Stages Alfie cannot observe; their numbers are reported as unknown.
    var unobservable: [String]
    var closing: Closing?
}

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

    /// Write a whole small file (the session manifest), replacing any previous
    /// version. Same serial queue, so it never races the CSV appends.
    func replace(url: URL, data: Data) {
        queue.async { @Sendable in
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
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
            for url in urls where DiagnosticsLog.isPrunable(url) {
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

    /// Session CSVs and their `alfie_session_*.json` manifests age out
    /// together; a manifest left behind keeps the capture device's name and
    /// model (CR-025).
    nonisolated static func isPrunable(_ url: URL) -> Bool {
        url.pathExtension == "csv"
            || (url.pathExtension == "json" && url.lastPathComponent.hasPrefix("alfie_session_"))
    }

    static func openInFinder() {
        let directory = Self.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    /// Column order and definitions. `elapsed_s` is the column to sort by when
    /// hunting the onset; `thermal` is the column that confirms or kills the
    /// throttling hypothesis without needing `sudo powermetrics`. Existing
    /// column names are kept so older spreadsheets still line up by name; the
    /// old mixed `out_drops_*` columns are now split by stage.
    nonisolated static let columns: [MetricColumn] = {
        let row = "row window (~5 s; see window_s)"
        let rowMean = "row window, mean over frames"
        let rowMax = "row window, max over frames"
        let atClose = "instant at row close"
        let total = "cumulative since capture start"
        let lastFrame = "last admitted frame in the row window"
        func c(_ name: String, _ stage: MetricStage, _ unit: String, _ window: String, _ provenance: String) -> MetricColumn {
            MetricColumn(name: name, stage: stage, unit: unit, window: window, provenance: provenance)
        }
        return [
            c("elapsed_s", .session, "s", atClose, "host monotonic clock since the capture's first processed frame; the 'detection start' note marks when Vision load began"),
            c("clock", .session, "HH:mm:ss", atClose, "local wall clock"),
            c("window_kind", .session, "full|partial|marker", row, "partial = window flushed early by Stop; marker = event row with no measurements"),
            c("thermal", .system, "state", atClose, "ProcessInfo.thermalState"),
            c("low_power", .system, "yes|no", atClose, "ProcessInfo.isLowPowerModeEnabled"),
            c("cpu_cores", .system, "CPU-seconds per second", row, "task_info thread times, differenced across the window"),
            c("cpu_pct", .system, "%", row, "cpu_cores × 100 (Activity Monitor scale)"),
            c("threads", .system, "count", atClose, "task_threads"),
            c("source_h", .picture, "px", lastFrame, "delivered capture buffer height"),
            c("crop_h_frac", .picture, "fraction of source height", lastFrame, "CropEngine current crop"),
            c("upscale", .picture, "×", lastFrame, "output height ÷ (source_h × crop_h_frac)"),
            c("footprint_mb", .system, "MB", atClose, "task_vm_info phys_footprint"),
            c("hop_mean_ms", .admitted, "ms", rowMean, "capture callback enqueue → MainActor frame start"),
            c("hop_max_ms", .admitted, "ms", rowMax, "capture callback enqueue → MainActor frame start"),
            c("queue_mean_ms", .detection, "ms", rowMean, "detection dispatch queue wait"),
            c("queue_max_ms", .detection, "ms", rowMax, "detection dispatch queue wait"),
            c("vision_mean_ms", .detection, "ms", rowMean, "Vision request wall time"),
            c("vision_max_ms", .detection, "ms", rowMax, "Vision request wall time"),
            c("frame_wall_mean_ms", .admitted, "ms", rowMean, "processFrame wall time incl. awaited off-main render"),
            c("frame_wall_max_ms", .admitted, "ms", rowMax, "processFrame wall time incl. awaited off-main render"),
            c("detections", .detection, "count", row, "Vision runs completed"),
            c("frames_window", .handoff, "frames", row, "frames the active route's sink accepted (includes repeats)"),
            c("frames_total", .handoff, "frames", total, "frames the active route's sink accepted (includes repeats)"),
            c("handoff_refused_window", .handoff, "frames", row, "frames the active route's sink refused"),
            c("handoff_refused_total", .handoff, "frames", total, "frames the active route's sink refused"),
            c("gate_drops_window", .delivered, "frames", row, "delivered frames skipped by the one-frame processing gate"),
            c("gate_drops_total", .delivered, "frames", total, "delivered frames skipped by the one-frame processing gate"),
            c("main_active_mean_ms", .admitted, "ms", rowMean, "MainActor busy time per admitted frame"),
            c("main_active_max_ms", .admitted, "ms", rowMax, "MainActor busy time per admitted frame"),
            c("observation_age_mean_ms", .detection, "ms", rowMean, "detection capture → consumption by the composer"),
            c("observation_age_max_ms", .detection, "ms", rowMax, "detection capture → consumption by the composer"),
            c("processed_input_fps", .admitted, "fps", "rolling 2 s at row close", "source PTS of admitted frames"),
            c("detector_fps", .detection, "fps", row, "detections ÷ window_s"),
            c("handoff_fps", .handoff, "fps", row, "frames_window ÷ window_s; host handoff, not presentation"),
            c("window_s", .session, "s", row, "host monotonic length of this window"),
            c("delivered_window", .delivered, "frames", row, "admitted_window + gate_drops_window"),
            c("admitted_window", .admitted, "frames", row, "frames that entered processFrame"),
            c("capture_dropped_window", .captureUpstream, "frames", row, "AVCapture didDrop callbacks (lost before delivery)"),
            c("capture_dropped_total", .captureUpstream, "frames", total, "AVCapture didDrop callbacks (lost before delivery)"),
            c("render_failed_window", .render, "frames", row, "crop renders that failed (HOLD re-sends last good)"),
            c("render_failed_total", .render, "frames", total, "crop renders that failed (HOLD re-sends last good)"),
            c("routed_window", .routed, "frames", row, "program frames offered to the output manager"),
            c("no_route_window", .routed, "frames", row, "program frames produced while no output route was active"),
            c("repeated_window", .repeated, "frames", row, "accepted handoffs that re-sent the last good render"),
            c("repeated_total", .repeated, "frames", total, "accepted handoffs that re-sent the last good render"),
            c("presented_fps", .presented, "fps", row, "always 'unknown': display compositor and virtual-camera consumer do not report presentation"),
            c("diag_emit_ms", .instrumentation, "ms", row, "MainActor time to aggregate this row (file write is async, excluded)"),
            c("note", .session, "text", row, "operator / pipeline markers since the previous row"),
        ]
    }()

    nonisolated static var header: String {
        columns.map(\.name).joined(separator: ",") + "\n"
    }

    /// What is never observable from inside the app, recorded in every manifest.
    nonisolated static let alwaysUnobservable = [
        "ATEM / downstream switcher acquisition, cadence and tally",
        "physical display scan-out time",
        "end-to-end glass-to-glass latency",
    ]

    /// Columns for the memory-growth file.
    ///
    /// The point of this row is to answer one question: *what kind* of memory is
    /// growing? Each group discriminates a different suspect.
    ///
    /// - `heap_mb` / `heap_blocks` — the app's own allocations. If `heap_blocks`
    ///   climbs steadily, objects are accumulating and we can go find them. If it
    ///   stays flat while `footprint_mb` climbs, the growth is NOT ours: it is
    ///   image/GPU memory held below the allocator, which points at Core Image's
    ///   caches in `CropEngine.processCrop`.
    /// - `internal_mb` / `compressed_mb` / `external_mb` — the same split as
    ///   Activity Monitor. `external` covers IOSurface-backed frame buffers, so
    ///   growth there means frames are being retained somewhere.
    /// - the collection counts — the Swift arrays on the frame path. Static code
    ///   review says all four are bounded; these columns prove it in a live run
    ///   rather than taking the review's word for it.
    private static let memoryHeader = """
        elapsed_s,clock,footprint_mb,internal_mb,compressed_mb,external_mb,\
        heap_mb,heap_blocks,latency_samples,drop_timestamps,input_timestamps,\
        detected_persons,frames_total,note

        """

    private let writer = DiagnosticsFileWriter()

    /// Second file, same folder and same 5 s cadence, dedicated to the memory
    /// growth investigation. Kept separate from the throughput CSV so neither
    /// chart has to carry the other's columns.
    private let memoryWriter = DiagnosticsFileWriter()

    private var sessionStart: TimeInterval = 0
    private var isOpen = false

    /// Previous CPU sample, so each row reports the average over that window
    /// rather than a meaningless instantaneous reading.
    private var lastCPUSeconds: Double = 0
    private var lastCPUSampleAt: TimeInterval = 0

    /// Free-text markers recorded since the last row, emitted in that row's
    /// `note` column. Bounded: a runaway caller can't grow this unboundedly
    /// because it is cleared on every emit, and appends are capped per window.
    private var pendingNotes: [String] = []
    /// Same markers, consumed separately so both files carry them — each file is
    /// emitted on its own row and clears its own queue.
    private var pendingMemoryNotes: [String] = []
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

    private var manifest: DiagnosticsManifest?
    private var manifestURL: URL?
    private var windowsWritten = 0
    private var partialWindowFlushed = false
    private var emitSumMS: Double = 0
    private var emitMaxMS: Double = 0

    private static let isoFormatter = ISO8601DateFormatter()

    func beginSession(note: String, identity: DiagnosticsSessionIdentity? = nil) {
        guard !isOpen else { return }
        let stamp = Self.fileStampFormatter.string(from: Date())
        let name = "alfie_soak_\(stamp).csv"
        let url = Self.directory.appendingPathComponent(name)
        // Same folder, same timestamp, so the set from one run is obvious.
        let memoryName = "alfie_memory_\(stamp).csv"
        let memoryURL = Self.directory.appendingPathComponent(memoryName)

        writer.open(url: url, header: Self.header)
        memoryWriter.open(url: memoryURL, header: Self.memoryHeader)
        writer.prune(directory: Self.directory, olderThan: 30)

        sessionStart = CACurrentMediaTime()
        lastCPUSeconds = Self.processCPUSeconds()
        lastCPUSampleAt = sessionStart
        isOpen = true
        currentFileName = name
        pendingNotes = []
        pendingMemoryNotes = []
        windowsWritten = 0
        partialWindowFlushed = false
        emitSumMS = 0
        emitMaxMS = 0

        if let identity {
            let manifest = DiagnosticsManifest(
                csvFile: name,
                memoryFile: memoryName,
                startedAt: Self.isoFormatter.string(from: Date()),
                identity: identity,
                columns: Self.columns,
                unobservable: Self.alwaysUnobservable + [identity.output.presentation])
            let manifestURL = Self.directory.appendingPathComponent("alfie_session_\(stamp).json")
            self.manifest = manifest
            self.manifestURL = manifestURL
            writeManifest()
        } else {
            manifest = nil
            manifestURL = nil
        }

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
        pendingMemoryNotes = []
        appendMarkerRow(closing)
        if manifest != nil {
            manifest?.closing = DiagnosticsManifest.Closing(
                endedAt: Self.isoFormatter.string(from: Date()),
                note: note,
                windowsWritten: windowsWritten,
                partialWindowFlushed: partialWindowFlushed,
                emitMeanMS: windowsWritten > 0 ? emitSumMS / Double(windowsWritten) : 0,
                emitMaxMS: emitMaxMS)
            writeManifest()
        }
        isOpen = false
        currentFileName = nil
        manifest = nil
        manifestURL = nil
        writer.close()
        memoryWriter.close()
    }

    private func writeManifest() {
        guard let manifest, let manifestURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return }
        writer.replace(url: manifestURL, data: data)
    }

    /// A row carrying only the timing/thermal columns and a note. Measurement
    /// columns are left empty so these markers don't distort a chart of the
    /// real windows.
    private func appendMarkerRow(_ text: String) {
        let processInfo = ProcessInfo.processInfo
        let fields = Self.markerFields(
            elapsed: CACurrentMediaTime() - sessionStart,
            clock: Self.clockFormatter.string(from: Date()),
            thermal: Self.thermalStateName(processInfo.thermalState),
            lowPower: processInfo.isLowPowerModeEnabled,
            note: text)
        writer.append(fields.joined(separator: ",") + "\n")
    }

    /// Record a marker (capture start, lock acquired, route change) to appear in
    /// the next row's `note` column.
    func note(_ text: String) {
        guard isOpen, pendingNotes.count < Self.maxNotesPerWindow else { return }
        pendingNotes.append(text)
        pendingMemoryNotes.append(text)
    }

    // MARK: Row emission

    /// One row per soak window. All pipeline values are computed by
    /// `ProgramOutputManager.emitSoakLineIfDue`; only the process-wide system
    /// sample (thermal, CPU, threads) is taken here.
    func appendRow(_ window: DiagnosticsWindow) {
        guard isOpen else { return }

        let now = CACurrentMediaTime()
        let processInfo = ProcessInfo.processInfo
        let noteField = pendingNotes.isEmpty ? "" : pendingNotes.joined(separator: "; ")
        pendingNotes = []

        // Average CPU over this window. `cores` is CPU-seconds per wall second —
        // 1.0 means one core saturated, 3.5 means three and a half cores' worth.
        let cpuNow = Self.processCPUSeconds()
        let cpuWindowSeconds = lastCPUSampleAt > 0 ? now - lastCPUSampleAt : 0
        let cpuCores = cpuWindowSeconds > 0 ? (cpuNow - lastCPUSeconds) / cpuWindowSeconds : 0
        lastCPUSeconds = cpuNow
        lastCPUSampleAt = now

        let system = DiagnosticsSystemSample(
            thermal: Self.thermalStateName(processInfo.thermalState),
            lowPower: processInfo.isLowPowerModeEnabled,
            cpuCores: cpuCores,
            threads: Self.liveThreadCount())
        let fields = Self.rowFields(
            elapsed: now - sessionStart,
            clock: Self.clockFormatter.string(from: Date()),
            system: system,
            window: window,
            note: noteField)
        writer.append(fields.joined(separator: ",") + "\n")

        windowsWritten += 1
        if window.kind == .partial { partialWindowFlushed = true }
        emitSumMS += window.emitMS
        emitMaxMS = max(emitMaxMS, window.emitMS)
    }

    /// CSV fields for one measured row, in `columns` order. Pure so tests can
    /// check it against the column table.
    nonisolated static func rowFields(
        elapsed: Double,
        clock: String,
        system: DiagnosticsSystemSample,
        window w: DiagnosticsWindow,
        note: String
    ) -> [String] {
        func f(_ value: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", value) }
        return [
            f(elapsed, 1), clock, w.kind.rawValue,
            system.thermal, system.lowPower ? "yes" : "no",
            f(system.cpuCores), f(system.cpuCores * 100, 0), String(system.threads),
            String(w.sourceHeight), f(w.cropHeightFraction, 4), f(w.upscale), f(w.footprintMB, 0),
            f(w.hopMeanMS), f(w.hopMaxMS),
            f(w.queueMeanMS), f(w.queueMaxMS),
            f(w.visionMeanMS), f(w.visionMaxMS),
            f(w.frameMeanMS), f(w.frameMaxMS),
            String(w.detections),
            String(w.window.handoffAccepted), String(w.totals.handoffAccepted),
            String(w.window.handoffRefused), String(w.totals.handoffRefused),
            String(w.window.gateSkipped), String(w.totals.gateSkipped),
            f(w.mainMeanMS), f(w.mainMaxMS),
            f(w.observationMeanMS), f(w.observationMaxMS),
            f(w.processedInputFPS), f(w.detectorFPS), f(w.handoffFPS), f(w.windowSeconds, 3),
            String(w.window.delivered), String(w.window.admitted),
            String(w.window.captureDropped), String(w.totals.captureDropped),
            String(w.window.renderFailed), String(w.totals.renderFailed),
            String(w.window.routed), String(w.window.noRoute),
            String(w.window.repeated), String(w.totals.repeated),
            "unknown",
            f(w.emitMS, 3),
            csvEscaped(note),
        ]
    }

    /// CSV fields for a marker row: time, kind, thermal and note; every
    /// measurement column empty.
    nonisolated static func markerFields(
        elapsed: Double, clock: String, thermal: String, lowPower: Bool, note: String
    ) -> [String] {
        columns.map { column in
            switch column.name {
            case "elapsed_s": return String(format: "%.1f", elapsed)
            case "clock": return clock
            case "window_kind": return DiagnosticsWindowKind.marker.rawValue
            case "thermal": return thermal
            case "low_power": return lowPower ? "yes" : "no"
            case "note": return csvEscaped(note)
            default: return ""
            }
        }
    }

    /// Build and host identity for the manifest.
    nonisolated static func currentBuildIdentity() -> DiagnosticsSessionIdentity.Build {
        let bundle = Bundle.main
        let fingerprint = (bundle.object(forInfoDictionaryKey: "AlfieSourceFingerprint") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? "unrecorded"
        return DiagnosticsSessionIdentity.Build(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            sourceFingerprint: fingerprint,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            machineModel: machineModel())
    }

    nonisolated static func machineModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    /// One row per soak window in the memory file. Counts are pushed in by the
    /// callers that own those collections; nothing is measured on the frame path.
    func appendMemoryRow(
        latencySamples: Int,
        dropTimestamps: Int,
        inputTimestamps: Int,
        detectedPersons: Int,
        framesTotal: Int
    ) {
        guard isOpen else { return }

        let elapsed = CACurrentMediaTime() - sessionStart
        let vm = Self.vmBreakdown()
        let heap = Self.heapStats()
        let noteField = pendingMemoryNotes.isEmpty ? "" : pendingMemoryNotes.joined(separator: "; ")
        pendingMemoryNotes = []

        let row = String(
            format: "%.1f,%@,%.0f,%.0f,%.0f,%.0f,%.1f,%llu,%d,%d,%d,%d,%d,%@\n",
            elapsed,
            Self.clockFormatter.string(from: Date()),
            vm.footprintMB, vm.internalMB, vm.compressedMB, vm.externalMB,
            heap.megabytes, heap.blocks,
            latencySamples, dropTimestamps, inputTimestamps,
            detectedPersons, framesTotal,
            Self.csvEscaped(noteField)
        )
        memoryWriter.append(row)
    }

    /// Memory split the same way Activity Monitor splits it.
    nonisolated static func vmBreakdown() -> (
        footprintMB: Double, internalMB: Double, compressedMB: Double, externalMB: Double
    ) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0, 0) }
        let mb = 1024.0 * 1024.0
        return (
            Double(info.phys_footprint) / mb,
            Double(info.internal) / mb,
            Double(info.compressed) / mb,
            Double(info.external) / mb
        )
    }

    /// Allocator totals for the default malloc zone. `blocks` is the count of
    /// live allocations — the single most useful number here, because a steady
    /// climb means objects are accumulating rather than image memory growing.
    nonisolated static func heapStats() -> (megabytes: Double, blocks: UInt64) {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(malloc_default_zone(), &stats)
        return (Double(stats.size_in_use) / (1024.0 * 1024.0), UInt64(stats.blocks_in_use))
    }

    /// Cumulative CPU time consumed by the whole process, live threads plus
    /// already-exited ones. Differenced across a window it gives true average
    /// load, which is far more useful than an instantaneous sample: a pipeline
    /// that pins a core in bursts and a pipeline that sits at half a core look
    /// identical in a snapshot and completely different here.
    nonisolated static func processCPUSeconds() -> Double {
        func seconds(_ value: time_value_t) -> Double {
            Double(value.seconds) + Double(value.microseconds) / 1_000_000.0
        }

        var total: Double = 0

        // Live threads.
        var threadTimes = task_thread_times_info_data_t()
        var threadCount = mach_msg_type_number_t(
            MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let threadResult = withUnsafeMutablePointer(to: &threadTimes) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(threadCount)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), intPtr, &threadCount)
            }
        }
        if threadResult == KERN_SUCCESS {
            total += seconds(threadTimes.user_time) + seconds(threadTimes.system_time)
        }

        // Threads that have already exited — without this, work done on
        // short-lived Dispatch threads simply vanishes from the total.
        var basic = task_basic_info_64_data_t()
        var basicCount = mach_msg_type_number_t(
            MemoryLayout<task_basic_info_64_data_t>.size / MemoryLayout<natural_t>.size
        )
        let basicResult = withUnsafeMutablePointer(to: &basic) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO_64), intPtr, &basicCount)
            }
        }
        if basicResult == KERN_SUCCESS {
            total += seconds(basic.user_time) + seconds(basic.system_time)
        }

        return total
    }

    /// Live thread count. Worth recording alongside CPU: runaway Dispatch thread
    /// creation shows up here first, and it drives both CPU burn and latency.
    nonisolated static func liveThreadCount() -> Int {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS,
              let threads else {
            return 0
        }
        // task_threads vends a send right per thread plus the array itself; both
        // must be released or this diagnostic becomes its own leak.
        for index in 0..<Int(count) {
            mach_port_deallocate(mach_task_self_, threads[index])
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(Int(count) * MemoryLayout<thread_t>.size)
        )
        return Int(count)
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
