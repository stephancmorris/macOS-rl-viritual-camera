//
//  DetectionOverlayView.swift
//  CinematicCoreMacOS
//
//  Hairline subject rectangles with corner ticks. Three states:
//   - idle  → cyan
//   - locked → white, with PROGRAM CROP chip top-left
//   - recovering → amber, pulsing
//

import SwiftUI

struct DetectionOverlayView: View {
    let detectedPersons: [PersonDetector.DetectedPerson]
    let imageSize: CGSize
    let activeTargetID: UUID?
    let manualLockedTargetID: UUID?
    let trackedSubjectRect: CGRect?
    let isRecovering: Bool
    let framingTitle: String
    var onSelectPerson: ((UUID) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(detectedPersons) { person in
                    let usesTrackedRect = person.id == activeTargetID || person.id == manualLockedTargetID
                    BoundingBoxView(
                        person: person,
                        displayBoundingBox: usesTrackedRect
                            ? (trackedSubjectRect ?? person.boundingBox)
                            : person.boundingBox,
                        imageSize: imageSize,
                        viewSize: geometry.size,
                        isLocked: person.id == manualLockedTargetID,
                        isActive: person.id == activeTargetID,
                        isRecovering: isRecovering && (person.id == activeTargetID || person.id == manualLockedTargetID),
                        framingTitle: framingTitle,
                        onSelect: onSelectPerson
                    )
                }
            }
        }
    }
}

// MARK: - BoundingBoxView

struct BoundingBoxView: View {
    let person: PersonDetector.DetectedPerson
    let displayBoundingBox: CGRect
    let imageSize: CGSize
    let viewSize: CGSize
    let isLocked: Bool
    let isActive: Bool
    let isRecovering: Bool
    let framingTitle: String
    var onSelect: ((UUID) -> Void)?

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        let rect = calculateDisplayRect()
        let style = currentStyle

        ZStack(alignment: .topLeading) {
            // Hairline rectangle
            Rectangle()
                .stroke(style.color.opacity(style.isPulsing ? pulseOpacity : 1.0), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner ticks (8pt L-shapes)
            ForEach(Corner.allCases, id: \.self) { corner in
                CornerTick(corner: corner, color: style.color)
                    .frame(width: 12, height: 12)
                    .position(cornerPoint(corner, rect: rect))
            }

            // Label chip (top-left of rect)
            label(style: style)
                .position(
                    x: rect.minX + chipWidth(style.label) / 2 + 6,
                    y: max(14, rect.minY - 12)
                )

            // Hit target
            Rectangle()
                .fill(Color.clear)
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .position(x: rect.midX, y: rect.midY)
                .onTapGesture {
                    onSelect?(person.id)
                }
        }
        .onAppear {
            if style.isPulsing {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.45
                }
            }
        }
        .onChange(of: isRecovering) { _, recovering in
            if recovering {
                pulseOpacity = 1.0
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.45
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pulseOpacity = 1.0
                }
            }
        }
    }

    private func label(style: BoxStyle) -> some View {
        Text(style.label)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(style.color)
            )
    }

    private func chipWidth(_ text: String) -> CGFloat {
        // Rough approximation: 9.5pt monospace ≈ 6.5pt per glyph + 16pt padding
        CGFloat(text.count) * 6.5 + 16
    }

    private var currentStyle: BoxStyle {
        if isRecovering {
            return BoxStyle(
                color: Color(red: 1.0, green: 0.72, blue: 0.24),
                label: "RECOVERING · \(Int(person.confidence * 100))%",
                isPulsing: true
            )
        }
        if isLocked || isActive {
            return BoxStyle(
                color: Color.white.opacity(0.98),
                label: "PROGRAM CROP · \(framingTitle.uppercased()) · \(Int(person.confidence * 100))%",
                isPulsing: false
            )
        }
        return BoxStyle(
            color: Color(red: 0.47, green: 0.86, blue: 1.0),
            label: "PERSON · \(Int(person.confidence * 100))%",
            isPulsing: false
        )
    }

    private struct BoxStyle {
        let color: Color
        let label: String
        let isPulsing: Bool
    }

    // MARK: - Geometry

    private func calculateDisplayRect() -> CGRect {
        let pixelRect = CGRect(
            x: displayBoundingBox.origin.x * imageSize.width,
            y: (1 - displayBoundingBox.origin.y - displayBoundingBox.height) * imageSize.height,
            width: displayBoundingBox.width * imageSize.width,
            height: displayBoundingBox.height * imageSize.height
        )
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale
        let offsetX = (viewSize.width - displayWidth) / 2
        let offsetY = (viewSize.height - displayHeight) / 2
        return CGRect(
            x: pixelRect.origin.x * scale + offsetX,
            y: pixelRect.origin.y * scale + offsetY,
            width: pixelRect.width * scale,
            height: pixelRect.height * scale
        )
    }

    private func cornerPoint(_ corner: Corner, rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

private struct CornerTick: View {
    let corner: Corner
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let arm: CGFloat = 8
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: arm))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: size.width - arm, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: arm))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: size.height - arm))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: arm, y: size.height))
            case .bottomRight:
                path.move(to: CGPoint(x: size.width - arm, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height - arm))
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.8)
        }
    }
}

#Preview {
    let mockPersons = [
        PersonDetector.DetectedPerson(
            id: UUID(),
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.6),
            confidence: 0.95,
            timestamp: 0,
            poseKeypoints: nil
        )
    ]
    return DetectionOverlayView(
        detectedPersons: mockPersons,
        imageSize: CGSize(width: 1920, height: 1080),
        activeTargetID: mockPersons.first?.id,
        manualLockedTargetID: mockPersons.first?.id,
        trackedSubjectRect: mockPersons.first?.boundingBox,
        isRecovering: false,
        framingTitle: "Waist Up"
    )
    .frame(width: 800, height: 600)
    .background(Color.black)
}
