// Synthetic boxes only: no pose and no faces.
// A person is reported when at least 80% of their box is inside the scanned region.
// A person behind another is dropped when overlapped by more than half.
// Each box is randomly missed 3% of the time. Box noise is 0.2% of the frame
// on centre and 1% on size. None of this is measured from real Vision.

import CoreGraphics
import Foundation
import Testing
@preconcurrency import Vision
@testable import Alfie

final class ProbeRng {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03 }
    func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    func gauss() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

enum TrackingScenarioOptions {
    static var wide: Bool { ProcessInfo.processInfo.environment["TRACKING_SCENARIO_WIDE"] == "1" }
    static var trace: Bool { ProcessInfo.processInfo.environment["TRACKING_SCENARIO_TRACE"] == "1" }
}

func r2(_ v: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f", v) }
func scenarioBox(cx: Double, bottom: Double = 0.25, w: Double = 0.07, h: Double = 0.30) -> CGRect {
    CGRect(x: cx - w / 2, y: bottom, width: w, height: h)
}

@MainActor
private func makePerson(_ id: UUID, _ box: CGRect, _ t: Double) -> PersonDetector.DetectedPerson {
    .init(id: id, boundingBox: box, confidence: 0.9, timestamp: t, poseKeypoints: nil,
          faceBoundingBox: nil, faceLandmarkRatios: nil)
}

/// A copy of the glue in CameraManager.processFrame (5cac138, lines 2188-2400)
/// for .autoTracking with the rule-based composer: detection cadence, the
/// latest-result mailbox, lock tick, band-exit boost, compose, spring step.
@MainActor
final class FramingLoop {
    let composer = ShotComposer()
    let engine: CropEngine
    let id = UUID()
    var visionLatency = 0.018
    private var inFlight = false
    private var counter: UInt64 = 0
    private var pending: (done: Double, capturedAt: Double, obsID: UInt64, persons: [PersonDetector.DetectedPerson])?
    private var latest: (capturedAt: Double, obsID: UInt64, persons: [PersonDetector.DetectedPerson])?
    private var consumedID: UInt64?
    private var seq: UInt64 = 0
    private var fastUntil = 0.0
    private var lastBand: ShotComposer.SteadyBand?
    private var lastTrackingCrop: CropEngine.CropRect?
    var detections = 0
    var bandExits = 0
    var targetUpdates = 0
    var lastObservationAge = 0.0
    var lastFresh = false

    init(preset: ShotComposer.Config.ShotPreset, feel: ShotComposer.Config.TuningPreset) throws {
        engine = try #require(CropEngine())
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = preset
        composer.config.apply(feel)
        let floor = CropEngine.QualityFloor.forSource(height: 2160)
        engine.qualityFloor = floor
        composer.qualityFloorHeightFraction = floor.minCropHeightFraction
        composer.lockTarget(id)
        composer.forceTrackingForTesting()
    }

    func step(t: Double, subject: (Double) -> CGRect?) -> CropEngine.CropRect {
        if seq == 0, latest == nil {
            seq = 1
            latest = (t, seq, subject(t).map { [makePerson(id, $0, t)] } ?? [])
        }
        if let p = pending, p.done <= t {
            latest = (p.capturedAt, p.obsID, p.persons)
            pending = nil
            inFlight = false
        }
        var due = false
        if !inFlight {
            counter &+= 1
            due = CameraManager.detectionSlotIsDue(eligibleFrameCount: counter, interval: 2)
        }
        if due {
            inFlight = true
            seq &+= 1
            let persons = subject(t).map { [makePerson(id, $0, t)] } ?? []
            pending = (t + visionLatency, t, seq, persons)
            detections += 1
        }
        var persons: [PersonDetector.DetectedPerson] = []
        var fresh = false
        var obsT: Double?
        var obsID: UInt64?
        if let l = latest, t - l.capturedAt <= DetectionFrameStore.maximumAge {
            persons = l.persons
            fresh = consumedID != l.obsID
            consumedID = l.obsID
            obsT = l.capturedAt
            obsID = l.obsID
            lastObservationAge = t - l.capturedAt
        } else { latest = nil }
        lastFresh = fresh
        _ = composer.tick(detections: persons, timestamp: t, pixelBuffer: nil, isFresh: fresh,
                          observationID: obsID, observationTimestamp: obsT)
        if case .tracking = composer.lockState, composer.steadyBand == nil, lastBand != nil {
            fastUntil = t + 0.5
            bandExits += 1
        }
        lastBand = composer.steadyBand
        let primary = composer.primaryPerson(from: persons)
        let smoothing: Float = t < fastUntil ? 0.25 : composer.config.smoothingFactor
        engine.applyFrameSmoothing(smoothing, operatorSetting: composer.config.smoothingFactor)
        if let primary {
            if let crop = composer.compose(person: primary, isFresh: fresh, observationTimestamp: obsT) {
                if crop != lastTrackingCrop { targetUpdates += 1 }
                lastTrackingCrop = crop
                engine.setTargetCrop(crop)
            }
        } else if let lastTrackingCrop { engine.setTargetCrop(lastTrackingCrop) }
        return engine.tickInterpolation(now: t).crop
    }
}

// Copy of CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift:2188-2400
// at 5cac138, for rule-based auto tracking. Main's #138 adds read-only world
// observation bookkeeping; it does not change this tracking glue.
// Re-copy from the control turn when #141 merges.
@MainActor
final class ScenarioLoop {
    let detector = PersonDetector()
    let composer = ShotComposer()
    let engine: CropEngine
    let id: UUID
    private var roiBox: CGRect?
    private var inFlight = false
    private var counter: UInt64 = 0
    private var pending: (done: Double, capturedAt: Double, obsID: UInt64, boxes: [CGRect])?
    private var latest: (capturedAt: Double, obsID: UInt64, persons: [PersonDetector.DetectedPerson])?
    private var consumedID: UInt64?
    private var seq: UInt64 = 0
    private var fastUntil = 0.0
    private var lastBand: ShotComposer.SteadyBand?
    private var lastTrackingCrop: CropEngine.CropRect?
    struct ScanTrace {
        let capturedAt: Double
        let lockState: String
        let lockedBox: CGRect?
        let visionBoxes: [CGRect]
        let passABound: Bool
        let lockLastSeen: Double?
    }
    var traceEnabled = false
    private(set) var trace: [ScanTrace] = []
    private var reportedBoxes: [CGRect] = []
    var visionLatency = 0.018
    var lockedBox: CGRect?
    var isHold = false
    var isTracking = true
    var freshThisFrame = false

    init(preset: ShotComposer.Config.ShotPreset, feel: ShotComposer.Config.TuningPreset, first: CGRect, t: Double) throws {
        engine = try #require(CropEngine())
        detector.updateTracking(rectObservations: [VNHumanObservation(boundingBox: first)], poseObservations: [],
                                faceObservations: [], timestamp: t)
        id = try #require(detector.detectedPersons.first?.id)
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = preset
        composer.config.apply(feel)
        let floor = CropEngine.QualityFloor.forSource(height: 2160)
        engine.qualityFloor = floor
        composer.qualityFloorHeightFraction = floor.minCropHeightFraction
        composer.lockTarget(id)
        composer.forceTrackingForTesting()
        roiBox = first
        // Acquisition already observed the subject. Make that observation available immediately.
        // This also keeps the first scheduled scan in the tracking ROI, rather than
        // the accidental startup hold's full-frame scan. Do not subtract startup hold time.
        reportedBoxes = [first]
        latest = (t, 1, detector.detectedPersons)
        seq = 1
    }

    /// world(t, roi) returns the boxes Vision reports for the frame captured at t.
    func step(t: Double, world: (Double, CGRect?) -> [CGRect]) -> CropEngine.CropRect {
        if let p = pending, p.done <= t {
            // PersonDetector.processFrame: updateTracking runs on the main actor when Vision returns,
            // stamped with the detection start time.
            detector.updateTracking(rectObservations: p.boxes.map { VNHumanObservation(boundingBox: $0) },
                                    poseObservations: [], faceObservations: [], timestamp: p.capturedAt)
            reportedBoxes = p.boxes
            latest = (p.capturedAt, p.obsID, detector.detectedPersons)
            pending = nil
            inFlight = false
        }
        var due = false
        if !inFlight {
            counter &+= 1
            due = CameraManager.detectionSlotIsDue(eligibleFrameCount: counter, interval: 2)
        }
        detector.lockedTargetID = composer.manualLockedTargetID
        if due {
            var roi: CGRect?
            if case .tracking = composer.lockState {
                let motion = detector.trackMotion(for: id)
                roi = CameraManager.lockedSearchRegion(box: roiBox ?? composer.currentTrackedBounds,
                                                       velocity: motion?.velocity ?? .zero,
                                                       elapsed: motion.map { t - $0.lastSeen } ?? 0)
            }
            inFlight = true
            seq &+= 1
            pending = (t + visionLatency, t, seq, world(t, roi))
        }
        var persons: [PersonDetector.DetectedPerson] = []
        var fresh = false
        var obsT: Double?
        var obsID: UInt64?
        if let l = latest, t - l.capturedAt <= DetectionFrameStore.maximumAge {
            persons = l.persons
            fresh = consumedID != l.obsID
            consumedID = l.obsID
            obsT = l.capturedAt
            obsID = l.obsID
        } else { latest = nil }
        freshThisFrame = fresh
        if fresh {
            if let sid = composer.manualLockedTargetID, let b = persons.first(where: { $0.id == sid })?.boundingBox {
                roiBox = b
            } else if composer.manualLockedTargetID == nil { roiBox = nil }
        }
        lockedBox = persons.first(where: { $0.id == id })?.boundingBox
        _ = composer.tick(detections: persons, timestamp: t, pixelBuffer: nil, isFresh: fresh,
                          observationID: obsID, observationTimestamp: obsT)
        if case .tracking = composer.lockState, composer.steadyBand == nil, lastBand != nil { fastUntil = t + 0.5 }
        lastBand = composer.steadyBand
        isHold = { if case .hold = composer.lockState { return true }; return false }()
        isTracking = { if case .tracking = composer.lockState { return true }; return false }()
        let primary = composer.primaryPerson(from: persons)
        let smoothing: Float = t < fastUntil ? 0.25 : composer.config.smoothingFactor
        engine.applyFrameSmoothing(smoothing, operatorSetting: composer.config.smoothingFactor)
        if let primary {
            if let crop = composer.compose(person: primary, isFresh: fresh, observationTimestamp: obsT) {
                lastTrackingCrop = crop
                engine.setTargetCrop(crop)
            }
        } else if let lastTrackingCrop { engine.setTargetCrop(lastTrackingCrop) }
        if fresh, traceEnabled, let obsT {
            let motion = detector.trackMotion(for: id)
            let state: String
            switch composer.lockState {
            case .tracking: state = "tracking"
            case .hold: state = "hold"
            case .wideWaiting: state = "wide"
            default: state = "other"
            }
            trace.append(ScanTrace(capturedAt: obsT, lockState: state, lockedBox: lockedBox,
                visionBoxes: reportedBoxes, passABound: motion?.lastSeen == obsT,
                lockLastSeen: motion?.lastSeen))
        }
        return engine.tickInterpolation(now: t).crop
    }
}

@MainActor
struct TrackingScenarios {
    let t0 = 1000.0
    let fps = 50.0
    struct Actor {
        var x: (Double) -> Double
        var w = 0.07
        var h = 0.30
        var layer = 0
        var present: (Double) -> Bool = { _ in true }
        /// width factor, height factor, left-edge shift in widths
        var shape: (Double) -> (Double, Double, Double) = { _ in (1, 1, 0) }
        var visionMiss: (Double) -> Bool = { _ in false }
    }
    enum Overlap { case layers, both, merged }
    struct Scenario {
        var name: String
        var duration: Double
        var overlap: Overlap = .layers
        var make: (ProbeRng) -> [Actor]   // actor 0 is the locked subject
    }
    private func box(_ a: Actor, _ e: Double) -> CGRect {
        let s = a.shape(e)
        return CGRect(x: a.x(e) - a.w / 2 + s.2 * a.w, y: 0.25, width: a.w * s.0, height: a.h * s.1)
    }
    private func overlapShare(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        return i.isNull ? 0 : Double(i.width) / Double(min(a.width, b.width))
    }

    func run(_ sc: Scenario, seed: UInt64) throws -> (final: String, wrong: Double, hold: Double, holdVisible: Double) {
        let rng = ProbeRng(seed)
        let actors = sc.make(rng)
        func hidden(_ i: Int, _ e: Double) -> Bool {
            guard sc.overlap == .layers else { return false }
            let bi = box(actors[i], e)
            for j in actors.indices where j != i && actors[j].present(e) && actors[j].layer > actors[i].layer {
                if overlapShare(bi, box(actors[j], e)) > 0.5 { return true }
            }
            return false
        }
        func subjectVisible(_ e: Double) -> Bool {
            actors[0].present(e) && !hidden(0, e) && !actors[0].visionMiss(e)
        }
        let loop = try ScenarioLoop(preset: .waistUp, feel: .steadyFollow, first: box(actors[0], 0), t: t0)
        loop.traceEnabled = TrackingScenarioOptions.trace && !TrackingScenarioOptions.wide
        var traceIndex = 0
        var on = 0
        var wrong = 0.0, hold = 0.0, holdVisible = 0.0
        for frame in 1...Int((TrackingScenarioOptions.wide ? sc.duration : min(sc.duration, 15)) * fps) {
            let el = Double(frame) / fps
            _ = loop.step(t: t0 + el) { t, roi in
                let e = t - self.t0
                func jit(_ b: CGRect) -> CGRect {
                    let k = 1 + rng.gauss() * 0.01
                    return CGRect(x: Double(b.midX) + rng.gauss() * 0.002 - Double(b.width) * k / 2,
                                  y: Double(b.minY) + rng.gauss() * 0.002, width: Double(b.width) * k, height: Double(b.height) * k)
                }
                func inROI(_ b: CGRect) -> Bool {
                    guard let roi else { return true }
                    let i = b.intersection(roi)
                    return !i.isNull && Double(i.width * i.height) / Double(b.width * b.height) >= 0.8
                }
                var out: [CGRect] = []
                var mergedWithSubject = Set<Int>()
                if sc.overlap == .merged, actors[0].present(e) {
                    var u = self.box(actors[0], e)
                    for j in actors.indices.dropFirst() where actors[j].present(e) && self.overlapShare(u, self.box(actors[j], e)) > 0.5 {
                        u = u.union(self.box(actors[j], e)); mergedWithSubject.insert(j)
                    }
                    if !mergedWithSubject.isEmpty {
                        mergedWithSubject.insert(0)
                        if inROI(u), rng.uniform() > 0.03 { out.append(jit(u)) }
                    }
                }
                for i in actors.indices where !mergedWithSubject.contains(i) {
                    let a = actors[i]
                    guard a.present(e), !hidden(i, e), !a.visionMiss(e) else { continue }
                    let b = self.box(a, e)
                    guard inROI(b), rng.uniform() > 0.03 else { continue }
                    out.append(jit(b))
                }
                return out
            }
            if frame == 1, !TrackingScenarioOptions.wide { #expect(!loop.isHold) }
            if loop.trace.count > traceIndex {
                let scan = loop.trace[traceIndex]
                let actor = scan.lockedBox.flatMap { lb in
                    actors.indices.filter { actors[$0].present(el) && PersonDetector.iou(lb, box(actors[$0], el)) > 0.3 }.max {
                        PersonDetector.iou(lb, box(actors[$0], el)) < PersonDetector.iou(lb, box(actors[$1], el))
                    }
                }
                let boxes = scan.visionBoxes.map { "\(r2(Double($0.midX), 4)),\(r2(Double($0.width), 4))" }.joined(separator: ";")
                print("TRACKING-TRACE|\(sc.name)|seed=\(seed)|t=\(r2(scan.capturedAt - t0, 3))|state=\(scan.lockState)|actor=\(actor.map(String.init) ?? "none")|vision=\(scan.visionBoxes.count)|passA=\(scan.passABound)|lastSeen=\(scan.lockLastSeen.map { r2($0 - t0, 3) } ?? "expired")|boxes=\(boxes)")
                traceIndex += 1
            }
            if loop.isTracking, let lb = loop.lockedBox {
                var best = on, bestIoU = 0.0
                for i in actors.indices where actors[i].present(el) {
                    let v = Double(PersonDetector.iou(lb, box(actors[i], el)))
                    if v > bestIoU { bestIoU = v; best = i }
                }
                if bestIoU > 0.3 { on = best }
                if on != 0 { wrong += 1 / fps }
            }
            if loop.isHold {
                hold += 1 / fps
                if subjectVisible(el) { holdVisible += 1 / fps }
            }
        }
        let final = loop.isHold ? "hold" : (loop.isTracking ? (on == 0 ? "subject" : "WRONG") : "wide")
        return (final, wrong, hold, holdVisible)
    }

    func scenarios() -> [Scenario] {
        var list: [Scenario] = []
        func still(_ x: Double) -> (Double) -> Double { { _ in x } }
        for size in [1.0, 0.85] {
            for v in [0.05, 0.10, 0.25] {
                list.append(Scenario(name: "crossInFront_size\(r2(size))_v\(r2(v))", duration: 0.8 / v + 3) { rng in
                    let ph = rng.uniform() * 0.04
                    return [Actor(x: still(0.5)),
                            Actor(x: { 0.12 + v * ($0 + ph) }, w: 0.07 * size, h: 0.30 * size, layer: 1,
                                  present: { 0.12 + v * ($0 + ph) < 0.92 })]
                })
            }
        }
        for v in [0.10, 0.25] {
            list.append(Scenario(name: "crossBehind_v\(r2(v))", duration: 0.8 / v + 3) { rng in
                let ph = rng.uniform() * 0.04
                return [Actor(x: still(0.5)),
                        Actor(x: { 0.12 + v * ($0 + ph) }, layer: -1, present: { 0.12 + v * ($0 + ph) < 0.92 })]
            })
        }
        for (label, model) in [("crossBothSeen", Overlap.both), ("crossMergedBox", .merged)] {
            list.append(Scenario(name: "\(label)_v0.10", duration: 11, overlap: model) { rng in
                let ph = rng.uniform() * 0.04
                return [Actor(x: still(0.5)),
                        Actor(x: { 0.12 + 0.10 * ($0 + ph) }, layer: 1, present: { 0.12 + 0.10 * ($0 + ph) < 0.92 })]
            })
        }
        list.append(Scenario(name: "crossInFront_subjectWalking0.04", duration: 9) { rng in
            let ph = rng.uniform() * 0.04
            return [Actor(x: { 0.62 - 0.04 * $0 }),
                    Actor(x: { 0.12 + 0.10 * ($0 + ph) }, layer: 1, present: { 0.12 + 0.10 * ($0 + ph) < 0.92 })]
        })
        for spacing in [1.0, 1.4] {
            list.append(Scenario(name: "groupGestures_spacing\(r2(spacing, 1))bw", duration: 30) { rng in
                func gestures() -> (Double) -> (Double, Double, Double) {
                    var plan: [(Double, Double, Int)] = []
                    var t = 1.0 + rng.uniform() * 4
                    while t < 30 { plan.append((t, t + 0.6 + rng.uniform() * 0.8, Int(rng.next() % 3))); t += 2.5 + rng.uniform() * 5 }
                    return { e in
                        guard let gst = plan.first(where: { e >= $0.0 && e < $0.1 }) else { return (1, 1, 0) }
                        switch gst.2 { case 0: return (1, 1.2, 0); case 1: return (1.6, 1, 0); default: return (1.6, 1, -0.6) }
                    }
                }
                let d = spacing * 0.07
                return [Actor(x: still(0.5), shape: gestures()),
                        Actor(x: still(0.5 - d), w: 0.063, h: 0.27, shape: gestures()),
                        Actor(x: still(0.5 + d), w: 0.077, h: 0.33, shape: gestures())]
            })
        }
        list.append(Scenario(name: "groupStill_subjectMissed0.4s_every5s", duration: 30) { _ in
            let d = 1.4 * 0.07
            return [Actor(x: still(0.5), visionMiss: { $0.truncatingRemainder(dividingBy: 5) >= 2.0 && $0.truncatingRemainder(dividingBy: 5) < 2.4 }),
                    Actor(x: still(0.5 - d)), Actor(x: still(0.5 + d))]
        })
        for (v, gap, w) in [(0.10, 0.36, 0.07), (0.15, 0.20, 0.035)] {
            list.append(Scenario(name: "walkerGap_v\(r2(v))_gap\(r2(gap))_w\(r2(w, 3))", duration: 0.7 / v + 2) { _ in
                [Actor(x: { 0.15 + v * min($0, 0.7 / v) }, w: w, visionMiss: { $0 > 1.5 && $0 <= 1.5 + gap })]
            })
        }
        list.append(Scenario(name: "walkerPastRowOfFour_gap0.3", duration: 9) { _ in
            var a = [Actor(x: { 0.15 + 0.10 * min($0, 7) }, visionMiss: { $0 > 3.0 && $0 <= 3.3 })]
            for x in [0.34, 0.46, 0.58, 0.70] { a.append(Actor(x: still(x), layer: -1)) }
            return a
        })
        return list
    }

}
