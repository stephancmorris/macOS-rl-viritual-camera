//
//  FrameWorkScheduler.swift
//  CinematicCoreMacOS
//
//  Bounded, fair admission of per-frame work across channels (SCHEDULER card;
//  docs/ALFIE_MULTICAMERA_SPEC.md "Scheduler, admission, and degraded
//  operation").
//
//  - Render: one slot per camera. Each CropEngine has its own serial render
//    queue and its own filter, so one camera's render never waits behind
//    another's (D-02 path 1). A camera still renders one frame at a time.
//  - Perception: one slot for the whole show, shared by every camera.
//  - Latest-only: each channel has at most one waiting request per class and
//    per kind. A newer request of the same kind supersedes the older one
//    (which returns nil and is dropped); nothing grows without bound and
//    retired work is never queued. A tracking request and a census request
//    from the same camera are different kinds and do not cancel each other
//    (C-01 path 2).
//  - Program first, bounded (perception): when the slot frees and both Program and another
//    channel are waiting, Program may be chosen at most `maxProgramStreak`
//    times in a row; then the waiting channel is served. Within one channel,
//    tracking is served before a census.
//  - A running job cannot be pre-empted, so there is no wall-clock guarantee;
//    missed freshness shows up as Take unavailable, not as a hidden queue.
//
//  With one channel the slot is always free when asked (the capture gate
//  already allows one frame at a time), so single-camera timing is unchanged.
//

import Foundation

final class FrameWorkScheduler {

    enum WorkClass: Hashable, Sendable {
        case render
        case perception
    }

    /// What a request is for. Tracking is every existing use (the lock's
    /// scans, discovery, render). A census is the world model's full-frame
    /// box scan. Declared in service order.
    enum Kind: Hashable, Sendable, CaseIterable {
        case tracking
        case census
    }

    struct Permit: Equatable, Sendable {
        let workClass: WorkClass
        let channel: ChannelID
        let id: UInt64
        var kind: Kind = .tracking
    }

    struct ChannelStats: Equatable, Sendable {
        var granted = 0
        var superseded = 0
        var cancelled = 0
    }

    static let maxProgramStreak = 2

