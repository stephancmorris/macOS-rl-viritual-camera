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

    /// Frames cross XPC as IOSurface objects (F-03), so the extension holds its
    /// own reference, and marks each surface in use (`IOSurfaceIncrementUseCount`)
    /// from receipt until the frame is dropped or replaced on air. The use
    /// count is what tells CropEngine's CoreVideo pool not to re-vend a
    /// surface the extension may still read.
    ///
    /// That covers the extension's queue and the frame it has just sent. It
    /// does not cover two other windows, so this sink still retains the most
    /// recent sends (10 frames ≈ 200 ms at 50 fps):
    /// - transit: between this send and the extension decoding the message,
    ///   nothing else keeps the pool from recycling the buffer;
    /// - downstream clients: after the extension hands a frame to the CMIO
    ///   stream, a receiving app (Zoom, OBS, QuickTime) can keep that buffer
    ///   longer than one playout interval, while the extension releases its
    ///   use count at the next drain (~20 ms). Nothing shows that the stream's
    ///   wrap or the client's copy holds a use count of its own.
    ///
    /// Keep 10 until an attended long session with a receiving app shows that
    /// a smaller depth holds without tearing.
    static let retainedFrameDepth = 10
    private var recentlySentBuffers: [CVPixelBuffer] = []
    /// Connection-scoped agreement on the frame transport. No frame is sent
    /// until the extension answers with the surface-object version.
    private var transportHandshake = FrameTransportHandshake()
    private let now: () -> TimeInterval
    init(now: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.now = now
    }

    var onStateChange: (() -> Void)? {
        didSet {
            xpcManager.onStateChange = onStateChange
        }
    }

    /// Shown when the extension refused, or never answered, the transport
    /// negotiation on this connection.
    static let transportMismatchMessage =
        "The virtual camera extension is older than this app and cannot take its frames. "
        + "Re-activate the camera extension, then reconnect."

    private var transportMismatched: Bool {
        transportHandshake.isMismatched(generation: xpcManager.connectionGeneration)
    }

    var isAvailable: Bool {
        if case .connected = xpcManager.connectionState {
            return !transportMismatched
        }
        return false
    }

    var summary: String {
        if transportMismatched, case .connected = xpcManager.connectionState {
            return "Virtual camera extension needs re-activating."
        }
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
        if transportMismatched, case .connected = xpcManager.connectionState {
            return Self.transportMismatchMessage
        }
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
        if transportMismatched { return Self.transportMismatchMessage }
        return xpcManager.lastErrorDescription
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
        transportHandshake = FrameTransportHandshake()
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
            prepareTransportIfNeeded()
        }
        xpcManager.remoteProxy()?.updateCaptureStatus(isRunning: isRunning)
    }

    /// Agree the frame transport with the extension, once per connection.
    /// True only when the extension has answered with the surface-object
    /// version. A refusal, or no answer within `FrameTransportHandshake.replyTimeout`
    /// (an extension older than F-03 drops the unknown message), is final for
    /// the connection: no frame is sent, the route reports itself unavailable
    /// and says the extension needs re-activating.
    @discardableResult
    private func prepareTransportIfNeeded() -> Bool {
        guard case .connected = xpcManager.connectionState else { return false }
        let generation = xpcManager.connectionGeneration
        if transportHandshake.isReady(generation: generation) { return true }
        // The proxy is fetched before the handshake starts its timeout: with
        // no proxy nothing is sent, the handshake stays idle and the next
        // call tries again, so a missing proxy can never read as an old
        // extension that did not answer.
        let xpcManager = self.xpcManager
        let sent = transportHandshake.negotiateIfDue(generation: generation, now: now()) {
            guard let proxy = xpcManager.remoteProxy() else { return false }
            proxy.negotiateFrameTransport(FrameTransport.surfaceObject) { [weak self] accepted in
                Task { @MainActor in
                    guard let self else { return }
                    self.transportHandshake.complete(generation: generation, acceptedVersion: accepted)
                    if self.transportHandshake.isMismatched(generation: generation) {
                        Self.logger.error("Virtual camera extension refused frame transport \(FrameTransport.surfaceObject, privacy: .public); it answered \(accepted, privacy: .public)")
                        self.onStateChange?()
                    }
                }
            }
            return true
        }
        if !sent, transportHandshake.expireIfDue(now: now()) {
            Self.logger.error("Virtual camera extension did not answer the frame transport check; it is likely older than this app")
            onStateChange?()
        }
        return false
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
        let rateReady = pushPlayoutRateIfNeeded()
        let transportReady = prepareTransportIfNeeded()
        guard rateReady, transportReady,
              let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
              let proxy = xpcManager.remoteProxy() else {
            lastFrameSendDuration = nil
            Self.signposter.endInterval("xpcSend", sendInterval)
            return false
        }

        // The surface object itself crosses XPC (F-03): the extension gets
        // its own reference, and no global ID is sent.
        proxy.sendVideoFrame(
            surface: ioSurface,
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
