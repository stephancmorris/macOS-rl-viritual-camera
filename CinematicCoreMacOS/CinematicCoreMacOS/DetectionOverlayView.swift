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

            // Task 2.3: Pose keypoint markers (head and waist)
            if let keypoints = person.poseKeypoints {
                let headPos = keypointToDisplayPoint(keypoints.head)
                let waistPos = keypointToDisplayPoint(keypoints.waist)

                // Head marker (cyan circle)
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                    .position(x: headPos.x, y: headPos.y)

                Text("H")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .position(x: headPos.x + 10, y: headPos.y - 10)

                // Waist marker (orange circle)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                    .position(x: waistPos.x, y: waistPos.y)

                Text("W")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .position(x: waistPos.x + 10, y: waistPos.y - 10)
            }
        }
    }
    
    /// Convert a normalized Vision keypoint (0-1, bottom-left origin) to display coordinates
    private func keypointToDisplayPoint(_ point: CGPoint) -> CGPoint {
        // Vision: bottom-left origin. Convert to pixel coords (top-left origin).
        let pixelX = point.x * imageSize.width
        let pixelY = (1 - point.y) * imageSize.height

        // Scale to view (aspect fit)
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale
        let offsetX = (viewSize.width - displayWidth) / 2
        let offsetY = (viewSize.height - displayHeight) / 2

        return CGPoint(
            x: (pixelX * scale) + offsetX,
            y: (pixelY * scale) + offsetY
        )
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
            timestamp: 0,
            poseKeypoints: PersonDetector.PoseKeypoints(
                head: CGPoint(x: 0.5, y: 0.8),
                waist: CGPoint(x: 0.5, y: 0.4),
                confidence: 0.9
            )
        )
    ]

    DetectionOverlayView(
        detectedPersons: mockPersons,
        imageSize: CGSize(width: 1920, height: 1080)
    )
    .frame(width: 800, height: 600)
    .background(Color.black)
}
