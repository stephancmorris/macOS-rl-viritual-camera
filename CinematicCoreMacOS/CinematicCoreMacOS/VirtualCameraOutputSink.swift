//
//  VirtualCameraOutputSink.swift
//  CinematicCoreMacOS
//

import CoreVideo
import Foundation
import IOSurface
import OSLog
import QuartzCore

@MainActor
final class VirtualCameraOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .virtualCamera
    private static let logger = Logger(subsystem: "com.alfie", category: "VirtualCameraOutput")
    private static let signposter = OSSignposter(logger: logger)

    private let xpcManager = XPCConnectionManager()
    private(set) var lastFrameSendDuration: TimeInterval?
    private var hasLoggedFirstFrameSend = false
    /// Set once the current session's show standard has been pushed to the
    /// extension, so the drain clock matches what this sink is sending.
    private var playoutHandshake = PlayoutRateHandshake()

    /// The XPC message carries only an IOSurfaceID — nothing on the extension
    /// side retains the backing CVPixelBuffer for us. The extension's frame
    /// queue can hold a frame for one playout interval per queued entry (the
    /// drain clock runs at the show standard, e.g. 10 frames ≈ 200 ms at 50),
    /// while the CropEngine pool recycles a buffer as soon as the app drops
    /// its last reference (~one frame later). Retaining the most recent sends
    /// here keeps a surface alive until the extension has certainly consumed
    /// it; without this, the next render can overwrite a surface the extension
    /// is still reading (visible as tearing).
    private static let retainedFrameDepth = 10
    private var recentlySentBuffers: [CVPixelBuffer] = []
    var onStateChange: (() -> Void)? {
        didSet {
            xpcManager.onStateChange = onStateChange
        }
    }

    var isAvailable: Bool {
        if case .connected = xpcManager.connectionState {
            return true
        }
        return false
    }

    var summary: String {
        switch xpcManager.connectionState {
        case .connected:
            return "CMIO extension is connected and ready."
        case .connecting:
            return "Connecting to the CMIO extension."
        case .disconnected:
            return "Virtual camera route is idle."
        case .error:
            return "Virtual camera route hit a connection problem."
        }
    }

    var detail: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Frames are being sent to the system extension over XPC."
        case .connecting:
            return "Waiting for the extension service to answer the connection check."
        case .disconnected:
            return "Start capture to connect the host app to the virtual camera extension."
        case .error(let message):
            return message
        }
    }

    var lastErrorDescription: String? {
        xpcManager.lastErrorDescription
    }

    /// The extension drains its queue at this rate — the host pushes
    /// `ShowStandard.activeOrCurrent.frameRate` over XPC whenever capture status
    /// changes and before the first frame, so both sides agree by construction.
    /// Reporting it here is what arms the HUD frame-rate-match check for the
    /// virtual-camera route (it used to read nil and never warn).
    var playoutFrameRate: Double? {
        ShowStandard.activeOrCurrent.frameRate
    }

    var canReconnect: Bool {
        xpcManager.canReconnect
    }

    var reconnectStatus: String? {
        xpcManager.reconnectStatusDescription
    }

    var bringUpChecks: [OutputBringUpCheck] {
        [
            OutputBringUpCheck(
                id: "virtual.xpc",
                title: "Virtual Camera · XPC Link",
                status: xpcStatusTitle,
                detail: xpcStatusDetail,
                level: xpcStatusLevel
            ),
            OutputBringUpCheck(
                id: "virtual.frames",
                title: "Virtual Camera · Frame Handoff",
                status: frameHandoffStatusTitle,
                detail: frameHandoffDetail,
                level: frameHandoffLevel
            )
        ]
    }

    func connect() {
        xpcManager.connect()
    }

    func disconnect() {
        xpcManager.disconnect()
        recentlySentBuffers.removeAll()
        playoutHandshake = PlayoutRateHandshake()
    }

    func reconnect() {
        xpcManager.forceReconnect()
    }

    func updateCaptureStatus(isRunning: Bool) {
        if isRunning {
            Self.logger.notice("Sending capture status RUNNING to virtual camera extension")
        } else {
            Self.logger.notice("Sending capture status STOPPED to virtual camera extension")
        }
        if isRunning {
            pushPlayoutRateIfNeeded()
        }
        xpcManager.remoteProxy()?.updateCaptureStatus(isRunning: isRunning)
    }

    /// Tell the extension to drain at the show standard. Idempotent per
    /// connection; re-pushed on every capture-status change so a reconnect
    /// always lands the current rate before frames flow. The show standard is
    /// applied at capture start, so this value matches what processFrame is
    /// producing for the whole session.
    @discardableResult
    private func pushPlayoutRateIfNeeded() -> Bool {
        guard case .connected = xpcManager.connectionState,
              let proxy = xpcManager.remoteProxy() else { return false }
        let rate = ShowStandard.activeOrCurrent.frameRate
        let generation = xpcManager.connectionGeneration
        if playoutHandshake.isReady(rate: rate, generation: generation) { return true }
        if playoutHandshake.begin(rate: rate, generation: generation) {
            proxy.updatePlayoutFrameRate(rate) { [weak self] accepted in
                Task { @MainActor in
                    guard let self else { return }
                    self.playoutHandshake.complete(rate: rate, generation: generation, accepted: accepted)
                    if !accepted { Self.logger.error("Extension rejected the requested show standard") }
                }
            }
        }
        return false
    }

    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        let sendInterval = Self.signposter.beginInterval("xpcSend")
        let sendStart = CACurrentMediaTime()
        guard pushPlayoutRateIfNeeded(),
              let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
              let proxy = xpcManager.remoteProxy() else {
            lastFrameSendDuration = nil
            Self.signposter.endInterval("xpcSend", sendInterval)
            return false
        }

        proxy.sendVideoFrame(
            surfaceID: IOSurfaceGetID(ioSurface),
            timestamp: timestamp,
            width: Int32(CVPixelBufferGetWidth(pixelBuffer)),
            height: Int32(CVPixelBufferGetHeight(pixelBuffer))
        )
        recentlySentBuffers.append(pixelBuffer)
        if recentlySentBuffers.count > Self.retainedFrameDepth {
            recentlySentBuffers.removeFirst()
        }
        if !hasLoggedFirstFrameSend {
            hasLoggedFirstFrameSend = true
            Self.logger.notice(
                "First frame handed to virtual camera extension at \(timestamp, privacy: .public)s"
            )
        }
        lastFrameSendDuration = CACurrentMediaTime() - sendStart
        Self.signposter.endInterval("xpcSend", sendInterval)
        return true
    }

    private var xpcStatusTitle: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    private var xpcStatusDetail: String {
        switch xpcManager.connectionState {
        case .connected:
            return "Host app can reach the CMIO extension Mach service."
        case .connecting:
            return "Waiting for the extension service to answer the XPC ping."
        case .disconnected:
            return "The CMIO extension is not connected. Check that the system extension is installed and loaded."
        case .error(let message):
            return message
        }
    }

    private var xpcStatusLevel: OutputCheckLevel {
        switch xpcManager.connectionState {
        case .connected:
            return .ok
        case .connecting:
            return .info
        case .disconnected:
            return .warning
        case .error:
            return .error
        }
    }

    private var frameHandoffStatusTitle: String {
        if lastFrameSendDuration != nil {
            return "Sending"
        }
        if case .connected = xpcManager.connectionState {
            return "Connected"
        }
        return "Waiting"
    }

    private var frameHandoffDetail: String {
        if let lastFrameSendDuration {
            return String(
                format: "Frames are being handed to the extension over XPC. Last send: %.2f ms.",
                lastFrameSendDuration * 1000
            )
        }
        if case .connected = xpcManager.connectionState {
            return "XPC is connected, but no program frames have been handed off yet."
        }
        return "No frame handoff is possible until the XPC link is connected."
    }

    private var frameHandoffLevel: OutputCheckLevel {
        if lastFrameSendDuration != nil {
            return .ok
        }
        if case .connected = xpcManager.connectionState {
            return .info
        }
        return .warning
    }
}
