//
//  FramingCapability.swift
//  CinematicCoreMacOS
//

import CoreGraphics
import Foundation

/// Pixel geometry for a requested program crop. This describes resampling,
/// not perceived sharpness or whether a subject can be detected or tracked.
struct FramingCapability: Sendable {
    enum Reason: Hashable, Sendable {
        case nativeOrDownsampled
        case enlargedImage
        case hardZoomBound
    }

    /// The crop after applying the same hard floor used by the renderer.
    let legalCrop: CropEngine.CropRect
    let sourceCropPixels: CGSize
    let outputPixels: CGSize
    /// Largest per-axis output/source scale. Values above 1 enlarge pixels.
    let enlargement: CGFloat
    /// True at the smallest crop that the source resolution and crop aspect allow.
    let isHardZoomLimited: Bool
    let reasons: Set<Reason>

    /// `sourceSize` must be the delivered frame dimensions, not the advertised
    /// capture format. A nil result means the geometry is unavailable or invalid.
    static func evaluate(
        sourceSize: CGSize,
        requestedCrop: CropEngine.CropRect,
        outputSize: CGSize
    ) -> FramingCapability? {
        let values = [sourceSize.width, sourceSize.height,
                      requestedCrop.origin.x, requestedCrop.origin.y,
                      requestedCrop.size.width, requestedCrop.size.height,
                      outputSize.width, outputSize.height]
        guard values.allSatisfy(\.isFinite),
              sourceSize.width > 0, sourceSize.height > 0,
              sourceSize.height < CGFloat(Int.max),
              outputSize.width > 0, outputSize.height > 0,
              requestedCrop.size.width > 0, requestedCrop.size.width <= 1,
              requestedCrop.size.height > 0, requestedCrop.size.height <= 1 else {
            return nil
        }

        // Keep the requested aspect when fitting the hard floor to the frame.
        // CropEngine owns both the minimum height and the aspect-preserving
        // enlargement, so diagnostics cannot drift from actual rendering.
        let floor = CropEngine.QualityFloor.forSource(height: Int(sourceSize.height))
        let legalCrop = requestedCrop.clampedToQualityFloor(floor).clamped()
        let sourceCropPixels = CGSize(
            width: sourceSize.width * legalCrop.size.width,
            height: sourceSize.height * legalCrop.size.height
        )
        let enlargement = max(
            outputSize.width / sourceCropPixels.width,
            outputSize.height / sourceCropPixels.height
        )

        // A wide normalized aspect can hit the frame edge before reaching the
        // nominal height floor. This is still a hard geometric zoom limit.
        let cropAspect = requestedCrop.size.width / requestedCrop.size.height
        let smallestLegalHeight = min(floor.minCropHeightFraction, min(1, 1 / cropAspect))
        let isHardZoomLimited = legalCrop.size.height <= smallestLegalHeight + 0.000001
        var reasons: Set<Reason> = enlargement > 1 + 0.000001
            ? [.enlargedImage] : [.nativeOrDownsampled]
        if isHardZoomLimited { reasons.insert(.hardZoomBound) }

        return FramingCapability(
            legalCrop: legalCrop,
            sourceCropPixels: sourceCropPixels,
            outputPixels: outputSize,
            enlargement: enlargement,
            isHardZoomLimited: isHardZoomLimited,
            reasons: reasons
        )
    }
}
