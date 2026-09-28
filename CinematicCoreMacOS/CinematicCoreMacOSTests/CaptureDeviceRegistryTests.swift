//
//  CaptureDeviceRegistryTests.swift
//  CinematicCoreMacOSTests
//
//  DEVICES card: exclusive leases by stable device ID, no duplicate claim, a
//  missing device is never substituted, only the single-camera first run
//  auto-selects, and a stale lease cannot release someone else's claim.
//

import Testing
@testable import Alfie

@MainActor
struct CaptureDeviceRegistryTests {
    private func registry(present: Set<String> = ["cam-1", "cam-2"]) -> CaptureDeviceRegistry {
        let registry = CaptureDeviceRegistry()
        registry.isPresent = { present.contains($0) }
        return registry
    }

    @Test func aDeviceBelongsToOneChannel() throws {
        let registry = registry()
        let lease = try registry.claim("cam-1", for: .a).get()
        #expect(registry.owner(of: "cam-1") == .a)
        #expect(registry.claim("cam-1", for: .b) == .failure(.inUse(by: .a)))
        // Re-claiming your own device is idempotent.
        #expect(registry.claim("cam-1", for: .a) == .success(lease))
    }

    @Test func missingDeviceCannotBeClaimed() {
        #expect(registry().claim("cam-9", for: .b) == .failure(.missing))
    }

    @Test func releaseFreesTheDeviceForAnotherChannel() throws {
        let registry = registry()
        let lease = try registry.claim("cam-1", for: .a).get()
        registry.release(lease)
        #expect(registry.owner(of: "cam-1") == nil)
        #expect((try? registry.claim("cam-1", for: .b).get())?.channel == .b)
    }

    @Test func staleLeaseCannotReleaseANewerClaim() throws {
        let registry = registry()
        let old = try registry.claim("cam-1", for: .a).get()
        registry.release(old)
        _ = try registry.claim("cam-1", for: .b).get()
        registry.release(old)                   // stale token from A
        #expect(registry.owner(of: "cam-1") == .b)
    }

    @Test func aChannelHoldsOneDevice() throws {
        let registry = registry()
        _ = try registry.claim("cam-1", for: .a).get()
        _ = try registry.claim("cam-2", for: .a).get()
        #expect(registry.owner(of: "cam-1") == nil)
        #expect(registry.lease(for: .a)?.uniqueID == "cam-2")
    }

    @Test func leaseSurvivesUnplugSoNoOneElseTakesTheDevice() throws {
        var present: Set<String> = ["cam-1"]
        let registry = CaptureDeviceRegistry()
        registry.isPresent = { present.contains($0) }
        _ = try registry.claim("cam-1", for: .a).get()
        present.remove("cam-1")                  // hot unplug
        present.insert("cam-1")                  // replug
        #expect(registry.claim("cam-1", for: .b) == .failure(.inUse(by: .a)))
    }

    // MARK: Resolution

    private func resolve(selected: String?, present: [String] = ["cam-1", "cam-2"],
                         owners: [String: ChannelID] = [:], channel: ChannelID = .b,
                         autoSelect: Bool = false) -> CaptureDeviceRegistry.Resolution {
        CaptureDeviceRegistry.resolve(selected: selected, present: present, owner: { owners[$0] },
                                      channel: channel, allowAutoSelect: autoSelect)
    }

    @Test func selectedPresentFreeDeviceIsUsed() {
        #expect(resolve(selected: "cam-2") == .use(uniqueID: "cam-2"))
    }

    @Test func selectedDeviceOwnedByAnotherChannelIsInUse() {
        #expect(resolve(selected: "cam-1", owners: ["cam-1": .a]) == .inUse(by: .a))
    }

    @Test func missingSelectionIsNeverSubstituted() {
        // Other cameras are present, but the chosen one is not: stay missing.
        #expect(resolve(selected: "cam-9", autoSelect: true) == .missing)
    }

    @Test func onlyTheFirstRunAutoSelectsAndSkipsClaimedDevices() {
        #expect(resolve(selected: nil, autoSelect: false) == .noneSelected)
        #expect(resolve(selected: nil, owners: ["cam-1": .b], channel: .a, autoSelect: true) == .use(uniqueID: "cam-2"))
        #expect(resolve(selected: nil, present: [], channel: .a, autoSelect: true) == .missing)
    }

    @Test func showSharesOneRegistryAcrossChannels() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let b = show.addChannel(.b)
        #expect(show.channelA.deviceRegistry === show.deviceRegistry)
        #expect(b.deviceRegistry === show.deviceRegistry)
    }

    @Test func sourceLossWithoutARunningSessionIsIgnored() {
        let manager = CameraManager(channelID: .b, programOutput: ProgramOutputManager(sinks: []), routed: false)
        manager.handleSourceLost()
        #expect(!manager.sourceMissing)
    }
}
