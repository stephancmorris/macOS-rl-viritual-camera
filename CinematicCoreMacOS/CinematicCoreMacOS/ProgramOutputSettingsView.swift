//
//  ProgramOutputSettingsView.swift
//  CinematicCoreMacOS
//

import SwiftUI

struct ProgramOutputSettingsView<SystemExtensionManager: SystemExtensionStatusProviding>: View {
    @ObservedObject var programOutput: ProgramOutputManager
    @ObservedObject var systemExtensionManager: SystemExtensionManager

    /// Persisted show standard, as a raw string so it survives relaunch and is
    /// read back by CameraManager at capture start.
    @AppStorage(ShowStandard.userDefaultsKey) private var showStandardRaw = ShowStandard.p50.rawValue

    /// Persisted Program Display target, as a `CGDirectDisplayID` stored as an
    /// Int (0 = "use default"). Read back live by `DisplayOutputSink`. `Int`
    /// because @AppStorage has no UInt32 binding; the sink casts to
    /// `CGDirectDisplayID`.
    @AppStorage(ProgramDisplaySelection.userDefaultsKey) private var programDisplayID = 0

    /// Snapshot of currently attached displays, refreshed whenever the display
    /// arrangement changes so the picker stays in sync with hot-plug events.
    @State private var availableDisplays: [ProgramDisplayOption] = ProgramDisplayOption.current()

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

                Text("Must match the ATEM switcher's video standard. Applies after the show stops and starts again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Active Route", value: programOutput.activeRouteTitle)

                Text(programOutput.routingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if programOutput.configuredRoutes.contains(.display) {
                Section("Direct output (HDMI / USB-C)") {
                    Picker("Output port", selection: $programDisplayID) {
                        ForEach(availableDisplays) { option in
                            Text(option.label).tag(option.id)
                        }
                    }

                    Text("Pick the port your HDMI-to-SDI converter or ATEM is plugged into. A picked port is reserved while this output is selected: it shows black until the show starts, then Program. At Start, Alfie switches it to the show standard (e.g. 1080p50) and macOS restores its own setting when you switch output or quit. Turn on Focus / Do Not Disturb so notifications can't reach the feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didChangeScreenParametersNotification
                    )
                ) { _ in
                    availableDisplays = ProgramDisplayOption.current()
                }
            }

            Section("Diagnostics") {
                LabeledContent("Session Log") {
                    Button("Open in Finder") {
                        DiagnosticsLog.openInFinder()
                    }
                    .buttonStyle(.borderless)
                }

                LabeledContent(
                    "Recording To",
                    value: programOutput.diagnosticsFileName ?? "Not Capturing"
                )

                LabeledContent(
                    "Thermal State",
                    value: DiagnosticsLog.thermalStateName(ProcessInfo.processInfo.thermalState)
                        .capitalized
                )

                Text("A CSV row is written every ~5 s while capture is running: memory, frame timings, dropped frames, and the system thermal state. Open the folder after a session and chart the columns against elapsed_s to see where and why throughput fell off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
#endif
