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
                            imageSize: image.extent.size
                        )
                    }
                    
                    // Task 2.2: Crop region indicator
                    if let cropRect = cropIndicator {
                        CropIndicatorView(
                            cropRect: cropRect,
                            imageSize: image.extent.size
                        )
                    }
                }
            } else {
                // Placeholder when no camera feed
                ZStack {
                    Color.black
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Camera Feed")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Check the Xcode console for camera diagnostics")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
        showDetections: true
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
                .strokeBorder(Color.green, lineWidth: 3)
                .background(Color.green.opacity(0.1))
                .frame(width: cropWidth, height: cropHeight)
                .position(
                    x: cropX + cropWidth / 2,
                    y: cropY + cropHeight / 2
                )
                .overlay(
                    // Corner handles
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .position(cornerPosition(index: index, x: cropX, y: cropY, width: cropWidth, height: cropHeight))
                    }
                )
                .overlay(
                    // Label
                    Text("Output Frame")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                        .position(
                            x: cropX + cropWidth / 2,
                            y: cropY - 16
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

