//
//  DirectorModeControl.swift
//  CinematicCoreMacOS
//
//  C-02. Manual · Assist · Auto · Backup, and the always-visible
//  Manual / Hand to Alfie toggle. Unqualified levels stay grey.
//  A refusal is shown and does not change the level.
//
//  Shortcut: Command Shift H. It hands control to Alfie, or takes over
//  when Alfie already has it. Esc is left for cancel next cut (C-06).
//  The only other console shortcut today is Command Option Shift S (stop).
//

import SwiftUI

enum DirectorHandShortcut {
    static let key: KeyEquivalent = "h"
    static let modifiers: EventModifiers = [.command, .shift]
    /// Spoken and written name of the shortcut.
    static let title = "Command Shift H"
}

struct DirectorModeControl: View {
    @ObservedObject var controller: FakeDirectorConsole
    /// The gallery's live control owns the shortcut. Snapshot cards leave it off
    /// so a stack of cards does not register the key more than once.
    var ownsShortcut: Bool = true

    private var section: NextShotStatus.DirectorSection { controller.directorSection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeRow
            handRow
            if let message = controller.refusalMessage {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsoleStyle.amber)
                    .accessibilityLabel(message)
            }
            Text(section.statusLine)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityLabel(section.statusLine)
        }
        .padding(16)
        .frame(maxWidth: 720, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ConsoleStyle.neutralFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ConsoleStyle.neutralBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var modeRow: some View {
        HStack(spacing: 8) {
            ForEach(NextShotStatus.DirectorSection.Level.allCases, id: \.self) { level in
                modeButton(level)
            }
        }
    }

    private func modeButton(_ level: NextShotStatus.DirectorSection.Level) -> some View {
        let selected = level == section.level
        let allowed = section.canSelect(level)
        let caption = allowed ? nil : NextShotStatus.DirectorSection.notQualifiedCaption
        let access = selected
            ? "\(level.title), selected"
            : (caption.map { "\(level.title), \($0)" } ?? level.title)
        return Button {
            _ = controller.setLevel(level)
        } label: {
            VStack(spacing: 2) {
                Text(level.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(allowed ? 1 : 0.38))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 88, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? ConsoleStyle.previewGreen : ConsoleStyle.neutralBorder, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(access)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var handRow: some View {
        HStack(spacing: 0) {
            handSegment("Manual", selected: !section.handedToAlfie) {
                controller.takeOver()
            }
            handSegment("Hand to Alfie", selected: section.handedToAlfie) {
                _ = controller.handToAlfie()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.handedToAlfie ? "Hand to Alfie, selected" : "Manual, selected")
        .accessibilityHint("Shortcut \(DirectorHandShortcut.title)")
        .background {
            if ownsShortcut {
                Button(action: toggleHand) { EmptyView() }
                    .keyboardShortcut(DirectorHandShortcut.key, modifiers: DirectorHandShortcut.modifiers)
                    .accessibilityHidden(true)
            }
        }
    }

    private func handSegment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? Color.white.opacity(0.10) : Color.clear)
                .overlay(
                    Rectangle()
                        .strokeBorder(selected ? ConsoleStyle.previewGreen : ConsoleStyle.neutralBorder, lineWidth: selected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "\(title), selected" : title)
    }

    private func toggleHand() {
        if section.handedToAlfie {
            controller.takeOver()
        } else {
            _ = controller.handToAlfie()
        }
    }
}
