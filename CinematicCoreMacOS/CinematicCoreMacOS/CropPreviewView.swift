//
//  CropPreviewView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//  Ticket: GFX-01 - Metal Crop Engine (Preview UI)
//

import SwiftUI

/// Side-by-side preview showing original camera feed and cropped output
struct CropPreviewView: View {
    let originalFrame: CIImage?
    let croppedFrame: CIImage?
    let detectedPersons: [PersonDetector.DetectedPerson]
    let cropRect: CropEngine.CropRect
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                // Original Feed with Crop Indicator
                VStack(spacing: 4) {
                    Text("Source (4K)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    CameraPreviewView(
                        image: originalFrame,
                        detectedPersons: detectedPersons,
                        showDetections: true,
                        cropIndicator: cropRect
                    )
                }
                
                // Cropped Output
                VStack(spacing: 4) {
                    Text("Output (1080p)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ZStack {
                        Color.black
                        
                        if let cropped = croppedFrame {
                            Image(decorative: cropped, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "crop.rotate")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Crop Disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.green, lineWidth: 2)
                    )
                }
            }
            .padding(8)
        }
    }
}

/// Settings panel for the crop engine
struct CropSettingsView: View {
    @ObservedObject var cropEngine: CropEngine
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "crop.rotate")
                Text("Crop Engine Settings")
                    .font(.headline)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Enable/Disable Cropping
            Toggle(isOn: $cameraManager.cropEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Cropping")
                        .font(.subheadline)
                    Text("Apply intelligent crop to video feed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            
            if cameraManager.cropEnabled {
                Divider()
                
                // Output Resolution
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Resolution")
                        .font(.subheadline)
                    
                    Picker("Resolution", selection: $cropEngine.config.outputSize) {
                        Text("1920 × 1080 (Full HD)").tag(CGSize(width: 1920, height: 1080))
                        Text("1280 × 720 (HD)").tag(CGSize(width: 1280, height: 720))
                        Text("3840 × 2160 (4K)").tag(CGSize(width: 3840, height: 2160))
                    }
                    .pickerStyle(.menu)
                }
                
                // Transition Smoothing
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transition Smoothing")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f%%", cropEngine.config.transitionSmoothing * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(cropEngine.config.transitionSmoothing) },
                            set: { cropEngine.config.transitionSmoothing = Float($0) }
                        ),
                        in: 0.05...0.3
                    )
                    
                    HStack {
                        Text("Fast")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Cinematic")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Quality Settings
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $cropEngine.config.useHighQuality) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("High Quality Mode")
                                .font(.subheadline)
                            Text("Better image quality, slightly more GPU usage")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    
                    Toggle(isOn: $cropEngine.config.enableVignette) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cinematic Vignette")
                                .font(.subheadline)
                            Text("Subtle edge darkening for cinematic look")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                
                Divider()
                
                // Statistics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Performance")
                        .font(.subheadline)
                    
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text("Render Time:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f ms", cropEngine.stats.lastRenderTime * 1000))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        
                        GridRow {
                            Text("Average:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f ms", cropEngine.stats.averageRenderTime * 1000))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        
                        GridRow {
                            Text("Frames Rendered:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(cropEngine.stats.totalFramesRendered)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                        
                        GridRow {
                            Text("Interpolating:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(cropEngine.isInterpolating ? Color.green : Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(cropEngine.isInterpolating ? "Yes" : "No")
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Manual Controls
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manual Controls")
                        .font(.subheadline)
                    
                    HStack(spacing: 8) {
                        Button("Reset to Full Frame") {
                            cropEngine.resetToFullFrame()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Jump to Target") {
                            cropEngine.jumpToTarget()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .frame(width: 350)
    }
}

#Preview("Crop Settings") {
    if let cropEngine = CropEngine() {
        CropSettingsView(
            cropEngine: cropEngine,
            cameraManager: CameraManager()
        )
    } else {
        Text("Metal not available")
    }
}