    /// Which channel is Program; supplied by the router.
    var isProgram: (ChannelID) -> Bool = { $0 == .a }

    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Permit?, Never>
    }

    private struct WaiterKey: Hashable {
        let channel: ChannelID
        let kind: Kind
    }

    private struct Lane {
        var running: Permit?
        var waiting: [WaiterKey: Waiter] = [:]
        /// Program selections in a row while another channel was waiting.
        var programStreak = 0
        var priorityOwner: ChannelID?
    }

    /// Render has one lane per camera; perception has one lane for the show.
    private struct LaneKey: Hashable {
        let workClass: WorkClass
        let channel: ChannelID?
    }
    private static func laneKey(_ workClass: WorkClass, _ channel: ChannelID) -> LaneKey {
        switch workClass {
        case .render: return LaneKey(workClass: .render, channel: channel)
        case .perception: return LaneKey(workClass: .perception, channel: nil)
        }
    }

    private var lanes: [LaneKey: Lane] = [:]
    private var nextID: UInt64 = 0
    private(set) var stats: [ChannelID: ChannelStats] = [:]

    /// Channels currently waiting for a class (bounded by the channel count).
    func waitingChannels(_ workClass: WorkClass) -> Set<ChannelID> {
        Set(lanes.filter { $0.key.workClass == workClass }.flatMap { $0.value.waiting.keys.map(\.channel) })
    }

    /// Whether a channel has a request of this kind waiting for a class.
    func isWaiting(_ workClass: WorkClass, for channel: ChannelID, kind: Kind) -> Bool {
        lanes[Self.laneKey(workClass, channel)]?.waiting[WaiterKey(channel: channel, kind: kind)] != nil
    }

    /// The job holding a slot. Perception has one slot, so `channel` is
    /// ignored for it. Render has a slot per camera: pass the camera, or nil
    /// for the first camera (in A-D order) that is rendering.
    func runningPermit(_ workClass: WorkClass, for channel: ChannelID? = nil) -> Permit? {
        let channels = channel.map { [$0] } ?? ChannelID.allCases
        return channels.lazy.compactMap { self.lanes[Self.laneKey(workClass, $0)]?.running }.first
    }

    /// Wait for the class's slot. Returns immediately when it is free; nil if
    /// this request was superseded by a newer one of the same kind from the
    /// same channel, or cancelled.
    func acquire(_ workClass: WorkClass, for channel: ChannelID, kind: Kind = .tracking) async -> Permit? {
        let key = Self.laneKey(workClass, channel)
        var lane = lanes[key] ?? Lane()
        if lane.running == nil {
            lane.programStreak = 0
            lane.priorityOwner = ChannelID.allCases.first(where: isProgram)
            let permit = makePermit(workClass, channel, kind)
            lane.running = permit
            lanes[key] = lane
            stats[channel, default: .init()].granted += 1
            return permit
        }
        let waiterKey = WaiterKey(channel: channel, kind: kind)
        if let older = lane.waiting.removeValue(forKey: waiterKey) {
            stats[channel, default: .init()].superseded += 1
            lanes[key] = lane
            older.continuation.resume(returning: nil)
        }
        nextID &+= 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            lanes[key, default: Lane()].waiting[waiterKey] = Waiter(id: id, continuation: continuation)
        }
    }

    /// Finish the running job and hand the slot to the next waiting channel.
    func release(_ permit: Permit) {
        let key = Self.laneKey(permit.workClass, permit.channel)
        guard var lane = lanes[key], lane.running == permit else { return }
        lane.running = nil
        let priorityOwner = ChannelID.allCases.first(where: isProgram)
        if lane.priorityOwner != priorityOwner { lane.programStreak = 0 }
        lane.priorityOwner = priorityOwner
        guard !lane.waiting.isEmpty else {
            lane.programStreak = 0
            lanes[key] = lane
            return
        }
        let waitingIDs = ChannelID.allCases.filter { id in lane.waiting.keys.contains { $0.channel == id } }
        let program = waitingIDs.first(where: isProgram)
        let others = waitingIDs.filter { !isProgram($0) }
        let next: ChannelID
        if let program, others.isEmpty || lane.programStreak < Self.maxProgramStreak {
            next = program
            lane.programStreak = others.isEmpty ? 0 : lane.programStreak + 1
        } else {
            next = others.first ?? waitingIDs[0]
            lane.programStreak = 0
        }
        // Within one camera the lock's tracking goes before a census.
        let waiterKey = Kind.allCases.lazy.map { WaiterKey(channel: next, kind: $0) }.first { lane.waiting[$0] != nil }!
        let waiter = lane.waiting.removeValue(forKey: waiterKey)!
        let granted = Permit(workClass: permit.workClass, channel: next, id: waiter.id, kind: waiterKey.kind)
        lane.running = granted
        lanes[key] = lane
        stats[next, default: .init()].granted += 1
        waiter.continuation.resume(returning: granted)
    }

    /// Drop a channel's waiting requests of every kind (its source stopped).
    /// A running job cannot be pre-empted; its completion is rejected by the
    /// channel's own generation check.
    func cancelWaiting(for channel: ChannelID) {
        for key in Array(lanes.keys) {
            guard var lane = lanes[key] else { continue }
            let waiters = Kind.allCases.compactMap { lane.waiting.removeValue(forKey: WaiterKey(channel: channel, kind: $0)) }
            guard !waiters.isEmpty else { continue }
            resetStreakIfUncontended(&lane)
            lanes[key] = lane
            for waiter in waiters {
                stats[channel, default: .init()].cancelled += 1
                waiter.continuation.resume(returning: nil)
            }
        }
    }

    /// Cancel only this lane's waiting request of one kind. A discovery owner
    /// calls this only while its own one-in-flight job is current; render
    /// admission, running work and a waiting census are unaffected.
    func cancelWaiting(_ workClass: WorkClass, for channel: ChannelID, kind: Kind = .tracking) {
        let key = Self.laneKey(workClass, channel)
        guard var lane = lanes[key],
              let waiter = lane.waiting.removeValue(forKey: WaiterKey(channel: channel, kind: kind)) else { return }
        resetStreakIfUncontended(&lane)
        lanes[key] = lane
        stats[channel, default: .init()].cancelled += 1
        waiter.continuation.resume(returning: nil)
    }

    private func makePermit(_ workClass: WorkClass, _ channel: ChannelID, _ kind: Kind) -> Permit {
        nextID &+= 1
        return Permit(workClass: workClass, channel: channel, id: nextID, kind: kind)
    }

    private func resetStreakIfUncontended(_ lane: inout Lane) {
        if !lane.waiting.keys.contains(where: { !isProgram($0.channel) }) {
            lane.programStreak = 0
        }
    }
}
