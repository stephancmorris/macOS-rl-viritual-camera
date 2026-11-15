import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct SteadyCadenceTests {
    private let start = 1000.0

    // FramingLoop uses the production interval-2 eligible-frame rule and a
    // capture-time mailbox. Latency is varied without changing that rule.
    @Test(arguments: [25.0, 29.97, 30.0, 50.0, 59.94, 60.0], [0.010, 0.018, 0.025, 0.040, 0.080])
    func productionCadenceMatrix(fps: Double, latency: Double) throws {
        var restByNoise: [Double] = []
        for noise in [0.001, 0.003] {
            var rests: [Double] = []
            for seed: UInt64 in 9000..<9008 {
                let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
                loop.visionLatency = latency
                let rng = ProbeRng(seed)
                var rest = Double.infinity
                for frame in 0...Int(ceil(1.5 * fps)) {
                    let elapsed = Double(frame) / fps
                    _ = loop.step(t: start + elapsed) { _ in
                        let scale = 1 + rng.gauss() * noise * 5
                        return scenarioBox(cx: 0.5 + rng.gauss() * noise,
                            bottom: 0.25 + rng.gauss() * noise,
                            w: 0.07 * scale, h: 0.30 * scale)
                    }
                    if loop.composer.steadyBand != nil { rest = elapsed; break }
                }
                rests.append(rest)
            }
            // Same eight-seed median statistic as the existing rest tests.
            let median = rests.sorted()[4]
            restByNoise.append(median)
            #expect(median <= 1.5, "fps=\(fps) latency=\(latency) noise=\(noise) rests=\(rests)")
        }
        var fastestParked = 0.0
        var observationRate = 0.0
        for step in 1...17 {
            let speed = Double(step) * 0.002
            let result = try drift(fps: fps, latency: latency, speed: speed)
            observationRate = result.rate
            if result.parked { fastestParked = speed }
        }
        #expect(fastestParked <= 0.024)
        if observationRate >= 12.5 - 1e-6 { #expect(fastestParked >= 0.012) }
        #expect(try !drift(fps: fps, latency: latency, speed: 0.05).parked)
        print("STEADY-CADENCE|fps=\(fps)|latencyMs=\(latency * 1000)|observationsHz=\(observationRate)|restMedians=\(restByNoise)|fastestParked=\(fastestParked)")
    }

    private func drift(fps: Double, latency: Double, speed: Double) throws -> (parked: Bool, rate: Double) {
        let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
        loop.visionLatency = latency
        var captures: [Double] = [], parked = false
        for frame in 0..<Int(8 * fps) {
            _ = loop.step(t: start + Double(frame) / fps) { t in
                captures.append(t)
                return scenarioBox(cx: 0.3 + speed * (t - start))
            }
            parked = parked || loop.composer.steadyBand != nil
        }
        // Exclude the priming observation from the steady cadence measurement.
        let samples = captures.dropFirst()
        let rate = samples.count > 1 ? Double(samples.count - 1) / (samples.last! - samples.first!) : 0
        return (parked, rate)
    }

    @Test func unchangedFiftyFramePark() throws {
        let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
        var parkedAt: Double?, target: CropEngine.CropRect?
        for frame in 0...100 {
            let elapsed = Double(frame) / 50
            _ = loop.step(t: start + elapsed) { _ in scenarioBox(cx: 0.5) }
            if loop.composer.steadyBand != nil {
                parkedAt = elapsed; target = loop.engine.targetCrop; break
            }
        }
        print("STEADY-BASELINE|time=\(String(describing: parkedAt))|target=\(String(describing: target))")
        #expect(parkedAt == 0.28)
        let baseline = CropEngine.CropRect(center: CGPoint(x: 0.5, y: 0.396),
            size: CGSize(width: 0.35, height: 0.35))
        #expect(target == baseline)
    }

    @Test(arguments: [false, true])
    func irregularFreshTimesAndInvalidSamples(jittered: Bool) {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        composer.config.apply(.steadyFollow)
        let id = UUID()
        func observe(_ t: Double, fresh: Bool = true) {
            let person = PersonDetector.DetectedPerson(id: id,
                boundingBox: scenarioBox(cx: 0.5), confidence: 1, timestamp: t,
                poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
            _ = composer.compose(person: person, isFresh: fresh, observationTimestamp: t)
        }
        observe(start)
        observe(start + 0.04)
        for t in [start + 0.04, start, Double.nan, Double.infinity, -Double.infinity] {
            observe(t)
            #expect(composer.steadyBand == nil)
        }
        observe(start + 0.08, fresh: false)
        #expect(composer.steadyBand == nil)
        var t = start + 0.04
        for i in 1...30 {
            t += jittered ? 0.04 + (i.isMultiple(of: 2) ? 0.002 : -0.002) : (i.isMultiple(of: 2) ? 0.06 : 0.04)
            observe(t)
            if composer.steadyBand != nil { break }
        }
        #expect(composer.steadyBand != nil)
    }
}
