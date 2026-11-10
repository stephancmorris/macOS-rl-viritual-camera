import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct FreshMotionTests {
    private func person(time: Double, step: Bool = false) -> PersonDetector.DetectedPerson {
        .init(id: UUID(), boundingBox: CGRect(x: 0.25 + time * 0.1,
                    y: 0.2 + (step && time >= 0.2 ? 0.06 : 0), width: 0.12, height: 0.4),
              confidence: 0.95, timestamp: time, poseKeypoints: nil,
              faceBoundingBox: nil, faceLandmarkRatios: nil)
    }

    private func composer() -> ShotComposer {
        let composer = ShotComposer()
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = .waistUp
        composer.config.steadyFollowingEnabled = false
        return composer
    }

    private func run(fps: Double, repeats: Bool, step: Bool) throws -> [(anchor: CGFloat, speed: Double)] {
        let composer = composer()
        var result: [(CGFloat, Double)] = []
        for frame in 0...Int(fps) {
            let isFresh = !repeats || frame % 2 == 0
            let observedFrame = repeats ? frame - frame % 2 : frame
            let time = Double(observedFrame) / fps
            _ = composer.compose(person: person(time: time, step: step), isFresh: isFresh,
                                 observationTimestamp: time)
            if [0.4, 0.6, 0.8, 1.0].contains(where: { abs(Double(frame) / fps - $0) < 1e-9 }) {
                result.append((try #require(composer.currentComputedCrop).origin.y, composer.subjectSpeed))
            }
        }
        return result
    }

    @Test(arguments: [30.0, 50.0], [false, true])
    func anchorCurveAndSpeedAgreeAcrossRatesAndRepeats(fps: Double, repeats: Bool) throws {
        let baselineAnchor = try run(fps: 50, repeats: false, step: true)
        let sampledAnchor = try run(fps: fps, repeats: repeats, step: true)
        let baselineSpeed = try run(fps: 50, repeats: false, step: false)
        let sampledSpeed = try run(fps: fps, repeats: repeats, step: false)
        #expect(sampledAnchor.count == baselineAnchor.count)
        for index in sampledAnchor.indices {
            // Includes sampling a step on a 15 Hz detector (30 fps / 2).
            #expect(abs(sampledAnchor[index].anchor - baselineAnchor[index].anchor) < 0.002)
            #expect(abs(sampledSpeed[index].speed - baselineSpeed[index].speed) < 0.001)
        }
    }

    @Test func repeatsAndDuplicateTimesCannotAdvanceAnchorOrSpeed() throws {
        let composer = composer()
        _ = composer.compose(person: person(time: 0), observationTimestamp: 0)
        let next = person(time: 0.2, step: true)
        _ = composer.compose(person: next, observationTimestamp: 0.2)
        let anchor = try #require(composer.currentComputedCrop).origin.y
        let speed = composer.subjectSpeed
        for _ in 0..<20 {
            _ = composer.compose(person: next, isFresh: false, observationTimestamp: 0.2)
            #expect(composer.currentComputedCrop?.origin.y == anchor)
            #expect(composer.subjectSpeed == speed)
            _ = composer.compose(person: next, isFresh: true, observationTimestamp: 0.2)
            #expect(composer.currentComputedCrop?.origin.y == anchor)
            #expect(composer.subjectSpeed == speed)
        }
    }
}

struct TimedLockProbationTests {
    private let reference = CGRect(x: 0.47, y: 0.3, width: 0.06, height: 0.5)
    private var candidate: CGRect { reference.offsetBy(dx: 0.1, dy: 0) }

    private func resolve(_ time: Double, probation: PersonDetector.LockProbation?,
                         contested: Bool = false, boxes: [CGRect]? = nil) -> PersonDetector.LockedResolution {
        PersonDetector.resolveLockedAssignment(
            detections: boxes ?? [candidate], referenceBox: reference,
            lockVelocityMagnitude: 0, timeSinceLockSeen: time,
            otherTrackBoxes: contested ? [candidate.insetBy(dx: -0.01, dy: -0.01)] : [],
            probation: probation, observationTimestamp: time)
    }

    @Test(arguments: [15.0, 25.0, 30.0, 50.0, 60.0], [false, true])
    func probationDependsOnDurationRatherThanCount(rate: Double, contested: Bool) throws {
        var probation: PersonDetector.LockProbation?
        let required = contested ? 0.28 : 0.08
        var accepted: Double?
        for frame in 0...Int(ceil(required * rate) + 1) {
            let time = Double(frame) / rate
            let resolution = resolve(time, probation: probation, contested: contested)
            if resolution.assignedIndex != nil { accepted = time; break }
            probation = resolution.probation
            let repeated = resolve(time, probation: probation, contested: contested)
            #expect(repeated.assignedIndex == nil)
            #expect(repeated.probation == probation)
        }
        let time = try #require(accepted)
        #expect(time + 1e-9 >= required)
        #expect(time <= required + 1 / rate + 1e-9)
    }

    @Test func olderObservationCannotReplaceProbationEvidence() {
        let first = resolve(0.1, probation: nil)
        let later = resolve(0.14, probation: first.probation)
        let old = resolve(0.1, probation: later.probation, boxes: [reference.offsetBy(dx: -0.1, dy: 0)])
        #expect(old.probation == later.probation)
        #expect(old.assignedIndex == nil)
    }

    @Test func missingCandidatesAndLongGapsResetElapsedEvidence() {
        let first = resolve(0, probation: nil)
        let second = resolve(0.04, probation: first.probation)
        #expect(resolve(0.04, probation: second.probation).probation == second.probation)
        #expect(resolve(0.05, probation: second.probation, boxes: []).probation == nil)
        let afterGap = resolve(0.3, probation: second.probation)
        #expect(afterGap.assignedIndex == nil)
        #expect(afterGap.probation?.startedAt == 0.3)
        #expect(resolve(0.38, probation: afterGap.probation).assignedIndex == 0)
    }
}
