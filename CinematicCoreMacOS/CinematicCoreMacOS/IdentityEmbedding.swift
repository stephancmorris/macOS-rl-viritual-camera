//
//  IdentityEmbedding.swift
//  CinematicCoreMacOS
//
//  An identity signature taken from one face crop, independent of the model
//  that produced it. Today every production signature is a pinned Vision
//  feature print; the vector case lets tests and future embedders use the
//  same gallery and admission rules without Vision.
//

import Foundation
@preconcurrency import Vision

/// `VNFeaturePrintObservation` is an immutable class and is not `Sendable`.
/// It is never mutated after capture, so the wrapper can cross tasks.
nonisolated enum IdentityEmbedding: @unchecked Sendable {
    case visionPrint(VNFeaturePrintObservation)
    case vector([Float])

    /// Euclidean distance; lower is more similar. Nil when the two signatures
    /// come from different kinds of embedder, or Vision fails to compare them.
    static func distance(_ a: IdentityEmbedding, _ b: IdentityEmbedding) -> Float? {
        switch (a, b) {
        case let (.visionPrint(x), .visionPrint(y)):
            return FaceSignatureExtractor.distance(x, y)
        case let (.vector(x), .vector(y)):
            guard x.count == y.count, !x.isEmpty else { return nil }
            var sum: Float = 0
            for (u, v) in zip(x, y) { sum += (u - v) * (u - v) }
            return sum.squareRoot()
        default:
            return nil
        }
    }

    /// Smallest distance from `candidate` to any reference; nil when none compares.
    static func bestDistance(from candidate: IdentityEmbedding, to references: [IdentityEmbedding]) -> Float? {
        references.compactMap { distance($0, candidate) }.min()
    }
}

/// Whether a newly captured face may join the gallery.
///
/// The first `readyThreshold` entries, captured while the operator acquires
/// the subject, are anchors and need no check. After that every capture must
/// resemble the gallery. After an ambiguous moment the lock may have swapped
/// people, so a capture must resemble the anchors themselves before the
/// gallery is trusted again.
nonisolated enum GalleryAdmission {
    enum Scope: Equatable, Sendable {
        case anchors
        case wholeGallery
    }

    static func scope(entryCount: Int, unverified: Bool) -> Scope? {
        guard entryCount >= ShotComposer.FaceSignatureGallery.readyThreshold else { return nil }
        return unverified ? .anchors : .wholeGallery
    }

    static func admits(bestDistance: Float?, threshold: Float) -> Bool {
        guard let bestDistance else { return false }
        return bestDistance < threshold
    }
}
