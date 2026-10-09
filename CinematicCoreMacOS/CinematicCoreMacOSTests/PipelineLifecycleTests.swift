import Testing
import Foundation
import Combine
@testable import Alfie

struct PipelineLifecycleTests {
    @Test func retiredFrameCannotUnlockNewSession() throws {
        let gate = CaptureFrameProcessingGate()
        let old = try #require(gate.begin())
        #expect(gate.begin() == nil)
        gate.reset()
        let current = try #require(gate.begin())
        #expect(!gate.isCurrent(old))
        #expect(gate.isCurrent(current))
        gate.finish(old)
        #expect(gate.begin() == nil)
        gate.finish(current)
        #expect(gate.begin() != nil)
    }

    @MainActor @Test func diagnosticsDistinguishWallTimeFromMainWork() {
        let fields = DiagnosticsLog.header.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        #expect(Set(fields).count == fields.count)
        for name in ["frame_wall_mean_ms", "main_active_mean_ms", "observation_age_mean_ms", "processed_input_fps", "detector_fps", "handoff_fps", "window_s"] {
            #expect(fields.contains(Substring(name)))
        }
    }
}


#if DEBUG
@MainActor
struct CameraSwitchLifecycleTests {
    private final class SwitchPause {
        private var entered = false
        private var entryWaiter: CheckedContinuation<Void, Never>?
        private var resumeWaiter: CheckedContinuation<Void, Error>?

        func suspend() async throws {
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
            try await withCheckedThrowingContinuation { resumeWaiter = $0 }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { entryWaiter = $0 }
        }

        func resume() {
            let waiter = resumeWaiter
            resumeWaiter = nil
            waiter?.resume()
        }
    }

    private enum Stop: CaseIterable { case channel, show, removePreview }
    private final class StartCalls { var count = 0 }

    private func camera(_ id: String) -> CameraManager.CameraDevice {
        .init(id: id, name: id, modelID: "synthetic", uniqueID: id,
              maxResolution: "1920x1080", supports4K: false, formatCount: 1)
    }

    private func rig(running: Bool = true) -> (ShowCoordinator, CameraManager, SwitchPause, StartCalls) {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let b = show.addChannel(.b)
        b.selectedCamera = camera("original")
        b.setRunningForTesting(running)
        let pause = SwitchPause()
        let starts = StartCalls()
        b.cameraSwitchPauseForTesting = { try await pause.suspend() }
        b.cameraSwitchStartForTesting = { [weak b] in
            starts.count += 1
            b?.setRunningForTesting(true)
        }
        return (show, b, pause, starts)
    }

    private func clear(_ show: ShowCoordinator, _ b: CameraManager) {
        b.cameraSwitchPauseForTesting = nil
        b.cameraSwitchStartForTesting = nil
        b.stopCapture()
        show.stopShow()
    }

