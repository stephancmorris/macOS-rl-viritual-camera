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
import SwiftUI

@MainActor
protocol ProgramOutputSink: AnyObject {
    var route: ProgramOutputManager.Route { get }
    var isAvailable: Bool { get }
    var summary: String { get }
    var detail: String { get }
    var lastErrorDescription: String? { get }
    var canReconnect: Bool { get }
    var reconnectStatus: String? { get }
    var onStateChange: (() -> Void)? { get set }

    func connect()
    func disconnect()
    func reconnect()
    func updateCaptureStatus(isRunning: Bool)
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double)
}

extension ProgramOutputSink {
    var canReconnect: Bool { false }
    var reconnectStatus: String? { nil }
    func reconnect() {}
}

@MainActor
final class ProgramOutputManager: ObservableObject {

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

    @Published var preferredRoute: Route = .virtualCamera {
        didSet {
            refreshRoutingDecision()
        }
    }

    @Published private(set) var activeRoute: Route?
    @Published private(set) var sinkStatuses: [SinkStatus] = []
    @Published private(set) var framesSent: Int = 0
    @Published private(set) var lastFrameSize: CGSize?
    @Published private(set) var lastFrameTimestamp: Double?

    private let sinks: [any ProgramOutputSink]
    private var isCaptureRunning = false

    init(sinks: [any ProgramOutputSink] = []) {
        self.sinks = sinks
        self.sinks.forEach { sink in
            sink.onStateChange = { [weak self] in
                self?.refreshStatuses()
            }
        }
        refreshRoutingDecision()
    }

    func start() {
        framesSent = 0
        lastFrameSize = nil
        lastFrameTimestamp = nil
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
        refreshStatuses()
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
            refreshStatuses()
            return
        }

        lastFrameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        lastFrameTimestamp = timestamp

        activeSink.sendFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        framesSent += 1
        refreshStatuses()
    }

    var activeRouteTitle: String {
        activeRoute?.title ?? "No Active Output"
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
        sink(for: preferredRoute)?.reconnect()
        refreshStatuses()
    }

    private var activeSink: (any ProgramOutputSink)? {
        guard let activeRoute else { return nil }
        return sink(for: activeRoute)
    }

    private func sink(for route: Route) -> (any ProgramOutputSink)? {
        sinks.first { $0.route == route }
    }

    private func refreshRoutingDecision() {
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

        refreshStatuses()
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
}

struct ProgramOutputSettingsView: View {
    @ObservedObject var programOutput: ProgramOutputManager

    var body: some View {
        Form {
            Section("Output Route") {
                Picker("Preferred Route", selection: $programOutput.preferredRoute) {
                    ForEach(ProgramOutputManager.Route.allCases) { route in
                        Label(route.title, systemImage: route.systemImage)
                            .tag(route)
                    }
                }

                LabeledContent("Active Route", value: programOutput.activeRouteTitle)

                Text(programOutput.routingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Program Feed") {
                LabeledContent("Frames Sent", value: "\(programOutput.framesSent)")

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
            }

            Section("Sink Health") {
                ForEach(programOutput.sinkStatuses) { status in
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
}

#Preview {
    ProgramOutputSettingsView(programOutput: ProgramOutputManager(sinks: [PreviewOutputSink()]))
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
    var onStateChange: (() -> Void)?
    func connect() {}
    func disconnect() {}
    func reconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) {}
}
