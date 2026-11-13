import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct FramingMotionScenarioTests {
    private let t0 = 1000.0
    private let fps = 50.0

    @Test func defaultSpringRampLag() throws {
        let engine = try #require(CropEngine())
        // Measure a real ramp, rather than asserting the probe's 2/sqrt(k) formula.
        // Stay above the spring's small-distance snap threshold.
        let speed = 0.10
        let size = CGSize(width: 0.35, height: 0.35)
        engine.setTargetCrop(.init(center: CGPoint(x: 0.15, y: 0.5), size: size))
        engine.jumpToTarget()
        var lags: [Double] = []
        for frame in 0...250 {
            let elapsed = Double(frame) / fps
            let target = 0.15 + speed * elapsed
            engine.setTargetCrop(.init(center: CGPoint(x: target, y: 0.5), size: size))
            let crop = engine.tickInterpolation(now: t0 + elapsed).crop
            if elapsed > 3 { lags.append((target - Double(crop.center.x)) / speed * 1000) }
        }
        let lag = lags.reduce(0, +) / Double(lags.count)
        print("FRAMING-MOTION|springRampLagMs=\(r2(lag))")
        #expect((240...280).contains(lag))
    }

    @Test func springStepHasNoOvershoot() throws {
        let engine = try #require(CropEngine())
        let size = CGSize(width: 0.35, height: 0.35)
        engine.setTargetCrop(.init(center: CGPoint(x: 0.4, y: 0.5), size: size))
        engine.jumpToTarget()
        engine.setTargetCrop(.init(center: CGPoint(x: 0.5, y: 0.5), size: size))
        var overshoot = 0.0
        for frame in 0..<500 {
            let crop = engine.tickInterpolation(now: t0 + Double(frame) / fps).crop
            overshoot = max(overshoot, Double(crop.center.x) - 0.5)
        }
        print("FRAMING-MOTION|springStepOvershoot=\(overshoot)")
        #expect(overshoot == 0)
    }

    // Probe B/L measurement only. No predictive lead is added to the subject.
    private func walk(speed: Double) throws -> (lagMs: Double, overshootFraction: Double) {
        let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
        let stand = 2.0, duration = 0.4 / speed
        func position(_ time: Double) -> Double {
            0.3 + speed * max(0, min(time - t0 - stand, duration))
        }
        var lagSum = 0.0, lagCount = 0, overshoot = 0.0
        for frame in 0..<Int((stand + duration + 4) * fps) {
            let elapsed = Double(frame) / fps
            let time = t0 + elapsed
            let crop = loop.step(t: time) { scenarioBox(cx: position($0)) }
            let lag = position(time) - Double(crop.center.x)
            let progress = (elapsed - stand) / duration
            if progress > 0.4, progress < 0.95 { lagSum += lag; lagCount += 1 }
            if elapsed >= stand + duration {
                overshoot = max(overshoot, -lag / Double(crop.size.width))
            }
        }
        return (lagSum / Double(lagCount) / speed * 1000, overshoot)
    }

    @Test func walkerLagToday() throws {
        let result = try walk(speed: 0.10)
        print("FRAMING-MOTION|walkerLagMs=\(r2(result.lagMs))")
        #expect((250...310).contains(result.lagMs))
    }

    @Test func walkerLagTarget() throws {
        let result = try walk(speed: 0.10)
        withKnownIssue("T-03, fixed by stage C1") { #expect(result.lagMs <= 150) }
    }

    @Test func deadStopOvershootGuard() throws {
        let result = try walk(speed: 0.20)
        print("FRAMING-MOTION|deadStopOvershootPctPicture=\(r2(result.overshootFraction * 100))")
        #expect(result.overshootFraction <= 0.04)
    }

    @Test func stillCropDoesNotMoveAfterHolding() throws {
        let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
        var reference: CropEngine.CropRect?
        var maxMovementPixels = 0.0
        for frame in 0..<500 {
            let crop = loop.step(t: t0 + Double(frame) / fps) { _ in scenarioBox(cx: 0.5) }
            // Let the initial wide-to-subject spring move finish before measuring rest.
            if frame >= 150 {
                #expect(loop.composer.steadyBand != nil)
                if let reference {
                    maxMovementPixels = max(maxMovementPixels,
                        abs(Double(crop.center.x - reference.center.x)) / Double(crop.size.width) * 1920,
                        abs(Double(crop.center.y - reference.center.y)) / Double(crop.size.height) * 1080,
                        abs(Double(crop.size.width - reference.size.width)) * 1920,
                        abs(Double(crop.size.height - reference.size.height)) * 1080)
                } else { reference = crop }
            }
        }
        print("FRAMING-MOTION|stillMovementPixels=\(maxMovementPixels)")
        #expect(maxMovementPixels == 0)
    }

    private func medianRestTime(noise: Double) throws -> Double {
        var times: [Double] = []
        for seed: UInt64 in 9000..<9008 {
            let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
            let rng = ProbeRng(seed)
            // An unsettled run contributes the 15-second censoring bound, never disappears.
            var restTime = 15.0
            for frame in 0..<Int(15 * fps) {
                let elapsed = Double(frame) / fps
                _ = loop.step(t: t0 + elapsed) { _ in
                    let scale = 1 + rng.gauss() * noise * 5
                    return scenarioBox(cx: 0.5 + rng.gauss() * noise,
                                       bottom: 0.25 + rng.gauss() * noise,
                                       w: 0.07 * scale, h: 0.30 * scale)
                }
                if loop.composer.steadyBand != nil { restTime = elapsed; break }
            }
            times.append(restTime)
        }
        times.sort()
        let median = times[times.count / 2]
        print("FRAMING-MOTION|noisePctFrame=\(r2(noise * 100))|medianRestSeconds=\(r2(median))|notRestedBy15s=\(times.filter { $0 == 15 }.count)/8")
        return median
    }

    @Test func lowNoiseRestToday() throws { #expect(try medianRestTime(noise: 0.001) <= 0.6) }
    @Test func noisyRestTarget() throws {
        let median = try medianRestTime(noise: 0.003)
        withKnownIssue("T-04, fixed by stage C2") { #expect(median <= 1.5) }
    }
}
