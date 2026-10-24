import Foundation
import Testing
@testable import Alfie

/// Synthetic move timelines; no real camera, approved N2 rate or qualification.
nonisolated struct DirectorOnAirMovePolicyTests {
    private let wide = DirectorShot(preset: .stage(.wide))
    private let full = DirectorShot(preset: .stage(.fullBody))
    private let tight = DirectorShot(preset: .stage(.waistUp))
    private var prerequisites: DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.auto, .backup])
    }
    private func authority(_ level: DirectorAuthority.Level = .auto) -> DirectorAuthority {
        var a = DirectorAuthority()
        a.apply(.enable(level), prerequisites: prerequisites)
        return a
    }
    private func style(rate: Double = 0.1) -> DirectorStyle {
        .init(minimumShotDuration: 5, preferredShotDuration: 10, softMaximumShotDuration: 30,
              wideCadence: 20, repetitionWindow: 4, maximumMovement: 0.2,
              settleTime: 1, onAirMoveRate: rate, cutOnMotionAllowed: false)
    }
    private func context(_ a: DirectorAuthority? = nil, now: Double = 10, started: Double = 0,
                         single: Bool = false, better: Bool? = false, ready: Bool = true,
                         gesture: Bool = false, healthy: Bool = true, program: ChannelID = .a,
                         generation: UInt64 = 1, route: UInt64 = 1, policy: UInt64 = 1,
                         nomination: UInt64 = 1, from: DirectorShot? = nil, to: DirectorShot? = nil) -> OnAirMovePolicy.Context {
        .init(authority: a ?? authority(), prerequisites: prerequisites, program: program,
              programRevisions: .init(sourceGeneration: generation, controlEpoch: 2, shotRevision: 3),
              routeGeneration: route, policyRevision: policy, nominationRevision: nomination,
              currentShot: from ?? wide, targetShot: to ?? full, runningInputs: single ? [program] : [.a, .b],
              betterInputCutReady: better, readiness: .init(reasons: ready ? [] : [.identityUncertain]),
              sourceHealthy: healthy, operatorGestureInProgress: gesture, programStartedAt: started, sampledAt: now)
    }
    private func propose(_ p: inout OnAirMovePolicy, _ c: OnAirMovePolicy.Context? = nil,
                         now: Double = 10) throws -> OnAirMovePolicy.Plan {
        let decision = p.propose(c ?? context(now: now), style: style(), now: now, maximumSampleAge: 1)
        guard case .move(let plan) = decision else { Issue.record("Expected slow move"); throw TestError.noPlan }
        return plan
    }
    private enum TestError: Error { case noPlan }

    @Test func onlyMovesWhenCuttingIsUnavailableOrThereIsOneInput() throws {
        var p = OnAirMovePolicy()
        #expect(p.propose(context(better: true), style: style(), now: 10, maximumSampleAge: 1) == .abstain(.betterInputReady))
        #expect(p.propose(context(better: nil), style: style(), now: 10, maximumSampleAge: 1) == .abstain(.alternativeEvidenceUnavailable))
        let single = try propose(&p, context(single: true, better: nil))
        #expect(single.program == .a && single.from == wide && single.to == full && single.maximumRate == 0.1)
        #expect(p.consume(single, live: context(single: true), style: style(), now: 10, maximumSampleAge: 1) == single)
    }
    @Test func syntheticReplaySpacesConsumedMovesEvenWhenTheSinkFails() throws {
        var p = OnAirMovePolicy()
        let first = try propose(&p)
        #expect(p.consume(first, live: context(), style: style(), now: 10, maximumSampleAge: 1) == first)
        #expect(p.consume(first, live: context(), style: style(), now: 10, maximumSampleAge: 1) == nil)
        for now in [10.0, 12, 14.999] {
            #expect(p.propose(context(now: now, from: full, to: tight), style: style(), now: now,
                              maximumSampleAge: 1) == .abstain(.moveHold))
        }
        let next = try propose(&p, context(now: 15, from: full, to: tight), now: 15)
        #expect(p.consume(next, live: context(now: 15, from: full, to: tight), style: style(), now: 15, maximumSampleAge: 1) == next)
        #expect(p.lastMoveAt == 15)
    }
    @Test(arguments: ["gesture", "editLive", "nudge", "manual", "fault", "unready", "missing"])
    func syntheticReplayHasZeroMovesDuringInterventions(event: String) throws {
        var p = OnAirMovePolicy(), a = authority()
        let plan = try propose(&p, context(a))
        switch event {
        case "editLive": a.apply(.editLive(true))
        case "nudge": a.apply(.operatorTake, takeTiming: .init(now: 10, minimumShotDuration: 5))
        case "manual": a.apply(.manualCommand)
        case "fault": a.apply(.outputFault)
        default: break
        }
        let live = context(a, gesture: event == "gesture", healthy: event != "missing", to: full)
        let actual = event == "unready" ? context(a, ready: false) : live
        #expect(p.consume(plan, live: actual, style: style(), now: 10, maximumSampleAge: 1) == nil)
        #expect(p.pending == nil && p.lastMoveAt == nil)
    }
    @Test(arguments: [DirectorAuthority.Level.off, .suggest, .assist])
    func nonCuttingLevelsNeverMove(level: DirectorAuthority.Level) {
        var p = OnAirMovePolicy()
        #expect(p.propose(context(authority(level)), style: style(), now: 10, maximumSampleAge: 1) == .abstain(.authority))
    }
    @Test func onlyAdjacentShotsInTheSameFormatCanMove() throws {
        var p = OnAirMovePolicy()
        for target in [wide, tight, .init(preset: .webcam(.tight))] {
            #expect(p.propose(context(to: target), style: style(), now: 10, maximumSampleAge: 1) == .abstain(.notOneStep))
        }
        let pullOut = try propose(&p, context(from: full, to: wide))
        #expect(pullOut.to == wide)
        #expect(p.propose(context(started: 6), style: style(), now: 10, maximumSampleAge: 1) == .abstain(.minimumDwell))
    }
    @Test(arguments: 0..<7)
    func bindingsAndFreshnessAreRecheckedAtConsumption(index: Int) throws {
        var p = OnAirMovePolicy()
        let plan = try propose(&p)
        let live: OnAirMovePolicy.Context
        switch index {
        case 0: live = context(program: .b)
        case 1: live = context(generation: 2)
        case 2: live = context(route: 2)
        case 3: live = context(policy: 2)
        case 4: live = context(nomination: 2)
        case 5: live = context(better: true)
        default: live = context(now: 9)
        }
        #expect(p.consume(plan, live: live, style: style(), now: 11, maximumSampleAge: 1) == nil)
        #expect(p.pending == nil)
    }
    @Test func staleCallbackCannotConsumeReplacementAndAnOldPlanCannotBeRefreshedIntoExecution() throws {
        var p = OnAirMovePolicy()
        let old = try propose(&p)
        let replacement = try propose(&p, context(route: 2))
        #expect(p.consume(old, live: context(route: 2), style: style(), now: 10, maximumSampleAge: 1) == nil)
        #expect(p.pending == replacement)
        #expect(p.consume(replacement, live: context(now: 12, route: 2), style: style(), now: 12, maximumSampleAge: 1) == nil)
        #expect(p.pending == nil)
    }
    @Test(arguments: [Double.nan, .infinity, -1])
    func malformedClocksDurationsAndRatesFailClosed(value: Double) {
        var p = OnAirMovePolicy()
        #expect(p.propose(context(), style: style(), now: value, maximumSampleAge: 1) == .abstain(.invalidInput))
        #expect(p.propose(context(), style: style(rate: value), now: 10, maximumSampleAge: 1) == .abstain(.invalidInput))
        #expect(p.propose(context(), style: style(), now: 10, maximumSampleAge: value) == .abstain(.invalidInput))
        #expect(p.propose(context(now: value), style: style(), now: 10, maximumSampleAge: 1) == .abstain(.invalidInput))
    }
}
