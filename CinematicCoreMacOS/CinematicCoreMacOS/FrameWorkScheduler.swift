//
//  FrameWorkScheduler.swift
//  CinematicCoreMacOS
//
//  Bounded, fair admission of per-frame work across channels (SCHEDULER card;
//  docs/ALFIE_MULTICAMERA_SPEC.md "Scheduler, admission, and degraded
//  operation").
//
//  - One slot per work class (render, perception). CropEngine's static serial
//    queue stays the executor, but it is no longer the hidden owner: work only
//    reaches it holding a permit, so it never queues more than one job.
//  - Latest-only: each channel has at most one waiting request per class. A
//    newer request supersedes the older one (which returns nil and is
//    dropped); nothing grows without bound and retired work is never queued.
//  - Program first, bounded: when the slot frees and both Program and another
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
    }

    private var lanes: [WorkClass: Lane] = [:]
    private var nextID: UInt64 = 0
    private(set) var stats: [ChannelID: ChannelStats] = [:]

    /// Channels currently waiting for a class (bounded by the channel count).
    func waitingChannels(_ workClass: WorkClass) -> Set<ChannelID> {
        Set(lanes[workClass].map { Array($0.waiting.keys) } ?? [])
    }

    func runningPermit(_ workClass: WorkClass) -> Permit? { lanes[workClass]?.running }

    /// Wait for the class's slot. Returns immediately when it is free; nil if
    /// this request was superseded by a newer one from the same channel or
    /// cancelled.
    func acquire(_ workClass: WorkClass, for channel: ChannelID) async -> Permit? {
        var lane = lanes[workClass] ?? Lane()
        if lane.running == nil {
            let permit = makePermit(workClass, channel)
            lane.running = permit
            lanes[workClass] = lane
            stats[channel, default: .init()].granted += 1
            return permit
        }
        if let older = lane.waiting.removeValue(forKey: channel) {
            stats[channel, default: .init()].superseded += 1
            lanes[workClass] = lane
            older.continuation.resume(returning: nil)
        }
        nextID &+= 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            lanes[workClass, default: Lane()].waiting[channel] = Waiter(id: id, continuation: continuation)
        }
    }

    /// Finish the running job and hand the slot to the next waiting channel.
    func release(_ permit: Permit) {
        guard var lane = lanes[permit.workClass], lane.running == permit else { return }
        lane.running = nil
        guard !lane.waiting.isEmpty else {
            lanes[permit.workClass] = lane
            return
        }
        let waitingIDs = ChannelID.allCases.filter { lane.waiting[$0] != nil }
        let program = waitingIDs.first(where: isProgram)
        let others = waitingIDs.filter { !isProgram($0) }
        let next: ChannelID
        if let program, others.isEmpty || lane.programStreak < Self.maxProgramStreak {
            next = program
            if !others.isEmpty { lane.programStreak += 1 }
        } else {
            next = others.first ?? waitingIDs[0]
            lane.programStreak = 0
        }
        let waiter = lane.waiting.removeValue(forKey: next)!
        let granted = Permit(workClass: permit.workClass, channel: next, id: waiter.id)
        lane.running = granted
        lanes[permit.workClass] = lane
        stats[next, default: .init()].granted += 1
        waiter.continuation.resume(returning: granted)
    }

    /// Drop a channel's waiting requests (its source stopped). A running job
    /// cannot be pre-empted; its completion is rejected by the channel's own
    /// generation check.
    func cancelWaiting(for channel: ChannelID) {
        for workClass in Array(lanes.keys) {
            guard var lane = lanes[workClass], let waiter = lane.waiting.removeValue(forKey: channel) else { continue }
            lanes[workClass] = lane
            stats[channel, default: .init()].cancelled += 1
            waiter.continuation.resume(returning: nil)
        }
    }

    private func makePermit(_ workClass: WorkClass, _ channel: ChannelID) -> Permit {
        nextID &+= 1
        return Permit(workClass: workClass, channel: channel, id: nextID)
    }
}
