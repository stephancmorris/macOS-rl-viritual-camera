//
//  CameraPreviewView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/2/2026.
//

import SwiftUI
import CoreImage
import AppKit

/// SwiftUI view that displays the live camera feed
struct CameraPreviewView: View {
    let image: CIImage?
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
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
    CameraPreviewView(image: nil)
        .frame(width: 800, height: 600)
}
