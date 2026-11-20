//
//  A01LockScenarioTests.swift
//  CinematicCoreMacOSTests
//
//  A-01: lock and recover without a frontal face. The rows of the design's
//  section 6, on synthetic boxes from `TrackingScenarios.a01Scenarios()`.
//  Today's behaviour is recorded as guards, characterisations and known
//  issues; nothing here is measured from real Vision.
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct A01LockScenarioTests {
    private var seeds: [UInt64] { Array(40_000..<(TrackingScenarioOptions.wide ? 40_024 : 40_008)) }

    struct Measurement {
        var runs = 0
        var wrongRuns = 0
        var meanHold = 0.0
        var ends: [String: Int] = [:]
        /// Runs that reached tracking within 1.3 s of the click.
        var lockedWithin1_3 = 0
        /// Mean time to lock over the runs that locked.
        var meanTimeToLock: Double?
        /// Runs that ended with three or more real gallery entries.
        var confirmed = 0
        var maxGallery = 0
        func endsOn(_ state: String) -> Bool { ends[state] == runs }
        var endsHoldOrWide: Bool { (ends["hold"] ?? 0) + (ends["wide"] ?? 0) == runs }
    }

    func measure(_ name: String) throws -> Measurement {
        let harness = TrackingScenarios()
        let scenario = try #require(harness.a01Scenarios().first { $0.name == name })
        var m = Measurement()
        var lockTimes: [Double] = []
        for seed in seeds {
            let run = try harness.run(scenario, seed: seed)
            m.runs += 1
            if run.latchedWrong > 0.2 { m.wrongRuns += 1 }
            m.meanHold += run.hold / Double(seeds.count)
            m.ends[run.final, default: 0] += 1
            if let t = run.timeToLock {
                lockTimes.append(t)
                if t <= 1.3 { m.lockedWithin1_3 += 1 }
            }
            if run.identityConfirmed { m.confirmed += 1 }
            m.maxGallery = max(m.maxGallery, run.gallerySize)
            print("A01-SCENARIO|\(name)|seed=\(seed)|latchedWrongSeconds=\(run.latchedWrong)|holdSeconds=\(r2(run.hold))|endsOn=\(run.final)|timeToLock=\(run.timeToLock.map { r2($0) } ?? "never")|gallery=\(run.gallerySize)")
        }
        if !lockTimes.isEmpty { m.meanTimeToLock = lockTimes.reduce(0, +) / Double(lockTimes.count) }
        let ends = m.ends.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        print("A01-SCENARIO|\(name)|wrongRuns=\(m.wrongRuns)/\(m.runs)|meanHoldSeconds=\(r2(m.meanHold))|endsOn=\(ends)|lockedWithin1.3s=\(m.lockedWithin1_3)/\(m.runs)|meanTimeToLock=\(m.meanTimeToLock.map { r2($0) } ?? "never")|identityConfirmed=\(m.confirmed)/\(m.runs)|maxGallery=\(m.maxGallery)")
        return m
    }

    private var wide: Bool { TrackingScenarioOptions.wide }

    // MARK: Occlusion in place

    @Test(arguments: [0.6, 0.9])
    func shortOcclusionReturns(gap: Double) throws {
        let m = try measure("occludedInPlace_gap\(r2(gap, 1))")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsOn("subject"))
        #expect(m.meanHold <= gap + 0.5)
    }

    @Test(arguments: [1.2, 2.0, 2.8])
    func longerOcclusionReturns(gap: Double) throws {
        let m = try measure("occludedInPlace_gap\(r2(gap, 1))")
        if wide { return }
        #expect(m.wrongRuns == 0)
        withKnownIssue("A-01: the locked track is forgotten after 1.0 s unseen; only a face brings it back (stage 3, body re-bind)") {
            #expect(m.endsOn("subject"))
            #expect(m.meanHold <= gap + 0.5)
        }
    }

    @Test func occlusionBeyondMemory() throws {
        let m = try measure("occludedInPlace_gap4.0")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsOn("wide"))
    }

    // MARK: Newcomers and bystanders

    @Test(arguments: [0.4, 0.7])
    func newcomerArrivingSoon(arrive: Double) throws {
        let m = try measure("newcomerOnSpot_arrive\(r2(arrive, 1))")
        if wide { return }
        withKnownIssue("A-01: a newcomer on the empty spot within 1 s takes the lock (outsider rule, stage 1)") {
            #expect(m.wrongRuns == 0)
            #expect(m.endsHoldOrWide)
        }
    }

    @Test(arguments: [1.5, 2.5])
    func newcomerArrivingLate(arrive: Double) throws {
        let m = try measure("newcomerOnSpot_arrive\(r2(arrive, 1))")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsHoldOrWide)
    }

    @Test(arguments: ["farBystanderRevealedAtHold", "subjectReturnsBesideBystander"])
    func bystanderShortGap(row: String) throws {
        let m = try measure("\(row)_gap0.6")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsOn("subject"))
    }

    @Test(arguments: ["farBystanderRevealedAtHold", "subjectReturnsBesideBystander"])
    func bystanderLongGap(row: String) throws {
        let m = try measure("\(row)_gap2.0")
        if wide { return }
        #expect(m.wrongRuns == 0)
        withKnownIssue("A-01: after 1.0 s unseen only a face brings the subject back (stage 3, body re-bind)") {
            #expect(m.endsOn("subject"))
        }
    }

    /// The residual risk (owner decision D3). Today: frozen, never wrong.
    @Test func otherEmergesOnSpotCharacterisation() throws {
        let m = try measure("otherEmergesOnSpot_after1.5")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsOn("wide"))
    }

    @Test func shorterOtherEmergesOnSpot() throws {
        let m = try measure("otherEmergesOnSpot_after1.5_height0.75")
        if wide { return }
        #expect(m.wrongRuns == 0)
    }

    // MARK: Clicks

    @Test(arguments: ["acquireNoFace_still", "acquireNoFace_walking0.10"])
    func clickWithoutFace(row: String) throws {
        let m = try measure(row)
        if wide { return }
        #expect(m.wrongRuns == 0)
        // Today: no face, so the click times out after 8 s.
        #expect(m.endsOn("inactive"))
        withKnownIssue("A-01: a click needs three face samples to lock (stage 2, lock without a face)") {
            #expect(m.lockedWithin1_3 == m.runs)
        }
    }

    @Test func clickBesideGesturingNeighbour() throws {
        let m = try measure("acquireNoFace_neighbour1.0bw_gestures")
        if wide { return }
        #expect(m.wrongRuns == 0)
    }

    @Test func clickWithFace() throws {
        let m = try measure("acquireFace0.7")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsOn("subject"))
        #expect(m.confirmed == m.runs)
    }

    /// Today the 2 s gap during acquisition releases the click.
    @Test func weakLockLongGapCharacterisation() throws {
        let m = try measure("weakLockLongGapThenFace")
        if wide { return }
        #expect(m.wrongRuns == 0)
        #expect(m.endsOn("inactive"))
    }
}
