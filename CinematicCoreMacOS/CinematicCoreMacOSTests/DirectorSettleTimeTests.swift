//
//  DirectorSettleTimeTests.swift
//  CinematicCoreMacOSTests
//
//  SU-03 (SU-4): the segment's style tightens the cut bar. A shot isn't
//  cut-ready until the subject has stayed still for the style's settle time,
//  and "wait until they settle" also caps the motion allowed. Preparation
//  (the prepare bar) is unchanged, and a style can never loosen the bar.
//

import Foundation
import Testing
@testable import Alfie

struct DirectorSettleTimeTests {
    /// Test fixture values only: the injected study parameters.
    private let study = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 0.3,
        cutOnMotionAllowed: true, minimumCutSettledTime: 0.25, maximumCutMotion: 0.2)

    private func style(settle: TimeInterval, movement: Double = 0.05, cutWhileMoving: Bool = false) -> DirectorStyle {
        DirectorStyle(minimumShotDuration: 8, preferredShotDuration: 20, softMaximumShotDuration: 40,
                      wideCadence: 75, repetitionWindow: 40, maximumMovement: movement, settleTime: settle,
                      onAirMoveRate: 0.35, cutOnMotionAllowed: cutWhileMoving)
    }

    private func inputs(settledFor: TimeInterval, motion: Double = 0) -> DirectorReadiness.Inputs {
        DirectorReadiness.Inputs(take: TakeAvailability(program: .a, preview: .b, standard: .p50, reason: nil, takePending: false, editLive: false),
                                 identity: .confirmed, framingSettledFor: settledFor,
                                 motion: motion, cropConverged: true)
    }

    @Test func notCutReadyUntilTheSettleTimePasses() {
        let p = study.tightened(by: style(settle: 1.0))
        #expect(p.isValid)
        #expect(DirectorReadiness.evaluate(inputs(settledFor: 0.5), parameters: p, bar: .cut).reasons == [.framingUnsettled])
        #expect(DirectorReadiness.evaluate(inputs(settledFor: 1.0), parameters: p, bar: .cut).isReady)
    }

    @Test func movingAgainResetsReadiness() {
        let p = study.tightened(by: style(settle: 1.0))
        // The evidence clock restarts when the subject moves; a fresh short
        // settled time is not ready again.
        #expect(DirectorReadiness.evaluate(inputs(settledFor: 2.0), parameters: p, bar: .cut).isReady)
        #expect(!DirectorReadiness.evaluate(inputs(settledFor: 0.1), parameters: p, bar: .cut).isReady)
    }

    @Test func waitUntilSettledCapsCutMotion() {
        let p = study.tightened(by: style(settle: 0, movement: 0.05))
        #expect(p.maximumCutMotion == 0.05)
        #expect(DirectorReadiness.evaluate(inputs(settledFor: 5, motion: 0.1), parameters: p, bar: .cut).reasons == [.moving])
    }

    @Test func cutWhileMovingKeepsTheStudyMotionLimit() {
        let p = study.tightened(by: style(settle: 0, movement: 0.15, cutWhileMoving: true))
        #expect(p.maximumCutMotion == study.maximumCutMotion)
    }

    @Test func aStyleNeverLoosensTheBar() {
        let p = study.tightened(by: style(settle: 0, movement: 0.9))
        #expect(p.minimumCutSettledTime == study.minimumCutSettledTime)
        #expect(p.maximumCutMotion == study.maximumCutMotion)
    }

    @Test func preparationIsUnchanged() {
        let p = study.tightened(by: style(settle: 3))
        #expect(p.minimumSettledTime == study.minimumSettledTime)
        #expect(p.maximumMotion == study.maximumMotion)
        #expect(p.cutOnMotionAllowed == study.cutOnMotionAllowed)
        #expect(DirectorReadiness.evaluate(inputs(settledFor: 0, motion: 0.25), parameters: p, bar: .prepare).isReady)
    }

    @Test func noStyleLeavesTheStudyParameters() {
        let p = study.tightened(by: nil)
        #expect(p.minimumCutSettledTime == study.minimumCutSettledTime)
        #expect(p.maximumCutMotion == study.maximumCutMotion)
        #expect(p.cutOnMotionAllowed == study.cutOnMotionAllowed)
    }
}
