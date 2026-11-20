// Synthetic boxes only: no pose and no faces.
// A person is reported when at least 80% of their box is inside the scanned region.
// A person behind another is dropped when overlapped by more than half.
// Each box is randomly missed 3% of the time. Box noise is 0.2% of the frame
// on centre and 1% on size. None of this is measured from real Vision.

import CryptoKit
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
/// Synthetic provenance is held only by the harness; the detector receives CGRects.
struct SyntheticObservation {
    let box: CGRect
    let actors: Set<Int>
}

@MainActor
final class ScenarioLoop {
    let commands = CommandDispatcher()
    private var programIsWide = false
    private(set) var lockedSources: Set<Int> = [0]
    let detector = PersonDetector()
    let composer = ShotComposer()
    let engine: CropEngine
    let id: UUID
    private var roiBox: CGRect?
    private var inFlight = false
    private var counter: UInt64 = 0
    private var pending: (done: Double, capturedAt: Double, obsID: UInt64, boxes: [SyntheticObservation], faces: Bool)?
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
        let persons: [PersonDetector.DetectedPerson]
        let witnesses: Set<UUID>
    }
    var traceEnabled = false
    private(set) var trace: [ScanTrace] = []
    private var reportedBoxes: [CGRect] = []
    var visionLatency = 0.018
    var lockedBox: CGRect?
    var isHold = false
    var isTracking = true
    var freshThisFrame = false
    /// The detector's lock-ambiguity window as passed to `tick` this frame.
    private(set) var ambiguityOpen = false

    // Synthetic identity channel. Each face is graded from box provenance:
    // the subject alone is a strong match, a box without the subject a
    // strong mismatch, a union no evidence. At availability 0 nothing here
    // runs and the loop is exactly as before.
    let faceAvailability: Double
    private var faceRng: ProbeRng
    private var lastDelivered: [SyntheticObservation] = []
    private var now = 0.0
    private var evidenceQueue: [(due: Double, request: IdentityEvidenceRequest, tier: IdentityTier)] = []
    static let identityLatency = 0.03
    private var recoveryQueue: [(due: Double, request: ShotComposer.ReacquisitionRequest)] = []
    /// Faces also reach hold/wide recovery scoring (today's face recovery).
    /// Off, faces only feed the verify window.
    let faceRecovery: Bool
    /// The lock's current track. Face recovery can bind a different ID.
    private(set) var currentLockID: UUID
    private(set) var identityRequests = 0
    /// The bound box's sources each time a shadow veto was recorded.
    private(set) var wouldVetoSources: [Set<Int>] = []

    // A-01 gallery model. With a face chance set, the loop mirrors the
    // production face scans (acquiring, the 0.4 s refresh while tracking,
    // full-frame in hold and wide) and fills the real gallery through the
    // synchronous capture seam. Off, nothing here runs.
    private let faceChance: ((Double) -> Double)?
    private var captureQueue: [(due: Double, request: ShotComposer.SignatureCaptureRequest, embedding: IdentityEmbedding?)] = []
    private(set) var captureRequests = 0

    init(preset: ShotComposer.Config.ShotPreset, feel: ShotComposer.Config.TuningPreset, first: CGRect, t: Double,
         faceAvailability: Double = 0, faceSeed: UInt64 = 0, faceRecovery: Bool = false,
         identityLive: Bool = false, acquire: Bool = false, faceChance: ((Double) -> Double)? = nil) throws {
        self.faceRecovery = (faceRecovery && faceAvailability > 0) || faceChance != nil
        self.faceAvailability = faceAvailability
        self.faceChance = faceChance
        faceRng = ProbeRng(faceSeed ^ 0xFACE)
        engine = try #require(CropEngine())
        detector.updateTracking(rectObservations: [VNHumanObservation(boundingBox: first)], poseObservations: [],
                                faceObservations: [], timestamp: t)
        id = try #require(detector.detectedPersons.first?.id)
        currentLockID = id
        composer.config.cinematicFormat = .stage
        composer.config.shotPreset = preset
        composer.config.apply(feel)
        let floor = CropEngine.QualityFloor.forSource(height: 2160)
        engine.qualityFloor = floor
        composer.qualityFloorHeightFraction = floor.minCropHeightFraction
        composer.lockTarget(id)
        if acquire {
            // A click: acquisition starts now, on the harness clock.
            composer.setAcquisitionClockForTesting(t)
        } else {
            composer.forceTrackingForTesting(readyGallery: faceAvailability > 0)
        }
        commands.setTrackingOwnership(true)
        if identityLive { composer.identityVetoEnabledForTesting = true }
        if self.faceRecovery {
            composer.reacquisitionSchedulerForTesting = { [unowned self] request in
                self.recoveryQueue.append((self.now + Self.identityLatency, request))
            }
        }
        if faceAvailability > 0 || faceChance != nil {
            composer.identityEvidenceSchedulerForTesting = { [unowned self] request in self.queueEvidence(request) }
            composer.identityWouldVetoForTesting = { [unowned self] in self.wouldVetoSources.append(self.lockedSources) }
        }
        if faceChance != nil {
            composer.signatureCaptureSchedulerForTesting = { [unowned self] request in self.queueCapture(request) }
        }
        roiBox = first
        // Acquisition already observed the subject. Make that observation available immediately.
        // This also keeps the first scheduled scan in the tracking ROI, rather than
        // the accidental startup hold's full-frame scan. Do not subtract startup hold time.
        reportedBoxes = [first]
        latest = (t, 1, detector.detectedPersons)
        seq = 1
    }

    /// A head-sized face box near the top of a body box (bottom-left origin).
    static func faceBox(in body: CGRect) -> CGRect {
        CGRect(x: body.midX - body.width * 0.2, y: body.maxY - body.height * 0.2,
               width: body.width * 0.4, height: body.height * 0.15)
    }

    /// The source actors of a person's box in the latest observation.
    private func sources(of personID: UUID) -> Set<Int>? {
        guard let person = latest?.persons.first(where: { $0.id == personID }) else { return nil }
        return lastDelivered.first(where: { $0.box == person.boundingBox })?.actors
    }

    private func queueEvidence(_ request: IdentityEvidenceRequest) {
        identityRequests += 1
        let tier: IdentityTier = {
            guard let actors = sources(of: request.targetID) else { return .none }
            if actors == [0] { return .strongMatch }
            return actors.contains(0) ? .none : .strongMismatch
        }()
        evidenceQueue.append((now + Self.identityLatency, request, tier))
    }

    /// A synthetic face print from box provenance: the subject alone has the
    /// subject's print, anyone else a print far from it (distance 1.41), a
    /// union of people no usable print.
    static func print(of actors: Set<Int>?) -> IdentityEmbedding? {
        guard let actors, actors.count == 1, let actor = actors.first else { return nil }
        var vector = [Float](repeating: 0, count: 8)
        vector[min(actor, 7)] = 1
        return .vector(vector)
    }

    private func queueCapture(_ request: ShotComposer.SignatureCaptureRequest) {
        captureRequests += 1
        captureQueue.append((now + Self.identityLatency, request, Self.print(of: sources(of: request.targetID))))
    }

    /// Recovery scores graded the same way: the subject alone scores as a
    /// strong match, anyone else as clearly different, a union as unknown.
    private func recoveryScores(for request: ShotComposer.ReacquisitionRequest) -> [ShotComposer.ReacquisitionScore] {
        request.candidates.map { candidate in
            let actors = sources(of: candidate.id)
            let distance: Float? = actors.map { $0 == [0] ? 0.10 : ($0.contains(0) ? nil : 0.80) } ?? nil
            // The harness has no pixels; faces are taken as usable (above the 64 px gate).
            return ShotComposer.ReacquisitionScore(id: candidate.id, printDistance: distance,
                landmarkDistance: actors == [0] ? 0.01 : 0.05, isExcluded: candidate.isExcluded,
                faceHeightPixels: 80)
        }
    }

    /// world(t, roi) returns the boxes Vision reports for the frame captured at t.
    func step(t: Double, world: (Double, CGRect?) -> [CGRect]) -> CropEngine.CropRect {
        stepTagged(t: t) { capture, roi in
            world(capture, roi).map { SyntheticObservation(box: $0, actors: [0]) }
        }
    }

    func stepTagged(t: Double, world: (Double, CGRect?) -> [SyntheticObservation]) -> CropEngine.CropRect {
        now = t
        while let next = evidenceQueue.first, next.due <= t {
            evidenceQueue.removeFirst()
            composer.finishIdentityEvidence(next.request, tier: next.tier)
        }
        while let next = captureQueue.first, next.due <= t {
            captureQueue.removeFirst()
            composer.finishSignatureCaptureForTesting(next.request, embedding: next.embedding)
        }
        while let next = recoveryQueue.first, next.due <= t {
            recoveryQueue.removeFirst()
            composer.finishReacquisitionScoring(generation: next.request.generation,
                visibilityRevision: next.request.visibilityRevision,
                observationID: next.request.observationID, scores: recoveryScores(for: next.request))
        }
        if let lock = composer.manualLockedTargetID { currentLockID = lock }
        if let p = pending, p.done <= t {
            // PersonDetector.processFrame: updateTracking runs on the main actor when Vision returns,
            // stamped with the detection start time.
            let chance = faceChance?(p.capturedAt) ?? faceAvailability
            let faces: [VNFaceObservation] = p.faces ? p.boxes.compactMap { observation in
                faceRng.uniform() < chance ? VNFaceObservation(boundingBox: Self.faceBox(in: observation.box)) : nil
            } : []
            detector.updateTracking(rectObservations: p.boxes.map { VNHumanObservation(boundingBox: $0.box) },
                                    poseObservations: [], faceObservations: faces, timestamp: p.capturedAt)
            lastDelivered = p.boxes
            reportedBoxes = p.boxes.map(\.box)
            if detector.trackMotion(for: currentLockID)?.lastSeen == p.capturedAt,
               let bound = detector.detectedPersons.first(where: { $0.id == currentLockID }) {
                if let input = p.boxes.first(where: { $0.box == bound.boundingBox }) {
                    lockedSources = input.actors
                } else { Issue.record("Fresh bound box has no input provenance") }
            }
            latest = (p.capturedAt, p.obsID, detector.detectedPersons)
            pending = nil
            inFlight = false
        }
        var due = false
        if !inFlight {
            counter &+= 1
            due = CameraManager.detectionSlotIsDue(eligibleFrameCount: counter, interval: 2)
        }
        detector.lockedTargetID = composer.lockBindingTargetID
        if due {
            var roi: CGRect?
            // CameraManager.currentDetectionPlan: tracking and acquiring scan the locked region.
            if composer.isAcquiring || composer.lockState.isTracking {
                let motion = detector.trackMotion(for: currentLockID)
                roi = CameraManager.lockedSearchRegion(box: roiBox ?? composer.currentTrackedBounds,
                                                       velocity: motion?.velocity ?? .zero,
                                                       elapsed: motion.map { t - $0.lastSeen } ?? 0)
            }
            inFlight = true
            seq &+= 1
            // Recovery scans are full-frame with faces; tracking adds faces on verify scans.
            let recovering: Bool = {
                switch composer.lockState {
                case .hold, .wideWaiting: return true
                default: return false
                }
            }()
            let faces: Bool
            if faceChance != nil {
                // CameraManager.currentDetectionPlan: acquiring, hold and wide
                // always include faces; tracking on verify and refresh scans.
                faces = composer.isAcquiring || recovering
                    || (composer.lockState.isTracking && (composer.shouldRunIdentityVerifyScan(now: t)
                        || composer.shouldRunGalleryRefreshScan(now: t)))
            } else {
                faces = faceAvailability > 0
                    && ((faceRecovery && recovering) || composer.shouldRunIdentityVerifyScan(now: t))
            }
            pending = (t + visionLatency, t, seq, world(t, roi), faces)
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
            // CameraManager.refreshSubjectROISeed
            if let sid = composer.lockBindingTargetID, let b = persons.first(where: { $0.id == sid })?.boundingBox {
                roiBox = b
            } else if composer.manualLockedTargetID == nil { roiBox = nil }
        }
        let wasVetoHeld = composer.isIdentityVetoHeld
        lockedBox = persons.first(where: { $0.id == currentLockID })?.boundingBox
        ambiguityOpen = detector.lockAmbiguityOpen
        let outcome = composer.tick(detections: persons, timestamp: t, pixelBuffer: nil, isFresh: fresh,
                          observationID: obsID, observationTimestamp: obsT,
                          excludedFromReacquisition: detector.witnessedOtherIDs(),
                          lockAmbiguityOpen: ambiguityOpen,
                          lockAmbiguityReasons: detector.lockAmbiguityOpenReasons)
        // CameraManager.reseedSubjectROIAfterVetoRecovery
        if wasVetoHeld, case .resumeTracking = outcome, let bound = composer.manualLockedTargetID,
           let b = persons.first(where: { $0.id == bound })?.boundingBox { roiBox = b }
        if commands.admitRecovery(outcome) {
            engine.endZoom()
            switch outcome {
            case .pullBackToWide:
                engine.clearZoomAdjustment()
                composer.setVisibleZoomHeight(nil)
                programIsWide = true
                fastUntil = t + 0.5
            case .resumeTracking, .acquired:
                programIsWide = false
                fastUntil = t + 0.5
            case .noChange: break
            }
        }
        if case .tracking = composer.lockState, composer.steadyBand == nil, lastBand != nil { fastUntil = t + 0.5 }
        lastBand = composer.steadyBand
        isHold = { if case .hold = composer.lockState { return true }; return false }()
        isTracking = { if case .tracking = composer.lockState { return true }; return false }()
        let primary = composer.primaryPerson(from: persons)
        let smoothing: Float = t < fastUntil ? 0.25 : composer.config.smoothingFactor
        engine.applyFrameSmoothing(smoothing, operatorSetting: composer.config.smoothingFactor)
        if programIsWide {
            engine.setTargetCrop(CameraManager.widestSafeCrop(sourceAspect: 16.0 / 9.0,
                outputAspect: composer.config.outputAspectRatio, normalizedAspect: composer.normalizedAspect))
        } else if let primary {
            if let crop = composer.compose(person: primary, isFresh: fresh, observationTimestamp: obsT) {
                lastTrackingCrop = crop
                engine.setTargetCrop(crop)
            }
        } else if let lastTrackingCrop { engine.setTargetCrop(lastTrackingCrop) }
        if fresh, traceEnabled, let obsT {
            let motion = detector.trackMotion(for: currentLockID)
            let state: String
            switch composer.lockState {
            case .tracking: state = "tracking"
            case .hold: state = "hold"
            case .wideWaiting: state = "wide"
            default: state = "other"
            }
            trace.append(ScanTrace(capturedAt: obsT, lockState: state, lockedBox: lockedBox,
                visionBoxes: reportedBoxes, passABound: motion?.lastSeen == obsT,
                lockLastSeen: motion?.lastSeen, persons: persons, witnesses: detector.witnessedOtherIDs()))
        }
        return engine.tickInterpolation(now: t).crop
    }
}

