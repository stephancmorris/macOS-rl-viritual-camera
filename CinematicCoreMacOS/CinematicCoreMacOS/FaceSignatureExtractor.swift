//
//  FaceSignatureExtractor.swift
//  CinematicCoreMacOS
//
//  Extracts an opaque identity signature for a face crop using Apple's
//  built-in Vision perceptual hasher (VNGenerateImageFeaturePrintRequest).
//
//  Used by the lock state machine in ShotComposer to:
//    1. Capture a signature of the operator-locked subject at lock time.
//    2. Compare candidate faces against the stored signature during
//       wide-waiting, so the lock can re-acquire the same physical person
//       after they leave and return.
//
//  Pure Vision — no CoreML model required, no network.
//

@preconcurrency import Vision
import CoreImage
import CoreVideo
import Foundation
import OSLog

/// Wraps the per-face feature-print extraction so callers can hand it a
/// pixel buffer + face bbox and receive a comparable signature back.
///
/// The signature is `VNFeaturePrintObservation` — an opaque ~768-dim vector
/// from Apple's general-purpose perceptual hasher. Two signatures are
/// compared with `VNFeaturePrintObservation.computeDistance(_:to:)`; lower
/// distance = better match. Empirical threshold tuning is left to the
/// caller (see plan: re-acquisition threshold tuned from console logs).
final class FaceSignatureExtractor: @unchecked Sendable {
    private nonisolated static let logger = Logger(subsystem: "com.alfie", category: "Vision")

    private let processingQueue = DispatchQueue(
        label: "com.cinematiccore.faceSignature",
        qos: .userInitiated
    )

    /// CIContext is heavyweight; instantiate once and reuse.
    private let ciContext: CIContext

