import Foundation

nonisolated enum HardwarePhase: String, Codable, Equatable, Sendable {
    case disconnected, discovered, negotiating, connectedDisarmed, armed, stopped, faulted
}
nonisolated enum HardwareCommand: Equatable, Sendable {
    case ping, disarm, stop, motion(velocity: Double, lease: TimeInterval)
}
nonisolated enum HardwareRejection: String, Error, Codable, Equatable, Sendable {
    case wrongPhase, versionMismatch, estopLatched, motionDisabled, leaseTooLong
    case malformed, oversize, duplicate, outOfOrder, late, heartbeatLost
    case unknownType, invalidRange, invalidClock, unhealthy, sequenceExhausted
}

/// A negotiated epoch, not a hardware serial number or authentication credential.
/// Both identities rotate at every negotiation; reboot also rotates boot immediately.
nonisolated struct HardwareNegotiation: Encodable, Equatable, Sendable {
    let v: Int
    let type: String = "hello"
    let boot: String
    let session: String
    let nonce: String?
    let motion: Bool = false
    let deviceTime: TimeInterval
    let maximumRecordBytes: Int
    let maximumMotionLease: TimeInterval
    let linkLossInterval: TimeInterval
}
nonisolated struct HardwareTelemetry: Encodable, Equatable, Sendable {
    let v: Int
    let type: String = "telemetry"
    let boot: String
    let session: String?
    let deviceTime: TimeInterval?
    let phase: HardwarePhase
    let healthy: Bool
    let estopLatched: Bool
    let driveEnabled: Bool = false
    let position: Double?
    let velocity: Double?
    let current: Double?
    let limits: [Bool]?
    let fault: String?

    enum CodingKeys: String, CodingKey {
        case v, type, boot, session, deviceTime, phase, healthy, estopLatched, driveEnabled
        case position, velocity, current, limits, fault
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(type, forKey: .type)
        try container.encode(boot, forKey: .boot)
        try container.encode(session, forKey: .session)
        try container.encode(deviceTime, forKey: .deviceTime)
        try container.encode(phase, forKey: .phase)
        try container.encode(healthy, forKey: .healthy)
        try container.encode(estopLatched, forKey: .estopLatched)
        try container.encode(driveEnabled, forKey: .driveEnabled)
        try container.encode(position, forKey: .position)
        try container.encode(velocity, forKey: .velocity)
        try container.encode(current, forKey: .current)
        try container.encode(limits, forKey: .limits)
        try container.encode(fault, forKey: .fault)
    }
}
/// Acceptance acknowledges a logical operation only, never physical rest or arrival.
nonisolated struct HardwareAck: Encodable, Equatable, Sendable {
    let v: Int
    let type: String = "ack"
    let boot: String
    let session: String
    let sequence: UInt64
    let accepted: Bool
    let rejection: HardwareRejection?
    enum CodingKeys: String, CodingKey {
        case v, type, boot, session, accepted, rejection
        case sequence = "ack_seq"
    }
}

nonisolated protocol HardwareTransport {
    func send(_ data: Data) throws
    func receive() throws -> Data?
}
nonisolated protocol HardwareLink {
    var phase: HardwarePhase { get }
    func discover() -> Bool
    func negotiate(version: Int) -> Result<Int, HardwareRejection>
    func connect() -> Result<Void, HardwareRejection>
    func arm() -> Result<Void, HardwareRejection>
    func disarm()
    func emergencyStop()
    func resetEmergencyStop() -> Result<Void, HardwareRejection>
    func command(_ command: HardwareCommand) -> Result<HardwareAck, HardwareRejection>
    func telemetry() -> HardwareTelemetry
    func heartbeat()
    func checkLink()
}

nonisolated struct HardwareTiming: Equatable, Sendable {
    let heartbeatInterval: TimeInterval
    let telemetryInterval: TimeInterval
    let maximumMotionLease: TimeInterval
    let linkLossInterval: TimeInterval
    // Study starting values, not qualified physical stopping limits.
    static let proposed = HardwareTiming(heartbeatInterval: 0.1,
        telemetryInterval: 0.05, maximumMotionLease: 0.2, linkLossInterval: 0.3)
    var isValid: Bool {
        let values = [heartbeatInterval, telemetryInterval, maximumMotionLease, linkLossInterval]
        return values.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 60 }
            && heartbeatInterval < linkLossInterval && maximumMotionLease <= linkLossInterval
    }
}

/// Deterministic device time: advancing it delivers watchdog events without host traffic.
/// This is a simulation scheduler, not a Mac timer or a physical safety implementation.
nonisolated final class SimulatedDeviceClock {
    private(set) var now: TimeInterval = 0
    private var observers: [UUID: () -> Void] = [:]
    func advance(by delta: TimeInterval) throws {
        guard delta.isFinite, delta >= 0, (now + delta).isFinite else {
            throw HardwareRejection.invalidClock
        }
        now += delta
        for observer in observers.values { observer() }
    }
    func observe(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID(); observers[id] = observer; return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}

/// Bootstrap has no command sequence or device deadline: neither exists yet.
/// The caller must first discover/open the link. A hello never establishes health.
nonisolated struct HardwareHelloRequest: Codable, Equatable, Sendable {
    let v: Int
    let type: String
    let nonce: String
}
nonisolated enum HardwareInboundRecord: Equatable, Sendable {
    case hello(HardwareHelloRequest)
    case command(HardwareWireRecord)
}
nonisolated enum HardwareResponse: Encodable, Equatable, Sendable {
    case hello(HardwareNegotiation)
    case ack(HardwareAck)
    var acknowledgement: HardwareAck? {
        if case .ack(let ack) = self { return ack }
        return nil
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .hello(let hello): try hello.encode(to: encoder)
        case .ack(let ack): try ack.encode(to: encoder)
        }
    }
}
