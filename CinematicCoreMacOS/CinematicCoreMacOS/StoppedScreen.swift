//
//  StoppedScreen.swift
//  CinematicCoreMacOS
//
//  Replaces the dual feed when the session is stopped.
//

import SwiftUI

struct StoppedScreen: View {
    let lastSessionEndedAt: Date?
    var onStart: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Text("SESSION STOPPED")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.5))

                Text("Alfie is standing by.")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button(action: onStart) {
                    Text("Start session")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.92))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.45), radius: 24, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(40)
        }
    }

    private var subtitle: String {
        if let lastSessionEndedAt {
            return "Last session ended \(Self.timeFormatter.string(from: lastSessionEndedAt)). Virtual camera released."
        }
        return "Virtual camera released."
    }
}
