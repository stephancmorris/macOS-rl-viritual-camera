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
    var cropIndicator: CropEngine.CropRect? = nil  // Task 2.2: Show crop region
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                ZStack {
                    // Camera feed
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    // Detection overlay
                    if showDetections {
                        DetectionOverlayView(
                            detectedPersons: detectedPersons,
                            imageSize: image.extent.size,
                            activeTargetID: activeTargetID,
                            manualLockedTargetID: manualLockedTargetID,
                            trackedSubjectRect: trackedSubjectRect,
                            onSelectPerson: onSelectPerson
                        )
                    }
                    
                    // Task 2.2: Crop region indicator
                    if let cropRect = cropIndicator {
                        CropIndicatorView(
                            cropRect: cropRect,
                            imageSize: image.extent.size
                        )
                        .allowsHitTesting(false)
                    }
                }
            } else {
                // Placeholder when no camera feed
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.black,
                            Color(red: 0.06, green: 0.08, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 42))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("No Camera Feed")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                        Text("Connect a source and start capture to light up the live glass console.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
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

/// Draws a rectangle showing the active crop region
struct CropIndicatorView: View {
    let cropRect: CropEngine.CropRect
    let imageSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            
            // Calculate aspect-fit scaling
            let imageAspect = imageSize.width / imageSize.height
            let viewAspect = viewSize.width / viewSize.height
            
            let (scale, offset): (CGFloat, CGSize) = {
                if imageAspect > viewAspect {
                    // Image is wider - fit to width
                    let scale = viewSize.width / imageSize.width
                    let scaledHeight = imageSize.height * scale
                    return (scale, CGSize(width: 0, height: (viewSize.height - scaledHeight) / 2))
                } else {
                    // Image is taller - fit to height
                    let scale = viewSize.height / imageSize.height
                    let scaledWidth = imageSize.width * scale
                    return (scale, CGSize(width: (viewSize.width - scaledWidth) / 2, height: 0))
                }
            }()
            
            // Convert normalized crop rect to view coordinates
            // Vision uses bottom-left origin, SwiftUI uses top-left
            let cropX = cropRect.origin.x * imageSize.width * scale + offset.width
            let cropY = (1 - cropRect.origin.y - cropRect.size.height) * imageSize.height * scale + offset.height
            let cropWidth = cropRect.size.width * imageSize.width * scale
            let cropHeight = cropRect.size.height * imageSize.height * scale
            
            // Draw crop indicator
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.red.opacity(0.95), Color.orange.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .frame(width: cropWidth, height: cropHeight)
                .position(
                    x: cropX + cropWidth / 2,
                    y: cropY + cropHeight / 2
                )
                .overlay(
                    // Corner handles
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color.red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 11, height: 11)
                            .shadow(color: .red.opacity(0.45), radius: 6)
                            .position(cornerPosition(index: index, x: cropX, y: cropY, width: cropWidth, height: cropHeight))
                    }
                )
                .overlay(
                    // Label
                    Text("Program Crop")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        )
                        .foregroundStyle(.white.opacity(0.92))
                        .position(
                            x: cropX + cropWidth / 2,
                            y: max(18, cropY - 18)
                        )
                )
        }
    }
    
    private func cornerPosition(index: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: x, y: y) // Top-left
        case 1: return CGPoint(x: x + width, y: y) // Top-right
        case 2: return CGPoint(x: x, y: y + height) // Bottom-left
        case 3: return CGPoint(x: x + width, y: y + height) // Bottom-right
        default: return .zero
        }
    }
}
