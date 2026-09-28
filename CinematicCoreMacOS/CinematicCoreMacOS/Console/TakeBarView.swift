//
//  TakeBarView.swift
//  CinematicCoreMacOS
//
//  TAKE and EDIT LIVE, directly under the Program pane (600×70 at 1280 pt).
//  Appearance comes only from TakeAvailability, i.e. the router's committed
//  roles: after a click the bar keeps showing the old roles until commit.
//
//  TAKE is never `.disabled`: an ineligible click must still reach the
//  coordinator (which refuses it and records why) and must visibly repeat the
//  refusal reason. There is no queued or armed cut, and no keyboard shortcut.
//

import AppKit
import SwiftUI

struct TakeBarView: View {
    let availability: TakeAvailability
    var onTake: () -> Void = {}
    var onSetEditLive: (Bool) -> Void = { _ in }

    static var editLiveWidth: CGFloat { 180 }
    static var spacing: CGFloat { 12 }

    /// Bumped on every refused click to re-flash the reason.
    @State private var refusalFlash = 0

    var body: some View {
        HStack(spacing: Self.spacing) {
            takeButton
            editLiveButton
                .frame(width: Self.editLiveWidth)
        }
    }

    // MARK: - TAKE

    private var takeButton: some View {
        Button(action: takeTapped) {
            VStack(spacing: 3) {
                Text("TAKE")
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(2)
                Text(availability.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(refusalFlash.isMultiple(of: 2) ? 1 : 0.55)
                    .animation(.easeInOut(duration: 0.18).repeatCount(3, autoreverses: true),
                               value: refusalFlash)
            }
            .foregroundStyle(availability.isEligible ? Color.white : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(availability.isEligible ? ConsoleStyle.programRed : ConsoleStyle.disabledFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(availability.takeAccessibilityLabel)
        .accessibilityValue(availability.isEligible ? "Ready" : availability.subtitle)
    }

    private func takeTapped() {
        onTake()
        guard !availability.isEligible else { return }
        refusalFlash += 1
        if let reason = availability.reasonText {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: reason, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    // MARK: - EDIT LIVE

    private var editLiveButton: some View {
        Button {
            onSetEditLive(!availability.editLive)
        } label: {
            Text(availability.editLiveTitle)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(availability.editLive ? Color.white : ConsoleStyle.programRed)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(availability.editLive ? ConsoleStyle.programRed : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ConsoleStyle.programRed, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(availability.editLiveAccessibilityLabel)
        .accessibilityValue(availability.editLive ? "On" : "Off")
    }
}
