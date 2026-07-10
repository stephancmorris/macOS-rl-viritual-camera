//
//  ProgramOutputManager.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 4/20/2026.
//

import Combine
import CoreGraphics
import CoreVideo
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

    static func append(_ category: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"

        queue.async {
            let url = fileURL
            let directory = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                } else {
                    try line.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                Logger(subsystem: "com.alfie", category: "DiagnosticsFile")
                    .error("Failed to append diagnostics log: \(error.localizedDescription, privacy: .public)")
            }
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

@MainActor
protocol SystemExtensionStatusProviding: ObservableObject {
    var badgeTitle: String { get }
    var summaryText: String { get }
    var primaryActionTitle: String? { get }
    var primaryActionSystemImage: String { get }
    var outputCheckLevel: OutputCheckLevel { get }

    func triggerPrimaryAction() async
}

@MainActor
protocol ProgramOutputSink: AnyObject {
    var route: ProgramOutputManager.Route { get }
    var isAvailable: Bool { get }
    var summary: String { get }
    var detail: String { get }
    var lastErrorDescription: String? { get }
    var lastFrameSendDuration: TimeInterval? { get }
    var canReconnect: Bool { get }
    var reconnectStatus: String? { get }
    var bringUpChecks: [OutputBringUpCheck] { get }
    /// The fixed hardware playout rate of this route, if it has one. `nil`
    /// for routes with no clock of their own (e.g. the virtual camera, which
    /// is drained at whatever rate the consuming app pulls frames).
    var playoutFrameRate: Double? { get }
    var onStateChange: (() -> Void)? { get set }

    func connect()
    func disconnect()
    func reconnect()
    func updateCaptureStatus(isRunning: Bool)
    @discardableResult
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool
}

extension ProgramOutputSink {
    var lastFrameSendDuration: TimeInterval? { nil }
    var canReconnect: Bool { false }
    var reconnectStatus: String? { nil }
    var bringUpChecks: [OutputBringUpCheck] { [] }
    var playoutFrameRate: Double? { nil }
    func reconnect() {}
}

@MainActor
final class ProgramOutputManager: ObservableObject {
    private let logger = Logger(subsystem: "com.alfie", category: "ProgramOutput")

    enum LatencyStage: String, CaseIterable, Identifiable {
        case detection
        case compose
        case cropRender
        case xpcSend
        case total

        var id: String { rawValue }

        var title: String {
            switch self {
            case .detection:
                return "Detection"
            case .compose:
                return "Compose"
            case .cropRender:
                return "Crop Render"
            case .xpcSend:
                return "XPC Send"
            case .total:
                return "Total"
            }
        }
    }

    struct StageLatency: Identifiable {
        let stage: LatencyStage
        let averageDuration: TimeInterval

        var id: LatencyStage { stage }
    }

    private struct TimedDuration {
        let timestamp: TimeInterval
        let duration: TimeInterval
    }

    enum Route: String, CaseIterable, Identifiable {
        case virtualCamera
        case blackmagicSDI

        var id: String { rawValue }

        var title: String {
            switch self {
            case .virtualCamera:
                return "Virtual Camera"
            case .blackmagicSDI:
                return "Blackmagic SDI"
            }
        }

        var systemImage: String {
            switch self {
            case .virtualCamera:
                return "video.badge.waveform"
            case .blackmagicSDI:
                return "cable.connector"
            }
        }
    }

    enum StatusLevel {
        case active
        case standby
        case unavailable
        case error

        var title: String {
            switch self {
            case .active:
                return "Active"
            case .standby:
                return "Standby"
            case .unavailable:
                return "Unavailable"
            case .error:
                return "Error"
            }
        }

        var color: Color {
            switch self {
            case .active:
                return .green
            case .standby:
                return .secondary
            case .unavailable:
                return .orange
            case .error:
                return .red
            }
        }
    }

    struct SinkStatus: Identifiable {
        let route: Route
        let level: StatusLevel
        let summary: String
        let detail: String

        var id: Route { route }
    }

    @Published var preferredRoute: Route = .blackmagicSDI {
        didSet {
            refreshRoutingDecision()
        }
    }

    @Published private(set) var activeRoute: Route?
    @Published private(set) var sinkStatuses: [SinkStatus] = []
    @Published private(set) var framesSent: Int = 0
    @Published private(set) var droppedFrames: Int = 0
    @Published private(set) var dropRatePerMinute: Double = 0
    @Published private(set) var lastFrameSize: CGSize?
    @Published private(set) var lastFrameTimestamp: Double?
    @Published private(set) var lastDropTimestamp: Double?
    @Published private(set) var lastDropReason: String?
    @Published private(set) var stageLatencies: [StageLatency] = []
    @Published private(set) var bringUpChecks: [OutputBringUpCheck] = []

    /// Frame rate actually delivered by the capture side, measured over a
    /// rolling window of capture timestamps. This is the number that proves
    /// (or disproves) that the input chain matches the playout clock — the
    /// device's advertised format is not trustworthy here.
    @Published private(set) var measuredInputFPS: Double = 0

    /// Playout clock of the active route, if it has one (the DeckLink runs a
    /// fixed hardware clock; the virtual camera has none). Drives the HUD
    /// mismatch tint and the frame-rate bring-up check.
    var activePlayoutFrameRate: Double? {
        activeSink?.playoutFrameRate
    }

    private let sinks: [any ProgramOutputSink]
    private var isCaptureRunning = false
    private var dropTimestamps: [Double] = []
    private var latencySamples: [LatencyStage: [TimedDuration]] = [:]
    private var inputFrameTimestamps: [Double] = []
    private static let inputRateWindow: Double = 2.0

    // Per-frame counters land here (plain storage), NOT in the @Published
    // properties above. Every @Published mutation fires objectWillChange on the
    // MainActor — the same thread that owns the 20 ms frame budget — and
    // sendFrame/recordLatency run 50–250×/sec. Publishing each one forced
    // SwiftUI to re-evaluate observers at frame rate, which is exactly the kind
    // of contention that makes the pipeline blow its budget the moment a
    // settings window is open. The published snapshots are refreshed from this
    // raw state by `refreshPublishedStatsIfDue()` at most every
    // `statsRefreshInterval` seconds.
    private var rawFramesSent: Int = 0
    private var rawDroppedFrames: Int = 0
    private var rawLastFrameSize: CGSize?
    private var rawLastFrameTimestamp: Double?
    private var rawLastDropTimestamp: Double?
    private var rawLastDropReason: String?
    private var lastStatsRefresh: TimeInterval = 0
    private let statsRefreshInterval: TimeInterval = 0.5

    init(sinks: [any ProgramOutputSink] = []) {
        self.sinks = sinks
        self.sinks.forEach { sink in
            sink.onStateChange = { [weak self] in
                self?.refreshRoutingDecision()
            }
        }
        refreshRoutingDecision()
    }

    func start() {
        framesSent = 0
        droppedFrames = 0
        dropRatePerMinute = 0
        lastFrameSize = nil
        lastFrameTimestamp = nil
        lastDropTimestamp = nil
        lastDropReason = nil
        rawFramesSent = 0
        rawDroppedFrames = 0
        rawLastFrameSize = nil
        rawLastFrameTimestamp = nil
        rawLastDropTimestamp = nil
        rawLastDropReason = nil
        lastStatsRefresh = 0
        dropTimestamps = []
        latencySamples = [:]
        stageLatencies = []
        inputFrameTimestamps = []
        measuredInputFPS = 0
        sinks.forEach { $0.connect() }
        refreshRoutingDecision()
    }

    func stop() {
        isCaptureRunning = false
        sinks.forEach {
            $0.updateCaptureStatus(isRunning: false)
            $0.disconnect()
        }
        activeRoute = nil
        // Final flush so the HUD shows the session's closing numbers rather
        // than whatever the last coalesced refresh happened to capture.
        refreshPublishedStatsIfDue(force: true)
    }

    func updateCaptureStatus(isRunning: Bool) {
        let previousActiveSink = activeSink
        isCaptureRunning = isRunning
        if !isRunning {
            previousActiveSink?.updateCaptureStatus(isRunning: false)
        }
        refreshRoutingDecision()
        if isRunning {
            activeSink?.updateCaptureStatus(isRunning: true)
        }
        refreshStatuses()
    }

    func sendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double) {
        guard let activeSink else {
            refreshPublishedStatsIfDue()
            return
        }

        rawLastFrameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        rawLastFrameTimestamp = timestamp

        let didSend = activeSink.sendFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        if !didSend {
            recordDroppedFrame(
                timestamp: timestamp,
                reason: "Active output route did not accept the frame."
            )
            return
        }
        if let sendDuration = activeSink.lastFrameSendDuration {
            recordLatency(stage: .xpcSend, duration: sendDuration)
        }
        rawFramesSent += 1
        refreshPublishedStatsIfDue()
    }

    func recordDroppedFrame(timestamp: Double, reason: String) {
        rawDroppedFrames += 1
        rawLastDropTimestamp = timestamp
        rawLastDropReason = reason
        dropTimestamps.append(timestamp)
        trimDropTimestamps(relativeTo: timestamp)
        logger.warning("Dropped frame: \(reason, privacy: .public)")
        refreshPublishedStatsIfDue()
    }

    /// Called once per delivered capture frame with the frame's presentation
    /// timestamp. Accumulate only (frame path — no @Published mutation here);
    /// `measuredInputFPS` is rebuilt by the coalesced refresh.
    func recordInputFrame(timestamp: Double) {
        // A backwards timestamp means the source restarted (e.g. a looping
        // validation clip); start the window over rather than mixing epochs.
        if let last = inputFrameTimestamps.last, timestamp < last {
            inputFrameTimestamps.removeAll()
        }
        inputFrameTimestamps.append(timestamp)
        let windowStart = timestamp - Self.inputRateWindow
        inputFrameTimestamps.removeAll { $0 < windowStart }
    }

    func recordLatency(
        stage: LatencyStage,
        duration: TimeInterval,
        timestamp: TimeInterval = CACurrentMediaTime()
    ) {
        // Accumulate only; the published `stageLatencies` snapshot is rebuilt by
        // the coalesced refresh, not on every sample (~250 samples/sec arrive here).
        var samples = latencySamples[stage, default: []]
        samples.append(TimedDuration(timestamp: timestamp, duration: duration))
        let windowStart = timestamp - 5
        samples.removeAll { $0.timestamp < windowStart }
        latencySamples[stage] = samples
    }

    /// Copies the per-frame raw counters into the @Published snapshots at most
    /// once per `statsRefreshInterval`. This is the only place frame-cadence
    /// data is allowed to touch a @Published property.
    private func refreshPublishedStatsIfDue(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastStatsRefresh >= statsRefreshInterval else { return }
        lastStatsRefresh = now

        framesSent = rawFramesSent
        droppedFrames = rawDroppedFrames
        dropRatePerMinute = Double(dropTimestamps.count)
        lastFrameSize = rawLastFrameSize
        lastFrameTimestamp = rawLastFrameTimestamp
        lastDropTimestamp = rawLastDropTimestamp
        lastDropReason = rawLastDropReason
        // Must precede refreshBringUpChecks() below — the frame-rate-match
        // check reads this snapshot.
        if inputFrameTimestamps.count >= 2,
           let first = inputFrameTimestamps.first,
           let last = inputFrameTimestamps.last,
           last > first {
            measuredInputFPS = Double(inputFrameTimestamps.count - 1) / (last - first)
        } else {
            measuredInputFPS = 0
        }
        refreshLatencySnapshot()
        refreshStatuses()
        refreshBringUpChecks()
    }

    var activeRouteTitle: String {
        activeRoute?.title ?? "No Active Output"
    }

    var configuredRoutes: [Route] {
        sinks.map(\.route)
    }

    var routingSummary: String {
        guard isCaptureRunning else {
            return "\(preferredRoute.title) is selected and will carry the processed feed when capture is running."
        }

        guard let activeRoute else {
            return "No output route is active."
        }

        if activeRoute == preferredRoute {
            return "\(activeRoute.title) is carrying the processed program feed."
        }

        return "\(preferredRoute.title) is not available yet, so output is falling back to \(activeRoute.title)."
    }

    var preferredSinkCanReconnect: Bool {
        sink(for: preferredRoute)?.canReconnect ?? false
    }

    var preferredSinkReconnectStatus: String? {
        sink(for: preferredRoute)?.reconnectStatus
    }

    func reconnectPreferredRoute() {
        let sink = sink(for: preferredRoute)
        logger.notice(
            "Reconnect Output pressed; preferredRoute=\(self.preferredRoute.title, privacy: .public); activeRoute=\(self.activeRoute?.title ?? "none", privacy: .public); sinkAvailable=\((sink?.isAvailable ?? false), privacy: .public); sinkSummary=\(sink?.summary ?? "missing", privacy: .public); sinkDetail=\(sink?.detail ?? "missing", privacy: .public); sinkError=\(sink?.lastErrorDescription ?? "none", privacy: .public)"
        )
        AlfieDiagnosticsLog.append(
            "ProgramOutput",
            "Reconnect Output pressed preferredRoute=\(preferredRoute.title) activeRoute=\(activeRoute?.title ?? "none") sinkAvailable=\(sink?.isAvailable ?? false) sinkSummary=\(sink?.summary ?? "missing") sinkDetail=\(sink?.detail ?? "missing") sinkError=\(sink?.lastErrorDescription ?? "none")"
        )
        sink?.reconnect()
        refreshStatuses()
        refreshBringUpChecks()
    }

    private var activeSink: (any ProgramOutputSink)? {
        guard let activeRoute else { return nil }
        return sink(for: activeRoute)
    }

    private func sink(for route: Route) -> (any ProgramOutputSink)? {
        sinks.first { $0.route == route }
    }

    private func refreshRoutingDecision() {
        let previousRoute = activeRoute
        let preferredSink = sink(for: preferredRoute)
        let resolvedRoute: Route?
        if let preferredSink, preferredSink.isAvailable {
            resolvedRoute = preferredRoute
        } else if let fallbackSink = sink(for: .virtualCamera), fallbackSink.isAvailable {
            resolvedRoute = .virtualCamera
        } else {
            resolvedRoute = nil
        }

        activeRoute = isCaptureRunning ? resolvedRoute : nil

        if previousRoute != activeRoute {
            if let previousRoute, let previousSink = sink(for: previousRoute) {
                previousSink.updateCaptureStatus(isRunning: false)
            }
            if isCaptureRunning, let activeRoute, let currentSink = sink(for: activeRoute) {
                currentSink.updateCaptureStatus(isRunning: true)
            }
        }

        refreshStatuses()
        refreshBringUpChecks()
    }

    private func refreshStatuses() {
        sinkStatuses = sinks.map { sink in
            let level: StatusLevel
            if sink.lastErrorDescription != nil {
                level = .error
            } else if sink.route == activeRoute {
                level = .active
            } else if sink.isAvailable {
                level = .standby
            } else {
                level = .unavailable
            }

            return SinkStatus(
                route: sink.route,
                level: level,
                summary: sink.summary,
                detail: sink.detail
            )
        }
    }

    private func trimDropTimestamps(relativeTo timestamp: Double) {
        let windowStart = timestamp - 60
        dropTimestamps.removeAll { $0 < windowStart }
    }

    private func refreshLatencySnapshot() {
        stageLatencies = LatencyStage.allCases.compactMap { stage in
            guard let samples = latencySamples[stage], !samples.isEmpty else { return nil }
            let total = samples.reduce(0) { $0 + $1.duration }
            return StageLatency(stage: stage, averageDuration: total / Double(samples.count))
        }
    }

    private func refreshBringUpChecks() {
        var checks = sinks.flatMap(\.bringUpChecks)
        // Frame-rate match: input faster than the playout clock pins the
        // hardware queue at its cap (standing latency) and back-pressure drops
        // the surplus (judder); slower means the hardware repeats frames.
        if let playoutRate = activeSink?.playoutFrameRate, measuredInputFPS > 0 {
            let matched = abs(measuredInputFPS - playoutRate) <= 0.5
            checks.append(
                OutputBringUpCheck(
                    id: "programOutput.frameRateMatch",
                    title: "Program Feed · Frame Rate Match",
                    status: String(format: "In %.2f fps · out %g fps", measuredInputFPS, playoutRate),
                    detail: matched
                        ? "Capture delivery matches the playout clock."
                        : String(
                            format: "Capture is delivering %.2f fps but the output plays out at %g fps. Align the camera/capture chain with the output standard.",
                            measuredInputFPS,
                            playoutRate
                        ),
                    level: matched ? .ok : .warning
                )
            )
        }
        bringUpChecks = checks
    }
}

