import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct TrackingScenarioTests {
    // Same initial seeds as the study; every run owns its complete tracking chain.
    private var seeds: [UInt64] { Array(40_000..<(TrackingScenarioOptions.wide ? 40_024 : 40_008)) }

    private struct Measurement {
        var wrongRuns = 0
        var meanHold = 0.0
        var ends: [String: Int] = [:]
        var allOnSubject: Bool { ends["subject"] == 8 }
    }

    private func measure(_ name: String) throws -> Measurement {
        let harness = TrackingScenarios()
        let scenario = try #require(harness.scenarios().first { $0.name == name })
        var result = Measurement()
        for seed in seeds {
            let run = try harness.run(scenario, seed: seed)
            if run.wrong > 0.2 { result.wrongRuns += 1 }
            result.meanHold += run.hold / Double(seeds.count)
            result.ends[run.final, default: 0] += 1
        }
        let ends = result.ends.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        print("TRACKING-SCENARIO|\(name)|wrongRuns=\(result.wrongRuns)/\(seeds.count)|meanHoldSeconds=\(r2(result.meanHold))|endsOn=\(ends)")
        return result
    }

    private func target(_ name: String, fraction: Double, stage: String) throws {
        let result = try measure(name)
        if TrackingScenarioOptions.wide { return }
        withKnownIssue("T-01/T-10, fixed by stage \(stage)") {
            #expect(Double(result.wrongRuns) / Double(seeds.count) <= fraction)
        }
    }

    private func guardTarget(_ name: String, fraction: Double) throws {
        let result = try measure(name)
        if TrackingScenarioOptions.wide { return }
        #expect(Double(result.wrongRuns) / Double(seeds.count) <= fraction)
    }

    @Test(arguments: [true, false])
    func witnessedBoxNeverTakesLock(wasBound: Bool) {
        if TrackingScenarioOptions.wide { return }
        let reference = CGRect(x: 0.465, y: 0.25, width: 0.07, height: 0.30)
        let other = reference.offsetBy(dx: 0.02, dy: 0)
        var probation: PersonDetector.LockProbation?
        for frame in 0..<100 {
            let time = Double(frame) * 0.04
            let result = PersonDetector.resolveLockedAssignment(detections: [other],
                referenceBox: reference, lockVelocityMagnitude: 0, timeSinceLockSeen: time,
                otherTrackBoxes: [], probation: probation, observationTimestamp: time,
                witnessBoxes: [other], lockWasBoundLastScan: wasBound)
            #expect(result.assignedIndex == nil)
            #expect(result.probation == nil)
            probation = result.probation
        }
    }

    @Test func frontSameSlow() throws { try guardTarget("crossInFront_size1.00_v0.05", fraction: 0) }
    @Test func frontSameWalking() throws { try target("crossInFront_size1.00_v0.10", fraction: 0.25, stage: "L2") }
    @Test func frontSameFast() throws { try guardTarget("crossInFront_size1.00_v0.25", fraction: 0.125) }
    @Test func frontSmallerSlow() throws { try guardTarget("crossInFront_size0.85_v0.05", fraction: 0) }
    @Test func frontSmallerWalking() throws { try guardTarget("crossInFront_size0.85_v0.10", fraction: 0) }
    @Test func frontSmallerFast() throws { try guardTarget("crossInFront_size0.85_v0.25", fraction: 0) }
    @Test func behindWalking() throws {
        let r = try measure("crossBehind_v0.10")
        if TrackingScenarioOptions.wide { return }
        withKnownIssue("lock lost during overlap on main; explained in L-a, fixed by L-b") {
            #expect(r.wrongRuns == 0)
            #expect(r.allOnSubject)
        }
    }
    @Test func behindFast() throws {
        let r = try measure("crossBehind_v0.25")
        if TrackingScenarioOptions.wide { return }
        #expect(r.wrongRuns == 0)
        #expect(r.allOnSubject)
    }
    @Test func bothReported() throws {
        let r = try measure("crossBothSeen_v0.10")
        if TrackingScenarioOptions.wide { return }
        #expect(r.wrongRuns == 0)
        #expect(r.allOnSubject)
    }
    @Test func mergedBox() throws {
        let r = try measure("crossMergedBox_v0.10")
        if TrackingScenarioOptions.wide { return }
        withKnownIssue("lock lost during overlap on main; explained in L-a, fixed by L-b") {
            #expect(r.allOnSubject)
        }
    }
    @Test func walkingSubjectCrossed() throws { try guardTarget("crossInFront_subjectWalking0.04", fraction: 0.5) }
    @Test func gesturesOneWidth() throws { try guardTarget("groupGestures_spacing1.0bw", fraction: 0.125) }
    @Test func gesturesWider() throws { try guardTarget("groupGestures_spacing1.4bw", fraction: 0) }
    @Test func groupSubjectMissed() throws { try target("groupStill_subjectMissed0.4s_every5s", fraction: 0, stage: "L5") }
    @Test func walkerMiss() throws {
        let r = try measure("walkerGap_v0.10_gap0.36_w0.070")
        if TrackingScenarioOptions.wide { return }
        #expect(r.allOnSubject)
        #expect(r.meanHold <= 0.3)
    }
    @Test func narrowWalkerMiss() throws {
        let r = try measure("walkerGap_v0.15_gap0.20_w0.035")
        if TrackingScenarioOptions.wide { return }
        #expect(r.allOnSubject)
        #expect(r.meanHold <= 0.3)
    }
    @Test func walkerPastRow() throws { try target("walkerPastRowOfFour_gap0.3", fraction: 0.25, stage: "L5") }
}
