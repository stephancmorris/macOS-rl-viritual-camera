//
//  DetectionOverlayView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/4/2026.
//

import SwiftUI

/// Overlay view that draws bounding boxes for detected persons
struct DetectionOverlayView: View {
    let detectedPersons: [PersonDetector.DetectedPerson]
    let imageSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(detectedPersons) { person in
                    BoundingBoxView(
                        person: person,
                        imageSize: imageSize,
                        viewSize: geometry.size
                    )
                }
            }
        }
    }
}

/// Individual bounding box for a detected person
struct BoundingBoxView: View {
    let person: PersonDetector.DetectedPerson
    let imageSize: CGSize
    let viewSize: CGSize
    
    var body: some View {
        let rect = calculateDisplayRect()
        
        ZStack(alignment: .topLeading) {
            // Bounding box
            Rectangle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            
            // Confidence label
            Text(String(format: "%.0f%%", person.confidence * 100))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.8))
                .cornerRadius(4)
                .position(x: rect.minX + 40, y: rect.minY + 12)
        }
    }
    
    private func calculateDisplayRect() -> CGRect {
        // Get pixel coordinates
        let pixelRect = person.pixelBoundingBox(imageSize: imageSize)
        
        // Calculate scale factor to fit image in view
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        
        // Calculate image display size (aspect fit)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale
        
        // Calculate offset to center image
        let offsetX = (viewSize.width - displayWidth) / 2
        let offsetY = (viewSize.height - displayHeight) / 2
        
        // Transform bounding box
        return CGRect(
            x: (pixelRect.origin.x * scale) + offsetX,
            y: (pixelRect.origin.y * scale) + offsetY,
            width: pixelRect.width * scale,
            height: pixelRect.height * scale
        )
    }
}

#Preview {
    // Mock data for preview
    let mockPersons = [
        PersonDetector.DetectedPerson(
            id: UUID(),
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.6),
            confidence: 0.95,
            timestamp: 0
        )
    ]
    
    DetectionOverlayView(
        detectedPersons: mockPersons,
        imageSize: CGSize(width: 1920, height: 1080)
    )
    .frame(width: 800, height: 600)
    .background(Color.black)
}
