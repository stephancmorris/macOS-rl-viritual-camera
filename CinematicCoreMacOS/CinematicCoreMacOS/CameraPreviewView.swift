//
//  CameraPreviewView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import SwiftUI
import CoreImage
import AppKit
import CoreVideo
import CoreGraphics

/// SwiftUI view that displays the live camera feed with detection overlay
struct CameraPreviewView: View {
    /// Backing pixel buffer for the wide pane, displayed via a zero-copy
    /// IOSurface layer (see `PixelBufferPreviewView`). Overlay/tap math reads
    /// the frame's pixel dimensions straight off this buffer.
    let pixelBuffer: CVPixelBuffer?
    let detectedPersons: [PersonDetector.DetectedPerson]
    let showDetections: Bool
    let activeTargetID: UUID?
    let manualLockedTargetID: UUID?
    var acquiringTargetID: UUID? = nil
    var trackedSubjectRect: CGRect? = nil
    var onSelectPerson: ((UUID) -> Void)? = nil
    var onTapPoint: ((CGPoint) -> Void)? = nil
    var cropIndicator: CropEngine.CropRect? = nil
    var isRecovering: Bool = false
    var isZoomLimited: Bool = false
    /// Steady Following guide band. Non-nil ⇔ the composer is holding; drives
    /// the two yellow guide lines. Nil hides them.
    var steadyBand: ShotComposer.SteadyBand? = nil
    var framingTitle: String = "Wide"
    var aspectFill: Bool = false

    var body: some View {
        GeometryReader { geometry in
            if let pixelBuffer = pixelBuffer {
                // Pixel dimensions of the source frame; drives all overlay and
                // tap-to-select coordinate math (formerly `image.extent.size`).
                let imageSize = CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
                ZStack {
                    // Zero-copy IOSurface display (already black-backed).
                    PixelBufferPreviewView(pixelBuffer: pixelBuffer, aspectFill: aspectFill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    if showDetections {
                        DetectionOverlayView(
                            detectedPersons: detectedPersons,
                            imageSize: imageSize,
                            activeTargetID: activeTargetID,
                            manualLockedTargetID: manualLockedTargetID,
                            acquiringTargetID: acquiringTargetID,
                            trackedSubjectRect: trackedSubjectRect,
                            isRecovering: isRecovering,
                            framingTitle: framingTitle,
                            onSelectPerson: onSelectPerson
                        )
                    }

                    SteadyBandOverlayView(steadyBand: steadyBand, imageSize: imageSize)
                        .allowsHitTesting(false)

                    if let cropRect = cropIndicator {
                        CropIndicatorView(
                            cropRect: cropRect,
                            imageSize: imageSize,
                            framingTitle: framingTitle,
                            isRecovering: isRecovering,
                            isZoomLimited: isZoomLimited
                        )
                        .allowsHitTesting(false)
                    }

                    if onTapPoint != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let viewSize = geometry.size
                                let scale = aspectFill
                                    ? max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
                                    : min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
                                let displayWidth = imageSize.width * scale
                                let displayHeight = imageSize.height * scale
                                let offsetX = (viewSize.width - displayWidth) / 2
                                let offsetY = (viewSize.height - displayHeight) / 2

                                let x = (location.x - offsetX) / displayWidth
                                let y = 1.0 - ((location.y - offsetY) / displayHeight)

                                if x >= 0 && x <= 1 && y >= 0 && y <= 1 {
                                    onTapPoint?(CGPoint(x: x, y: y))
                                }
                            }
                    }
                }
            } else {
                Color.black
            }
        }
    }
}

extension Image {
    /// Single shared CIContext for the CIImage display path. Hoisted to a
    /// `static let` so it is created once, not per SwiftUI render — the old
    /// per-call `CIContext()` was a major cost on the frame thread. Retained
    /// only for lower-priority callers that still render a CIImage; the two
    /// main panes now use the zero-copy `PixelBufferPreviewView` instead.
    private static let sharedDisplayContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Helper initializer for CIImage
    init(decorative ciImage: CIImage, scale: CGFloat, orientation: Image.Orientation = .up) {
        // Convert CIImage to CGImage for SwiftUI display
        if let cgImage = Image.sharedDisplayContext.createCGImage(ciImage, from: ciImage.extent) {
            self.init(decorative: cgImage, scale: scale, orientation: orientation)
        } else {
            // Fallback to a system image if conversion fails
            self.init(systemName: "exclamationmark.triangle")
        }
    }
}

#Preview {
    CameraPreviewView(
        pixelBuffer: nil,
        detectedPersons: [],
        showDetections: true,
        activeTargetID: nil,
        manualLockedTargetID: nil,
        trackedSubjectRect: nil
    )
    .frame(width: 800, height: 600)
}
// MARK: - Crop Indicator View (Task 2.2)

