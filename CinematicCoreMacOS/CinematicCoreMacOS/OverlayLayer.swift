//
//  OverlayLayer.swift
//  CinematicCoreMacOS
//
//  Floating chrome over the dual-feed background:
//   - top-left identity stack (Alfie, live indicator, source, elapsed)
//   - top-right telemetry (DETECTION, PERSONS, ROUTED)
//   - PROGRAM · ON AIR badge over the right pane
//

import SwiftUI

// MARK: - Identity stack (top-left, over wide pane)

struct IdentityStackOverlay: View {
    @ObservedObject var cameraManager: CameraManager
    let elapsedSeconds: Int
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INPUT · WIDE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.7))

            Text("Alfie")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(.white.opacity(0.96))

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.19, green: 0.82, blue: 0.35))
                    .frame(width: 6, height: 6)
                    .opacity(pulse ? 0.55 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: pulse
                    )

                Text(liveLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 1)
        .onAppear { pulse = true }
    }

    private var liveLine: String {
        let source = (cameraManager.selectedCamera?.name ?? "No source").uppercased()
        return "LIVE · \(source) · \(formatElapsed(elapsedSeconds))"
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Telemetry (top-right)

struct TelemetryOverlay: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            telemetryBlock(
                label: "DETECTION",
                value: detectionValue,
                monospaced: true
            )
            telemetryBlock(
                label: "PERSONS",
                value: "\(cameraManager.personDetector.detectedPersons.count)",
                monospaced: true
            )
            telemetryBlock(
                label: "ROUTED",
                value: cameraManager.programOutput.activeRoute != nil ? "✓" : "—",
                monospaced: false
            )
        }
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 1)
    }

    private var detectionValue: String {
        let ms = cameraManager.personDetector.stats.lastDetectionTime * 1000
        if ms <= 0 { return "—" }
        return String(format: "%.1fms", ms)
    }

    private func telemetryBlock(label: String, value: String, monospaced: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(
                    size: 14,
                    weight: .semibold,
                    design: monospaced ? .monospaced : .rounded
                ))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

// MARK: - PROGRAM · ON AIR badge anchored to the top of the right (program) pane

/// Wraps the badge so it sits ~24pt inside the program (right) pane,
/// regardless of overall window width.
struct ProgramOnAirBadgeAnchor: View {
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left half (wide pane) — empty
                Color.clear.frame(width: geo.size.width / 2)
                // Right half (program pane) — badge sits 24pt from its left edge
                HStack {
                    ProgramOnAirBadge()
                        .padding(.leading, 24)
                        .padding(.top, 24)
                    Spacer()
                }
            }
        }
    }
}

struct ProgramOnAirBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(red: 1.0, green: 0.27, blue: 0.23))
                .frame(width: 7, height: 7)
                .opacity(pulse ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulse
                )

            Text("PROGRAM · ON AIR")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.9))
        }
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 1)
        .onAppear { pulse = true }
    }
}
