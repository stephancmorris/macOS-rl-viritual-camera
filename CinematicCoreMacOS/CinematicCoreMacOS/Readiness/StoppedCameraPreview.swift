import AppKit
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

/// Preview-only capture. It has no Program port, router or virtual-camera
/// connection, and never requests permission. Only the explicit button starts it.
@MainActor
final class StoppedCameraPreviewController: ObservableObject {
    @Published private(set) var isPreviewing = false
    @Published private(set) var isChanging = false
    @Published private(set) var error: String?
    private let worker = StoppedPreviewWorker()
    private var generation = 0
    var session: AVCaptureSession { worker.session }

    func start(deviceID: String?) async {
        guard !isChanging, !isPreviewing else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard let deviceID else {
            error = "Choose a camera, then try Preview cameras again."
            return
        }
        generation += 1
        let request = generation
        error = nil
        isChanging = true
        let succeeded = await worker.start(deviceID: deviceID)
        guard generation == request else { return }
        isChanging = false
        isPreviewing = succeeded
        if succeeded { OperatorAnnouncement.say("Camera previews are on. Program output is off.") }
        else { error = "Camera preview could not start. Reconnect or choose another camera, then try Preview cameras again." }
    }

    func stop() async {
        generation += 1
        isChanging = true
        await worker.stop()
        isPreviewing = false
        isChanging = false
        error = nil
    }
}

/// All mutable session configuration and start/stop calls run on this queue.
/// The preview layer may retain the session on the main thread, as AVFoundation
/// requires for display, but never configures it.
nonisolated private final class StoppedPreviewWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.alfie.stopped-preview")

    func start(deviceID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let device = AVCaptureDevice(uniqueID: deviceID),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }
                session.beginConfiguration()
                for existing in session.inputs { session.removeInput(existing) }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
                session.commitConfiguration()
                session.startRunning()
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration()
                for input in session.inputs { session.removeInput(input) }
                session.commitConfiguration()
                continuation.resume()
            }
        }
    }
}

struct StoppedCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: PreviewView, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
    }
    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = preview
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }
}
