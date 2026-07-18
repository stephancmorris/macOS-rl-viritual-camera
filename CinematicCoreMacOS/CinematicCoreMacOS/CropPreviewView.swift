//
//  CropPreviewView.swift
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//  Ticket: GFX-01 - Metal Crop Engine (Preview UI)
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
        Form {
            Section("Output Resolution") {
                if cameraManager.shotComposer.config.frameProfile == .livestream {
                    LabeledContent("Output", value: "1920 × 1080 (Locked)")
                } else {
                    Picker("Resolution", selection: $cropEngine.config.outputSize) {
                        ForEach(resolutionOptions, id: \.0) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text(cameraManager.shotComposer.config.frameProfile.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transition Smoothing") {
                HStack {
                    Text("Smoothing")
                    Spacer()
                    Text(String(format: "%.0f%%", cropEngine.config.transitionSmoothing * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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

            Section("Quality") {
                Toggle(isOn: $cropEngine.config.useHighQuality) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("High Quality Mode")
                        Text("Better image quality, slightly more GPU usage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $cropEngine.config.enableVignette) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cinematic Vignette")
                        Text("Subtle edge darkening for cinematic look")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Performance") {
                LabeledContent(
                    "Render Time",
                    value: String(format: "%.2f ms", cropEngine.stats.lastRenderTime * 1000)
                )
                LabeledContent(
                    "Average",
                    value: String(format: "%.2f ms", cropEngine.stats.averageRenderTime * 1000)
                )
                LabeledContent(
                    "Frames Rendered",
                    value: "\(cropEngine.stats.totalFramesRendered)"
                )
                LabeledContent("Interpolating") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(cropEngine.isInterpolating ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(cropEngine.isInterpolating ? "Yes" : "No")
                    }
                }
            }

            Section("Manual Controls") {
                HStack(spacing: 8) {
                    Button("Reset to Full Frame") {
                        cropEngine.resetToFullFrame(
                            aspect: cameraManager.shotComposer.normalizedAspect
                        )
                    }
                    .buttonStyle(.bordered)

                    Button("Jump to Target") {
                        cropEngine.jumpToTarget()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 500)
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
