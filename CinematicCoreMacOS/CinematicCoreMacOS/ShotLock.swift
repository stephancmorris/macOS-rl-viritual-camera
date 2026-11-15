//
//  ShotLock.swift
//  CinematicCoreMacOS
//
//  Lock and re-acquisition value types: face signatures, the signature
//  gallery, the lock state and re-acquisition scoring.
//  Moved out of ShotComposer.swift unchanged (hygiene B13).
//

import Foundation
import CoreGraphics
import CoreVideo
@preconcurrency import Vision

extension ShotComposer {
    /// One captured reference view of the locked subject. The gallery
    /// holds 6-8 of these covering varied head pose / expression / lighting.
    ///
    /// `VNFeaturePrintObservation` is an immutable class and is not
    /// `Sendable`. It is not mutated after capture, so the struct can cross
    /// the re-acquisition task.
    struct FaceSignature: @unchecked Sendable {
        let embedding: IdentityEmbedding
        /// Pose-invariant landmark geometry captured at the same moment.
        /// Nil when Vision returned no landmarks (rare; subject heavily
        /// turned). Re-acquisition falls back to face-print-only matching
        /// against gallery entries that lack landmarks.
        let landmarkVector: LandmarkRatios?
        let capturedAt: TimeInterval
    }

    /// Sliding-window collection of reference signatures captured during
    /// healthy tracking. Compared against during wideWaiting:
    /// re-acquisition takes the *best* (lowest-distance) entry per
    /// candidate, which lets the locked subject return in a pose that
    /// matches only one of the stored views.
    ///
    /// `VNFeaturePrintObservation` is an immutable class and is not
    /// `Sendable`. It is not mutated after capture, so the struct can cross
    /// the re-acquisition task. The gallery value is copied into that task;
    /// its methods mutate the copy, not a shared instance.
    struct FaceSignatureGallery: @unchecked Sendable {
        private(set) var entries: [FaceSignature] = []
        private(set) var lastCaptureAt: TimeInterval = 0

        static let maxSize: Int = 8
        static let captureSpacing: TimeInterval = 0.4
        /// Minimum entries before re-acquisition is allowed to run.
        /// Below this, the gallery hasn't seen enough variation.
        static let readyThreshold: Int = 3

        #if DEBUG
        /// Synthetic scheduling tests need readiness without manufacturing Vision prints.
        var readyForTesting = false
        #endif

        var isReady: Bool {
            #if DEBUG
            if readyForTesting { return true }
            #endif
            return entries.count >= Self.readyThreshold
        }
        var size: Int { entries.count }

        /// Append a freshly-captured signature. The first `readyThreshold`
        /// entries are anchors: captured while the operator acquired the
        /// subject, they are never evicted. When the gallery is full the
        /// oldest non-anchor entry is evicted (FIFO sliding window), so the
        /// rest adapts to slow lighting, pose and wardrobe drift.
        mutating func append(_ signature: FaceSignature) {
            entries.append(signature)
            while entries.count > Self.maxSize {
                entries.remove(at: Self.readyThreshold)
            }
            lastCaptureAt = signature.capturedAt
        }

        /// The never-evicted acquisition entries.
        var anchors: ArraySlice<FaceSignature> { entries.prefix(Self.readyThreshold) }

        /// Whether enough time has passed since the last capture to allow
        /// the next one. Throttles the fill so we don't hammer Vision.
        func shouldCapture(at timestamp: TimeInterval) -> Bool {
            timestamp - lastCaptureAt >= Self.captureSpacing
        }
    }

    enum LockState {
        case inactive
        /// Operator tapped a subject; we have a track UUID but haven't locked
        /// yet. Detection runs ROI-only around the subject while the gallery
        /// fills. When `gallery.isReady` we promote to `tracking` (green box)
        /// and cropping begins. No program crop is produced while acquiring.
        case acquiring(targetID: UUID, gallery: FaceSignatureGallery, sinceTime: TimeInterval)
        case tracking(targetID: UUID, gallery: FaceSignatureGallery)
        case hold(targetID: UUID, gallery: FaceSignatureGallery, sinceTime: TimeInterval)
        /// Pulled back to wide, waiting for the original speaker to return.
        /// The gallery may be too small (< readyThreshold) — in that case
        /// re-acquisition is disabled and only an operator action will
        /// move state.
        case wideWaiting(gallery: FaceSignatureGallery)
    }

