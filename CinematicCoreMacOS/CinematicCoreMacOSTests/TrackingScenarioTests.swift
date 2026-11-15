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
        var legacyWrongRuns = 0
        var meanHold = 0.0
        var meanVisibleHold = 0.0
        var ends: [String: Int] = [:]
        var allOnSubject: Bool { ends["subject"] == 8 }
    }

    private func measure(_ name: String) throws -> Measurement {
        let harness = TrackingScenarios()
        let scenario = try #require(harness.scenarios().first { $0.name == name })
        var result = Measurement()
        for seed in seeds {
            let run = try harness.run(scenario, seed: seed)
            if run.latchedWrong > 0.2 { result.wrongRuns += 1 }
            if run.wrong > 0.2 { result.legacyWrongRuns += 1 }
            print("TRACKING-SCENARIO|\(name)|seed=\(seed)|legacyWrongSeconds=\(run.wrong)|latchedWrongSeconds=\(run.latchedWrong)|longestLatchedWrongSeconds=\(run.longestLatchedWrong)|unionSeconds=\(run.unionTime)|endsOn=\(run.final)|legacyEndsOn=\(run.legacyFinal)")
            result.meanHold += run.hold / Double(seeds.count)
            result.meanVisibleHold += run.holdVisible / Double(seeds.count)
            result.ends[run.final, default: 0] += 1
        }
        let ends = result.ends.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        print("TRACKING-SCENARIO|\(name)|wrongRuns=\(result.wrongRuns)/\(seeds.count)|legacyWrongRuns=\(result.legacyWrongRuns)/\(seeds.count)|meanHoldSeconds=\(r2(result.meanHold))|meanHoldWhileVisibleSeconds=\(r2(result.meanVisibleHold))|endsOn=\(ends)")
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

    @Test func reachingNeighboursDuringMiss() throws {
        try guardTarget("groupStill_reach_subjectMissed", fraction: 0)
    }
    @Test func smallSidestepRebinds() throws {
        let result = try measure("sidestepSmall_thenStill")
        if TrackingScenarioOptions.wide { return }
        #expect(result.allOnSubject)
    }
    @Test func largeSidestepCharacterisation() throws {
        let result = try measure("sidestepLarge_thenStill")
        if TrackingScenarioOptions.wide { return }
        #expect(result.ends == ["hold": 8])
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
    @Test func groupSubjectMissed() throws { try guardTarget("groupStill_subjectMissed0.4s_every5s", fraction: 0) }
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

    @Test func provenancePreservesInputBoxesAndLegacyMeasurements() throws {
        if TrackingScenarioOptions.wide { return }
        let harness = TrackingScenarios()
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "groupStill_reach_subjectMissed" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "7857750d79f11ce8c9cbccf8746290ca9581a4f08fe285eb8768c08cc79d0727", "groupStill_reach_subjectMissed")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "sidestepSmall_thenStill" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "cddf87ff5371099ccd1bd1ffbbe4784b0884ed7e3f79e4597a26b98c6cd8b8bd", "sidestepSmall_thenStill")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "sidestepLarge_thenStill" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "f308ec3d85e7d6454f25cce9b4ee25cf7d9f505f24510cb36c7a9faffa605364", "sidestepLarge_thenStill")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "hold")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_size1.00_v0.05" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "4b3806df65340e35b096bf170051c5a4a668e880f591c5b33b23c5a1ad074849", "crossInFront_size1.00_v0.05")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "hold")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_size1.00_v0.10" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "25af0ab563a83fc772641a112b39b2d006056992cf3e8ed8f844438ceed16383", "crossInFront_size1.00_v0.10")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_size1.00_v0.25" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "302ab5d72605c56972837f3301fea7be4a06576ad9d51981d9f0ffe8fc110e37", "crossInFront_size1.00_v0.25")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_size0.85_v0.05" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "05972b7e284c282bcfe727d0a8f13f19f44e76604c9f408e4f2138366c580bfe", "crossInFront_size0.85_v0.05")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "hold")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_size0.85_v0.10" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "f1d0ceb901a92d6a9816657c87c4e1102df0db2b5e4176f3a53be5f0b035c4c1", "crossInFront_size0.85_v0.10")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_size0.85_v0.25" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "442cf33508fbd1db919099ba784f394e4c5a7d9759fa4750c9bcf49c17c9432f", "crossInFront_size0.85_v0.25")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossBehind_v0.10" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "2d4485e06c3e1c412f94de8d6f33a16e62259149589f6e2d4d0c4586f8ccf64f", "crossBehind_v0.10")
            #expect(result.wrong == 0.04)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossBehind_v0.25" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "e89f0f63a7f591b0030590eeba2a89aee56ee8e635a0c054c217308be474fe66", "crossBehind_v0.25")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossBothSeen_v0.10" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "ea35af690272697771a5a581dd5dd8c5b33a317284a025286f96493c612a3525", "crossBothSeen_v0.10")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossMergedBox_v0.10" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "5b9e7d231fd389b20ecee4dae8232ec4b99c6033d76d600a8a048cd280a5490c", "crossMergedBox_v0.10")
            #expect(result.wrong == 0.25999999999999995)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "crossInFront_subjectWalking0.04" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "65696ca74ef5c2116f1f812fb5ba04e6a917525ac5fff0ab02e80e7b7344ab7d", "crossInFront_subjectWalking0.04")
            #expect(result.wrong == 4.879999999999984)
            #expect(result.legacyFinal == "hold")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "groupGestures_spacing1.0bw" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "9e6263145fc1d395e6924f08321d08974cfdf373b9d4f9b557d61a170219b0b7", "groupGestures_spacing1.0bw")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "groupGestures_spacing1.4bw" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "e71bcb40891e58849a44161e8cc4719c403b574c31bcc2c70b29edadad8d9793", "groupGestures_spacing1.4bw")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "groupStill_subjectMissed0.4s_every5s" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "dd12dd4a71f01b227f1200d81553ec02c728641f3b1dc023afa337620edf67fc", "groupStill_subjectMissed0.4s_every5s")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "walkerGap_v0.10_gap0.36_w0.070" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "64f329562a3e0fdcc985cc585b668d0136502a6c4bdfebddc50d132aa585f6f7", "walkerGap_v0.10_gap0.36_w0.070")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "walkerGap_v0.15_gap0.20_w0.035" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "870039614a8a758855e4650dbb1cda3d112a57e9d9d587589d8a532e9363c947", "walkerGap_v0.15_gap0.20_w0.035")
            #expect(result.wrong == 0.0)
            #expect(result.legacyFinal == "subject")
        }
        do {
            let scenario = try #require(harness.scenarios().first { $0.name == "walkerPastRowOfFour_gap0.3" })
            let result = try harness.run(scenario, seed: 40000)
            #expect(result.inputDigest == "1e7c1ee81716f2376cef83660909eb68424ae314706ae626d126447b1bbd2b34", "walkerPastRowOfFour_gap0.3")
            #expect(result.wrong == 0.4000000000000001)
            #expect(result.legacyFinal == "subject")
        }
    }
}
