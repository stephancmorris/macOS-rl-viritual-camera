//
//  NextShotPanel.swift
//  CinematicCoreMacOS
//
//  Panel directly under the Preview pane (600×70 at 1280 pt).
//  Two lines for the next shot. When a director section is present, a third
//  line adds the prepared shot and Alfie's plain status. The bar stays 70 pt.
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

    /// Prepared shot and plain status on one truncating line. Nil when Alfie is not reporting.
    static func directorLine(_ section: NextShotStatus.DirectorSection) -> String {
        "\(section.preparedLine) · \(section.statusLine)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: status.director == nil ? 6 : 4) {
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
            if let director = status.director {
                Text(Self.directorLine(director))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
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
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let director = status.director else { return status.accessibilityLabel }
        return status.accessibilityLabel + ". " + Self.directorLine(director)
    }
}

extension NextShotStatus {
    /// Same next-shot lines, with the director section the console was given.
    func withDirector(_ section: DirectorSection?) -> NextShotStatus {
        NextShotStatus(
            preview: preview,
            shotLine: shotLine,
            readiness: readiness,
            statusText: statusText,
            reasonText: reasonText,
            director: section)
    }
}