    @Test(arguments: Stop.allCases)
    private func stopRetiresDelayedCameraSwitch(stop: Stop) async throws {
        let (show, b, pause, starts) = rig()
        defer { clear(show, b) }
        let original = try #require(b.selectedCamera)
        let task = Task {
            do {
                try await b.restartWithCamera(camera("retired-choice"))
                return true
            } catch is CancellationError { return false }
            catch { Issue.record("Unexpected switch error: \(error)"); return false }
        }
        await pause.waitUntilEntered()
        switch stop {
        case .channel: b.stopCapture()
        case .show: show.stopShow()
        case .removePreview: show.removeChannel(.b)
        }
        let afterStop = b.revisions
        pause.resume()
        let completed = await task.value
        #expect(!completed)
        #expect(starts.count == 0)
        #expect(!b.isRunning)
        #expect(!b.isStartingSession)
        #expect(b.selectedCamera == original)
        #expect(b.revisions == afterStop)
        #expect(show.programChannel == .a)
        #expect(show.programOutput.activeRoute == nil)
        if stop == .removePreview { #expect(show.channel(.b) == nil) }
    }

    @Test func newerCameraChoiceSupersedesDelayedSwitch() async throws {
        let (show, b, pause, starts) = rig()
        defer { clear(show, b) }
        let first = camera("first-choice")
        let newest = camera("newest-choice")
        let task = Task {
            do { try await b.restartWithCamera(first); return true }
            catch is CancellationError { return false }
            catch { Issue.record("Unexpected switch error: \(error)"); return false }
        }
        await pause.waitUntilEntered()
        // The current implementation is stopped during its delay. A new choice
        // must stay selected and the old running intent must not revive capture.
        try await b.restartWithCamera(newest)
        #expect(b.selectedCamera == newest)
        pause.resume()
        let completed = await task.value
        #expect(!completed)
        #expect(b.selectedCamera == newest)
        #expect(starts.count == 0)
        #expect(!b.isRunning)
        #expect(show.programChannel == .a)
        #expect(show.programOutput.activeRoute == nil)
    }

    @Test func cancellationDuringNoncooperativePauseRetiresCameraSwitch() async throws {
        let (show, b, pause, starts) = rig()
        defer { clear(show, b) }
        let original = try #require(b.selectedCamera)
        let task = Task {
            do { try await b.restartWithCamera(camera("cancelled-choice")); return true }
            catch is CancellationError { return false }
            catch { Issue.record("Unexpected switch error: \(error)"); return false }
        }
        await pause.waitUntilEntered()
        task.cancel() // This checked continuation deliberately does not observe cancellation.
        pause.resume()
        let completed = await task.value
        #expect(!completed)
        #expect(b.selectedCamera == original)
        #expect(starts.count == 0)
        #expect(!b.isRunning)
        #expect(show.programChannel == .a)
        #expect(show.programOutput.activeRoute == nil)
    }

    @Test func stopDuringInternalStopPublicationRetiresSwitch() async throws {
        let (show, b, pause, starts) = rig()
        defer { clear(show, b) }
        let original = try #require(b.selectedCamera)
        var stopped = false
        let observer = b.$isRunning.dropFirst().sink { running in
            guard !running, !stopped else { return }
            stopped = true
            b.stopCapture()
        }
        defer { observer.cancel() }
        let task = Task {
            do { try await b.restartWithCamera(camera("reentrant-stop-choice")); return true }
            catch is CancellationError { return false }
            catch { Issue.record("Unexpected switch error: \(error)"); return false }
        }
        await pause.waitUntilEntered()
        #expect(stopped)
        pause.resume()
        let completed = await task.value
        #expect(!completed)
        #expect(starts.count == 0)
        #expect(b.selectedCamera == original)
        #expect(!b.isRunning)
        #expect(show.programOutput.activeRoute == nil)
    }

    @Test func stopDuringCameraChoicePublicationPreventsRestart() async throws {
        let (show, b, pause, starts) = rig()
        defer { clear(show, b) }
        let chosen = camera("reentrant-selection-choice")
        var stopped = false
        let observer = b.$selectedCamera.dropFirst().sink { selected in
            guard selected == chosen, !stopped else { return }
            stopped = true
            b.stopCapture()
        }
        defer { observer.cancel() }
        let task = Task {
            do { try await b.restartWithCamera(chosen); return true }
            catch is CancellationError { return false }
            catch { Issue.record("Unexpected switch error: \(error)"); return false }
        }
        await pause.waitUntilEntered()
        pause.resume()
        let completed = await task.value
        #expect(stopped)
        #expect(!completed)
        #expect(starts.count == 0)
        #expect(!b.isRunning)
        #expect(b.selectedCamera == chosen) // The preference was published; Stop blocks its restart.
        #expect(show.programOutput.activeRoute == nil)
    }

    @Test func uninterruptedCameraSwitchStillRestartsOnce() async throws {
        let (show, b, pause, starts) = rig()
        defer { clear(show, b) }
        let chosen = camera("fresh-choice")
        let task = Task { try await b.restartWithCamera(chosen) }
        await pause.waitUntilEntered()
        #expect(!b.isRunning)
        #expect(starts.count == 0)
        pause.resume()
        try await task.value
        #expect(b.selectedCamera == chosen)
        #expect(starts.count == 1)
        #expect(b.isRunning)
    }

    @Test func cameraChoiceWhileStoppedDoesNotStartCapture() async throws {
        let (show, b, _, starts) = rig(running: false)
        defer { clear(show, b) }
        let before = b.revisions
        let chosen = camera("stopped-choice")
        try await b.restartWithCamera(chosen)
        #expect(b.selectedCamera == chosen)
        #expect(starts.count == 0)
        #expect(!b.isRunning)
        #expect(b.revisions == before)
        #expect(show.programOutput.activeRoute == nil)
    }
}
#endif
