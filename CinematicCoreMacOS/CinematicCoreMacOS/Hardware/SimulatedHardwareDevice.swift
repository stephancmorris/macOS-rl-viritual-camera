import Foundation

/// Device-side safety model. Physical motion is impossible in this build.
nonisolated final class SimulatedHardwareDevice: HardwareLink {
    static let motionEnabled = false
    private(set) var phase: HardwarePhase = .disconnected
    private(set) var estopLatched = false
    private(set) var sequence: UInt64 = 0
    private(set) var protocolVersion: Int
    private let timing: HardwareTiming
    private let clock: () -> TimeInterval
    private var lastHeartbeat: TimeInterval?
    private var linkUp = true
    private var fault: String?
    private(set) var wireRejections: [HardwareRejection] = []
    private var codec: HardwareWireCodec

    init(protocolVersion: Int = 1, timing: HardwareTiming = .proposed,
         maximumRecordBytes: Int = 1024, clock: @escaping () -> TimeInterval) {
        self.protocolVersion = protocolVersion; self.timing = timing; self.clock = clock
        self.codec = HardwareWireCodec(maximumBytes: maximumRecordBytes, version: protocolVersion)
    }

    func discover() -> Bool {
        guard linkUp, phase == .disconnected else { return false }
        phase = .discovered; return true
    }
    func negotiate(version: Int) -> Result<Int, HardwareRejection> {
        guard phase == .discovered else { return .failure(.wrongPhase) }
        phase = .negotiating
        guard version == protocolVersion else {
            phase = .faulted; fault = "version mismatch"; return .failure(.versionMismatch)
        }
        return .success(protocolVersion)
    }
    func connect() -> Result<Void, HardwareRejection> {
        guard phase == .negotiating, linkUp else { return .failure(.wrongPhase) }
        phase = .connectedDisarmed; lastHeartbeat = clock(); fault = nil
        codec.begin(session: "session-\(sequence)")
        return .success(())
    }
    func arm() -> Result<Void, HardwareRejection> {
        guard !estopLatched else { return .failure(.estopLatched) }
        guard phase == .connectedDisarmed else { return .failure(.wrongPhase) }
        phase = .armed; return .success(())
    }
    func disarm() {
        if phase == .armed { phase = .connectedDisarmed }
    }
    func emergencyStop() {
        estopLatched = true; phase = .stopped; fault = "emergency stop"
    }
    func resetEmergencyStop() -> Result<Void, HardwareRejection> {
        guard estopLatched else { return .failure(.wrongPhase) }
        estopLatched = false
        phase = linkUp ? .connectedDisarmed : .disconnected
        fault = nil
        return .success(())
    }
    func command(_ command: HardwareCommand) -> Result<HardwareAck, HardwareRejection> {
        if estopLatched { return .failure(.estopLatched) }
        if case .motion(_, let lease) = command {
            if lease > timing.maximumMotionLease || lease <= 0 { return .failure(.leaseTooLong) }
            return .failure(.motionDisabled)
        }
        guard phase == .armed || phase == .connectedDisarmed else { return .failure(.wrongPhase) }
        sequence &+= 1
        switch command {
        case .disarm: disarm()
        case .stop: phase = .stopped
        case .ping, .motion: break
        }
        return .success(HardwareAck(sequence: sequence, accepted: true))
    }
    func telemetry() -> HardwareTelemetry {
        HardwareTelemetry(phase: phase, position: nil, velocity: nil, fault: fault)
    }
    func heartbeat() {
        guard linkUp, phase == .connectedDisarmed || phase == .armed else { return }
        lastHeartbeat = clock()
    }
    func checkLink() {
        guard phase == .armed || phase == .connectedDisarmed else { return }
        guard let lastHeartbeat, clock() - lastHeartbeat <= timing.linkLossInterval else {
            phase = .faulted; fault = "heartbeat lost"; return
        }
    }
    func dropLink() { linkUp = false; phase = .disconnected; lastHeartbeat = nil }
    func restoreLink() { linkUp = true; phase = .disconnected; lastHeartbeat = nil }
    func reboot() { sequence = 0; phase = .disconnected; lastHeartbeat = nil }
    func changeProtocolVersion(to version: Int) { protocolVersion = version; phase = .disconnected }
    func receiveWire(_ data: Data) -> Result<HardwareWireRecord, HardwareRejection> {
        let result = codec.decode(data)
        if case .failure(let reason) = result { wireRejections.append(reason) }
        return result
    }
    func sendGarbage() -> Result<HardwareWireRecord, HardwareRejection> {
        receiveWire(Data("garbage\n".utf8))
    }
    func stallHeartbeat() { /* Time advances through the injected clock. */ }
}