extension ShotComposer.LockState {
    var isTracking: Bool { if case .tracking = self { return true }; return false }
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
        /// A-01: start with a click (acquiring) instead of a forced lock.
        var acquire = false
        /// A-01: face availability by elapsed time. Set, the loop runs the
        /// gallery model (real gallery, production face scans); nil, no faces.
        var faces: ((Double) -> Double)? = nil
    }
    private func box(_ a: Actor, _ e: Double) -> CGRect {
        let s = a.shape(e)
        return CGRect(x: a.x(e) - a.w / 2 + s.2 * a.w, y: 0.25, width: a.w * s.0, height: a.h * s.1)
    }
    private func overlapShare(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        return i.isNull ? 0 : Double(i.width) / Double(min(a.width, b.width))
    }

    struct RunResult {
        var final: String
        var wrong: Double
        var hold: Double
        var holdVisible: Double
        var inputDigest: String
        var latchedWrong: Double
        var longestLatchedWrong: Double
        var unionTime: Double
        var legacyFinal: String
        var ambiguityShare: Double
        var identityRequests: Int
        var wouldVetoOnSubject: Int
        var wouldVetoOnOther: Int
        /// Seconds from the start until the lock first reached tracking; nil if never.
        var timeToLock: Double?
        /// Real gallery entries at the end (A-01 gallery model; 0 without it).
        var gallerySize: Int
        /// The gallery held at least `readyThreshold` real entries at the end.
        var identityConfirmed: Bool
    }

    func run(_ sc: Scenario, seed: UInt64, faceAvailability: Double = 0, faceRecovery: Bool = false,
             identityLive: Bool = false) throws -> RunResult {
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
        let base = t0
        let loop = try ScenarioLoop(preset: .waistUp, feel: .steadyFollow, first: box(actors[0], 0), t: t0,
                                    faceAvailability: faceAvailability, faceSeed: seed,
                                    faceRecovery: faceRecovery, identityLive: identityLive,
                                    acquire: sc.acquire, faceChance: sc.faces.map { f in { f($0 - base) } })
        var timeToLock: Double? = sc.acquire ? nil : 0
        loop.traceEnabled = TrackingScenarioOptions.trace && !TrackingScenarioOptions.wide
        var inputBytes = Data()
        func recordInputs(_ boxes: [CGRect], time: Double) {
            func append(_ bits: UInt64) {
                var bits = bits.littleEndian
                withUnsafeBytes(of: &bits) { inputBytes.append(contentsOf: $0) }
            }
            append(time.bitPattern); append(UInt64(boxes.count))
            for b in boxes {
                for v in [b.minX, b.minY, b.width, b.height] { append(Double(v).bitPattern) }
            }
        }
        var traceIndex = 0
        var on = 0
        var wrong = 0.0, hold = 0.0, holdVisible = 0.0
        var trackingFrames = 0, ambiguousFrames = 0
        var wrongFrames = 0, wrongStretch = 0, longestWrongStretch = 0, unionFrames = 0
        for frame in 1...Int((TrackingScenarioOptions.wide ? sc.duration : min(sc.duration, 15)) * fps) {
            let el = Double(frame) / fps
            _ = loop.stepTagged(t: t0 + el) { t, roi in
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
                var out: [SyntheticObservation] = []
                var mergedWithSubject = Set<Int>()
                if sc.overlap == .merged, actors[0].present(e) {
                    var u = self.box(actors[0], e)
                    for j in actors.indices.dropFirst() where actors[j].present(e) && self.overlapShare(u, self.box(actors[j], e)) > 0.5 {
                        u = u.union(self.box(actors[j], e)); mergedWithSubject.insert(j)
                    }
                    if !mergedWithSubject.isEmpty {
                        mergedWithSubject.insert(0)
                        if inROI(u), rng.uniform() > 0.03 { out.append(SyntheticObservation(box: jit(u), actors: mergedWithSubject)) }
                    }
                }
                for i in actors.indices where !mergedWithSubject.contains(i) {
                    let a = actors[i]
                    guard a.present(e), !hidden(i, e), !a.visionMiss(e) else { continue }
                    let b = self.box(a, e)
                    guard inROI(b), rng.uniform() > 0.03 else { continue }
                    out.append(SyntheticObservation(box: jit(b), actors: [i]))
                }
                recordInputs(out.map(\.box), time: t)
                return out
            }
            if frame == 1, !TrackingScenarioOptions.wide { #expect(!loop.isHold) }
            if timeToLock == nil, loop.isTracking { timeToLock = el }
            if loop.trace.count > traceIndex {
                let scan = loop.trace[traceIndex]
                let actor = scan.lockedBox.flatMap { lb in
                    actors.indices.filter { actors[$0].present(el) && PersonDetector.iou(lb, box(actors[$0], el)) > 0.3 }.max {
                        PersonDetector.iou(lb, box(actors[$0], el)) < PersonDetector.iou(lb, box(actors[$1], el))
                    }
                }
                let boxes = scan.visionBoxes.map { "\(r2(Double($0.midX), 4)),\(r2(Double($0.width), 4))" }.joined(separator: ";")
                let tracks = scan.persons.map { person in
                    let covered = actors.indices.filter { actors[$0].present(scan.capturedAt - t0) }
                        .max { PersonDetector.iou(person.boundingBox, box(actors[$0], scan.capturedAt - t0))
                             < PersonDetector.iou(person.boundingBox, box(actors[$1], scan.capturedAt - t0)) }
                    let actor = covered.flatMap { PersonDetector.iou(person.boundingBox, box(actors[$0], scan.capturedAt - t0)) > 0.3 ? $0 : nil }
                    return "\(person.id.uuidString.prefix(8)):actor=\(actor.map(String.init) ?? "none"),witness=\(scan.witnesses.contains(person.id)),lock=\(person.id == loop.id),x=\(r2(Double(person.boundingBox.midX), 4))"
                }.joined(separator: ";")
                print("TRACKING-TRACE|\(sc.name)|seed=\(seed)|t=\(r2(scan.capturedAt - t0, 3))|state=\(scan.lockState)|actor=\(actor.map(String.init) ?? "none")|vision=\(scan.visionBoxes.count)|passA=\(scan.passABound)|lastSeen=\(scan.lockLastSeen.map { r2($0 - t0, 3) } ?? "expired")|boxes=\(boxes)|tracks=\(tracks)")
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
            if loop.isTracking {
                trackingFrames += 1
                if loop.ambiguityOpen { ambiguousFrames += 1 }
            }
            if loop.isTracking, loop.lockedBox != nil {
                if !loop.lockedSources.contains(0) {
                    wrongFrames += 1; wrongStretch += 1
                    longestWrongStretch = max(longestWrongStretch, wrongStretch)
                } else { wrongStretch = 0 }
                if loop.lockedSources.count > 1 { unionFrames += 1 }
            } else { wrongStretch = 0 }
            if loop.isHold {
                hold += 1 / fps
                if subjectVisible(el) { holdVisible += 1 / fps }
            }
        }
        let legacyFinal = loop.isHold ? "hold" : (loop.isTracking ? (on == 0 ? "subject" : "WRONG") : "wide")
        // Inactive and acquiring occur only in runs that start with a click.
        let final = loop.isHold ? "hold" : (loop.isTracking ? (loop.lockedSources.contains(0) ? "subject" : "WRONG")
            : (loop.composer.isAcquiring ? "acquiring" : (loop.composer.isManualLockActive ? "wide" : "inactive")))
        let digest = SHA256.hash(data: inputBytes).map { String(format: "%02x", $0) }.joined()
        if seed == 40000 { print("TRACKING-INPUT-BASELINE|\(sc.name)|seed=\(seed)|digest=\(digest)|legacyWrong=\(wrong)|final=\(final)") }
        let realGallery = sc.faces == nil ? 0 : (loop.composer.galleryForTesting?.size ?? 0)
        return RunResult(final: final, wrong: wrong, hold: hold, holdVisible: holdVisible, inputDigest: digest,
                latchedWrong: Double(wrongFrames) / fps,
                longestLatchedWrong: Double(longestWrongStretch) / fps, unionTime: Double(unionFrames) / fps,
                legacyFinal: legacyFinal,
                ambiguityShare: trackingFrames > 0 ? Double(ambiguousFrames) / Double(trackingFrames) : 0,
                identityRequests: loop.identityRequests,
                wouldVetoOnSubject: loop.wouldVetoSources.filter { $0 == [0] }.count,
                wouldVetoOnOther: loop.wouldVetoSources.filter { !$0.contains(0) }.count,
                timeToLock: timeToLock, gallerySize: realGallery,
                identityConfirmed: realGallery >= ShotComposer.FaceSignatureGallery.readyThreshold)
    }

    @Test func pullbackActuallyWidensThePicture() throws {
        let loop = try ScenarioLoop(preset: .waistUp, feel: .steadyFollow,
            first: scenarioBox(cx: 0.5), t: t0)
        var crop = CropEngine.CropRect.fullFrame
        for frame in 1...700 { crop = loop.step(t: t0 + Double(frame) / fps) { _, _ in [] } }
        #expect(!loop.isTracking && !loop.isHold)
        let wide = CameraManager.widestSafeCrop(sourceAspect: 16.0 / 9.0,
            outputAspect: loop.composer.config.outputAspectRatio, normalizedAspect: loop.composer.normalizedAspect)
        #expect(loop.engine.targetCrop == wide)
        #expect(abs(crop.size.width - wide.size.width) < 0.001)
        #expect(abs(crop.size.height - wide.size.height) < 0.001)
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
        list.append(Scenario(name: "groupStill_reach_subjectMissed", duration: 30) { _ in
            func missed(_ t: Double) -> Bool {
                let phase = t.truncatingRemainder(dividingBy: 5)
                return phase >= 2 && phase < 2.4
            }
            let distance = 1.2 * 0.07
            return [Actor(x: still(0.5), visionMiss: missed),
                Actor(x: still(0.5 - distance), shape: { missed($0) ? (1.6, 1, 0) : (1, 1, 0) }),
                Actor(x: still(0.5 + distance), shape: { missed($0) ? (1.6, 1, -0.6) : (1, 1, 0) })]
        })
        for (label, widths) in [("Small", 0.7), ("Large", 1.2)] {
            list.append(Scenario(name: "sidestep\(label)_thenStill", duration: 6) { _ in
                [Actor(x: { 0.5 + widths * 0.07 * max(0, min(1, ($0 - 2) / 0.4)) },
                    visionMiss: { $0 >= 2 && $0 < 2.4 })]
            })
        }
        return list
    }

    /// A-01 (lock and recover without a face), design section 6. Kept apart
    /// from `scenarios()` so the existing tables, identity sweeps and golden
    /// digests do not change. Actor 0 is the subject; widths are 0.07.
    func a01Scenarios() -> [Scenario] {
        var list: [Scenario] = []
        func still(_ x: Double) -> (Double) -> Double { { _ in x } }
        let width = 0.07
        // The subject is unseen from 2 s for `gap` seconds, then returns in place.
        for gap in [0.6, 0.9, 1.2, 2.0, 2.8, 4.0] {
            list.append(Scenario(name: "occludedInPlace_gap\(r2(gap, 1))", duration: 14) { _ in
                [Actor(x: still(0.5), visionMiss: { $0 >= 2 && $0 < 2 + gap })]
            })
        }
        // The subject leaves at 2 s. A newcomer standing 1.4 widths away
        // (outside the locked region, so never seen while tracked) walks onto
        // the spot in 0.4 s and arrives `arrive` seconds after the subject vanished.
        for arrive in [0.4, 0.7, 1.5, 2.5] {
            list.append(Scenario(name: "newcomerOnSpot_arrive\(r2(arrive, 1))", duration: 14) { _ in
                let start = 0.5 + 1.4 * width, walk = 0.4, leaves = 2 + arrive - walk
                return [Actor(x: still(0.5), present: { $0 < 2 }),
                        Actor(x: { e in start + (0.5 - start) * max(0, min(1, (e - leaves) / walk)) })]
            })
        }
        // A bystander 0.25 frame away, outside the locked region, is first
        // seen by the hold's full-frame scan. The subject returns in place.
        for gap in [0.6, 2.0] {
            list.append(Scenario(name: "farBystanderRevealedAtHold_gap\(r2(gap, 1))", duration: 14) { _ in
                [Actor(x: still(0.5), visionMiss: { $0 >= 2 && $0 < 2 + gap }), Actor(x: still(0.75))]
            })
        }
        // A neighbour 1.4 widths away stays put; the subject returns in place.
        for gap in [0.6, 2.0] {
            list.append(Scenario(name: "subjectReturnsBesideBystander_gap\(r2(gap, 1))", duration: 14) { _ in
                [Actor(x: still(0.5), visionMiss: { $0 >= 2 && $0 < 2 + gap }), Actor(x: still(0.5 + 1.4 * width))]
            })
        }
        // The subject leaves at 2 s; someone else appears exactly on the spot at 3.5 s.
        for (label, height) in [("", 1.0), ("_height0.75", 0.75)] {
            list.append(Scenario(name: "otherEmergesOnSpot_after1.5\(label)", duration: 14) { _ in
                [Actor(x: still(0.5), present: { $0 < 2 }),
                 Actor(x: still(0.5), h: 0.30 * height, present: { $0 >= 3.5 })]
            })
        }
        // Clicks. No face is ever visible.
        list.append(Scenario(name: "acquireNoFace_still", duration: 10, make: { _ in [Actor(x: still(0.5))] },
                             acquire: true, faces: { _ in 0 }))
        list.append(Scenario(name: "acquireNoFace_walking0.10", duration: 10, make: { _ in
            // 0.10 frame/s from 0.2 to 0.8, then back.
            [Actor(x: { e in e <= 6 ? 0.2 + 0.10 * e : 0.8 - 0.10 * (e - 6) })]
        }, acquire: true, faces: { _ in 0 }))
        list.append(Scenario(name: "acquireNoFace_neighbour1.0bw_gestures", duration: 10, make: { rng in
            func gestures() -> (Double) -> (Double, Double, Double) {
                var plan: [(Double, Double, Int)] = []
                var t = 0.3 + rng.uniform() * 2
                while t < 10 { plan.append((t, t + 0.6 + rng.uniform() * 0.8, Int(rng.next() % 3))); t += 1.5 + rng.uniform() * 3 }
                return { e in
                    guard let gst = plan.first(where: { e >= $0.0 && e < $0.1 }) else { return (1, 1, 0) }
                    switch gst.2 { case 0: return (1, 1.2, 0); case 1: return (1.6, 1, 0); default: return (1.6, 1, -0.6) }
                }
            }
            return [Actor(x: still(0.5)), Actor(x: still(0.5 - width), shape: gestures())]
        }, acquire: true, faces: { _ in 0 }))
        // A click with the face visible on 70% of face scans.
        list.append(Scenario(name: "acquireFace0.7", duration: 10, make: { _ in [Actor(x: still(0.5))] },
                             acquire: true, faces: { _ in 0.7 }))
        // A click with no face, a 2 s gap in place from 3 s, then the face is visible from 5 s.
        list.append(Scenario(name: "weakLockLongGapThenFace", duration: 10, make: { _ in
            [Actor(x: still(0.5), visionMiss: { $0 >= 3 && $0 < 5 })]
        }, acquire: true, faces: { $0 >= 5 ? 0.7 : 0 }))
        return list
    }

}