struct ProgramOutputSettingsView<SystemExtensionManager: SystemExtensionStatusProviding>: View {
    @ObservedObject var programOutput: ProgramOutputManager
    @ObservedObject var systemExtensionManager: SystemExtensionManager

    /// Persisted show standard, as a raw string so it survives relaunch and is
    /// read back by CameraManager/BlackmagicOutputSink at capture start.
    @AppStorage(ShowStandard.userDefaultsKey) private var showStandardRaw = ShowStandard.p50.rawValue

    var body: some View {
        Form {
            Section("Output Route") {
                Picker("Preferred Route", selection: $programOutput.preferredRoute) {
                    ForEach(programOutput.configuredRoutes) { route in
                        Label(route.title, systemImage: route.systemImage)
                            .tag(route)
                    }
                }

                Picker("Show Standard", selection: $showStandardRaw) {
                    ForEach(ShowStandard.allCases) { standard in
                        Text(standard.title).tag(standard.rawValue)
                    }
                }

                Text("Must match the ATEM switcher's video standard. Applies the next time capture starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Active Route", value: programOutput.activeRouteTitle)

                Text(programOutput.routingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Program Feed") {
                LabeledContent("Frames Sent", value: "\(programOutput.framesSent)")
                LabeledContent("Dropped Frames", value: "\(programOutput.droppedFrames)")
                LabeledContent(
                    "Drop Rate",
                    value: String(format: "%.0f/min", programOutput.dropRatePerMinute)
                )

                if let size = programOutput.lastFrameSize {
                    LabeledContent(
                        "Last Frame",
                        value: "\(Int(size.width))×\(Int(size.height))"
                    )
                } else {
                    LabeledContent("Last Frame", value: "None Yet")
                }

                if let timestamp = programOutput.lastFrameTimestamp {
                    LabeledContent(
                        "Last Timestamp",
                        value: String(format: "%.3fs", timestamp)
                    )
                }

                if let lastDropTimestamp = programOutput.lastDropTimestamp {
                    LabeledContent(
                        "Last Drop",
                        value: String(format: "%.3fs", lastDropTimestamp)
                    )
                }

                if let lastDropReason = programOutput.lastDropReason {
                    Text(lastDropReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !programOutput.stageLatencies.isEmpty {
                Section("Latency (Last 5 Seconds)") {
                    ForEach(programOutput.stageLatencies, id: \.id) { latency in
                        LabeledContent(
                            latency.stage.title,
                            value: String(format: "%.1f ms", latency.averageDuration * 1000)
                        )
                    }
                }
            }

            Section("Bring-Up Checklist") {
                bringUpCheckRow(
                    title: "Virtual Camera Extension",
                    status: systemExtensionManager.badgeTitle,
                    detail: systemExtensionManager.summaryText,
                    level: systemExtensionManager.outputCheckLevel
                )

                if let actionTitle = systemExtensionManager.primaryActionTitle {
                    Button {
                        Task { await systemExtensionManager.triggerPrimaryAction() }
                    } label: {
                        Label(actionTitle, systemImage: systemExtensionManager.primaryActionSystemImage)
                    }
                }

                ForEach(programOutput.bringUpChecks) { check in
                    bringUpCheckRow(
                        title: check.title,
                        status: check.status,
                        detail: check.detail,
                        level: check.level
                    )
                }
            }

            Section("Sink Health") {
                ForEach(programOutput.sinkStatuses, id: \.id) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(status.route.title, systemImage: status.route.systemImage)
                            Spacer()
                            Text(status.level.title)
                                .foregroundStyle(status.level.color)
                        }

                        Text(status.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(status.detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if programOutput.preferredSinkCanReconnect {
                Section("Recovery") {
                    Button {
                        programOutput.reconnectPreferredRoute()
                    } label: {
                        Label("Reconnect Output", systemImage: "arrow.clockwise.circle")
                    }

                    if let reconnectStatus = programOutput.preferredSinkReconnectStatus {
                        Text(reconnectStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Force the preferred output route to tear down the current XPC connection and reconnect immediately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }

    @ViewBuilder
    private func bringUpCheckRow(
        title: String,
        status: String,
        detail: String,
        level: OutputCheckLevel
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(status)
                    .foregroundStyle(level.color)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    ProgramOutputSettingsView(
        programOutput: ProgramOutputManager(sinks: [PreviewOutputSink()]),
        systemExtensionManager: PreviewSystemExtensionStatusManager()
    )
}

@MainActor
private final class PreviewOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .virtualCamera
    var isAvailable: Bool { true }
    var summary: String { "Preview route is available." }
    var detail: String { "Used only for the SwiftUI preview." }
    var lastErrorDescription: String? { nil }
    var canReconnect: Bool { false }
    var reconnectStatus: String? { nil }
    var bringUpChecks: [OutputBringUpCheck] {
        [
            OutputBringUpCheck(
                id: "preview.virtual.link",
                title: "Virtual Camera · XPC Link",
                status: "Preview",
                detail: "Preview output sink is active only inside SwiftUI previews.",
                level: .info
            )
        ]
    }
    var onStateChange: (() -> Void)?
    func connect() {}
    func disconnect() {}
    func reconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
}

@MainActor
private final class PreviewSystemExtensionStatusManager: ObservableObject, SystemExtensionStatusProviding {
    let badgeTitle = "Extension Ready"
    let summaryText = "Preview system extension manager is active only inside SwiftUI previews."
    let primaryActionTitle: String? = nil
    let primaryActionSystemImage = "checkmark.seal"
    let outputCheckLevel: OutputCheckLevel = .ok

    func triggerPrimaryAction() async {}
}
#endif
