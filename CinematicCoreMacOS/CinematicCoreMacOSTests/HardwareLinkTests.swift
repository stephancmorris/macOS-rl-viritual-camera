import Foundation
import Testing
@testable import Alfie

@MainActor struct HardwareLinkTests {
    private func connected(_ clock: SimulatedDeviceClock = SimulatedDeviceClock(),
                           historyLimit: Int = 64) throws -> SimulatedHardwareDevice {
        let device = SimulatedHardwareDevice(historyLimit: historyLimit, deviceClock: clock)
        try connect(device)
        return device
    }
    private func connect(_ device: SimulatedHardwareDevice) throws {
        #expect(device.discover())
        #expect(try device.negotiate(version: 1).get() == 1)
        try device.connect().get()
    }
    private func record(_ device: SimulatedHardwareDevice, _ type: HardwareRecordType = .ping,
                        seq: UInt64? = nil, expiry: Double? = nil,
                        velocity: Double? = nil, lease: Double? = nil) throws -> HardwareWireRecord {
        let context = try #require(device.negotiation)
        return HardwareWireRecord(v: 1, boot: context.boot, session: context.session,
            seq: seq ?? (device.sequence + 1), type: type,
            expiresDeviceTime: expiry ?? ((device.telemetry().deviceTime ?? 0) + 0.1),
            velocity: velocity, lease: lease)
    }
    private func send(_ device: SimulatedHardwareDevice, _ record: HardwareWireRecord) throws -> HardwareAck {
        let outcomes = device.receiveWire(try HardwareWireCodec().encode(record))
        let result = try #require(outcomes.first).get()
        return try #require(result.acknowledgement)
    }
    @Test func noMotionCapabilityAndHealth() throws {
        let device = try connected()
        #expect(device.negotiation?.motion == false)
        #expect(throws: HardwareRejection.unhealthy) { try device.arm().get() }
        #expect(try send(device, record(device)).accepted)
        #expect(throws: HardwareRejection.motionDisabled) { try device.arm().get() }
        let ack = try send(device, record(device, .motion, velocity: 0.5, lease: 0.1))
        #expect(ack.rejection == .motionDisabled)
        #expect(device.phase == .connectedDisarmed)
        #expect(!device.telemetry().driveEnabled)
    }
    @Test func rebootReconnectAndEveryNegotiationRotateIdentities() throws {
        let device = try connected()
        let original = try #require(device.negotiation)
        let old = try record(device)
        device.dropLink(); device.restoreLink(); try connect(device)
        let second = try #require(device.negotiation)
        #expect(second.boot != original.boot && second.session != original.session)
        #expect(device.receiveWire(try HardwareWireCodec().encode(old)) == [.failure(.late)])
        device.reboot()
        #expect(device.boot != second.boot)
        try connect(device)
        #expect(device.negotiation?.session != second.session)
        #expect(!device.healthy && device.sequence == 0)
    }
    @Test func estopResetRequiresFreshNegotiationAndHealthThenRevokesAgain() throws {
        let device = try connected()
        device.heartbeat()
        let old = try record(device)
        #expect(try send(device, record(device, .estop)).accepted)
        #expect(device.estopLatched && device.phase == .stopped && device.negotiation == nil)
        #expect(throws: HardwareRejection.unhealthy) { try device.resetEmergencyStop().get() }
        device.dropLink(); device.restoreLink(); try connect(device)
        #expect(device.estopLatched)
        #expect(try send(device, record(device, .resetEstop)).rejection == .unhealthy)
        #expect(try send(device, record(device, .heartbeat)).accepted)
        let recovery = device.negotiation
        #expect(try send(device, record(device, .resetEstop)).accepted)
        #expect(!device.estopLatched && device.phase == .disconnected && device.negotiation == nil)
        #expect(device.receiveWire(try HardwareWireCodec().encode(old)) == [.failure(.late)])
        try connect(device)
        #expect(device.negotiation?.session != recovery?.session && !device.healthy)
        #expect(throws: HardwareRejection.unhealthy) { try device.arm().get() }
    }
    @Test func estopSurvivesRebootAndUnplug() throws {
        let device = try connected()
        device.emergencyStop(); device.reboot(); device.dropLink(); device.restoreLink()
        try connect(device)
        #expect(device.estopLatched)
        #expect(throws: HardwareRejection.estopLatched) { try device.arm().get() }
    }
    @Test func estopPrioritizesOverCoalescedPeersEvenSequenceGap() throws {
        let device = try connected()
        let codec = HardwareWireCodec()
        let ping = try record(device, .ping, seq: 1)
        let stop = try record(device, .estop, seq: 2)
        let reset = try record(device, .resetEstop, seq: 3)
        let result = device.receiveWire(try codec.encode(ping) + codec.encode(stop) + codec.encode(reset))
        #expect(result.count == 3)
        #expect(result[0] == .failure(.estopLatched))
        #expect(try result[1].get().acknowledgement?.rejection == .outOfOrder)
        #expect(result[2] == .failure(.estopLatched))
        #expect(device.estopLatched && !device.healthy && device.negotiation == nil)
    }
    @Test func expiredAndForeignEstopAreNotCommands() throws {
        let device = try connected()
        #expect(try send(device, record(device, .estop, expiry: 0)).rejection == .late)
        let foreign = HardwareWireRecord(v: 1, boot: UUID().uuidString, session: UUID().uuidString,
            seq: 1, type: .estop, expiresDeviceTime: 0.1)
        #expect(device.receiveWire(try HardwareWireCodec().encode(foreign)) == [.failure(.late)])
        #expect(!device.estopLatched)
    }
    @Test func watchdogFiresWithoutHostCallAtDeadline() throws {
        let clock = SimulatedDeviceClock(); let device = try connected(clock)
        #expect(try send(device, record(device, .heartbeat)).accepted)
        try clock.advance(by: 0.3)
        #expect(device.phase == .faulted && device.negotiation == nil && !device.healthy)
        #expect(device.telemetry().fault == HardwareRejection.heartbeatLost.rawValue)
    }
    @Test func duplicateHeartbeatCannotExtendWatchdog() throws {
        let clock = SimulatedDeviceClock(); let device = try connected(clock)
        let heartbeat = try record(device, .heartbeat, expiry: 0.2)
        #expect(try send(device, heartbeat).accepted)
        try clock.advance(by: 0.15)
        #expect(try send(device, heartbeat).rejection == .duplicate)
        try clock.advance(by: 0.15)
        #expect(device.phase == .faulted)
    }
    @Test func lateHeartbeatCannotReviveFault() throws {
        let clock = SimulatedDeviceClock(); let device = try connected(clock)
        let heartbeat = try record(device, .heartbeat)
        try clock.advance(by: 1)
        #expect(device.receiveWire(try HardwareWireCodec().encode(heartbeat)) == [.failure(.late)])
        #expect(device.phase == .faulted)
    }
    @Test func unplugQuitStopAndVersionMismatchRevoke() throws {
        for type in [HardwareRecordType.quit, .stop] {
            let device = try connected()
            #expect(try send(device, record(device, type)).accepted)
            #expect(device.negotiation == nil && !device.telemetry().driveEnabled)
        }
        let device = try connected()
        device.dropLink()
        #expect(device.phase == .disconnected && device.negotiation == nil)
        device.restoreLink()
        #expect(device.discover())
        #expect(device.negotiate(version: 2) == .failure(.versionMismatch))
        #expect(device.phase == .faulted)
    }
    @Test func wireVersionMismatchRevokesAndChangedVersionRequiresNegotiation() throws {
        let device = try connected(); let context = try #require(device.negotiation)
        let bad = HardwareWireRecord(v: 2, boot: context.boot, session: context.session,
            seq: 1, type: .ping, expiresDeviceTime: 0.1)
        #expect(device.receiveWire(try HardwareWireCodec().encode(bad)) == [.failure(.versionMismatch)])
        #expect(device.negotiation == nil && device.phase == .faulted)
        device.changeProtocolVersion(to: 2)
        #expect(device.discover())
        #expect(device.negotiate(version: 2) == .success(2))
        try device.connect().get()
        #expect(device.negotiation?.v == 2 && !device.healthy)
    }
    @Test func partialAndCoalescedRecordsReachEffectsOnlyAfterNewline() throws {
        let device = try connected(); let codec = HardwareWireCodec()
        let first = try codec.encode(record(device, .heartbeat, seq: 1))
        #expect(device.receiveWire(first.prefix(first.count - 1)).isEmpty)
        #expect(!device.healthy)
        let second = try codec.encode(record(device, .disarm, seq: 2))
        let replies = device.receiveWire(first.suffix(1) + second)
        #expect(replies.count == 2 && device.healthy && device.sequence == 2)
        #expect(try replies[0].get().acknowledgement?.sequence == 1)
        #expect(try replies[1].get().acknowledgement?.sequence == 2)
    }
    @Test func everyByteFragmentationWorks() throws {
        let device = try connected()
        let bytes = try HardwareWireCodec().encode(record(device))
        var replies: [Result<HardwareResponse, HardwareRejection>] = []
        for byte in bytes { replies += device.receiveWire(Data([byte])) }
        #expect(replies.count == 1 && device.healthy)
    }
    @Test func rejectedAttemptConsumesSequenceButGapDoesNot() throws {
        let device = try connected()
        #expect(try send(device, record(device, seq: 2)).rejection == .outOfOrder)
        #expect(device.sequence == 0)
        let expired = try record(device, seq: 1, expiry: 0)
        #expect(try send(device, expired).rejection == .late)
        #expect(try send(device, expired).rejection == .duplicate)
        #expect(try send(device, record(device, seq: 2)).accepted)
        #expect(try send(device, expired).rejection == .outOfOrder)
    }
    @Test func strictSchemaRejectsDuplicateEscapedUnknownAndNestedKeys() throws {
        let device = try connected()
        let good = String(decoding: try HardwareWireCodec().encode(record(device)), as: UTF8.self)
        let invalid = [
            "{\"v\":1," + good.dropFirst(),
            "{\"\\u0076\":1," + good.dropFirst(),
            "{\"unexpected\":{}," + good.dropFirst(),
            good.replacingOccurrences(of: "\"ping\"", with: "\"goto\""),
            good.replacingOccurrences(of: "\"ping\"", with: "\"ack\""),
            "[]\n", "null\n", "{\"type\":\"ping\"}\n", "garbage\n"
        ]
        for raw in invalid {
            let result = device.receiveWire(Data(raw.utf8))
            #expect(result.count == 1)
            if case .success = result[0] { Issue.record("Invalid schema accepted") }
        }
        #expect(!device.healthy && device.sequence == 0)
        #expect(try send(device, record(device)).accepted)
    }
    @Test func oversizePartialIsBoundedAndDrainedBeforeRecovery() throws {
        var codec = HardwareWireCodec(maximumBytes: 512)
        #expect(codec.feed(Data(repeating: 32, count: 512)) == [.failure(.oversize)])
        #expect(codec.bufferedBytes == 0)
        #expect(codec.feed(Data(repeating: 32, count: 4000)).isEmpty)
        let device = try connected()
        let bytes = try codec.encode(record(device))
        #expect(codec.feed(Data([10]) + bytes).count == 1)
        #expect(codec.bufferedBytes == 0)
    }
    @Test func chunkAndRecordCountBounds() {
        var codec = HardwareWireCodec()
        #expect(codec.feed(Data(repeating: 32, count: 65_537)) == [.failure(.oversize)])
        #expect(codec.bufferedBytes == 0)
        #expect(codec.feed(Data(repeating: 10, count: 65)) == [.failure(.oversize)])
    }
    @Test func partialOldSessionCannotCrossReconnect() throws {
        let device = try connected(); let bytes = try HardwareWireCodec().encode(record(device))
        #expect(device.receiveWire(bytes.dropLast()).isEmpty)
        device.dropLink(); device.restoreLink(); try connect(device)
        #expect(device.receiveWire(Data([10])) == [.failure(.malformed)])
        #expect(try send(device, record(device)).accepted)
    }
    @Test func invalidTimingAndBoundsFailClosed() {
        for bad in [Double.nan, .infinity, -.infinity, 0, -1, 61] {
            let timing = HardwareTiming(heartbeatInterval: bad, telemetryInterval: 0.05,
                maximumMotionLease: 0.2, linkLossInterval: 0.3)
            let device = SimulatedHardwareDevice(timing: timing, clock: { 0 })
            #expect(!device.discover() && device.phase == .faulted)
        }
        #expect(!HardwareTiming(heartbeatInterval: 0.3, telemetryInterval: 0.05,
            maximumMotionLease: 0.2, linkLossInterval: 0.3).isValid)
        #expect(!HardwareTiming(heartbeatInterval: 0.1, telemetryInterval: 0.05,
            maximumMotionLease: 0.4, linkLossInterval: 0.3).isValid)
        for limit in [0, 127, 4097] {
            #expect(!SimulatedHardwareDevice(maximumRecordBytes: limit, clock: { 0 }).discover())
        }
    }
    @Test func nonfiniteLeaseVelocityAndTimeNeverPassDirectAdapter() throws {
        let device = try connected(); device.heartbeat()
        for value in [Double.nan, .infinity, -.infinity, -1, 0, 0.3] {
            let ack = try device.command(.motion(velocity: 0.5, lease: value)).get()
            #expect(!ack.accepted)
        }
        for value in [Double.nan, .infinity, -.infinity, -2, 2] {
            #expect(try device.command(.motion(velocity: value, lease: 0.1)).get().rejection == .invalidRange)
        }
        #expect(device.phase == .connectedDisarmed)
    }
    @Test func wireInvalidRangesCannotUpdateHealth() throws {
        let device = try connected()
        let good = String(decoding: try HardwareWireCodec().encode(record(device)), as: UTF8.self)
        for expiry in ["1e999", "-1", "null", "true", "\"NaN\""] {
            let raw = good.replacingOccurrences(of: "\"expiresDeviceTime\":0.1", with: "\"expiresDeviceTime\":" + expiry)
            #expect(raw != good)
            #expect(device.receiveWire(Data(raw.utf8)) == [.failure(expiry == "1e999" ? .malformed : .invalidRange)])
        }
        #expect(!device.healthy)
    }
    @Test func invalidAndBackwardsClockRevokes() throws {
        var now = 1.0
        let device = SimulatedHardwareDevice(clock: { now }); try connect(device)
        device.heartbeat(); now = 0.5; device.checkLink()
        #expect(device.phase == .faulted && device.negotiation == nil)
        now = .nan; device.checkLink()
        #expect(device.phase == .faulted)
        let clock = SimulatedDeviceClock()
        for bad in [Double.nan, .infinity, -1] {
            #expect(throws: HardwareRejection.invalidClock) { try clock.advance(by: bad) }
        }
        #expect(clock.now == 0)
        #expect(device.telemetry().deviceTime == nil)
    }
    @Test func diagnosticsAreBoundedAndTelemetryDoesNotInventMeasurements() throws {
        let device = try connected(historyLimit: 3)
        for _ in 0..<100 { _ = device.receiveWire(Data("bad\n".utf8)) }
        #expect(device.wireRejections == [.malformed, .malformed, .malformed])
        let telemetry = device.telemetry()
        #expect(telemetry.position == nil && telemetry.velocity == nil && telemetry.current == nil && telemetry.limits == nil)
        #expect(!telemetry.driveEnabled && !telemetry.healthy)
        let ack = try send(device, record(device))
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ack)) as? [String: Any])
        #expect(json["ack_seq"] as? Int == 1 && json["seq"] == nil)
        #expect(json["type"] as? String == "ack")
        let telemetryJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(telemetry)) as? [String: Any])
        #expect(telemetryJSON["position"] is NSNull && telemetryJSON["velocity"] is NSNull)
        #expect(telemetryJSON["current"] is NSNull && telemetryJSON["limits"] is NSNull)
    }

    @Test func decodedHelloNegotiatesCapabilitiesAndRejectsReplay() throws {
        let device = SimulatedHardwareDevice(deviceClock: SimulatedDeviceClock())
        #expect(device.discover())
        let nonce = UUID().uuidString
        var hello = try JSONEncoder().encode(HardwareHelloRequest(v: 1, type: "hello", nonce: nonce))
        hello.append(10)
        let result = try #require(device.receiveWire(hello).first).get()
        guard case .hello(let negotiated) = result else { Issue.record("Expected hello"); return }
        #expect(negotiated.nonce == nonce && !negotiated.motion && !device.healthy)
        #expect(device.phase == .connectedDisarmed && device.sequence == 0)
        #expect(device.receiveWire(hello) == [.failure(.wrongPhase)])
        #expect(try send(device, record(device, .heartbeat)).accepted)
    }
    @Test func decodedHelloVersionMismatchStaysDisarmed() throws {
        let device = SimulatedHardwareDevice(deviceClock: SimulatedDeviceClock())
        #expect(device.discover())
        var hello = try JSONEncoder().encode(HardwareHelloRequest(v: 2, type: "hello", nonce: UUID().uuidString))
        hello.append(10)
        #expect(device.receiveWire(hello) == [.failure(.versionMismatch)])
        #expect(device.phase == .faulted && device.negotiation == nil)
    }
    @Test func invalidHistoryConfigurationCannotBeResetIntoUse() {
        let device = SimulatedHardwareDevice(historyLimit: 0, clock: { 0 })
        device.restoreLink()
        #expect(!device.discover())
    }
    @Test func motionWireRangesAndDeadlineBoundaries() throws {
        let device = try connected()
        #expect(try send(device, record(device, .motion, expiry: 0.2, velocity: 1, lease: 0.2)).rejection == .motionDisabled)
        #expect(try send(device, record(device, expiry: 0.20001)).rejection == .leaseTooLong)
        let invalid = try record(device, .motion, velocity: 1.01, lease: 0.1)
        #expect(device.receiveWire(try HardwareWireCodec().encode(invalid)) == [.failure(.invalidRange)])
        #expect(try send(device, record(device, .motion, velocity: 0, lease: 0.20001)).rejection == .leaseTooLong)
    }
    @Test func duplicateSequenceEstopStillLatchesWithNegativeAck() throws {
        let device = try connected()
        #expect(try send(device, record(device, .heartbeat, seq: 1)).accepted)
        let stop = try record(device, .estop, seq: 1)
        #expect(try send(device, stop).rejection == .duplicate)
        #expect(device.estopLatched && device.negotiation == nil && !device.healthy)
    }
    @Test func newProtocolRecordsUseNewVersionAtEffects() throws {
        let device = try connected()
        device.changeProtocolVersion(to: 2)
        #expect(device.discover())
        #expect(device.negotiate(version: 2) == .success(2))
        try device.connect().get()
        let context = try #require(device.negotiation)
        let ping = HardwareWireRecord(v: 2, boot: context.boot, session: context.session,
            seq: 1, type: .ping, expiresDeviceTime: 0.1)
        let ack = try send(device, ping)
        #expect(ack.accepted && ack.v == 2 && device.healthy)
    }

}
