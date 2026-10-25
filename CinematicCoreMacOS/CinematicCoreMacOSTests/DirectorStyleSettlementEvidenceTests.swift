import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorStyleSettlementEvidenceTests {
    private let target = UUID()
    private let limit = 0.005
    private var adapter: DirectorEvidenceAdapter {
        .init(parameters: .init(maximumObservationAge: 2, debounce: 0, stillSpeed: 0.05))
    }
    private func sample(_ time: Double, speed: Double = 0, age: Double = 0.05,
                        gesture: Bool = false, target: UUID? = nil,
                        phase: RecoveryState.Phase = .tracking) -> ChannelEvidenceSample {
        .init(channel: .b, sampledAt: time, lockPhase: phase, trackingOwnsControl: true,
              galleryReady: true, lockedTargetID: target ?? self.target, observationAge: age,
              subjectSpeed: speed, holdingSteady: true, cropConverged: true,
              operatorGestureInProgress: gesture, observedPersonCount: 1)
    }
    private var take: TakeAvailability {
        .init(program: .a, preview: .b, standard: .p50, reason: nil, takePending: false, editLive: false)
    }

    @Test func cutSettlementCannotInheritMovementAboveTheEffectiveStyleBound() throws {
        var a = adapter
        for t in [0.0, 1, 2] { a.ingest(sample(t, speed: 0.01), cutMotionLimit: limit) }
        let style = DirectorStyle(minimumShotDuration: 8, preferredShotDuration: 20,
            softMaximumShotDuration: 40, wideCadence: 75, repetitionWindow: 40,
            maximumMovement: limit, settleTime: 1, onAirMoveRate: 0.35, cutOnMotionAllowed: false)
        let study = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 0.03,
            cutOnMotionAllowed: true, minimumCutSettledTime: 0.25, maximumCutMotion: 0.02)
        let effective = study.tightened(by: style)
        let prepare = try #require(a.readinessInputs(for: .b, take: take, now: 2))
        #expect(DirectorReadiness.evaluate(prepare, parameters: effective, bar: .prepare).isReady)
        a.ingest(sample(2.1), cutMotionLimit: limit)
        let first = try #require(DirectorController.currentCutInputs(sample: sample(2.1), adapter: a,
            take: take, now: 2.1, cutMotionLimit: limit))
        #expect(a.settledFor(.b, now: 2.1) >= 2)
        #expect(first.framingSettledFor == 0)
        #expect(DirectorReadiness.evaluate(first, parameters: effective, bar: .cut).reasons == [.framingUnsettled])
        a.ingest(sample(3.2), cutMotionLimit: limit)
        let later = try #require(DirectorController.currentCutInputs(sample: sample(3.2), adapter: a,
            take: take, now: 3.2, cutMotionLimit: limit))
        #expect(DirectorReadiness.evaluate(later, parameters: effective, bar: .cut).isReady)
    }

    @Test func movementRestartsOnlyTheCutClock() {
        var a = adapter
        a.ingest(sample(0), cutMotionLimit: limit); a.ingest(sample(2), cutMotionLimit: limit)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2) == 2)
        a.ingest(sample(2.1, speed: 0.01), cutMotionLimit: limit)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2.1) == 0)
        #expect(a.settledFor(.b, now: 2.1) == 2.1)
        a.ingest(sample(2.2), cutMotionLimit: limit); a.ingest(sample(3.3), cutMotionLimit: limit)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 3.3) > 1)
    }

    @Test func changedBoundCannotReuseTheOldClock() {
        var a = adapter
        a.ingest(sample(0, speed: 0.01), cutMotionLimit: 0.02)
        a.ingest(sample(2, speed: 0.01), cutMotionLimit: 0.02)
        #expect(a.cutSettledFor(.b, motionLimit: 0.02, now: 2) == 2)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2) == 0)
        a.ingest(sample(2.1), cutMotionLimit: limit)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2.1) == 0)
        #expect(a.cutSettledFor(.b, motionLimit: 0.02, now: 2.1) == 0)
    }

    @Test(arguments: ["gesture", "stale", "target", "invalidClock"])
    func interruptionsRetireCutSettlement(kind: String) {
        var a = adapter
        a.ingest(sample(0), cutMotionLimit: limit); a.ingest(sample(2), cutMotionLimit: limit)
        switch kind {
        case "gesture": a.ingest(sample(2.1, gesture: true), cutMotionLimit: limit)
        case "stale": a.ingest(sample(2.1, age: 3), cutMotionLimit: limit)
        case "target": a.ingest(sample(2.1, target: UUID()), cutMotionLimit: limit)
        default: a.ingest(sample(.nan), cutMotionLimit: limit)
        }
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2.1) == 0)
    }

    @Test func historicalSampleCannotRewindTheCutConfigurationOrClock() {
        var a = adapter
        a.ingest(sample(0), cutMotionLimit: limit); a.ingest(sample(2), cutMotionLimit: limit)
        a.ingest(sample(1, speed: 1), cutMotionLimit: 1)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2) == 2)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 4.1) == 0)
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity])
    func invalidBoundsCannotRetainCutHistory(bound: Double) {
        var a = adapter
        a.ingest(sample(0), cutMotionLimit: limit); a.ingest(sample(2), cutMotionLimit: limit)
        a.ingest(sample(2.1), cutMotionLimit: bound)
        #expect(a.cutSettledFor(.b, motionLimit: bound, now: 2.1) == 0)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2.1) == 0)
    }

    @Test func unconfiguredAdapterRetainsItsPreparationClock() {
        var a = adapter
        a.ingest(sample(0)); a.ingest(sample(2))
        #expect(a.settledFor(.b, now: 2) == 2)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 2) == 0)
    }

    @Test func briefUnconfirmedLockCannotAccumulateCutSettlement() {
        var a = DirectorEvidenceAdapter(parameters: .init(maximumObservationAge: 2,
                                                         debounce: 0.5, stillSpeed: 0.05))
        a.ingest(sample(0), cutMotionLimit: limit)
        a.ingest(sample(0.6), cutMotionLimit: limit)
        a.ingest(sample(0.7, phase: .hold), cutMotionLimit: limit)
        #expect(a.state(for: .b)?.identity == .confirmed)
        #expect(a.settledFor(.b, now: 0.7) > 0)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 0.7) == 0)
        a.ingest(sample(0.8), cutMotionLimit: limit)
        #expect(a.cutSettledFor(.b, motionLimit: limit, now: 0.8) == 0)
    }
}
