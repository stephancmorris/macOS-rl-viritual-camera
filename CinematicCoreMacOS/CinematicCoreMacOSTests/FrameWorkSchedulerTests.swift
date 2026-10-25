//
//  FrameWorkSchedulerTests.swift
//  CinematicCoreMacOSTests
//
//  SCHEDULER card: bounded, latest-only admission; no starvation for more
//  than two scheduling opportunities when Program and Preview both wait;
//  cancellation; no cross-channel grants.
//

import Testing
@testable import Alfie

@MainActor
struct FrameWorkSchedulerTests {
    /// Let spawned MainActor tasks run up to their suspension point.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test func freeSlotIsGrantedImmediatelyAndRepeatedlyForOneChannel() async {
        let scheduler = FrameWorkScheduler()
        for _ in 0..<100 {
            let permit = await scheduler.acquire(.render, for: .a)
            #expect(permit?.channel == .a)
            scheduler.release(permit!)
        }
        #expect(scheduler.stats[.a]?.granted == 100)
        #expect(scheduler.waitingChannels(.render).isEmpty)
    }

    @Test func secondChannelWaitsUntilRelease() async {
        let scheduler = FrameWorkScheduler()
        let first = await scheduler.acquire(.render, for: .a)!
        let waiter = Task { await scheduler.acquire(.render, for: .b) }
        await settle()
        #expect(scheduler.waitingChannels(.render) == [.b])
        scheduler.release(first)
        let granted = await waiter.value
        #expect(granted?.channel == .b)
        #expect(scheduler.runningPermit(.render) == granted)
    }

    @Test func newerRequestSupersedesTheOlderOneFromTheSameChannel() async {
        let scheduler = FrameWorkScheduler()
        let running = await scheduler.acquire(.render, for: .a)!
        let older = Task { await scheduler.acquire(.render, for: .b) }
        await settle()
        let newer = Task { await scheduler.acquire(.render, for: .b) }
        await settle()
        #expect(await older.value == nil)
        #expect(scheduler.waitingChannels(.render) == [.b])   // bounded: one waiter per channel
        scheduler.release(running)
        #expect(await newer.value?.channel == .b)
        #expect(scheduler.stats[.b]?.superseded == 1)
    }

    @Test func previewIsServedWithinTwoProgramSelections() async {
        let scheduler = FrameWorkScheduler()
        scheduler.isProgram = { $0 == .a }
        var current = await scheduler.acquire(.render, for: .a)!
        let preview = Task { await scheduler.acquire(.render, for: .b) }
        var programSelections = 0
        var previewPermit: FrameWorkScheduler.Permit?
        for _ in 0..<5 {
            // Program always has fresh work waiting too.
            let program = Task { await scheduler.acquire(.render, for: .a) }
            await settle()
            scheduler.release(current)
            await settle()
            if let running = scheduler.runningPermit(.render), running.channel == .b {
                previewPermit = running
                // Hand the slot back so Program's waiting request completes.
                scheduler.release(running)
                if let next = await program.value { scheduler.release(next) }
                break
            }
            programSelections += 1
            current = await program.value!
        }
        #expect(previewPermit != nil)
        #expect(programSelections <= FrameWorkScheduler.maxProgramStreak)
        #expect(await preview.value?.channel == .b)
    }

    @Test func programIsPreferredWhenBothWaitAndStreakAllows() async {
        let scheduler = FrameWorkScheduler()
        scheduler.isProgram = { $0 == .b }          // B is Program after a Take
        let running = await scheduler.acquire(.perception, for: .a)!
        let a = Task { await scheduler.acquire(.perception, for: .a) }
        let b = Task { await scheduler.acquire(.perception, for: .b) }
        await settle()
        scheduler.release(running)
        await settle()
        #expect(scheduler.runningPermit(.perception)?.channel == .b)
        scheduler.release(scheduler.runningPermit(.perception)!)
        #expect(await a.value?.channel == .a)
        _ = await b.value
    }

    @Test func cancellingAChannelDropsOnlyItsWaitingRequest() async {
        let scheduler = FrameWorkScheduler()
        let running = await scheduler.acquire(.render, for: .a)!
        let b = Task { await scheduler.acquire(.render, for: .b) }
        await settle()
        scheduler.cancelWaiting(for: .b)
        #expect(await b.value == nil)
        #expect(scheduler.runningPermit(.render) == running)   // running job not pre-empted
        #expect(scheduler.stats[.b]?.cancelled == 1)
    }

    @Test func releasingAPermitThatIsNotRunningIsIgnored() async {
        let scheduler = FrameWorkScheduler()
        let running = await scheduler.acquire(.render, for: .a)!
        scheduler.release(FrameWorkScheduler.Permit(workClass: .render, channel: .b, id: 999))
        #expect(scheduler.runningPermit(.render) == running)
    }

    @Test func workClassesAreIndependent() async {
        let scheduler = FrameWorkScheduler()
        let render = await scheduler.acquire(.render, for: .a)
        let perception = await scheduler.acquire(.perception, for: .b)
        #expect(render != nil && perception != nil)
    }

    @Test(arguments: [FrameWorkScheduler.WorkClass.render, .perception], ["idle", "uncontended", "roles", "cancel"])
    func newContentionUsesTheCurrentProgramsPriority(workClass: FrameWorkScheduler.WorkClass, reset: String) async {
        let scheduler = FrameWorkScheduler()
        var running = await scheduler.acquire(workClass, for: .a)!
        let previousPreview = Task { await scheduler.acquire(workClass, for: .b) }
        await settle()
        // Spend the two consecutive Program selections while B waits.
        for _ in 0..<FrameWorkScheduler.maxProgramStreak {
            let program = Task { await scheduler.acquire(workClass, for: .a) }
            await settle()
            scheduler.release(running)
            running = await program.value!
        }
        let nextProgram: Task<FrameWorkScheduler.Permit?, Never>
        let nextPreview: Task<FrameWorkScheduler.Permit?, Never>
        let expected: ChannelID
        if reset == "roles" {
            // The waiting B becomes Program after a Take. The old Program's
            // contention history must not penalize the new priority owner.
            scheduler.isProgram = { $0 == .b }
            nextProgram = previousPreview
            nextPreview = Task { await scheduler.acquire(workClass, for: .a) }
            expected = .b
        } else {
            scheduler.cancelWaiting(workClass, for: .b)
            #expect(await previousPreview.value == nil)
            if reset == "idle" {
                scheduler.release(running)
                running = await scheduler.acquire(workClass, for: .a)!
            } else if reset == "uncontended" {
                let uncontended = Task { await scheduler.acquire(workClass, for: .a) }
                await settle()
                scheduler.release(running)
                running = await uncontended.value!
            }
            nextProgram = Task { await scheduler.acquire(workClass, for: .a) }
            nextPreview = Task { await scheduler.acquire(workClass, for: .b) }
            expected = .a
        }
        await settle()
        scheduler.release(running)
        #expect(scheduler.runningPermit(workClass)?.channel == expected)
        // Drain both requests regardless of the failed selection, so the
        // before-fix regression cannot leave a suspended test task behind.
        if let granted = scheduler.runningPermit(workClass) { scheduler.release(granted) }
        if let granted = scheduler.runningPermit(workClass) { scheduler.release(granted) }
        _ = await nextProgram.value
        _ = await nextPreview.value
        #expect(scheduler.runningPermit(workClass) == nil)
        #expect(scheduler.waitingChannels(workClass).isEmpty)
    }

    @Test func showSchedulerFollowsTheRoutersProgram() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let b = show.addChannel(.b)
        #expect(b.workScheduler === show.workScheduler)
        #expect(show.workScheduler.isProgram(.a))
        show.router.setProgram(.b, expectedRouteGeneration: show.router.routeGeneration)
        #expect(show.workScheduler.isProgram(.b))
        #expect(!show.workScheduler.isProgram(.a))
    }
}
