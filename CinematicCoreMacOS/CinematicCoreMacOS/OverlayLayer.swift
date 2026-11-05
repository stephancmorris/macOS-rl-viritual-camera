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

    /// Wall-clock 1.0 s ease pulse for the live dot. Time-derived via
    /// TimelineView instead of a repeatForever animation so it stops dead
    /// when the view leaves the hierarchy and can't stack on re-entry.
    static func statusPulseOpacity(at date: Date, low: Double) -> Double {
        let period = 2.0 // 1.0 s down + 1.0 s back
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / (period / 2) // 0..<2
        let triangle = phase < 1 ? phase : 2 - phase
        let eased = triangle * triangle * (3 - 2 * triangle) // smoothstep
        return 1.0 - (1.0 - low) * eased
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INPUT · WIDE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(AlfieColor.onVideo.secondary)

            Text("Alfie")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(AlfieColor.onVideo.emphasis)

            HStack(spacing: 8) {
                TimelineView(.animation) { timeline in
                    Circle()
                        .fill(AlfieColor.onVideo.live)
                        .frame(width: 6, height: 6)
                        .opacity(Self.statusPulseOpacity(at: timeline.date, low: 0.55))
                }

                Text(liveLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(AlfieColor.onVideo.secondary)
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 1)
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
    @ObservedObject var programOutput: ProgramOutputManager

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            if let progress = cameraManager.shotComposer.acquisitionProgress {
                telemetryBlock(
                    label: "ACQUIRING",
                    value: "\(Int(progress * 100))%",
                    monospaced: true,
                    valueColor: AlfieColor.tracking.acquiring
                )
            } else if cameraManager.tapPending {
                telemetryBlock(
                    label: "SUBJECT",
                    value: "FINDING",
                    monospaced: true,
                    valueColor: AlfieColor.tracking.candidate
                )
            }
            if programOutput.measuredInputFPS > 0 {
                telemetryBlock(
                    label: "IN",
                    value: String(format: "%.1f", programOutput.measuredInputFPS),
                    monospaced: true,
                    valueColor: inputRateColor
                )
            }
            telemetryBlock(
                label: "DETECTION",
                value: detectionValue,
                monospaced: true
            )
            telemetryBlock(
                label: "PERSONS",
                value: "\(cameraManager.personDetector.displayedPersons.count)",
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
        let ms = cameraManager.personDetector.displayedStats.lastDetectionTime * 1000
        if ms <= 0 { return "—" }
        return String(format: "%.1fms", ms)
    }

    /// Amber when the delivered input rate disagrees with the active route's
    /// playout clock — the mismatch that shows up as judder and queue latency.
    private var inputRateColor: Color {
        if let playoutRate = programOutput.activePlayoutFrameRate,
           abs(programOutput.measuredInputFPS - playoutRate) > 0.5 {
            return AlfieColor.onVideo.warning
        }
        return AlfieColor.onVideo.primary
    }

    private func telemetryBlock(
        label: String,
        value: String,
        monospaced: Bool,
        valueColor: Color = AlfieColor.onVideo.primary
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(AlfieColor.onVideo.tertiary)
            Text(value)
                .font(.system(
                    size: 14,
                    weight: .semibold,
                    design: monospaced ? .monospaced : .rounded
                ))
                .foregroundStyle(valueColor)
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
    var body: some View {
        HStack(spacing: 7) {
            // Time-derived pulse (see IdentityStackOverlay.statusPulseOpacity):
            // stops with the view, nothing to arm or stack.
            TimelineView(.animation) { timeline in
                Circle()
                    .fill(AlfieColor.tally.program)
                    .frame(width: 7, height: 7)
                    .opacity(IdentityStackOverlay.statusPulseOpacity(at: timeline.date, low: 0.5))
            }

            Text("PROGRAM · ON AIR")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(AlfieColor.onVideo.primary)
        }
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 1)
    }
}
