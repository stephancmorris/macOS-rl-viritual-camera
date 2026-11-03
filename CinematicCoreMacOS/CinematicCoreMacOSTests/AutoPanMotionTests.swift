//
//  AutoPanMotionTests.swift
//  CinematicCoreMacOSTests
//
//  PAN-EASE-MODEL: the eased sweep keeps transit time, the 1.5 s dwell,
//  monotonic travel, phase across width changes and zero travel; only the
//  turnarounds change. With ALFIE_AUTOPAN_CSV=1 the sweep is written to
//  $TMPDIR/AlfieAutoPan/ for the owner's constant-vs-eased comparison.
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

struct AutoPanMotionCurveTests {
    @Test func easedCurveIsMonotonicContinuousAndHitsBothEnds() {
        #expect(AutoPanMotion.eased(0) == 0)
        #expect(abs(AutoPanMotion.eased(1) - 1) < 1e-12)
        #expect(abs(AutoPanMotion.eased(0.5) - 0.5) < 1e-12)
        var previous: CGFloat = -1
        for step in 0...1000 {
            let value = AutoPanMotion.eased(CGFloat(step) / 1000)
            #expect(value >= previous)
            previous = value
        }
        // Continuous at both ramp joins.
        let r = AutoPanMotion.easeFraction
        for join in [r, 1 - r] {
            #expect(abs(AutoPanMotion.eased(join - 1e-7) - AutoPanMotion.eased(join + 1e-7)) < 1e-5)
        }
    }

    @Test func endsTurnAroundSlowerThanConstantSpeed() {
        let early: CGFloat = 0.02
        #expect(AutoPanMotion.eased(early) < AutoPanMotion.linear(early) / 4)
        #expect(1 - AutoPanMotion.eased(1 - early) < (1 - AutoPanMotion.linear(1 - early)) / 4)
    }

    @Test func outOfRangePhaseIsClamped() {
        #expect(AutoPanMotion.eased(-0.5) == 0)
        #expect(AutoPanMotion.eased(1.5) == 1)
        #expect(AutoPanMotion.eased(0.4, easeFraction: 0) == 0.4)
    }
}

@MainActor
struct AutoPanMotionSweepTests {
    private struct Sweep {
        var transits: [Double] = []
        var dwells: [Double] = []
        var monotonic = true
        var rows: [String] = []
    }

    /// Run 150 s at 50 Hz with travel 0.5. A transit runs from leaving one
    /// end to arriving at the other; a dwell from arriving to leaving.
    private func sweep(_ speed: ShotComposer.Config.AutoPanSpeed, eased: Bool) -> Sweep {
        let manager = CameraManager()
        manager.shotComposer.config.autoPanSpeed = speed.rawValue
        manager.autoPanEasing = eased
        let width: CGFloat = 0.5
        let low = width / 2, high = width / 2 + (1 - width)
        func isEnd(_ c: CGFloat) -> Bool { abs(c - low) < 1e-9 || abs(c - high) < 1e-9 }
        var result = Sweep()
        var leftAt: Double?, arrivedAt: Double?
        var last: CGFloat?, sign: CGFloat = 0
        for tick in 0...(150 * 50) {
            let now = 100 + Double(tick) / 50
            let center = manager.advanceAutoPan(now: now, width: width)
            result.rows.append(String(format: "%.2f,%.6f", now - 100, Double(center)))
            if let last {
                if isEnd(center), !isEnd(last) {            // arrive
                    if let leftAt { result.transits.append(now - leftAt) }
                    arrivedAt = now; sign = 0
                } else if !isEnd(center), isEnd(last) {     // leave
                    if let arrivedAt { result.dwells.append(now - arrivedAt) }
                    leftAt = now
                } else if !isEnd(center) {
                    let delta = center - last
                    if sign != 0, delta != 0, (delta > 0) != (sign > 0) { result.monotonic = false }
                    if delta != 0 { sign = delta }
                }
            }
            last = center
        }
        return result
    }

    private static let targets: [(ShotComposer.Config.AutoPanSpeed, ClosedRange<Double>)] = [
        (.slow, 25...35), (.normal, 15...20), (.fast, 8...12),
    ]

    @Test(arguments: [false, true])
    func transitAndDwellMeetTheTargetsAtEverySpeed(eased: Bool) throws {
        for (speed, target) in Self.targets {
            let result = sweep(speed, eased: eased)
            let full = result.transits
            #expect(!full.isEmpty, "\(speed) eased \(eased): no full transit")
            for transit in full {
                #expect(target.contains(transit), "\(speed) eased \(eased): transit \(transit) s")
            }
            for dwell in result.dwells {
                #expect(abs(dwell - 1.5) <= 0.05, "\(speed) eased \(eased): dwell \(dwell) s")
            }
            #expect(result.monotonic, "\(speed) eased \(eased): reversed mid-sweep")
            if ProcessInfo.processInfo.environment["ALFIE_AUTOPAN_CSV"] == "1" {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieAutoPan", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = "autopan-\(speed.rawValue)-\(eased ? "eased" : "constant").csv"
                try (["seconds,center"] + result.rows).joined(separator: "\n")
                    .write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
    }

    @Test func easedAndConstantSweepsTakeTheSameTime() {
        for (speed, _) in Self.targets {
            let constant = sweep(speed, eased: false).transits
            let eased = sweep(speed, eased: true).transits
            #expect(constant.count == eased.count)
            for (c, e) in zip(constant, eased) { #expect(abs(c - e) <= 0.05, "\(speed): \(c) vs \(e)") }
        }
    }

    @Test func phaseIsKeptAcrossAWidthChangeAndZeroTravelHolds() {
        let manager = CameraManager()
        manager.autoPanEasing = true
        _ = manager.advanceAutoPan(now: 100, width: 0.5)
        let before = manager.advanceAutoPan(now: 100.02, width: 0.5)
        let fraction = (before - 0.25) / 0.5
        // The same phase lands at the same fraction of the new travel.
        let after = manager.advanceAutoPan(now: 100.02, width: 0.3)
        #expect(abs((after - 0.15) / 0.7 - fraction) < 1e-9)
        // Zero travel: centred, and the phase waits for travel to return.
        #expect(manager.advanceAutoPan(now: 101, width: 1) == 0.5)
        #expect(manager.advanceAutoPan(now: 102, width: 1) == 0.5)
        let resumed = manager.advanceAutoPan(now: 102, width: 0.3)
        #expect(abs((resumed - 0.15) / 0.7 - fraction) < 1e-9)
    }
}
