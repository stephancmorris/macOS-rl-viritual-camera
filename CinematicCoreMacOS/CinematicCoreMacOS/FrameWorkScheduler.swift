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
//  - Latest-only: each channel has at most one waiting request per class. A
//    newer request supersedes the older one (which returns nil and is
//    dropped); nothing grows without bound and retired work is never queued.
//  - Program first, bounded (perception): when the slot frees and both Program and another
//    channel are waiting, Program may be chosen at most `maxProgramStreak`
//    times in a row; then the waiting channel is served.
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

    struct Permit: Equatable, Sendable {
        let workClass: WorkClass
        let channel: ChannelID
        let id: UInt64
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

    private struct Lane {
        var running: Permit?
        var waiting: [ChannelID: Waiter] = [:]
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
        Set(lanes.filter { $0.key.workClass == workClass }.flatMap { $0.value.waiting.keys })
    }

    /// The job holding a slot. Perception has one slot, so `channel` is
    /// ignored for it. Render has a slot per camera: pass the camera, or nil
    /// for the first camera (in A-D order) that is rendering.
    func runningPermit(_ workClass: WorkClass, for channel: ChannelID? = nil) -> Permit? {
        let channels = channel.map { [$0] } ?? ChannelID.allCases
        return channels.lazy.compactMap { self.lanes[Self.laneKey(workClass, $0)]?.running }.first
    }

    /// Wait for the class's slot. Returns immediately when it is free; nil if
    /// this request was superseded by a newer one from the same channel or
    /// cancelled.
    func acquire(_ workClass: WorkClass, for channel: ChannelID) async -> Permit? {
        let key = Self.laneKey(workClass, channel)
        var lane = lanes[key] ?? Lane()
        if lane.running == nil {
            lane.programStreak = 0
            lane.priorityOwner = ChannelID.allCases.first(where: isProgram)
            let permit = makePermit(workClass, channel)
            lane.running = permit
            lanes[key] = lane
            stats[channel, default: .init()].granted += 1
            return permit
        }
        if let older = lane.waiting.removeValue(forKey: channel) {
            stats[channel, default: .init()].superseded += 1
            lanes[key] = lane
            older.continuation.resume(returning: nil)
        }
        nextID &+= 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            lanes[key, default: Lane()].waiting[channel] = Waiter(id: id, continuation: continuation)
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
        let waitingIDs = ChannelID.allCases.filter { lane.waiting[$0] != nil }
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
        let waiter = lane.waiting.removeValue(forKey: next)!
        let granted = Permit(workClass: permit.workClass, channel: next, id: waiter.id)
        lane.running = granted
        lanes[key] = lane
        stats[next, default: .init()].granted += 1
        waiter.continuation.resume(returning: granted)
    }

    /// Drop a channel's waiting requests (its source stopped). A running job
    /// cannot be pre-empted; its completion is rejected by the channel's own
    /// generation check.
    func cancelWaiting(for channel: ChannelID) {
        for key in Array(lanes.keys) {
            guard var lane = lanes[key], let waiter = lane.waiting.removeValue(forKey: channel) else { continue }
            resetStreakIfUncontended(&lane)
            lanes[key] = lane
            stats[channel, default: .init()].cancelled += 1
            waiter.continuation.resume(returning: nil)
        }
    }

    /// Cancel only this lane's waiting request. A discovery owner calls this
    /// only while its own one-in-flight job is current; render admission and
    /// running work are unaffected.
    func cancelWaiting(_ workClass: WorkClass, for channel: ChannelID) {
        let key = Self.laneKey(workClass, channel)
        guard var lane = lanes[key], let waiter = lane.waiting.removeValue(forKey: channel) else { return }
        resetStreakIfUncontended(&lane)
        lanes[key] = lane
        stats[channel, default: .init()].cancelled += 1
        waiter.continuation.resume(returning: nil)
    }

    private func makePermit(_ workClass: WorkClass, _ channel: ChannelID) -> Permit {
        nextID &+= 1
        return Permit(workClass: workClass, channel: channel, id: nextID)
    }

    private func resetStreakIfUncontended(_ lane: inout Lane) {
        if !lane.waiting.keys.contains(where: { !isProgram($0) }) {
            lane.programStreak = 0
        }
    }
}
