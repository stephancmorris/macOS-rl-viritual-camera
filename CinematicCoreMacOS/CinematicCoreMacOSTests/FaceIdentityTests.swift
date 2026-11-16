//
//  FaceIdentityTests.swift
//  CinematicCoreMacOSTests
//
//  Face evidence grading and the identity verify window. Evidence is
//  delivered through the DEBUG scheduler seam, so the window's gates and
//  streaks are the real ones without Vision.
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct FaceIdentityTests {
    private static let face = LandmarkRatios(eyeSpacing: 0.4, eyeToNose: 0.3, eyeToMouth: 0.6, mouthWidth: 0.35)
    private static let otherFace = LandmarkRatios(eyeSpacing: 0.6, eyeToNose: 0.5, eyeToMouth: 0.9, mouthWidth: 0.55)
    private static let thresholds = IdentityThresholds.featurePrintProvisional

    private static func references(anchors: [[Float]], rest: [[Float]] = []) -> [FaceIdentityEvidence.Reference] {
        anchors.map { FaceIdentityEvidence.Reference(embedding: .vector($0), landmarks: face, isAnchor: true) }
            + rest.map { FaceIdentityEvidence.Reference(embedding: .vector($0), landmarks: face, isAnchor: false) }
    }

    private static func tier(_ candidate: [Float], landmarks: LandmarkRatios? = face, height: CGFloat = 80,
                             anchors: [[Float]] = [[1, 0, 0, 0]], rest: [[Float]] = []) -> IdentityTier {
        FaceIdentityEvidence.tier(candidate: .vector(candidate), landmarks: landmarks, faceHeightPixels: height,
                                  references: references(anchors: anchors, rest: rest), thresholds: thresholds)
    }

    // MARK: Tiers

    @Test func qualityGateGivesNoEvidence() {
        #expect(Self.tier([1, 0, 0, 0], height: 63) == .none)
        #expect(Self.tier([0, 1, 0, 0], height: 63) == .none)
        #expect(Self.tier([1, 0, 0, 0], landmarks: nil) == .none)
    }

    @Test func strongMatchNeedsCloseDistanceAndLandmarks() {
        #expect(Self.tier([0.9, 0.1, 0, 0]) == .strongMatch)
        // Close print, different face geometry: not strong either way.
        #expect(Self.tier([0.9, 0.1, 0, 0], landmarks: Self.otherFace) == .none)
        // Between the thresholds: no evidence.
        #expect(Self.tier([0.6, 0.6, 0, 0]) == .none)
    }

    @Test func strongMismatchIsJudgedAgainstTheAnchors() {
        #expect(Self.tier([0, 0, 1, 0]) == .strongMismatch)
        // A non-anchor entry near the candidate does not excuse a stranger
        // far from every anchor unless it is a strong match itself.
        #expect(Self.tier([0, 0.6, 0.8, 0], rest: [[0, 0, 1, 0]]) == .strongMismatch)
    }

    // MARK: Verify window

    @MainActor private final class Fixture {
        let composer = ShotComposer()
        let subject = UUID()
        var requests: [IdentityEvidenceRequest] = []
        var time = 1000.0
        var observation: UInt64 = 0

        init() {
            composer.lockTarget(subject)
            composer.forceTrackingForTesting(readyGallery: true)
            composer.identityEvidenceSchedulerForTesting = { [unowned self] in self.requests.append($0) }
        }

        func tick(present: Bool = true, face: Bool = true, ambiguous: Bool = false) {
            time += 0.04
            observation += 1
            let persons = present ? [PersonDetector.DetectedPerson(id: subject,
                boundingBox: CGRect(x: 0.45, y: 0.25, width: 0.07, height: 0.30),
                confidence: 1, timestamp: time, poseKeypoints: nil,
                faceBoundingBox: face ? CGRect(x: 0.47, y: 0.48, width: 0.03, height: 0.04) : nil,
                faceLandmarkRatios: nil)] : []
            _ = composer.tick(detections: persons, timestamp: time, pixelBuffer: nil,
                              observationID: observation, observationTimestamp: time,
                              lockAmbiguityOpen: ambiguous)
        }

        /// Answers the newest request, then ticks again to schedule the next.
        @discardableResult
        func answer(_ tier: IdentityTier) -> Bool {
            guard let request = requests.last else {
                Issue.record("No identity request was scheduled")
                return false
            }
            let counted = composer.finishIdentityEvidence(request, tier: tier)
            tick()
            return counted
        }
    }

    @Test func threeStrongMatchesVerify() {
        let f = Fixture()
        f.tick(ambiguous: true)
        #expect(f.composer.identityVerifyOpenForTesting)
        f.answer(.strongMatch)
        f.answer(.strongMatch)
        #expect(f.composer.identityVerifyOpenForTesting)
        f.answer(.strongMatch)
        #expect(!f.composer.identityVerifyOpenForTesting)
    }

    @Test func noEvidenceBreaksTheStreak() {
        let f = Fixture()
        f.tick(ambiguous: true)
        f.answer(.strongMatch)
        f.answer(.strongMatch)
        f.answer(.none)
        f.answer(.strongMatch)
        #expect(f.composer.identityVerifyOpenForTesting)
    }

    @Test func threeMismatchesRecordOneShadowVeto() {
        let f = Fixture()
        var vetoes = 0
        f.composer.identityWouldVetoForTesting = { vetoes += 1 }
        f.tick(ambiguous: true)
        f.answer(.strongMismatch)
        f.answer(.strongMismatch)
        #expect(vetoes == 0)
        for _ in 0..<4 { f.answer(.strongMismatch) }
        #expect(vetoes == 1)
        #expect(f.composer.identityWouldVetoCount == 1)
        // Shadow only: the lock keeps tracking the same target.
        guard case .tracking(let id, _) = f.composer.lockState else {
            Issue.record("Shadow veto changed the lock state")
            return
        }
        #expect(id == f.subject)
    }

    /// The lock leaves tracking and returns on the same target: the old
    /// request's generation is retired although the window is open again.
    @Test func retiredGenerationIsRefused() throws {
        let f = Fixture()
        f.tick(ambiguous: true)
        let stale = try #require(f.requests.last)
        f.tick(present: false)
        // The first tick back returns hold to tracking; the next opens the window.
        f.tick(face: false, ambiguous: true)
        f.tick(face: false, ambiguous: true)
        #expect(f.composer.identityVerifyOpenForTesting)
        #expect(!f.composer.finishIdentityEvidence(stale, tier: .strongMatch))
    }

    @Test func olderObservationIsRefused() throws {
        let f = Fixture()
        f.tick(ambiguous: true)
        let request = try #require(f.requests.last)
        f.tick(face: false)
        let newer = IdentityEvidenceRequest(generation: f.composer.identityGenerationForTesting,
            observationID: f.observation, targetID: f.subject, faceBox: .zero)
        #expect(f.composer.finishIdentityEvidence(newer, tier: .strongMatch))
        #expect(!f.composer.finishIdentityEvidence(request, tier: .strongMatch))
    }

    @Test func verifyScanCadenceAndCap() {
        let f = Fixture()
        f.tick(face: false, ambiguous: true)
        let opened = f.time
        var pattern: [Bool] = []
        for k in 0..<9 { pattern.append(f.composer.shouldRunIdentityVerifyScan(now: opened + Double(k) * 0.04)) }
        #expect(pattern == [true, false, false, true, false, false, true, false, false])
        var late: [Bool] = []
        for k in 0..<3 {
            late.append(f.composer.shouldRunIdentityVerifyScan(
                now: opened + ShotComposer.identityVerifyMaxDuration + Double(k) * 0.04))
        }
        #expect(late == [false, false, false])
    }

    /// The first window ran out without a verdict (no usable face). A new
    /// ambiguous moment later restarts its scans.
    @Test func newAmbiguityRestartsAStalledWindow() {
        let f = Fixture()
        f.tick(face: false, ambiguous: true)
        let pastCap = f.time + ShotComposer.identityVerifyMaxDuration + 0.1
        #expect(!f.composer.shouldRunIdentityVerifyScan(now: pastCap))
        f.time = pastCap
        f.tick(face: false)
        #expect(f.composer.identityVerifyOpenForTesting)
        f.tick(face: false, ambiguous: true)
        #expect(f.composer.shouldRunIdentityVerifyScan(now: f.time))
    }

    /// A second swap in the same tracking stretch records its own shadow
    /// veto; continued mismatches within one moment do not.
    @Test func aRestartAllowsAnotherShadowVeto() {
        let f = Fixture()
        f.tick(ambiguous: true)
        for _ in 0..<3 { f.answer(.strongMismatch) }
        #expect(f.composer.identityWouldVetoCount == 1)
        for _ in 0..<3 { f.answer(.strongMismatch) }
        #expect(f.composer.identityWouldVetoCount == 1)
        f.tick(ambiguous: true)
        f.answer(.strongMismatch)
        f.answer(.strongMismatch)
        #expect(f.composer.identityWouldVetoCount == 1)
        f.answer(.strongMismatch)
        #expect(f.composer.identityWouldVetoCount == 2)
    }

    /// A new ambiguous moment needs three fresh matches to verify.
    @Test func aRestartNeedsFreshMatches() {
        let f = Fixture()
        f.tick(ambiguous: true)
        f.answer(.strongMatch)
        f.answer(.strongMatch)
        f.tick(ambiguous: true)
        f.answer(.strongMatch)
        #expect(f.composer.identityVerifyOpenForTesting)
        f.answer(.strongMatch)
        f.answer(.strongMatch)
        #expect(!f.composer.identityVerifyOpenForTesting)
    }

    @Test func closedWindowAsksForNoScans() {
        let f = Fixture()
        f.tick(face: false)
        #expect(!f.composer.shouldRunIdentityVerifyScan(now: f.time))
        #expect(f.requests.isEmpty)
    }
}
