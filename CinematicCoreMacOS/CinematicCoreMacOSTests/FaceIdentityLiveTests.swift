//
//  FaceIdentityLiveTests.swift
//  CinematicCoreMacOSTests
//
//  Face identity acting on the lock: the live veto and strong-match
//  recovery. Production keeps this off (`DeveloperFlags.identityVetoEnabled`);
//  these tests switch it on through the Debug override. Evidence and scores
//  arrive through the synchronous scheduler seams.
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct FaceIdentityLiveTests {
    @MainActor private final class Fixture {
        let composer = ShotComposer()
        let subject = UUID()
        var evidence: [IdentityEvidenceRequest] = []
        var recovery: [ShotComposer.ReacquisitionRequest] = []
        var time = 1000.0
        var observation: UInt64 = 0

        init(live: Bool = true) {
            composer.identityVetoEnabledForTesting = live
            composer.lockTarget(subject)
            composer.forceTrackingForTesting(readyGallery: true)
            composer.identityEvidenceSchedulerForTesting = { [unowned self] in self.evidence.append($0) }
            composer.reacquisitionSchedulerForTesting = { [unowned self] in self.recovery.append($0) }
        }

        func person(_ id: UUID, x: Double = 0.45) -> PersonDetector.DetectedPerson {
            PersonDetector.DetectedPerson(id: id,
                boundingBox: CGRect(x: x, y: 0.25, width: 0.07, height: 0.30),
                confidence: 1, timestamp: time, poseKeypoints: nil,
                faceBoundingBox: CGRect(x: x + 0.02, y: 0.48, width: 0.03, height: 0.04),
                faceLandmarkRatios: nil)
        }

        func tick(_ ids: [UUID], excluded: Set<UUID> = [], ambiguous: Bool = false) {
            time += 0.04
            observation += 1
            let persons = ids.enumerated().map { person($1, x: 0.30 + Double($0) * 0.20) }
            _ = composer.tick(detections: persons, timestamp: time, pixelBuffer: nil,
                              observationID: observation, observationTimestamp: time,
                              excludedFromReacquisition: excluded, lockAmbiguityOpen: ambiguous)
        }

        /// Three strong mismatches on the tracked subject's face.
        func veto() {
            tick([subject], ambiguous: true)
            for _ in 0..<3 {
                guard let request = evidence.last else { Issue.record("No identity request"); return }
                composer.finishIdentityEvidence(request, tier: .strongMismatch)
                tick([subject])
            }
        }

        /// Answers the newest recovery batch: candidates absent from
        /// `distances` score as clearly different (0.80).
        func answer(_ distances: [UUID: Float], landmarks: Float = 0.01, faceHeight: Double = 80) {
            guard let request = recovery.last else { Issue.record("No recovery request"); return }
            let scores = request.candidates.map {
                ShotComposer.ReacquisitionScore(id: $0.id, printDistance: distances[$0.id] ?? 0.80,
                    landmarkDistance: landmarks, isExcluded: $0.isExcluded, faceHeightPixels: faceHeight)
            }
            composer.finishReacquisitionScoring(generation: request.generation,
                visibilityRevision: request.visibilityRevision, observationID: request.observationID, scores: scores)
        }

        var boundID: UUID? {
            if case .tracking(let id, _) = composer.lockState { return id }
            return nil
        }
        var isHold: Bool { if case .hold = composer.lockState { return true }; return false }
    }

    // MARK: Veto

    @Test func vetoHoldsAndDetectorStopsBinding() {
        let f = Fixture()
        f.veto()
        #expect(f.isHold)
        #expect(f.composer.manualLockedTargetID == f.subject)
        #expect(f.composer.lockBindingTargetID == nil)
        #expect(f.composer.identityVetoedIDs == [f.subject])
    }

    @Test func vetoedTrackCannotReturnOnBoxes() {
        let f = Fixture()
        f.veto()
        for _ in 0..<5 { f.tick([f.subject]) }
        #expect(f.isHold)
    }

    @Test func vetoStaysShadowWhenNotLive() {
        let f = Fixture(live: false)
        f.veto()
        #expect(f.boundID == f.subject)
        #expect(f.composer.identityWouldVetoCount == 1)
        #expect(f.composer.lockBindingTargetID == f.subject)
    }

    @Test func vetoedTrackReturnsOnlyOnAStrongMatch() {
        let f = Fixture()
        f.veto()
        // Weak (under the solo threshold, not strong): never binds the vetoed track.
        for _ in 0..<4 {
            f.tick([f.subject])
            f.answer([f.subject: 0.52])
        }
        f.tick([f.subject])
        #expect(f.isHold)
        for _ in 0..<3 {
            f.answer([f.subject: 0.10])
            f.tick([f.subject])
        }
        #expect(f.boundID == f.subject)
        #expect(f.composer.identityVetoedIDs.isEmpty)
    }

    // MARK: What a vetoed hold reports

    /// A camera whose composer is driven the way `processFrame` drives it:
    /// refresh the ROI seed, tick, then re-seed after a veto recovery.
    @MainActor private final class CameraFixture {
        let camera = TestHardware.makeCamera()
        var composer: ShotComposer { camera.shotComposer }
        let subject = UUID()
        let other = UUID()
        var evidence: [IdentityEvidenceRequest] = []
        var recovery: [ShotComposer.ReacquisitionRequest] = []
        var time = 1000.0
        var observation: UInt64 = 0

        init() {
            composer.identityVetoEnabledForTesting = true
            composer.lockTarget(subject)
            composer.forceTrackingForTesting(readyGallery: true)
            composer.identityEvidenceSchedulerForTesting = { [unowned self] in self.evidence.append($0) }
            composer.reacquisitionSchedulerForTesting = { [unowned self] in self.recovery.append($0) }
        }

        static func box(x: Double) -> CGRect { CGRect(x: x, y: 0.25, width: 0.07, height: 0.30) }

        @discardableResult
        func tick(_ people: [(id: UUID, x: Double)], ambiguous: Bool = false) -> ShotComposer.TickOutcome {
            time += 0.04
            observation += 1
            let persons = people.map {
                PersonDetector.DetectedPerson(id: $0.id, boundingBox: Self.box(x: $0.x), confidence: 1,
                    timestamp: time, poseKeypoints: nil,
                    faceBoundingBox: CGRect(x: $0.x + 0.02, y: 0.48, width: 0.03, height: 0.04),
                    faceLandmarkRatios: nil)
            }
            camera.refreshSubjectROISeed(from: persons)
            let wasVetoHeld = composer.isIdentityVetoHeld
            let outcome = composer.tick(detections: persons, timestamp: time, pixelBuffer: nil,
                                        observationID: observation, observationTimestamp: time,
                                        lockAmbiguityOpen: ambiguous)
            camera.reseedSubjectROIAfterVetoRecovery(wasVetoHeld: wasVetoHeld, outcome: outcome, persons: persons)
            _ = composer.primaryPerson(from: persons)
            return outcome
        }

        /// Three strong mismatches on the tracked subject at `x`.
        func veto(x: Double) {
            tick([(subject, x)], ambiguous: true)
            for _ in 0..<3 {
                guard let request = evidence.last else { Issue.record("No identity request"); return }
                composer.finishIdentityEvidence(request, tier: .strongMismatch)
                tick([(subject, x)])
            }
        }
    }

    /// Not fixed in the first review: the seed kept following the vetoed
    /// track, so the first ROI scan after recovery could aim at that person.
    @Test func roiSeedLeavesTheVetoedTrackAndFollowsTheRecoveryBind() {
        let f = CameraFixture()
        f.tick([(f.subject, 0.30)])
        #expect(f.camera.subjectROISeedForTesting == CameraFixture.box(x: 0.30))
        f.veto(x: 0.30)
        #expect(f.composer.isIdentityVetoHeld)
        // The vetoed person walks on; the real subject appears elsewhere.
        var outcome = f.tick([(f.subject, 0.50), (f.other, 0.70)])
        #expect(f.camera.subjectROISeedForTesting == CameraFixture.box(x: 0.30))
        for _ in 0..<4 {
            guard case .noChange = outcome, let request = f.recovery.last else { break }
            let scores = request.candidates.map {
                ShotComposer.ReacquisitionScore(id: $0.id, printDistance: $0.id == f.other ? 0.10 : 0.80,
                    landmarkDistance: 0.01, isExcluded: $0.isExcluded, faceHeightPixels: 80)
            }
            f.composer.finishReacquisitionScoring(generation: request.generation,
                visibilityRevision: request.visibilityRevision, observationID: request.observationID, scores: scores)
            outcome = f.tick([(f.subject, 0.50), (f.other, 0.70)])
        }
        guard case .resumeTracking = outcome else {
            Issue.record("Recovery did not bind the other track")
            return
        }
        #expect(f.composer.manualLockedTargetID == f.other)
        #expect(f.camera.subjectROISeedForTesting == CameraFixture.box(x: 0.70))
    }

    /// The vetoed person is still in view but is not the subject: the overlay
    /// and the world model get no subject track. The lock itself still reads
    /// as an ordinary hold, so lock gates and the Director are unchanged.
    @Test func aVetoedHoldReportsNoSubjectTrack() {
        let f = CameraFixture()
        f.tick([(f.subject, 0.30)])
        #expect(f.camera.subjectTrackID == f.subject)
        #expect(f.composer.activeTargetID == f.subject)
        #expect(f.camera.worldModelReading().lockedTrack == f.subject)
        f.veto(x: 0.30)
        f.tick([(f.subject, 0.30)])
        #expect(f.camera.subjectTrackID == nil)
        #expect(f.composer.activeTargetID == nil)
        #expect(f.camera.worldModelReading().lockedTrack == nil)
        #expect(f.camera.worldModelReading().lockPhase == .hold)
        #expect(f.camera.manualLockedTargetID == f.subject)
        let readings = f.camera.evidenceReadings(now: f.time)
        #expect(readings.lockPhase == .hold)
        #expect(readings.lockedTargetID == f.subject)
    }

    // MARK: Strong-match recovery

    /// A witness's track can carry the subject after an ID swap. A strong
    /// match with margin, three times running, may re-bind it.
    @Test func strongMatchRebindsOntoWitness() {
        let f = Fixture()
        let witness = UUID()
        f.tick([])
        #expect(f.isHold)
        for _ in 0..<3 {
            f.tick([witness], excluded: [witness])
            f.answer([witness: 0.10])
        }
        f.tick([witness], excluded: [witness])
        #expect(f.boundID == witness)
    }

    @Test func weakMatchOnWitnessStillExcluded() {
        let f = Fixture()
        let witness = UUID()
        f.tick([])
        for _ in 0..<5 {
            f.tick([witness], excluded: [witness])
            f.answer([witness: 0.52])
        }
        f.tick([witness], excluded: [witness])
        #expect(f.isHold)
    }

    @Test func twoStrongMatchesFreeze() {
        let f = Fixture()
        let a = UUID(), witness = UUID()
        f.tick([])
        for _ in 0..<5 {
            f.tick([a, witness], excluded: [witness])
            f.answer([a: 0.10, witness: 0.30])
        }
        f.tick([a, witness], excluded: [witness])
        #expect(f.isHold)
    }

    /// The evidence itself refuses a weak excluded winner (the drain also
    /// refuses a weak decision on an excluded person; this is the first line).
    @Test func excludedWinnerNeedsTheStrongTier() {
        var evidence = ShotComposer.ReacquisitionEvidence()
        let witness = UUID()
        func batch(_ distance: Float) -> [ShotComposer.ReacquisitionScore] {
            [ShotComposer.ReacquisitionScore(id: witness, printDistance: distance, landmarkDistance: 0.01,
                                             isExcluded: true, faceHeightPixels: 80)]
        }
        for observation: UInt64 in 1...4 {
            #expect(evidence.decide(observationID: observation, scores: batch(0.52), strong: .featurePrintProvisional) == nil)
        }
        #expect(evidence.decide(observationID: 5, scores: batch(0.10), strong: .featurePrintProvisional) == nil)
        #expect(evidence.decide(observationID: 6, scores: batch(0.10), strong: .featurePrintProvisional) == nil)
        #expect(evidence.decide(observationID: 7, scores: batch(0.10), strong: .featurePrintProvisional)
                == .init(id: witness, strong: true))
    }

    /// Review fix: excluded faces must not loosen a lone candidate's
    /// threshold. 0.58 is refused at the solo 0.55 even with a witness in shot.
    @Test func loneCandidateKeepsTheSoloThreshold() {
        let f = Fixture()
        let a = UUID(), witness = UUID()
        f.tick([])
        for _ in 0..<4 {
            f.tick([a, witness], excluded: [witness])
            f.answer([a: 0.58, witness: 0.80], landmarks: 0.05)
        }
        f.tick([a, witness], excluded: [witness])
        #expect(f.isHold)
    }

    /// Review fix: a face below the 64 px gate is never strong, so it cannot
    /// bind a witness however close its print.
    @Test func smallFaceGivesNoStrongDecision() {
        let f = Fixture()
        let witness = UUID()
        f.tick([])
        for _ in 0..<5 {
            f.tick([witness], excluded: [witness])
            f.answer([witness: 0.10], faceHeight: 40)
        }
        f.tick([witness], excluded: [witness])
        #expect(f.isHold)
    }

    /// Review fix: a strong override needs every observation behind the
    /// decision to be strong. Weak, weak, strong for someone who becomes a
    /// witness before the drain must not bind them.
    @Test func strongOverrideNeedsEveryObservationStrong() {
        let f = Fixture()
        let a = UUID()
        f.tick([])
        for distance: Float in [0.52, 0.52, 0.10] {
            f.tick([a])
            f.answer([a: distance])
        }
        f.tick([a], excluded: [a])
        #expect(f.isHold)
    }

    /// An excluded face now counts as a runner-up. Not live, it is not scored
    /// and the same candidate binds.
    @Test(arguments: [true, false])
    func excludedRunnerUpTightensTheMargin(live: Bool) {
        let f = Fixture(live: live)
        let a = UUID(), witness = UUID()
        f.tick([])
        for _ in 0..<3 {
            f.tick([a, witness], excluded: [witness])
            f.answer([a: 0.52, witness: 0.60], landmarks: 0.05)
        }
        f.tick([a, witness], excluded: [witness])
        #expect((f.boundID == a) == !live)
    }
}