/// Draws the active program-crop rectangle as a white hairline overlay,
/// with a top-left chip "PROGRAM CROP · {FRAMING} · {n}%".
struct CropIndicatorView: View {
    let cropRect: CropEngine.CropRect
    let imageSize: CGSize
    let framingTitle: String
    let isRecovering: Bool
    var isZoomLimited: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let imageAspect = imageSize.width / imageSize.height
            let viewAspect = viewSize.width / viewSize.height

            let (scale, offset): (CGFloat, CGSize) = {
                if imageAspect > viewAspect {
                    let s = viewSize.width / imageSize.width
                    return (s, CGSize(width: 0, height: (viewSize.height - imageSize.height * s) / 2))
                } else {
                    let s = viewSize.height / imageSize.height
                    return (s, CGSize(width: (viewSize.width - imageSize.width * s) / 2, height: 0))
                }
            }()

            let cropX = cropRect.origin.x * imageSize.width * scale + offset.width
            let cropY = (1 - cropRect.origin.y - cropRect.size.height) * imageSize.height * scale + offset.height
            let cropWidth = cropRect.size.width * imageSize.width * scale
            let cropHeight = cropRect.size.height * imageSize.height * scale

            let strokeColor = isRecovering
                ? Color(red: 1.0, green: 0.72, blue: 0.24)
                : Color.white.opacity(0.98)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(strokeColor, lineWidth: 1.5)
                    .frame(width: cropWidth, height: cropHeight)
                    .position(x: cropX + cropWidth / 2, y: cropY + cropHeight / 2)

                Text(chipLabel)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(strokeColor))
                    .position(
                        x: cropX + chipPosition(width: cropWidth) / 2 + 6,
                        y: max(14, cropY - 12)
                    )
            }
        }
    }

    private var percentLabel: String {
        let p = Int(round(cropRect.size.width * 100))
        return "\(p)%"
    }

    /// "ZOOM LIMITED" tells the operator the requested preset is tighter than
    /// the source resolution allows (CropEngine quality floor).
    private var chipLabel: String {
        var label = "PROGRAM CROP · \(framingTitle.uppercased()) · \(percentLabel)"
        if isZoomLimited {
            label += " · ZOOM LIMITED"
        }
        return label
    }

    private func chipPosition(width: CGFloat) -> CGFloat {
        // Best-effort approximation matching the detection chip
        return CGFloat(chipLabel.count) * 6.5 + 16
    }
}

// MARK: - Steady Following Overlay (Issue 4)

/// Draws the two yellow "Steady Following" guide lines. The speaker can move
/// between the lines before the camera re-centers. Rendered only while the
/// composer is holding (`steadyBand != nil`); fades in/out on that transition.
///
/// Uses the same X-only aspect-fit transform as `CropIndicatorView` (scale +
/// centering offset). The lines are vertical and span the displayed image
/// height, so there is no Y-flip — only the horizontal position matters.
struct SteadyBandOverlayView: View {
    let steadyBand: ShotComposer.SteadyBand?
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let imageAspect = imageSize.width / imageSize.height
            let viewAspect = viewSize.width / viewSize.height

            let (scale, offset): (CGFloat, CGSize) = {
                if imageAspect > viewAspect {
                    let s = viewSize.width / imageSize.width
                    return (s, CGSize(width: 0, height: (viewSize.height - imageSize.height * s) / 2))
                } else {
                    let s = viewSize.height / imageSize.height
                    return (s, CGSize(width: (viewSize.width - imageSize.width * s) / 2, height: 0))
                }
            }()

            // Displayed image bounds (the lines span the full image height).
            let displayedHeight = imageSize.height * scale
            let lineTop = offset.height
            let lineHeight = displayedHeight

            ZStack(alignment: .topLeading) {
                if let band = steadyBand {
                    let halfWidth = band.width / 2.0
                    let leftEdge = band.centerX - halfWidth
                    let rightEdge = band.centerX + halfWidth

                    // Skip an edge that falls off the frame.
                    if leftEdge >= 0 && leftEdge <= 1 {
                        guideLine(atNormalizedX: leftEdge, scale: scale, offset: offset,
                                  top: lineTop, height: lineHeight)
                    }
                    if rightEdge >= 0 && rightEdge <= 1 {
                        guideLine(atNormalizedX: rightEdge, scale: scale, offset: offset,
                                  top: lineTop, height: lineHeight)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: steadyBand)
        }
    }

    @ViewBuilder
    private func guideLine(
        atNormalizedX normalizedX: CGFloat,
        scale: CGFloat,
        offset: CGSize,
        top: CGFloat,
        height: CGFloat
    ) -> some View {
        let x = normalizedX * imageSize.width * scale + offset.width
        Rectangle()
            .fill(Color.yellow.opacity(0.8))
            .frame(width: 1.5, height: height)
            .position(x: x, y: top + height / 2)
    }
}
