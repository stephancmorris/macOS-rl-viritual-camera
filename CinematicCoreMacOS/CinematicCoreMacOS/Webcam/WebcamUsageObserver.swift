import Combine
import Foundation

/// Stream activity only; this does not identify a receiver or prove delivery.
nonisolated enum WebcamUsageState: Equatable, Sendable {
    case inUse, notInUse, unknown
}

/// Read-only monitoring. The caller activates it only for a live Webcam session.
/// Stop clears cached evidence immediately. Slow/failed reads never retain green.
@MainActor
final class WebcamUsageObserver: ObservableObject {
    @Published private(set) var state: WebcamUsageState = .unknown
    private(set) var isMonitoring = false
    private let reader: @Sendable () async -> WebcamUsageState
    private let now: () -> TimeInterval
    private let automaticallyPoll: Bool
    private let staleAfter: TimeInterval
    private var generation: UInt64 = 0
    private var lastFreshAt: TimeInterval?
    private var reading = false
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    init(automaticallyPoll: Bool = true, staleAfter: TimeInterval = 2.5,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         reader: @escaping @Sendable () async -> WebcamUsageState = {
             await Task.detached { CMIOWebcamUsageReader.read() }.value
         }) {
        self.automaticallyPoll = automaticallyPoll
        self.staleAfter = staleAfter
        self.now = now
        self.reader = reader
    }

    isolated deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    func setMonitoring(mode: OperatorMode, isLive: Bool) {
        let enabled = mode == .webcam && isLive
        guard enabled != isMonitoring else { return }
        generation &+= 1
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        reading = false
        lastFreshAt = nil
        state = .unknown
        isMonitoring = enabled
        guard enabled, automaticallyPoll else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    /// A separate tick expires evidence even if a property read has stalled.
    func poll() {
        guard isMonitoring else { return }
        checkFreshness()
        guard !reading else { return }
        refreshTask = Task { [weak self] in await self?.refresh() }
    }

    func checkFreshness() {
        guard let lastFreshAt else { return }
        if now() - lastFreshAt > staleAfter { state = .unknown }
    }

    /// Public for deterministic injected-reader tests and explicit refreshes.
    func refresh() async {
        guard isMonitoring, !reading else { return }
        reading = true
        let token = generation
        let started = now()
        let result = await reader()
        guard token == generation, isMonitoring else { return }
        reading = false
        guard now() - started <= staleAfter else {
            state = .unknown
            lastFreshAt = nil
            return
        }
        state = result
        lastFreshAt = now()
    }
}
