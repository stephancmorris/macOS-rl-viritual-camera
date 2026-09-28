//
//  NextShotPanel.swift
//  CinematicCoreMacOS
//
//  Two-line panel directly under the Preview pane (600×70 at 1280 pt).
//  Plain words only; freshness age, shot revision and reason codes belong in
//  the inspector. Never renders `NextShotStatus.director` in R2.
//

import SwiftUI

struct NextShotPanel: View {
    let status: NextShotStatus

    private var dotColor: Color {
        switch status.readiness {
        case .ready: return ConsoleStyle.previewGreen
        case .notReady: return ConsoleStyle.amber
        case .editingLive: return ConsoleStyle.programRed
        case .noPreviewCamera: return Color.white.opacity(0.35)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(NextShotStatus.label)
                    .font(ConsoleStyle.label(11))
                    .foregroundStyle(.white.opacity(0.55))
                Text(status.shotLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(status.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ConsoleStyle.neutralFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ConsoleStyle.neutralBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }
}
