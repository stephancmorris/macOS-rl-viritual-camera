//
//  CaptureDeviceRegistry.swift
//  CinematicCoreMacOS
//
//  Exclusive capture-device leases for the show (DEVICES card). A physical
//  device, identified by its stable unique ID, belongs to at most one
//  channel. A missing device stays missing: nothing binds by enumeration
//  index or silently substitutes another camera, and a lease survives a hot
//  unplug so no other channel can grab the device when it returns.
//

import AVFoundation
import Foundation

final class CaptureDeviceRegistry {

    struct Lease: Equatable, Sendable {
        let uniqueID: String
        let channel: ChannelID
        let token: UUID
    }

    enum ClaimError: Error, Equatable {
        case inUse(by: ChannelID)
        case missing
    }

    /// Where a channel's camera comes from, decided before any claim.
    nonisolated enum Resolution: Equatable, Sendable {
        case use(uniqueID: String)
        /// The selected device is not present. Never substituted.
        case missing
        /// The selected device belongs to another channel.
        case inUse(by: ChannelID)
        /// Nothing selected and this channel may not auto-select.
        case noneSelected
    }

    private var leases: [String: Lease] = [:]

    /// Presence check; injectable for tests.
    var isPresent: (String) -> Bool = { AVCaptureDevice(uniqueID: $0) != nil }

    func owner(of uniqueID: String) -> ChannelID? { leases[uniqueID]?.channel }

    func lease(for channel: ChannelID) -> Lease? {
        leases.values.first { $0.channel == channel }
    }

    /// Claim a present device for a channel. Re-claiming the device a channel
    /// already holds returns its existing lease; a channel holds one device.
    func claim(_ uniqueID: String, for channel: ChannelID) -> Result<Lease, ClaimError> {
        if let existing = leases[uniqueID] {
            return existing.channel == channel ? .success(existing) : .failure(.inUse(by: existing.channel))
        }
        guard isPresent(uniqueID) else { return .failure(.missing) }
        if let previous = lease(for: channel) { leases[previous.uniqueID] = nil }
        let lease = Lease(uniqueID: uniqueID, channel: channel, token: UUID())
        leases[uniqueID] = lease
        return .success(lease)
    }

    /// Release only the exact lease handed out (a stale token is ignored).
    func release(_ lease: Lease) {
        guard leases[lease.uniqueID] == lease else { return }
        leases[lease.uniqueID] = nil
    }

    /// Decide which device a channel should use.
    ///
    /// - Parameters:
    ///   - selected: the device the operator chose (persisted choices are
    ///     requests, not authority), or nil.
    ///   - present: present device IDs in preference order.
    ///   - owner: current lease holder per device.
    ///   - allowAutoSelect: true only for the single-camera first run
    ///     (Program channel with no choice yet).
    nonisolated static func resolve(
        selected: String?,
        present: [String],
        owner: (String) -> ChannelID?,
        channel: ChannelID,
        allowAutoSelect: Bool
    ) -> Resolution {
        if let selected {
            guard present.contains(selected) else { return .missing }
            if let holder = owner(selected), holder != channel { return .inUse(by: holder) }
            return .use(uniqueID: selected)
        }
        guard allowAutoSelect else { return .noneSelected }
        if let free = present.first(where: { owner($0) == nil || owner($0) == channel }) {
            return .use(uniqueID: free)
        }
        return present.isEmpty ? .missing : .inUse(by: owner(present[0]) ?? channel)
    }
}
