import Foundation

/// Serialized device-side model, with no motor implementation or armed transition.
/// Advancing SimulatedDeviceClock invokes its watchdog even with a silent host.
/// Injection of a raw clock remains available for compatibility/fault tests; callers
/// using that overload must poll checkLink. Neither mode proves physical stopping.
nonisolated final class SimulatedHardwareDevice: HardwareLink {
    static let motionEnabled = false
    private(set) var phase: HardwarePhase = .disconnected
    private(set) var estopLatched = false
    private(set) var sequence: UInt64 = 0
    private(set) var protocolVersion: Int
    private(set) var boot = UUID().uuidString
    private(set) var negotiation: HardwareNegotiation?
    private(set) var wireRejections: [HardwareRejection] = []
    private(set) var healthy = false
    private let timing: HardwareTiming
    private let clock: () -> TimeInterval
    private let historyLimit: Int
    private let historyConfigurationValid: Bool
    private var deviceClock: SimulatedDeviceClock?
    private var clockObserver: UUID?
    private var lastHeartbeat: TimeInterval?
    private var lastObservedTime: TimeInterval?
    private var linkUp = true
    private var fault: String?
    private var codec: HardwareWireCodec

    init(protocolVersion: Int = 1, timing: HardwareTiming = .proposed,
         maximumRecordBytes: Int = 1024, historyLimit: Int = 64,
         clock: @escaping () -> TimeInterval) {
        self.protocolVersion = protocolVersion; self.timing = timing; self.clock = clock
        self.historyLimit = min(max(historyLimit, 1), 256)
        self.historyConfigurationValid = (1...256).contains(historyLimit)
        codec = HardwareWireCodec(maximumBytes: maximumRecordBytes)
        if protocolVersion <= 0 || !timing.isValid || !(128...4096).contains(maximumRecordBytes)
            || !(1...256).contains(historyLimit) {
            phase = .faulted; fault = HardwareRejection.invalidRange.rawValue
        }
    }
    convenience init(protocolVersion: Int = 1, timing: HardwareTiming = .proposed,
                     maximumRecordBytes: Int = 1024, historyLimit: Int = 64,
                     deviceClock: SimulatedDeviceClock) {
        self.init(protocolVersion: protocolVersion, timing: timing,
                  maximumRecordBytes: maximumRecordBytes, historyLimit: historyLimit,
                  clock: { deviceClock.now })
        self.deviceClock = deviceClock
        clockObserver = deviceClock.observe { [weak self] in self?.checkLink() }
    }
    deinit { if let clockObserver { deviceClock?.removeObserver(clockObserver) } }

    private var configurationValid: Bool {
        historyConfigurationValid && protocolVersion > 0 && timing.isValid && (128...4096).contains(codec.maximumBytes)
    }
    private func revoke(_ nextPhase: HardwarePhase, reason: String? = nil) {
        phase = nextPhase; fault = reason; negotiation = nil; healthy = false
        lastHeartbeat = nil; sequence = 0; codec.reset()
    }
    private func remember(_ reason: HardwareRejection) {
        if wireRejections.count == historyLimit { wireRejections.removeFirst() }
        wireRejections.append(reason)
    }
    @discardableResult private func observeTime() -> TimeInterval? {
        let now = clock()
        guard now.isFinite, now >= 0, lastObservedTime.map({ now >= $0 }) ?? true else {
            revoke(.faulted, reason: HardwareRejection.invalidClock.rawValue); return nil
        }
        lastObservedTime = now
        return now
    }
    func checkLink() {
        guard let now = observeTime() else { return }
        checkLink(at: now)
    }
    private func checkLink(at now: TimeInterval) {
        guard phase == .connectedDisarmed else { return }
        guard let lastHeartbeat, now - lastHeartbeat < timing.linkLossInterval else {
            revoke(.faulted, reason: HardwareRejection.heartbeatLost.rawValue); return
        }
    }
    func discover() -> Bool {
        guard configurationValid, observeTime() != nil, linkUp, phase == .disconnected else { return false }
        phase = .discovered; return true
    }
    func negotiate(version: Int) -> Result<Int, HardwareRejection> {
        negotiate(version: version, nonce: nil)
    }
    private func negotiate(version: Int, nonce: String?) -> Result<Int, HardwareRejection> {
        guard phase == .discovered, linkUp, let now = observeTime(), configurationValid else {
            return .failure(.wrongPhase)
        }
        // Rotate even on a failed attempt. No identity from a previous negotiation survives.
        boot = UUID().uuidString
        revoke(.negotiating)
        guard version == protocolVersion else {
            revoke(.faulted, reason: HardwareRejection.versionMismatch.rawValue)
            return .failure(.versionMismatch)
        }
        negotiation = HardwareNegotiation(v: protocolVersion, boot: boot, session: UUID().uuidString, nonce: nonce,
            deviceTime: now, maximumRecordBytes: codec.maximumBytes,
            maximumMotionLease: timing.maximumMotionLease, linkLossInterval: timing.linkLossInterval)
        return .success(protocolVersion)
    }
    func connect() -> Result<Void, HardwareRejection> {
        guard phase == .negotiating, linkUp, negotiation != nil, let now = observeTime() else {
            return .failure(.wrongPhase)
        }
        phase = .connectedDisarmed; lastHeartbeat = now; healthy = false
        return .success(())
    }
    func arm() -> Result<Void, HardwareRejection> {
        checkLink()
        guard !estopLatched else { return .failure(.estopLatched) }
        guard phase == .connectedDisarmed else { return .failure(.wrongPhase) }
        guard healthy else { return .failure(.unhealthy) }
        return .failure(.motionDisabled)
    }
    func disarm() { _ = command(.disarm) }
    func emergencyStop() {
        estopLatched = true; revoke(.stopped, reason: "emergency stop")
    }
    func resetEmergencyStop() -> Result<Void, HardwareRejection> {
        checkLink()
        guard estopLatched else { return .failure(.wrongPhase) }
        // E-stop revoked its session. Only a fresh negotiation + current heartbeat
        // can reach this state. Clearing then revokes that recovery session as well.
        guard linkUp, phase == .connectedDisarmed, negotiation != nil, healthy else {
            return .failure(.unhealthy)
        }
        estopLatched = false; revoke(.disconnected)
        return .success(())
    }
    func command(_ command: HardwareCommand) -> Result<HardwareAck, HardwareRejection> {
        let type: HardwareRecordType
        var velocity: Double?; var lease: TimeInterval?
        switch command {
        case .ping: type = .ping
        case .disarm: type = .disarm
        case .stop: type = .stop
        case .motion(let speed, let duration): type = .motion; velocity = speed; lease = duration
        }
        return localRecord(type, velocity: velocity, lease: lease)
    }
    private func localRecord(_ type: HardwareRecordType, velocity: Double? = nil,
                             lease: TimeInterval? = nil) -> Result<HardwareAck, HardwareRejection> {
        checkLink()
        guard let context = negotiation, let now = observeTime() else { return .failure(.wrongPhase) }
        guard sequence < UInt64.max else { return .failure(.sequenceExhausted) }
        return apply(HardwareWireRecord(v: protocolVersion, boot: context.boot, session: context.session,
            seq: sequence + 1, type: type, expiresDeviceTime: now + timing.maximumMotionLease,
            velocity: velocity, lease: lease))
    }
    func heartbeat() { _ = localRecord(.heartbeat) }
    func telemetry() -> HardwareTelemetry {
        checkLink()
        return HardwareTelemetry(v: protocolVersion, boot: boot, session: negotiation?.session,
            deviceTime: fault == HardwareRejection.invalidClock.rawValue ? nil : lastObservedTime, phase: phase, healthy: healthy, estopLatched: estopLatched,
            position: nil, velocity: nil, current: nil, limits: nil, fault: fault)
    }
    func dropLink() { linkUp = false; revoke(.disconnected) }
    func appQuit() { dropLink() }
    func restoreLink() { linkUp = true; revoke(.disconnected) }
    func reboot() {
        boot = UUID().uuidString; lastObservedTime = nil; revoke(.disconnected)
        // Conservative simulator policy: reboot never clears the e-stop latch.
    }
    func changeProtocolVersion(to version: Int) {
        protocolVersion = version; boot = UUID().uuidString; revoke(.disconnected)
    }

    /// All commands, including coalesced/fragmented traffic, reach the same effect gate.
    /// A valid current e-stop is prioritized over every peer in this receive batch.
    /// Replayed/out-of-order e-stop still latches, but is negatively acknowledged;
    /// old-session, expired, malformed or wrong-version bytes never become commands.
    func receiveWire(_ data: Data) -> [Result<HardwareResponse, HardwareRejection>] {
        checkLink()
        let records = codec.feed(data)
        let now = observeTime()
        if let now { checkLink(at: now) }
        let context = negotiation
        if let context, let now, let index = records.firstIndex(where: {
            guard case .success(.command(let record)) = $0 else { return false }
            return record.type == .estop && record.v == protocolVersion
                && record.boot == context.boot && record.session == context.session
                && record.expiresDeviceTime > now
                && record.expiresDeviceTime <= now + timing.maximumMotionLease
        }), case .success(.command(let stop)) = records[index] {
            let rejection = sequenceReason(stop.seq)
            emergencyStop()
            return records.enumerated().map { offset, result in
                if offset == index { return reply(stop, rejection).map(HardwareResponse.ack) }
                if case .failure(let reason) = result { remember(reason); return .failure(reason) }
                return .failure(.estopLatched)
            }
        }
        return records.map {
            switch $0 {
            case .failure(let reason): remember(reason); return .failure(reason)
            case .success(.command(let record)): return apply(record).map(HardwareResponse.ack)
            case .success(.hello(let hello)):
                switch negotiate(version: hello.v, nonce: hello.nonce) {
                case .failure(let reason): remember(reason); return .failure(reason)
                case .success:
                    guard case .success = connect(), let negotiation else { return .failure(.wrongPhase) }
                    return .success(.hello(negotiation))
                }
            }
        }
    }
    private func sequenceReason(_ value: UInt64) -> HardwareRejection? {
        if value == sequence { return .duplicate }
        if value < sequence { return .outOfOrder }
        if sequence == UInt64.max { return .sequenceExhausted }
        if value != sequence + 1 { return .outOfOrder }
        return nil
    }
    private func reply(_ record: HardwareWireRecord, _ rejection: HardwareRejection?) -> Result<HardwareAck, HardwareRejection> {
        if let rejection { remember(rejection) }
        return .success(HardwareAck(v: protocolVersion, boot: record.boot, session: record.session,
            sequence: record.seq, accepted: rejection == nil, rejection: rejection))
    }
    private func apply(_ record: HardwareWireRecord) -> Result<HardwareAck, HardwareRejection> {
        checkLink()
        guard record.v == protocolVersion else {
            revoke(.faulted, reason: HardwareRejection.versionMismatch.rawValue)
            remember(.versionMismatch); return .failure(.versionMismatch)
        }
        guard let context = negotiation, record.boot == context.boot, record.session == context.session else {
            remember(.late); return .failure(.late)
        }
        if let reason = sequenceReason(record.seq) { return reply(record, reason) }
        // A correlated attempt consumes its sequence even if denied. No retry can
        // turn the same record into a newly authorized action after state changes.
        sequence = record.seq
        guard let now = observeTime(), record.expiresDeviceTime.isFinite,
              record.expiresDeviceTime >= 0 else { return reply(record, .invalidRange) }
        // Admission can cross the heartbeat deadline between clock samples.
        checkLink(at: now)
        guard negotiation == context else { remember(.late); return .failure(.late) }
        guard record.expiresDeviceTime > now else { return reply(record, .late) }
        guard record.expiresDeviceTime <= now + timing.maximumMotionLease else {
            return reply(record, .leaseTooLong)
        }
        guard linkUp, phase == .connectedDisarmed else { return reply(record, .wrongPhase) }
        switch record.type {
        case .estop: emergencyStop()
        case .quit: appQuit()
        case .stop: revoke(.stopped)
        case .disarm: break // Always disarmed; cannot clear faults or e-stop.
        case .ping, .heartbeat: lastHeartbeat = now; healthy = true
        case .resetEstop:
            if case .failure(let reason) = resetEmergencyStop() { return reply(record, reason) }
        case .arm:
            if case .failure(let reason) = arm() { return reply(record, reason) }
        case .motion:
            guard let velocity = record.velocity, velocity.isFinite, abs(velocity) <= 1,
                  let lease = record.lease, lease.isFinite, lease > 0 else { return reply(record, .invalidRange) }
            guard lease <= timing.maximumMotionLease else { return reply(record, .leaseTooLong) }
            return reply(record, estopLatched ? .estopLatched : .motionDisabled)
        }
        return reply(record, nil)
    }
}