    init() {
        // Hardware-accelerated CIContext for cropping the face region.
        ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Sendable wrapper so we can hand the buffer to a non-isolated queue.
    private struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    /// Extract a face signature from the given pixel buffer + normalised
    /// face bbox (Vision bottom-left origin, 0..1).
    ///
    /// Returns nil if the face crop is empty or the feature-print request
    /// fails for any reason. Caller is expected to be on the main actor;
    /// the work runs on a background queue and awaits the result.
    func extractSignature(
        from pixelBuffer: CVPixelBuffer,
        faceBoundingBox: CGRect
    ) async -> VNFeaturePrintObservation? {
        let sendableBuffer = SendablePixelBuffer(value: pixelBuffer)
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Pad the face bbox by 30% so the feature print sees a bit of head
        // and shoulders context, not just the face interior. Empirically
        // makes the signature more robust to slight pose changes.
        let padded = faceBoundingBox.insetBy(
            dx: -faceBoundingBox.width * 0.15,
            dy: -faceBoundingBox.height * 0.15
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard padded.width > 0, padded.height > 0 else { return nil }

        return await withCheckedContinuation { continuation in
            processingQueue.async { [self] in
                // Convert normalised bbox to pixel coords. Vision uses
                // bottom-left origin; CoreImage also uses bottom-left, so
                // no Y-flip needed for cropping.
                let pixelRect = CGRect(
                    x: padded.origin.x * bufferWidth,
                    y: padded.origin.y * bufferHeight,
                    width: padded.width * bufferWidth,
                    height: padded.height * bufferHeight
                )

                let ciImage = CIImage(cvPixelBuffer: sendableBuffer.value)
                    .cropped(to: pixelRect)

                guard !ciImage.extent.isEmpty,
                      let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                    let observation = request.results?.first
                    continuation.resume(returning: observation)
                } catch {
                    Self.logger.error("Face signature extraction failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// L2 distance between two face signatures. Lower = more similar.
    /// Returns nil if computeDistance throws.
    nonisolated static func distance(
        _ a: VNFeaturePrintObservation,
        _ b: VNFeaturePrintObservation
    ) -> Float? {
        var dist: Float = 0
        do {
            try a.computeDistance(&dist, to: b)
            return dist
        } catch {
            logger.error("Feature-print distance failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Landmark Ratios

/// Pose-invariant geometry vector derived from a face's landmark points.
/// Each ratio is normalised by the face's bounding-box width, so it's
/// scale-invariant and (approximately) invariant to camera distance.
///
/// These are ratios of bone structure: very person-specific, very stable
/// across expressions and modest pose changes. Used as a *veto* signal
/// during re-acquisition — if the candidate's landmark distance to any
/// gallery entry exceeds a small threshold, the candidate is rejected
/// regardless of how good their feature-print distance looks.
struct LandmarkRatios: Sendable, Hashable {
    /// Eye-to-eye distance / face width.
    let eyeSpacing: Float
    /// Eye midpoint → nose-tip distance / face width.
    let eyeToNose: Float
    /// Eye midpoint → mouth-center distance / face width.
    let eyeToMouth: Float
    /// Mouth width / face width.
    let mouthWidth: Float

    /// Euclidean distance between two ratio vectors. Smaller = more
    /// similar bone structure. Typical same-person values are < 0.05;
    /// different-person values are typically > 0.10.
    nonisolated static func distance(_ a: LandmarkRatios, _ b: LandmarkRatios) -> Float {
        let d0 = a.eyeSpacing - b.eyeSpacing
        let d1 = a.eyeToNose - b.eyeToNose
        let d2 = a.eyeToMouth - b.eyeToMouth
        let d3 = a.mouthWidth - b.mouthWidth
        return (d0 * d0 + d1 * d1 + d2 * d2 + d3 * d3).squareRoot()
    }

    /// Extract pose-invariant ratios from a Vision face observation that
    /// includes landmarks (i.e. produced by VNDetectFaceLandmarksRequest).
    ///
    /// Returns nil if any required region (eyes, nose, mouth) is missing
    /// — happens when the subject's face is heavily turned or occluded.
    /// Caller is expected to fall back to face-print-only matching when
    /// the vector isn't available.
    nonisolated static func extract(from face: VNFaceObservation) -> LandmarkRatios? {
        guard let landmarks = face.landmarks else { return nil }
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.nose,
              let outerLips = landmarks.outerLips
        else { return nil }

        // Landmark points are in normalized face-bbox coordinates (0..1
        // relative to the face's bounding box). We compute centroids of
        // each region and derive ratios. Face width is by definition 1.0
        // in this coordinate space, so the ratios are already normalised.
        let leftEyeCentroid = centroid(of: leftEye.normalizedPoints)
        let rightEyeCentroid = centroid(of: rightEye.normalizedPoints)
        let noseCentroid = centroid(of: nose.normalizedPoints)
        let mouthCentroid = centroid(of: outerLips.normalizedPoints)

        let eyeMidpoint = CGPoint(
            x: (leftEyeCentroid.x + rightEyeCentroid.x) / 2,
            y: (leftEyeCentroid.y + rightEyeCentroid.y) / 2
        )

        let eyeSpacing = Float(distance(leftEyeCentroid, rightEyeCentroid))
        let eyeToNose = Float(distance(eyeMidpoint, noseCentroid))
        let eyeToMouth = Float(distance(eyeMidpoint, mouthCentroid))
        let mouthWidth = Float(mouthExtent(outerLips.normalizedPoints))

        // Sanity check — all ratios should be small positives in [0, 1].
        // If any are zero or NaN, the extraction probably failed (face
        // turned so far that the region collapsed to a single point).
        guard eyeSpacing > 0.01, eyeToNose > 0.01,
              eyeToMouth > 0.01, mouthWidth > 0.01,
              eyeSpacing.isFinite, eyeToNose.isFinite,
              eyeToMouth.isFinite, mouthWidth.isFinite
        else { return nil }

        return LandmarkRatios(
            eyeSpacing: eyeSpacing,
            eyeToNose: eyeToNose,
            eyeToMouth: eyeToMouth,
            mouthWidth: mouthWidth
        )
    }

    private nonisolated static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for p in points {
            sumX += p.x
            sumY += p.y
        }
        let n = CGFloat(points.count)
        return CGPoint(x: sumX / n, y: sumY / n)
    }

    private nonisolated static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Mouth extent = horizontal width of the lip outline (max-x minus min-x).
    private nonisolated static func mouthExtent(_ points: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        var minX = points[0].x
        var maxX = points[0].x
        for p in points {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
        }
        return maxX - minX
    }
}
