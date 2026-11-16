//
//  FaceIdentity.swift
//  CinematicCoreMacOS
//
//  Face evidence about whether the locked person is still the operator's
//  subject. An embedder turns a face crop into an `IdentityEmbedding`; the
//  pure `tier` function grades it against the subject's gallery. Today's
//  embedder is the pinned Vision feature print; a face-recognition model can
//  replace it behind `IdentityEmbedder` without touching the lock rules.
//

import CoreGraphics
import CoreVideo
import Foundation

/// Distances and quality gate for one embedder. The feature-print values are
/// provisional until the labelled-footage study sets them at ≤0.1% false
/// accepts per decision.
nonisolated struct IdentityThresholds: Sendable, Equatable {
    /// Best gallery distance below which a face is the subject…
    var strongMatch: Float
    /// …provided its landmark geometry is also this close to that entry.
    var strongMatchLandmark: Float
    /// Nearest anchor distance above which a face is someone else.
    var strongMismatch: Float
    /// Faces shorter than this, in source pixels, give no evidence.
    var minFaceHeightPixels: CGFloat

    static let featurePrintProvisional = IdentityThresholds(
        strongMatch: 0.50, strongMatchLandmark: 0.10, strongMismatch: 0.90, minFaceHeightPixels: 64)
}

/// Graded face evidence. Anything short of strong is `none` and leaves the
/// box rules to decide.
nonisolated enum IdentityTier: Equatable, Sendable {
    case strongMatch
    case strongMismatch
    case none
}

nonisolated protocol IdentityEmbedder: Sendable {
    var thresholds: IdentityThresholds { get }
    func embed(pixelBuffer: CVPixelBuffer, faceBox: CGRect) async -> IdentityEmbedding?
}

/// The pinned Vision feature print (Revision2) on a padded face crop.
nonisolated struct VisionFeaturePrintEmbedder: IdentityEmbedder {
    let extractor: FaceSignatureExtractor
    var thresholds: IdentityThresholds { .featurePrintProvisional }

    func embed(pixelBuffer: CVPixelBuffer, faceBox: CGRect) async -> IdentityEmbedding? {
        await extractor.extractSignature(from: pixelBuffer, faceBoundingBox: faceBox)
            .map(IdentityEmbedding.visionPrint)
    }
}

/// One identity check of the locked person's face, matched to its result by
/// lock generation, verify epoch and observation.
nonisolated struct IdentityEvidenceRequest: Sendable, Equatable {
    let generation: UInt64
    let observationID: UInt64
    let targetID: UUID
    let faceBox: CGRect
    /// The verify window's epoch when the check was scheduled. A restart
    /// moves the epoch on, so a check from before it is not counted.
    var verifyEpoch: UInt64 = 0
}

nonisolated enum FaceIdentityEvidence {
    struct Reference: Sendable {
        let embedding: IdentityEmbedding
        let landmarks: LandmarkRatios?
        /// Captured at acquisition and never evicted.
        let isAnchor: Bool
    }

    static func references(from gallery: ShotComposer.FaceSignatureGallery) -> [Reference] {
        gallery.entries.enumerated().map { index, entry in
            Reference(embedding: entry.embedding, landmarks: entry.landmarkVector,
                      isAnchor: index < ShotComposer.FaceSignatureGallery.readyThreshold)
        }
    }

    /// A strong match needs a close gallery entry with matching landmark
    /// geometry. A strong mismatch is judged against the anchors only, so a
    /// gallery that adapted towards someone else cannot excuse them.
    static func tier(candidate: IdentityEmbedding, landmarks: LandmarkRatios?,
                     faceHeightPixels: CGFloat, references: [Reference],
                     thresholds: IdentityThresholds) -> IdentityTier {
        guard faceHeightPixels >= thresholds.minFaceHeightPixels, let landmarks else { return .none }
        var bestDistance = Float.infinity
        var bestLandmarks: LandmarkRatios?
        for reference in references {
            if let distance = IdentityEmbedding.distance(reference.embedding, candidate), distance < bestDistance {
                bestDistance = distance
                bestLandmarks = reference.landmarks
            }
        }
        if bestDistance < thresholds.strongMatch, let bestLandmarks,
           LandmarkRatios.distance(landmarks, bestLandmarks) <= thresholds.strongMatchLandmark {
            return .strongMatch
        }
        let anchorDistances = references.filter(\.isAnchor).compactMap {
            IdentityEmbedding.distance($0.embedding, candidate)
        }
        if let nearestAnchor = anchorDistances.min(), nearestAnchor > thresholds.strongMismatch {
            return .strongMismatch
        }
        return .none
    }
}
