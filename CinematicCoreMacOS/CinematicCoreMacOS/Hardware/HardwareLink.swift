import Foundation

nonisolated enum HardwarePhase: Equatable, Sendable {
    case disconnected, discovered, negotiating, connectedDisarmed, armed, stopped, faulted
}
nonisolated enum HardwareCommand: Equatable, Sendable {
    case ping, disarm, stop, motion(velocity: Double, lease: TimeInterval)
}
nonisolated enum HardwareRejection: Error, Equatable, Sendable {
    case wrongPhase, versionMismatch, estopLatched, motionDisabled, leaseTooLong
    case malformed, oversize, duplicate, outOfOrder, late, heartbeatLost
}
nonisolated struct HardwareTelemetry: Equatable, Sendable {
    let phase: HardwarePhase
    let position: Double?
    let velocity: Double?
    let fault: String?
}
nonisolated struct HardwareAck: Equatable, Sendable { let sequence: UInt64; let accepted: Bool }

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
    // Proposed starting points; hardware firmware must enforce its own deadline.
    static let proposed = HardwareTiming(heartbeatInterval: 0.1,
        telemetryInterval: 0.025, maximumMotionLease: 0.2, linkLossInterval: 0.3)
}
