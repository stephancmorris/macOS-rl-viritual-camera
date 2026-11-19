import AVFoundation
import Testing
@testable import Alfie

@MainActor
struct StoppedPreviewLifecycleTests {
    private final class Worker: StoppedPreviewCapturing {
        let session = AVCaptureSession()
        var devices: [String] = []
        var stops = 0
        var pending: CheckedContinuation<Bool, Never>?
        var began: CheckedContinuation<Void, Never>?
        func start(deviceID: String) async -> Bool {
            devices.append(deviceID)
            began?.resume(); began = nil
            return await withCheckedContinuation { pending = $0 }
        }
        func stop() async { stops += 1 }
        func waitUntilStarted() async {
            if devices.isEmpty { await withCheckedContinuation { began = $0 } }
        }
        func finish() { pending?.resume(returning: true); pending = nil }
    }

    @Test(.timeLimit(.minutes(1))) func delayedPreviewCannotReappearAfterModeOrDeviceStop() async {
        let worker = Worker()
        let preview = StoppedCameraPreviewController(worker: worker, isAuthorized: { true })
        #expect(worker.devices.isEmpty) // construction never opens a camera
        let start = Task { await preview.start(deviceID: "chosen") }
        await worker.waitUntilStarted()
        #expect(preview.isChanging)
        await preview.start(deviceID: "duplicate")
        #expect(worker.devices == ["chosen"])
        await preview.stop() // same path used by mode/device changes and Start
        worker.finish()
        await start.value
        #expect(!preview.isPreviewing && !preview.isChanging)
        #expect(worker.stops == 1)
    }

    @Test func unavailablePermissionOrSelectionNeverCallsCapture() async {
        let worker = Worker()
        let denied = StoppedCameraPreviewController(worker: worker, isAuthorized: { false })
        await denied.start(deviceID: "chosen")
        let noSelection = StoppedCameraPreviewController(worker: worker, isAuthorized: { true })
        await noSelection.start(deviceID: nil)
        #expect(worker.devices.isEmpty)
        #expect(noSelection.error != nil)
    }
}
