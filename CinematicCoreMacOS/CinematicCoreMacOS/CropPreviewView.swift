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
    let showDetections: Bool
    let cropRect: CropEngine.CropRect?
    let activeTargetID: UUID?
    let manualLockedTargetID: UUID?
    let trackedSubjectRect: CGRect?
    var onSelectPerson: ((UUID) -> Void)? = nil

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 16) {
                LiquidPreviewCard(
                    title: "Input · Wide",
                    subtitle: "Stage overview with operator overlays · tap a subject to lock",
                    accent: .mint
                ) {
                    CameraPreviewView(
                        image: originalFrame,
                        detectedPersons: detectedPersons,
                        showDetections: showDetections,
                        activeTargetID: activeTargetID,
                        manualLockedTargetID: manualLockedTargetID,
                        trackedSubjectRect: trackedSubjectRect,
                        onSelectPerson: onSelectPerson,
                        cropIndicator: cropRect
                    )
                }

                LiquidPreviewCard(
                    title: "Program · Output",
                    subtitle: "Processed switcher feed",
                    accent: .cyan
                ) {
                    ZStack {
                        Color.black

                        if let cropped = croppedFrame {
                            Image(decorative: cropped, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white.opacity(0.52))
                                Text("Program Output Unavailable")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("Enable the crop pipeline to generate the broadcast frame.")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Settings panel for the crop engine
struct CropSettingsView: View {
    @ObservedObject var cropEngine: CropEngine
    @ObservedObject var cameraManager: CameraManager

    private var resolutionOptions: [(String, CGSize)] {
        switch cameraManager.shotComposer.config.frameProfile {
        case .livestream:
            return [
                ("1920 × 1080 (Full HD)", CGSize(width: 1920, height: 1080)),
                ("1280 × 720 (HD)", CGSize(width: 1280, height: 720)),
                ("3840 × 2160 (4K)", CGSize(width: 3840, height: 2160))
            ]
        case .portrait:
            return [
                ("1080 × 1920 (Vertical HD)", CGSize(width: 1080, height: 1920)),
                ("720 × 1280 (Vertical SD)", CGSize(width: 720, height: 1280)),
                ("2160 × 3840 (Vertical 4K)", CGSize(width: 2160, height: 3840))
            ]
        }
    }
    
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

                    Text(cameraManager.shotComposer.config.frameProfile.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if cameraManager.shotComposer.config.frameProfile == .livestream {
                        LabeledContent("MVP Output", value: "1920 × 1080 (Locked)")
                            .font(.caption)
                    } else {
                        Picker("Resolution", selection: $cropEngine.config.outputSize) {
                            ForEach(resolutionOptions, id: \.0) { option in
                                Text(option.0).tag(option.1)
                            }
                        }
                        .pickerStyle(.menu)
                    }
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
