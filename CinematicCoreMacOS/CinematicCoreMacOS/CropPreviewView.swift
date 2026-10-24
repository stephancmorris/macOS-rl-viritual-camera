//
//  CropPreviewView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//

import SwiftUI
import CoreVideo

/// Edge-to-edge dual-feed pane: wide stage on the left, broadcast crop on the right.
struct CropPreviewView: View {
    /// Both panes display their frame's backing IOSurface directly (zero-copy),
    /// so they take `CVPixelBuffer`s rather than CIImages.
    let originalFrame: CVPixelBuffer?
    let croppedFrame: CVPixelBuffer?
    let detectedPersons: [PersonDetector.DetectedPerson]
    let showDetections: Bool
    let cropRect: CropEngine.CropRect?
    let activeTargetID: UUID?
    let manualLockedTargetID: UUID?
    let acquiringTargetID: UUID?
    let trackedSubjectRect: CGRect?
    let isRecovering: Bool
    var isZoomLimited: Bool = false
    var steadyBand: ShotComposer.SteadyBand? = nil
    let framingTitle: String
    var onSelectPerson: ((UUID) -> Void)? = nil
    var onTapPoint: ((CGPoint) -> Void)? = nil
    var onHoldPoint: ((CGPoint) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            CameraPreviewView(
                pixelBuffer: originalFrame,
                detectedPersons: detectedPersons,
                showDetections: showDetections,
                activeTargetID: activeTargetID,
                manualLockedTargetID: manualLockedTargetID,
                acquiringTargetID: acquiringTargetID,
                trackedSubjectRect: trackedSubjectRect,
                onSelectPerson: onSelectPerson,
                onTapPoint: onTapPoint,
                onHoldPoint: onHoldPoint,
                cropIndicator: cropRect,
                isRecovering: isRecovering,
                isZoomLimited: isZoomLimited,
                steadyBand: steadyBand,
                framingTitle: framingTitle,
                aspectFill: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            // Program pane: zero-copy IOSurface display of the crop output.
            PixelBufferPreviewView(pixelBuffer: croppedFrame, aspectFill: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
