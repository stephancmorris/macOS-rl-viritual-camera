import Foundation
import Testing
@testable import Alfie

@MainActor struct HardwareLinkTests {
    private func succeeded(_ result: Result<Void, HardwareRejection>) -> Bool {
        if case .success = result { return true }
        return false
    }
    private func failed(_ result: Result<Void, HardwareRejection>, as reason: HardwareRejection) -> Bool {
        if case .failure(let actual) = result { return actual == reason }
        return false
    }
    @Test func reconnectAndEmergencyStop() {
        var now = 0.0
        let device = SimulatedHardwareDevice(clock: { now })
        #expect(device.discover())
        #expect(device.negotiate(version: 1) == .success(1))
        #expect(succeeded(device.connect()))
        #expect(succeeded(device.arm()))
        #expect(device.command(.motion(velocity: 1, lease: 0.1)) == .failure(.motionDisabled))
        device.emergencyStop()
        #expect(device.command(.ping) == .failure(.estopLatched))
        #expect(failed(device.arm(), as: .estopLatched))
        #expect(succeeded(device.resetEmergencyStop()))
        #expect(device.phase == .connectedDisarmed)
        #expect(succeeded(device.arm()))
        now = 0.31; device.checkLink()
        #expect(device.phase == .faulted)
        device.dropLink(); device.restoreLink()
        #expect(device.discover())
        #expect(device.negotiate(version: 1) == .success(1))
        #expect(succeeded(device.connect()))
        #expect(device.phase == .connectedDisarmed)
        device.reboot()
        #expect(device.phase == .disconnected)
    }

    @Test func wireRejectsMalformedDuplicateLateAndOutOfOrder() throws {
        var codec = HardwareWireCodec(maximumBytes: 128, version: 1)
        codec.begin(session: "s")
        let first = HardwareWireRecord(v: 1, session: "s", seq: 4, type: "ack", payload: nil)
        let bytes = try codec.encode(first)
        #expect(codec.decode(bytes) == .success(first))
        #expect(codec.decode(bytes) == .failure(.duplicate))
        #expect(codec.decode(try codec.encode(.init(v: 1, session: "s", seq: 3, type: "ack", payload: nil))) == .failure(.outOfOrder))
        #expect(codec.decode(try codec.encode(.init(v: 1, session: "old", seq: 5, type: "ack", payload: nil))) == .failure(.late))
        #expect(codec.decode(Data("broken\n".utf8)) == .failure(.malformed))
        #expect(codec.decode(Data(repeating: 0x20, count: 129)) == .failure(.oversize))
    }

    @Test func versionMismatchAndQuitDisarm() {
        let device = SimulatedHardwareDevice(clock: { 0 })
        #expect(device.discover())
        #expect(device.negotiate(version: 2) == .failure(.versionMismatch))
        #expect(device.phase == .faulted)
        device.dropLink(); device.restoreLink()
        #expect(device.discover())
        #expect(device.negotiate(version: 1) == .success(1))
        #expect(succeeded(device.connect()))
        #expect(succeeded(device.arm()))
        device.dropLink() // app quit or unplug
        #expect(device.phase == .disconnected)
    }
}