    struct ReacquisitionScore: Sendable {
        let id: UUID
        let printDistance: Float?
        let landmarkDistance: Float?
        /// A witness or identity-vetoed person: only a strong decision may bind them.
        var isExcluded = false
    }

    /// One decision per completed observation, after ALL visible candidates were scored.
    struct ReacquisitionEvidence {
        private(set) var candidate: UUID?
        private(set) var count = 0
        private var lastObservationID: UInt64?

        mutating func reset() { candidate = nil; count = 0; lastObservationID = nil }

        mutating func consider(observationID: UInt64, scores: [ReacquisitionScore]) -> UUID? {
            // Results can complete out of order when a session/target changes.
            // Only a strictly newer observation may add evidence; duplicates
            // and late older batches are ignored rather than counted twice.
            guard lastObservationID.map({ observationID > $0 }) ?? true else { return nil }
            lastObservationID = observationID
            // Unknown/failed candidates make this observation ambiguous.
            guard !scores.isEmpty, scores.allSatisfy({ $0.printDistance?.isFinite == true }) else {
                candidate = nil; count = 0; return nil
            }
            let eligible = scores.filter { ($0.landmarkDistance ?? 0) <= ShotComposer.landmarkRejectionThreshold }
                .sorted { $0.printDistance! < $1.printDistance! }
            guard let winner = eligible.first,
                  // A landmark-vetoed face is not a viable runner-up and must
                  // not relax the stricter threshold for an effectively solo
                  // candidate.
                  winner.printDistance! < (eligible.count == 1 ? ShotComposer.soloThreshold : ShotComposer.absoluteThreshold),
                  eligible.count < 2 || eligible[1].printDistance! >= winner.printDistance! * ShotComposer.marginRatio else {
                candidate = nil; count = 0; return nil
            }
            count = candidate == winner.id ? count + 1 : 1
            candidate = winner.id
            return count >= ShotComposer.reacquisitionConsecutiveFrames ? winner.id : nil
        }

        struct Decision: Equatable, Sendable {
            let id: UUID
            /// Strong-tier face evidence. Only a strong decision may bind an excluded person.
            let strong: Bool
        }

        /// The face-identity rules, used only while face identity is live.
        ///
        /// Excluded faces (witnesses, vetoed tracks) are scored too, so they
        /// count as runners-up: a deliberate tightening of the margin. An
        /// excluded winner needs the strong tier as well as the margin. Two
        /// strong matches in one observation are ambiguous: the evidence
        /// resets and the lock stays frozen.
        mutating func decide(observationID: UInt64, scores: [ReacquisitionScore],
                             strong: IdentityThresholds) -> Decision? {
            guard lastObservationID.map({ observationID > $0 }) ?? true else { return nil }
            lastObservationID = observationID
            guard !scores.isEmpty, scores.allSatisfy({ $0.printDistance?.isFinite == true }) else {
                candidate = nil; count = 0; return nil
            }
            let eligible = scores.filter { ($0.landmarkDistance ?? 0) <= ShotComposer.landmarkRejectionThreshold }
                .sorted { $0.printDistance! < $1.printDistance! }
            func isStrong(_ score: ReacquisitionScore) -> Bool {
                guard let landmarks = score.landmarkDistance else { return false }
                return score.printDistance! < strong.strongMatch && landmarks <= strong.strongMatchLandmark
            }
            guard eligible.filter(isStrong).count < 2, let winner = eligible.first,
                  eligible.count < 2 || eligible[1].printDistance! >= winner.printDistance! * ShotComposer.marginRatio,
                  winner.isExcluded
                    ? isStrong(winner)
                    : winner.printDistance! < (eligible.count == 1 ? ShotComposer.soloThreshold : ShotComposer.absoluteThreshold)
            else {
                candidate = nil; count = 0; return nil
            }
            count = candidate == winner.id ? count + 1 : 1
            candidate = winner.id
            return count >= ShotComposer.reacquisitionConsecutiveFrames
                ? Decision(id: winner.id, strong: isStrong(winner)) : nil
        }
    }
}
