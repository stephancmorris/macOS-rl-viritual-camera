import CoreGraphics
import Foundation

/// B-10 software boundary. Study parameters are injected explicitly; this
/// module supplies no discovery workload approval or authority grant.
nonisolated enum DirectorSubjectDiscovery {
    struct Configuration: Sendable {
        let revision: UInt64
        let maximumStartsPerSecond: Double
        let maximumResultAge: TimeInterval
        let maximumStableSpeed: Double
        let selectorParameters: SubjectSelector.Parameters
        let positionHintZone: SubjectSelector.Zone?

        var isValid: Bool {
            maximumStartsPerSecond.isFinite && maximumStartsPerSecond > 0 &&
                (1 / maximumStartsPerSecond).isFinite && 1 / maximumStartsPerSecond > 0 &&
                maximumResultAge.isFinite && maximumResultAge >= 0 &&
                maximumStableSpeed.isFinite && maximumStableSpeed >= 0 &&
                selectorParameters.isValid && (positionHintZone.map(\.isValid) ?? true)
        }
    }

    /// The controller supplies current show facts. Explicit scan permission
    /// does not imply permission to acquire a subject. In particular it cannot
    /// satisfy a missing nomination/qualification prerequisite by itself.
    struct Context: Equatable, Sendable {
        let program: ChannelID
        let routeGeneration: UInt64
        let authorityEpoch: UInt64
        let policyRevision: UInt64
        let nominationRevision: UInt64
        let permitted: Bool
        let mayAcquire: Bool
    }

    struct Binding: Equatable, Sendable {
        let channel: ChannelID
        let sourceGeneration: UInt64
        let controlEpoch: UInt64
        let shotRevision: UInt64
        let configurationRevision: UInt64
        let context: Context
    }
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let bounds: CGRect
    }
    struct Statistics: Equatable, Sendable {
        var requested: UInt64 = 0
        var started: UInt64 = 0
        var completed: UInt64 = 0
        var cancelledBeforeStart: UInt64 = 0
        var retiredWhileRunning: UInt64 = 0
        var rejectedResults: UInt64 = 0
        var acquired: UInt64 = 0
        var lastPermitWait: TimeInterval?
        var lastServiceTime: TimeInterval?
    }
    struct Snapshot: Sendable {
        var sourceGeneration: UInt64 = 0
        var configurationRevision: UInt64?
        var selectionRevision: UInt64 = 0
        var candidates: [Candidate] = []
        var decision: SubjectSelector.Decision?
        var sampledAt: TimeInterval?
        var statistics = Statistics()
        var selected: SubjectSelector.Selection? {
            guard case .selected(let selection) = decision else { return nil }
            return selection
        }
    }

    /// Starts, rather than requests, obey this cadence. There are no saved
    /// credits: delayed permits cannot create a catch-up burst.
    final class StartGate: @unchecked Sendable {
        private let lock = NSLock()
        private let minimumInterval: TimeInterval
        private var lastStart: TimeInterval?
        init(maximumStartsPerSecond: Double) { minimumInterval = 1 / maximumStartsPerSecond }
        func admit(at now: TimeInterval) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard minimumInterval.isFinite, minimumInterval > 0, now.isFinite, now >= 0,
                  lastStart.map({ now >= $0 && now - $0 >= minimumInterval }) ?? true else { return false }
            lastStart = now
            return true
        }
    }

    /// Shared with the detector's serial executor. Retirement and beginning
    /// actual Vision work serialize on the same lock. A running call cannot
    /// be preempted; its completion remains unpublishable after retirement.
    final class WorkToken: @unchecked Sendable {
        enum Retirement: Equatable, Sendable { case pending, running, finished, alreadyRetired }
        struct Outcome: Equatable, Sendable {
            let startedAt: TimeInterval?
            let finishedAt: TimeInterval?
            let isRetired: Bool
        }
        private let lock = NSLock()
        private let startGate: StartGate
        private var retired = false
        private var startedAt: TimeInterval?
        private var finishedAt: TimeInterval?
        init(startGate: StartGate) { self.startGate = startGate }
        func begin(at now: TimeInterval) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !retired, startedAt == nil, finishedAt == nil, startGate.admit(at: now) else { return false }
            startedAt = now
            return true
        }
        func finish(at now: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            if startedAt != nil, finishedAt == nil { finishedAt = now }
        }
        @discardableResult func retire() -> Retirement {
            lock.lock(); defer { lock.unlock() }
            guard !retired else { return .alreadyRetired }
            retired = true
            if finishedAt != nil { return .finished }
            return startedAt == nil ? .pending : .running
        }
        var outcome: Outcome {
            lock.lock(); defer { lock.unlock() }
            return .init(startedAt: startedAt, finishedAt: finishedAt, isRetired: retired)
        }
        var mayPublish: Bool {
            let value = outcome
            return !value.isRetired && value.startedAt != nil && value.finishedAt != nil
        }
    }

    /// Per-input numeric state only. No pixels, face signatures, names or
    /// persistent study logs are retained here.
    struct State: Sendable {
        private struct Stable: Sendable { let x: Double; let y: Double; let since: TimeInterval; let lastSeen: TimeInterval }
        private var stable: [UUID: Stable] = [:]
        private(set) var binding: Binding?
        private(set) var snapshot = Snapshot()
        private var requestedAt: TimeInterval?
        private var startGate: StartGate?

        mutating func configure(_ configuration: Configuration?) {
            retire()
            startGate = configuration.flatMap { $0.isValid ? StartGate(maximumStartsPerSecond: $0.maximumStartsPerSecond) : nil }
            snapshot.configurationRevision = configuration.flatMap { $0.isValid ? $0.revision : nil }
        }
        mutating func retire() {
            // Repeated ineligible frames may observe the same already-retired
            // token while non-preemptible work finishes. Retire a real binding
            // once; do not manufacture a new UI selection revision each frame.
            guard binding != nil || !stable.isEmpty || requestedAt != nil ||
                  !snapshot.candidates.isEmpty || snapshot.decision != nil || snapshot.sampledAt != nil else { return }
            binding = nil; stable.removeAll(); requestedAt = nil
            snapshot.candidates = []; snapshot.decision = nil; snapshot.sampledAt = nil
            snapshot.selectionRevision &+= 1
        }
        mutating func expireSnapshot(at now: TimeInterval, maximumAge: TimeInterval) {
            guard let sampledAt = snapshot.sampledAt else { return }
            guard now.isFinite, maximumAge.isFinite, maximumAge >= 0,
                  now >= sampledAt, now - sampledAt <= maximumAge else {
                stable.removeAll()
                snapshot.candidates = []; snapshot.decision = nil; snapshot.sampledAt = nil
                snapshot.selectionRevision &+= 1
                return
            }
        }
        mutating func request(binding next: Binding, configuration: Configuration, now: TimeInterval) -> WorkToken? {
            guard configuration.isValid, next.configurationRevision == configuration.revision,
                  next.channel != next.context.program, next.context.permitted,
                  now.isFinite, now >= 0, let startGate else { return nil }
            if binding != next { retire(); binding = next }
            guard requestedAt.map({ now >= $0 && now - $0 >= 1 / configuration.maximumStartsPerSecond }) ?? true else { return nil }
            requestedAt = now
            snapshot.sourceGeneration = next.sourceGeneration
            snapshot.configurationRevision = configuration.revision
            snapshot.statistics.requested &+= 1
            return WorkToken(startGate: startGate)
        }
        mutating func recordRetirement(_ retirement: WorkToken.Retirement) {
            if retirement == .pending { snapshot.statistics.cancelledBeforeStart &+= 1 }
            if retirement == .running { snapshot.statistics.retiredWhileRunning &+= 1 }
        }
        mutating func completed(_ token: WorkToken, requestedAt: TimeInterval, permitAt: TimeInterval?) {
            let outcome = token.outcome
            if let start = outcome.startedAt {
                snapshot.statistics.started &+= 1
                if let finish = outcome.finishedAt {
                    snapshot.statistics.completed &+= 1
                    snapshot.statistics.lastServiceTime = max(0, finish - start)
                }
            }
            if let permitAt { snapshot.statistics.lastPermitWait = max(0, permitAt - requestedAt) }
        }
        mutating func rejectResult() { snapshot.statistics.rejectedResults &+= 1 }
        mutating func acquired() { snapshot.statistics.acquired &+= 1 }
        mutating func ingest(_ candidates: [Candidate], capturedAt: TimeInterval, now: TimeInterval,
                             binding expected: Binding, configuration: Configuration) -> SubjectSelector.Decision? {
            guard binding == expected, configuration.isValid, now.isFinite, capturedAt.isFinite,
                  capturedAt >= 0, now >= capturedAt, now - capturedAt <= configuration.maximumResultAge,
                  candidates.allSatisfy({ candidate in
                      let b = candidate.bounds
                      return [b.minX, b.minY, b.maxX, b.maxY].allSatisfy { $0.isFinite && (0...1).contains($0) } && b.width > 0 && b.height > 0
                  }) else {
                rejectResult(); return nil
            }
            var nextStable: [UUID: Stable] = [:]
            let observations = candidates.map { candidate -> SubjectSelector.Observation in
                let x = Double(candidate.bounds.midX), y = Double(candidate.bounds.midY)
                var since = capturedAt
                if let previous = stable[candidate.id] {
                    let gap = capturedAt - previous.lastSeen
                    let distance = hypot(x - previous.x, y - previous.y)
                    if gap > 0, gap <= configuration.maximumResultAge,
                       distance / gap <= configuration.maximumStableSpeed { since = previous.since }
                }
                nextStable[candidate.id] = .init(x: x, y: y, since: since, lastSeen: capturedAt)
                return .init(id: candidate.id, x: x, y: y, stableFor: max(0, capturedAt - since), observationAge: now - capturedAt)
            }
            stable = nextStable
            let decision = SubjectSelector.select(.init(channel: expected.channel, sourceGeneration: expected.sourceGeneration,
                sampledAt: now, observations: observations), nomination: nil, positionHint: configuration.positionHintZone,
                now: now, parameters: configuration.selectorParameters)
            snapshot.candidates = candidates
            snapshot.sampledAt = capturedAt
            snapshot.decision = decision
            snapshot.selectionRevision &+= 1
            return decision
        }
    }
}
