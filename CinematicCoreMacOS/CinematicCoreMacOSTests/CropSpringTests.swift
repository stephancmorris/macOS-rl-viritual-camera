import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct CropSpringTests {
    private let start = CropEngine.CropRect(
        origin: CGPoint(x: 0.10, y: 0.35), size: CGSize(width: 0.30, height: 0.50))
    private let destination = CropEngine.CropRect(
        origin: CGPoint(x: 0.30, y: 0.15), size: CGSize(width: 0.50, height: 0.30))

    private func components(_ crop: CropEngine.CropRect) -> [CGFloat] {
        [crop.origin.x, crop.origin.y, crop.size.width, crop.size.height]
    }

    private func engine(from: CropEngine.CropRect, to: CropEngine.CropRect,
                        smoothing: Float = 0.25) throws -> CropEngine {
        let engine = try #require(CropEngine())
        engine.config.transitionSmoothing = smoothing
        engine.setTargetCrop(from)
        engine.jumpToTarget()
        engine.setTargetCrop(to)
        _ = engine.tickInterpolation(now: 100)
        return engine
    }

    @Test(arguments: [[0.08], [0.10], [0.08, 0.10], [0.10, 0.08]], [false, true])
    func droppedFrameKeepsEveryComponentMovingTowardItsTarget(gaps: [Double], reverse: Bool) throws {
        let from = reverse ? destination : start
        let to = reverse ? start : destination
        let engine = try engine(from: from, to: to)
        let targets = components(to)
        let directions = zip(components(from), targets).map { $1 > $0 ? CGFloat(1) : -1 }
        var previous = components(from)
        var now = 100.0
        // Start an interrupted move with nonzero velocity. Single and
        // consecutive gaps cover the old solver's overshoot and reversal.
        for dt in [0.02] + gaps + Array(repeating: 0.02, count: 150) {
            now += dt
            let current = components(engine.tickInterpolation(now: now).crop)
            for index in current.indices {
                #expect(current[index].isFinite)
                #expect((current[index] - previous[index]) * directions[index] >= -1e-12,
                        "component \(index) reversed after \(dt) seconds")
                #expect((targets[index] - current[index]) * directions[index] >= -1e-12,
                        "component \(index) overshot its target")
            }
            previous = current
        }
        #expect(engine.currentCrop == to)
        #expect(!engine.isInterpolating)
    }

    @Test(arguments: [Float(0.05), 0.06, 0.10, 0.20, 0.25, 0.30])
    func steadyTwentyMillisecondCurveStaysNearPreviousMotion(smoothing: Float) throws {
        let engine = try engine(from: start, to: destination, smoothing: smoothing)
        var old = components(start)
        var velocity = Array(repeating: CGFloat(0), count: 4)
        let target = components(destination)
        let stiffness = CGFloat(smoothing) * 600
        let damping = 2 * sqrt(stiffness)
        let dt: CGFloat = 0.02
        // For a 20%-of-source move, the largest integration difference across
        // the UI range is <1.8% of source; at the default it is <1.0%. This
        // bounds the old sampled curve without retuning stiffness to Euler.
        let tolerance: CGFloat = smoothing == 0.10 ? 0.011 : 0.019
        for frame in 1...150 {
            for index in old.indices {
                velocity[index] += ((target[index] - old[index]) * stiffness - velocity[index] * damping) * dt
                old[index] += velocity[index] * dt
            }
            let current = components(engine.tickInterpolation(now: 100 + Double(frame) / 50).crop)
            for index in current.indices {
                #expect(abs(current[index] - old[index]) < tolerance,
                        "component \(index), frame \(frame), smoothing \(smoothing)")
            }
        }
    }

    @Test func equalElapsedTimeHasTheSameResultAcrossFramePartitions() throws {
        let regular = try engine(from: start, to: destination)
        let delayed = try engine(from: start, to: destination)
        for frame in 1...5 { _ = regular.tickInterpolation(now: 100 + Double(frame) / 50) }
        _ = delayed.tickInterpolation(now: 100.1)
        for (a, b) in zip(components(regular.currentCrop), components(delayed.currentCrop)) {
            #expect(abs(a - b) < 1e-10)
        }
    }

    @Test func qualityFloorAndExactLandingRemainEnforced() throws {
        let engine = try #require(CropEngine())
        engine.qualityFloor = .init(minCropHeightFraction: 0.4)
        engine.setTargetCrop(.init(center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.8, height: 0.8)))
        engine.jumpToTarget()
        engine.setTargetCrop(.init(center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.2, height: 0.2)))
        #expect(engine.targetCrop.size.height == 0.4)
        for frame in 0...300 {
            let crop = engine.tickInterpolation(now: 100 + Double(frame) / 50).crop
            #expect(crop.size.height >= 0.4)
            #expect(crop.origin.x >= 0 && crop.origin.x + crop.size.width <= 1)
            #expect(crop.origin.y >= 0 && crop.origin.y + crop.size.height <= 1)
        }
        #expect(engine.currentCrop == engine.targetCrop)
        #expect(!engine.isInterpolating)
    }
}
