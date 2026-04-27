//
//  CameraPreviewView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import SwiftUI
import CoreImage
import AppKit

/// SwiftUI view that displays the live camera feed with detection overlay
struct CameraPreviewView: View {
    let image: CIImage?
    let detectedPersons: [PersonDetector.DetectedPerson]
    let showDetections: Bool
    let activeTargetID: UUID?
    let manualLockedTargetID: UUID?
    var trackedSubjectRect: CGRect? = nil
    var onSelectPerson: ((UUID) -> Void)? = nil
    var cropIndicator: CropEngine.CropRect? = nil
    var isRecovering: Bool = false
    var framingTitle: String = "Wide"
    var aspectFill: Bool = false

    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                ZStack {
                    Color.black

                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: aspectFill ? .fill : .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    if showDetections {
                        DetectionOverlayView(
                            detectedPersons: detectedPersons,
                            imageSize: image.extent.size,
                            activeTargetID: activeTargetID,
                            manualLockedTargetID: manualLockedTargetID,
                            trackedSubjectRect: trackedSubjectRect,
                            isRecovering: isRecovering,
                            framingTitle: framingTitle,
                            onSelectPerson: onSelectPerson
                        )
                    }

                    if let cropRect = cropIndicator {
                        CropIndicatorView(
                            cropRect: cropRect,
                            imageSize: image.extent.size,
                            framingTitle: framingTitle,
                            isRecovering: isRecovering
                        )
                        .allowsHitTesting(false)
                    }
                }
            } else {
                Color.black
            }
        }
    }
}

extension Image {
    /// Helper initializer for CIImage
    init(decorative ciImage: CIImage, scale: CGFloat, orientation: Image.Orientation = .up) {
        // Convert CIImage to CGImage for SwiftUI display
        let context = CIContext(options: [.useSoftwareRenderer: false])
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            self.init(decorative: cgImage, scale: scale, orientation: orientation)
        } else {
            // Fallback to a system image if conversion fails
            self.init(systemName: "exclamationmark.triangle")
        }
    }
}

#Preview {
    CameraPreviewView(
        image: nil,
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

                Text("PROGRAM CROP · \(framingTitle.uppercased()) · \(percentLabel)")
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

    private func chipPosition(width: CGFloat) -> CGFloat {
        // Best-effort approximation matching the detection chip
        let label = "PROGRAM CROP · \(framingTitle.uppercased()) · \(percentLabel)"
        return CGFloat(label.count) * 6.5 + 16
    }
}
