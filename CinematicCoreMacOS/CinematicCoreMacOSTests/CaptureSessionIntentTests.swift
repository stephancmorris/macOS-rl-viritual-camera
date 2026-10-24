#if DEBUG
import Foundation
import Testing
@testable import Alfie

/// These gates deliberately ignore task cancellation until released, as an
/// authorization callback or blocking session executor can do in production.
@MainActor
private final class CaptureIntentGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = enteredWaiters
            enteredWaiters = []
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilEntered() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

/// A serial session executor whose first blocking start can be completed by
/// the test. Later Stop/Start calls queue in their actual requested order.
@MainActor
private final class CaptureIntentSessionQueue {
    private enum Operation {
        case start(CheckedContinuation<Void, Never>)
        case stop
    }
    private var operations: [Operation] = []
    private var blockedStart: CheckedContinuation<Void, Never>?
    private var startCount = 0
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var events: [String] = []

    func start() async {
        await withCheckedContinuation { continuation in
            startCount += 1
            if startCount == 1 { blockedStart = continuation }
            else { operations.append(.start(continuation)) }
            let ready = startWaiters.filter { startCount >= $0.0 }
            startWaiters.removeAll { startCount >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForStarts(_ count: Int) async {
        guard startCount < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func stop() {
        if blockedStart != nil { operations.append(.stop) }
        else { events.append("stop") }
    }

    func completeBlockedStartAndDrain() {
        events.append("start")
        blockedStart?.resume()
        blockedStart = nil
        let queued = operations
        operations = []
        for operation in queued {
            switch operation {
            case .stop: events.append("stop")
            case .start(let continuation):
                events.append("start")
                continuation.resume()
            }
        }
    }
}

@MainActor
struct CaptureSessionIntentTests {
    private func manager() -> CameraManager {
        CameraManager(channelID: .a, programOutput: ProgramOutputManager(sinks: []), routed: false)
    }

    private func camera(_ id: String) -> CameraManager.CameraDevice {
        .init(id: id, name: id, modelID: "synthetic", uniqueID: id,
              maxResolution: "synthetic", supports4K: false, formatCount: 0)
    }

    private func expectCancellation(_ task: Task<Void, Error>) async {
        do {
            try await task.value
            Issue.record("Retired capture intent completed successfully")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func stopDuringCameraSwitchCannotRestartOrReplaceTheSelection() async {
        let manager = manager(), gate = CaptureIntentGate()
        let original = camera("original")
        manager.selectedCamera = original
        manager.setRunningForTesting(true)
        manager.sessionRestartWaitForTesting = { await gate.pause() }
        var starts = 0
        manager.sessionCaptureStartForTesting = { starts += 1 }
        let restart = Task { try await manager.restartWithCamera(camera("replacement")) }
        await gate.waitUntilEntered()
        #expect(manager.isStartingSession && !manager.isRunning)

        manager.stopCapture()
        let stopped = manager.revisions
        gate.release()
        await expectCancellation(restart)

        #expect(starts == 0)
        #expect(manager.selectedCamera == original)
        #expect(manager.revisions == stopped)
        #expect(!manager.isStartingSession && !manager.isRunning)
    }

    @Test func replacementCameraSwitchOwnsStartingStateAndFinalSelection() async throws {
        let manager = manager(), firstGate = CaptureIntentGate(), secondGate = CaptureIntentGate()
        let original = camera("original"), replacement = camera("latest")
        manager.selectedCamera = original
        manager.setRunningForTesting(true)
        var waits = 0
        manager.sessionRestartWaitForTesting = {
            waits += 1
            await (waits == 1 ? firstGate : secondGate).pause()
        }
        var started: [String] = []
        manager.sessionCaptureStartForTesting = {
            started.append(manager.selectedCamera?.uniqueID ?? "missing")
        }
        let first = Task { try await manager.restartWithCamera(camera("obsolete")) }
        await firstGate.waitUntilEntered()
        let second = Task { try await manager.restartWithCamera(replacement) }
        await secondGate.waitUntilEntered()

        firstGate.release()
        await expectCancellation(first)
        #expect(manager.isStartingSession)
        #expect(manager.selectedCamera == original)
        #expect(started.isEmpty)

        secondGate.release()
        try await second.value
        #expect(manager.selectedCamera == replacement)
        #expect(started == [replacement.uniqueID])
        #expect(!manager.isStartingSession)
    }

    @Test func cancellingCameraSwitchRetiresItsStartingState() async {
        let manager = manager(), gate = CaptureIntentGate()
        let original = camera("original")
        manager.selectedCamera = original
        manager.setRunningForTesting(true)
        manager.sessionRestartWaitForTesting = { await gate.pause() }
        var starts = 0
        manager.sessionCaptureStartForTesting = { starts += 1 }
        let restart = Task { try await manager.restartWithCamera(camera("replacement")) }
        await gate.waitUntilEntered()
        restart.cancel()
        gate.release()
        await expectCancellation(restart)
        #expect(starts == 0 && manager.selectedCamera == original)
        #expect(!manager.isStartingSession && !manager.isRunning)
    }

    @Test func retiredStartCannotClearAReplacementStartOrReportItsError() async throws {
        let manager = manager(), firstGate = CaptureIntentGate(), secondGate = CaptureIntentGate()
        var starts = 0
        manager.sessionCaptureStartForTesting = {
            starts += 1
            if starts == 1 {
                await firstGate.pause()
                throw CameraError.noDeviceSelected
            }
            await secondGate.pause()
        }
        #expect(manager.dispatch(manager.makeCommand(.startSession)) == .accepted)
        let first = try #require(manager.sessionStartTaskForTesting)
        await firstGate.waitUntilEntered()
        manager.stopCapture()
        #expect(manager.dispatch(manager.makeCommand(.startSession)) == .accepted)
        let second = try #require(manager.sessionStartTaskForTesting)
        await secondGate.waitUntilEntered()

        firstGate.release()
        await first.value
        #expect(manager.isStartingSession)
        #expect(manager.error == nil && manager.controlStatus == nil)

        secondGate.release()
        await second.value
        #expect(!manager.isStartingSession)
        #expect(manager.error == nil && manager.controlStatus == nil)
    }

    @Test func stopDuringCaptureStartupRejectsItsLateCompletion() async throws {
        let manager = manager(), gate = CaptureIntentGate()
        manager.sessionCaptureStartForTesting = { await gate.pause() }
        let start = Task { try await manager.startCapture() }
        await gate.waitUntilEntered()
        #expect(manager.isStartingSession)
        manager.stopCapture()
        let stopped = manager.revisions
        gate.release()
        await expectCancellation(start)
        #expect(manager.revisions == stopped)
        #expect(!manager.isStartingSession && !manager.isRunning)
    }

    @Test func currentStartupFailureStillStopsAndReportsItsError() async throws {
        let manager = manager()
        var stops = 0
        manager.sessionStopRunningForTesting = { stops += 1 }
        manager.sessionCaptureStartForTesting = { throw CameraError.noDeviceSelected }
        #expect(manager.dispatch(manager.makeCommand(.startSession)) == .accepted)
        let start = try #require(manager.sessionStartTaskForTesting)
        await start.value
        #expect(stops == 1)
        #expect(!manager.isStartingSession && !manager.isRunning)
        #expect(manager.error?.localizedDescription == CameraError.noDeviceSelected.localizedDescription)
        #expect(manager.controlStatus == CameraError.noDeviceSelected.localizedDescription)
    }

    @Test func cameraSwitchWaitKeepsLiveModeRestrictionsActive() async throws {
        let defaults = try #require(UserDefaults(suiteName: "alfie-capture-intent-\(UUID().uuidString)"))
        defaults.set(OperatorMode.multiCam.rawValue, forKey: OperatorModeStore.key)
        let modes = OperatorModeStore(defaults: defaults, multiviewEnabled: true)
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []), operatorModes: modes)
        show.addChannel(.b)
        let manager = show.channelA, gate = CaptureIntentGate()
        manager.setRunningForTesting(true)
        manager.sessionRestartWaitForTesting = { await gate.pause() }
        manager.sessionCaptureStartForTesting = { }
        let restart = Task { try await manager.restartWithCamera(camera("replacement")) }
        await gate.waitUntilEntered()
        #expect(show.isAnyChannelLive)
        #expect(modes.request(.singleCam) != nil)
        #expect(modes.mode == .multiCam && show.channel(.b) != nil)
        show.stopShow()
        gate.release()
        await expectCancellation(restart)
        #expect(!show.isAnyChannelLive)
    }

    @Test func staleReconnectCannotQueueAStopAfterTheReplacementStart() async throws {
        let manager = manager(), queue = CaptureIntentSessionQueue()
        manager.setRunningForTesting(true)
        manager.setSourceMissingForTesting(true)
        manager.setDeviceLeaseForTesting(.init(uniqueID: "synthetic", channel: .a, token: UUID()))
        manager.sessionConfigureForTesting = { }
        manager.sessionStartRunningForTesting = { await queue.start() }
        manager.sessionStopRunningForTesting = { queue.stop() }
        let reconnect = Task { try await manager.reconnectSource() }
        await queue.waitForStarts(1)

        manager.stopCapture()
        manager.sessionCaptureStartForTesting = { await queue.start() }
        let replacement = Task { try await manager.startCapture() }
        await queue.waitForStarts(2)
        queue.completeBlockedStartAndDrain()

        await expectCancellation(reconnect)
        try await replacement.value
        #expect(queue.events == ["start", "stop", "start"])
        #expect(!manager.isStartingSession)
    }

    @Test func stoppedCameraChoiceOnlyUpdatesThePreference() async throws {
        let manager = manager(), selected = camera("selection")
        var starts = 0
        manager.sessionRestartWaitForTesting = { Issue.record("Stopped camera selection waited to restart") }
        manager.sessionCaptureStartForTesting = { starts += 1 }
        try await manager.restartWithCamera(selected)
        #expect(manager.selectedCamera == selected && starts == 0)
        #expect(!manager.isStartingSession && !manager.isRunning)
    }
}
#endif
