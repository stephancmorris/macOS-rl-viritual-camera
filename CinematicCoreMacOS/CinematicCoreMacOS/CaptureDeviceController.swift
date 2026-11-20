//
//  CaptureDeviceController.swift
//  CinematicCoreMacOS
//
//  G-01 stage 5. Owns the capture-device state that used to be private
//  stored properties of CameraManager: the per-channel session executor, the
//  disconnect observer, and the format chosen at configuration (re-asserted
//  after startRunning). CameraManager keeps the device claim, the lease and
//  the published session state (error, source missing, capture status).
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog

@MainActor
final class CaptureDeviceController {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Camera")

    /// Per-channel serial executor for blocking session calls, so starting or
    /// stopping one camera never blocks the MainActor or the other channel.
    private let sessionQueue: DispatchQueue
    private var disconnectObserver: NSObjectProtocol?

    /// Format explicitly chosen at configuration, re-asserted after
    /// startRunning() because the macOS .high session preset clobbers it
    /// (see `reassertConfiguredFormatIfNeeded`).
    private(set) var configuredDevice: AVCaptureDevice?
    private var configuredFormat: AVCaptureDevice.Format?
    private(set) var configuredSize: (width: Int, height: Int)?
    private(set) var configuredReason: CaptureProfilePolicy.Reason?
    /// "1080p50", or "30 fps (show standard 1080p50)" for a Webcam fallback.
    private(set) var configuredRateLabel = ShowStandard.activeOrCurrent.title
    private var configuredMinFrameDuration: CMTime?
    private var configuredMaxFrameDuration: CMTime?

    init(channelLetter: String) {
        sessionQueue = DispatchQueue(label: "com.alfie.capture-session.\(channelLetter)", qos: .userInitiated)
    }

    // MARK: Session executor

    /// Stop the session on this channel's executor without blocking.
    func stopSession(_ captureSession: AVCaptureSession) {
        let session = CaptureSessionBox(captureSession)
        sessionQueue.async { @Sendable in
            if session.value.isRunning { session.value.stopRunning() }
        }
    }

    /// Start the session on this channel's executor; returns once it has.
    func startSession(_ captureSession: AVCaptureSession) async {
        let session = CaptureSessionBox(captureSession)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { @Sendable in
                session.value.startRunning()
                continuation.resume()
            }
        }
    }

    // MARK: Disconnect

    /// Watch the configured device for a hot unplug. Replaces any earlier
    /// watch; does nothing when no device is configured.
    func watchDisconnect(onLost: @escaping @MainActor @Sendable () -> Void) {
        stopWatchingDisconnect()
        guard let device = configuredDevice else { return }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onLost() }
        }
    }

    func stopWatchingDisconnect() {
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
        disconnectObserver = nil
    }

    // MARK: Configured format

    /// Remember the format chosen for `device`.
    func recordConfiguration(device: AVCaptureDevice, format: AVCaptureDevice.Format,
                             size: (width: Int, height: Int), reason: CaptureProfilePolicy.Reason,
                             rateLabel: String) {
        configuredDevice = device
        configuredFormat = format
        configuredSize = size
        configuredReason = reason
        configuredRateLabel = rateLabel
    }

    /// Remember the frame durations the device accepted.
    func recordFrameDurations(min: CMTime, max: CMTime) {
        configuredMinFrameDuration = min
        configuredMaxFrameDuration = max
    }

    /// Forget the configured device, format and size at stop. The reason,
    /// rate label and frame durations are left as they were.
    func clearConfiguredDevice() {
        configuredDevice = nil
        configuredFormat = nil
        configuredSize = nil
    }

    /// The .high session preset (macOS default; .inputPriority is iOS-only)
    /// re-configures the capture device's activeFormat during startRunning(),
    /// silently replacing the 4K format chosen at configuration with 1080p.
    /// Verified empirically with the Elgato 4K X: activeFormat reads
    /// 3840×2160 after commitConfiguration and 1920×1080 immediately after
    /// startRunning. Re-asserting the stored format after start sticks — the
    /// session only performs its preset-driven reconfiguration at start time.
    func reassertConfiguredFormatIfNeeded() {
        guard let device = configuredDevice,
              let format = configuredFormat,
              device.activeFormat != format else { return }
        let clobbered = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let wanted = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        Self.logger.warning(
            "Session preset clobbered activeFormat to \(clobbered.width)x\(clobbered.height); re-asserting \(wanted.width)x\(wanted.height)"
        )
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let min = configuredMinFrameDuration { device.activeVideoMinFrameDuration = min }
            if let max = configuredMaxFrameDuration { device.activeVideoMaxFrameDuration = max }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Failed to re-assert capture format: \(error.localizedDescription, privacy: .public)")
        }
    }
}
