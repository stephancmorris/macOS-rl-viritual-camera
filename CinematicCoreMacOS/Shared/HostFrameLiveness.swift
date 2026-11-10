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
}

/// Reserving an accepted connection is not proof that its messages satisfy
/// XPC's signing requirement. Only an authenticated service request activates
/// its epoch; an old request cannot displace a newer authenticated host.
nonisolated struct HostConnectionEpochs {
    private var reserved: UInt64 = 0
    private(set) var active: UInt64?

    mutating func reserve() -> UInt64 {
        reserved &+= 1
        return reserved
    }

    mutating func activate(_ connection: UInt64) -> Bool {
        guard connection > 0, connection <= reserved,
              active.map({ connection >= $0 }) ?? true else { return false }
        active = connection
        return true
    }

    func isCurrent(_ connection: UInt64) -> Bool { connection == active }
}
