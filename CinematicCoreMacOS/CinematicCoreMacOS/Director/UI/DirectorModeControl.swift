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

/// Works with any controller: the live Director (B-03) or the gallery fake.
/// The view keeps a refusal itself, from the result the controller returns,
/// so a real controller's refusal is always shown and the level never changes.
struct DirectorModeControl<Controller: DirectorConsoleControlling & ObservableObject>: View {
    @ObservedObject var controller: Controller
    /// The gallery's live control owns the shortcut. Snapshot cards leave it off
    /// so a stack of cards does not register the key more than once.
    var ownsShortcut: Bool
    @State private var refusal: String?

    init(controller: Controller, ownsShortcut: Bool = true, refusal: String? = nil) {
        self.controller = controller
        self.ownsShortcut = ownsShortcut
        _refusal = State(initialValue: refusal)
    }

    private var section: NextShotStatus.DirectorSection { controller.directorSection }
    /// Chip and toggle wording shared with the C-01 gallery.
    private var presentation: DirectorGalleryPresentation { DirectorGalleryPresentation(section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeRow
            handRow
            if let refusal {
                Text(refusal)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsoleStyle.amber)
                    .accessibilityLabel(refusal)
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
            ForEach(presentation.modeChips, id: \.level) { chip in
                modeButton(chip)
            }
        }
    }

    private func modeButton(_ chip: DirectorGalleryPresentation.ModeChip) -> some View {
        let allowed = chip.unqualifiedCaption == nil
        return Button {
            show(controller.setLevel(chip.level))
        } label: {
            VStack(spacing: 2) {
                Text(chip.title)
                    .font(.system(size: 13, weight: chip.selected ? .semibold : .regular))
                if let caption = chip.unqualifiedCaption {
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
                    .fill(chip.selected ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(chip.selected ? ConsoleStyle.previewGreen : ConsoleStyle.neutralBorder,
                                  lineWidth: chip.selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityAddTraits(chip.selected ? .isSelected : [])
    }

    /// Show a refusal; clear it after an accepted change.
    private func show(_ result: DirectorControlResult) {
        switch result {
        case .accepted: refusal = nil
        case .refused(let message): refusal = message
        }
    }

    private var handRow: some View {
        HStack(spacing: 0) {
            handSegment(presentation.handControl.manualTitle, selected: presentation.handControl.manualSelected) {
                controller.takeOver()
                refusal = nil
            }
            handSegment(presentation.handControl.handTitle, selected: !presentation.handControl.manualSelected) {
                show(controller.handToAlfie())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.handControl.accessibilityLabel)
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
            refusal = nil
        } else {
            show(controller.handToAlfie())
        }
    }
}
