import Foundation

/// Pure reception rules; callers supply a monotonic arrival clock and hold
/// their own state lock. Host-provided media timestamps are not liveness.
nonisolated enum HostFrameLiveness {
    static let timeout: TimeInterval = 1

    static func shouldStopReceiving(isReceiving: Bool, lastArrival: TimeInterval?, now: TimeInterval) -> Bool {
        guard isReceiving else { return false }
        guard let lastArrival, lastArrival.isFinite, now.isFinite, now >= lastArrival else { return true }
        return now - lastArrival >= timeout
    }

    static func isCurrentConnection(_ connection: UUID, active: UUID?) -> Bool {
        connection == active
    }
}
