// Exact per-stage latency window. The manager owns each instance on MainActor.
import Foundation

@MainActor
final class LatencySampleWindow {
    private struct Sample {
        let timestamp: TimeInterval
        let duration: TimeInterval
    }

    static let windowSeconds: TimeInterval = 5
    private static let initialCapacity = 64
    private var storage = [Sample?](repeating: nil, count: initialCapacity)
    private var head = 0
    private var lastTimestamp: TimeInterval?
    private(set) var count = 0
    var storageCapacity: Int { storage.count }

    /// A stage's finite, nondecreasing clock defines its window. Equal stamps
    /// remain separate observations; a backwards stamp starts a new epoch.
    /// Rejecting a timestamp affects this window only, not the manager's raw
    /// duration accumulators. Expiry happens on append, as in the original API.
    @discardableResult
    func append(timestamp: TimeInterval, duration: TimeInterval) -> Bool {
        guard timestamp.isFinite else { return false }
        if let lastTimestamp, timestamp < lastTimestamp {
            storage = [Sample?](repeating: nil, count: Self.initialCapacity)
            head = 0
            count = 0
        }
        lastTimestamp = timestamp
        let cutoff = timestamp - Self.windowSeconds
        while count > 0, let oldest = storage[head], oldest.timestamp < cutoff {
            storage[head] = nil
            head = (head + 1) % storage.count
            count -= 1
        }

        // Release a burst's backing allocation once most of it expires. The
        // quarter-full threshold gives resizing hysteresis at normal cadence.
        if storage.count > Self.initialCapacity, count <= storage.count / 4 {
            var capacity = Self.initialCapacity
            while capacity < count * 2 { capacity *= 2 }
            resize(to: capacity)
        }
        if count == storage.count { resize(to: storage.count * 2) }
        storage[(head + count) % storage.count] = Sample(timestamp: timestamp, duration: duration)
        count += 1
        return true
    }

    /// Preserve the original chronological reduce order and arithmetic. The
    /// manager calls this only at its existing coalesced publication cadence.
    var averageDuration: TimeInterval? {
        guard count > 0 else { return nil }
        var total: TimeInterval = 0
        for offset in 0..<count {
            total += storage[(head + offset) % storage.count]!.duration
        }
        return total / Double(count)
    }

    private func resize(to capacity: Int) {
        var replacement = [Sample?](repeating: nil, count: capacity)
        for offset in 0..<count {
            replacement[offset] = storage[(head + offset) % storage.count]
        }
        storage = replacement
        head = 0
    }
}
