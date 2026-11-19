import Testing
@testable import Alfie

@MainActor
struct WebcamUsageObserverTests {
    private final class Clock { var time: Double = 10 }
    private actor Reader {
        var result: WebcamUsageState = .notInUse
        var count = 0
        func read() -> WebcamUsageState { count += 1; return result }
        func set(_ value: WebcamUsageState) { result = value }
    }
    private actor Gate {
        var continuation: CheckedContinuation<WebcamUsageState, Never>?
        var started: CheckedContinuation<Void, Never>?
        var hasStarted = false
        func read() async -> WebcamUsageState {
            hasStarted = true
            started?.resume()
            started = nil
            return await withCheckedContinuation { continuation = $0 }
        }
        func waitUntilReading() async {
            if !hasStarted { await withCheckedContinuation { started = $0 } }
        }
        func finish(_ value: WebcamUsageState) { continuation?.resume(returning: value); continuation = nil }
    }

    @Test func readsOnlyDuringLiveWebcamAndStopClearsEvidence() async {
        let reader = Reader()
        // A fixed clock: this test is about the live-Webcam gate, and on a
        // loaded runner a real-clock read can exceed the 2.5 s freshness
        // bound and come back unknown (seen on hosted CI, 6 Nov 2026).
        let observer = WebcamUsageObserver(automaticallyPoll: false, now: { 0 }, reader: { await reader.read() })
        for mode in OperatorMode.allCases {
            for live in [false, true] {
                observer.setMonitoring(mode: mode, isLive: live)
                await observer.refresh()
                #expect(observer.isMonitoring == (mode == .webcam && live))
                #expect(observer.state == (mode == .webcam && live ? .notInUse : .unknown))
            }
        }
        #expect(await reader.count == 1)
        await reader.set(.inUse)
        observer.setMonitoring(mode: .webcam, isLive: true)
        await observer.refresh()
        #expect(observer.state == .inUse)
        observer.setMonitoring(mode: .webcam, isLive: false)
        #expect(observer.state == .unknown)
        #expect(!observer.isMonitoring)
    }

    @Test func errorsAndStalePositiveEvidenceBecomeUnknownAndRecover() async {
        let clock = Clock()
        let reader = Reader()
        await reader.set(.inUse)
        let observer = WebcamUsageObserver(automaticallyPoll: false, now: { clock.time }, reader: { await reader.read() })
        observer.setMonitoring(mode: .webcam, isLive: true)
        await observer.refresh()
        #expect(observer.state == .inUse)
        clock.time += 2.6
        observer.checkFreshness()
        #expect(observer.state == .unknown)
        await reader.set(.notInUse)
        await observer.refresh()
        #expect(observer.state == .notInUse)
        await reader.set(.unknown)
        await observer.refresh()
        #expect(observer.state == .unknown)
        await reader.set(.inUse)
        await observer.refresh()
        #expect(observer.state == .inUse)
    }

    @Test(.timeLimit(.minutes(1))) func stoppedSessionRejectsLateReadEvenAfterRestart() async {
        let gate = Gate()
        let observer = WebcamUsageObserver(automaticallyPoll: false, reader: { await gate.read() })
        observer.setMonitoring(mode: .webcam, isLive: true)
        let task = Task { await observer.refresh() }
        await gate.waitUntilReading()
        observer.setMonitoring(mode: .webcam, isLive: false)
        observer.setMonitoring(mode: .webcam, isLive: true)
        await gate.finish(.inUse)
        await task.value
        #expect(observer.state == .unknown)
    }

    @Test(.timeLimit(.minutes(1))) func slowReadIsUnknownAndConcurrentRefreshDoesNotDuplicateIt() async {
        let gate = Gate()
        let clock = Clock()
        let observer = WebcamUsageObserver(automaticallyPoll: false, now: { clock.time }, reader: { await gate.read() })
        observer.setMonitoring(mode: .webcam, isLive: true)
        let task = Task { await observer.refresh() }
        await gate.waitUntilReading()
        await observer.refresh() // Must return immediately, not start another read.
        clock.time += 3
        await gate.finish(.inUse)
        await task.value
        #expect(observer.state == .unknown)
    }

    @Test func propertyDecodingRequiresSupportedBooleanAndExactSize() {
        #expect(CMIOWebcamUsageReader.decode(status: 0, size: 4, value: 0) == .notInUse)
        #expect(CMIOWebcamUsageReader.decode(status: 0, size: 4, value: 1) == .inUse)
        #expect(CMIOWebcamUsageReader.decode(status: -1, size: 4, value: 0) == .unknown)
        #expect(CMIOWebcamUsageReader.decode(status: 0, size: 3, value: 1) == .unknown)
        #expect(CMIOWebcamUsageReader.decode(status: 0, size: 4, value: 2) == .unknown)
        #expect(CMIOWebcamUsageReader.matchesDeviceUID("6089d528-8d1b-45c5-8d24-e76cd0e2c3bf"))
        #expect(!CMIOWebcamUsageReader.matchesDeviceUID("Alfie"))
        #expect(!CMIOWebcamUsageReader.matchesDeviceUID("6089D528-8D1B-45C5-8D24-E76CD0E2C3BE"))
    }
}
