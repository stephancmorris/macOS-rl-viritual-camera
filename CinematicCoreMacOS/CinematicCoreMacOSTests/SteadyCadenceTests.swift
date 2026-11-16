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

        // Below about 15 Hz the window holds only four samples, so heavy noise
        // can delay parking; the camera keeps following gently meanwhile. This
        // is the safe direction (parking on a drifting subject is not), and
        // the 50 fps show standard is unaffected. 29.97 fps capture observes
        // at 14.985 Hz and belongs to the 15 Hz class.
        let fullWindow = observationRate >= 14.5
        var restByNoise: [Double] = []
        for noise in [0.001, 0.003] {
            let everySeedBound = noise > 0.002 && !fullWindow ? 6.0 : 1.5
            var rests: [Double] = []
            for seed: UInt64 in 9000..<9008 {
                let loop = try FramingLoop(preset: .waistUp, feel: .steadyFollow)
                loop.visionLatency = latency
                let rng = ProbeRng(seed)
                var rest = Double.infinity
                for frame in 0...Int(ceil(everySeedBound * fps)) {
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
            let median = rests.sorted()[4]
            restByNoise.append(median)
            let slowSeeds = rests.enumerated().filter { $0.element > 1.5 }.map { 9000 + $0.offset }
            print("STEADY-SEEDS|fps=\(fps)|latencyMs=\(latency * 1000)|noise=\(noise)|everySeedBound=\(everySeedBound)|over1.5s=\(slowSeeds.count)/8|slowSeeds=\(slowSeeds)|restMedian=\(median)|rests=\(rests)")
            // Same eight-seed median bar as noisyRestTarget at the show standard.
            #expect(median <= 1.5, "fps=\(fps) latency=\(latency) noise=\(noise) median=\(median)")
            for (offset, rest) in rests.enumerated() {
                #expect(rest <= everySeedBound,
                        "fps=\(fps) latency=\(latency) noise=\(noise) seed=\(9000 + offset) rest=\(rest) bound=\(everySeedBound)")
            }
        }
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

    private func makeComposer() -> ShotComposer {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        composer.config.apply(.steadyFollow)
        return composer
    }

    private func observe(_ composer: ShotComposer, id: UUID, time: Double,
                         fresh: Bool = true, center: Double = 0.5) {
        let person = PersonDetector.DetectedPerson(id: id,
            boundingBox: scenarioBox(cx: center), confidence: 1, timestamp: time,
            poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        _ = composer.compose(person: person, isFresh: fresh, observationTimestamp: time)
    }

    @Test(arguments: [false, true])
    func invalidSamplesNeitherCountNorReset(longGap: Bool) {
        let composer = makeComposer(), id = UUID()
        // Commit the initial framing before the measured settle window.
        // Framing-change observations return before collecting settle evidence.
        observe(composer, id: id, time: start - 0.04)
        for frame in 0...5 {
            observe(composer, id: id, time: start + Double(frame) * 0.04)
            #expect(composer.steadyBand == nil)
        }
        for time in [start + 0.20, start + 0.12, Double.nan, Double.infinity, -Double.infinity] {
            observe(composer, id: id, time: time)
            #expect(composer.steadyBand == nil)
        }
        observe(composer, id: id, time: start + 0.24, fresh: false)
        #expect(composer.steadyBand == nil)
        // 0.20 s exceeds steadyObservationGap (0.150 s).
        observe(composer, id: id, time: start + (longGap ? 0.40 : 0.24))
        #expect((composer.steadyBand != nil) == !longGap)
    }

    @Test(arguments: [false, true])
    func irregularFreshTimesPark(jittered: Bool) {
        let composer = makeComposer(), id = UUID()
        var time = start
        observe(composer, id: id, time: time)
        for i in 1...30 {
            time += jittered ? 0.04 + (i.isMultiple(of: 2) ? 0.002 : -0.002)
                             : (i.isMultiple(of: 2) ? 0.06 : 0.04)
            observe(composer, id: id, time: time)
            if composer.steadyBand != nil { break }
        }
        #expect(composer.steadyBand != nil)
    }

    @Test func walkingAtIrregularCadenceDoesNotPark() {
        let composer = makeComposer(), id = UUID()
        var time = start
        for i in 0...160 {
            if i > 0 { time += i.isMultiple(of: 2) ? 0.06 : 0.04 }
            observe(composer, id: id, time: time, center: 0.3 + 0.05 * (time - start))
            #expect(composer.steadyBand == nil)
        }
    }
}
