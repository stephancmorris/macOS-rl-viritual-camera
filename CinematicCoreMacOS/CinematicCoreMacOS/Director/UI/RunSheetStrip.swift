//
//  RunSheetStrip.swift
//  CinematicCoreMacOS
//
//  C-07. A run sheet changes style context only. Advancement is always an
//  explicit operator action and cannot wrap past the last segment.
//

import SwiftUI

nonisolated enum RunSheetSegmentText {
    static func title(_ segment: RunSheet.Segment) -> String {
        var parts = [segment.type.styleTitle]
        if let name = segment.name, !name.isEmpty { parts.append(name) }
        if let position = segment.positionHint { parts.append(position.title) }
        return parts.joined(separator: " · ")
    }
}

extension RunSheet.PositionHint {
    var title: String {
        switch self {
        case .lectern: "Lectern"
        case .centre: "Centre"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

nonisolated struct RunSheetStripPresentation: Equatable {
    let current: String
    let next: String
    let boundary: String?

    init(sheet: RunSheet) {
        current = sheet.current.map(RunSheetSegmentText.title) ?? "Live event · No run sheet"
        next = sheet.next.map(RunSheetSegmentText.title)
            ?? (sheet.current == nil ? "No segments" : "End of run sheet")
        boundary = sheet.current == nil ? "Add a segment to use a run sheet."
            : (sheet.next == nil ? "Last segment. Advance does not wrap." : nil)
    }
}

enum RunSheetAdvanceShortcut {
    static let key: KeyEquivalent = .return
    static let modifiers: EventModifiers = [.command, .shift]
    static let title = "Command Shift Return"
}

struct RunSheetStrip: View {
    @ObservedObject var editor: RunSheetEditor
    /// Snapshot strips must leave this false. The host also withdraws the
    /// shortcut while an editable name has focus, preserving text input.
    var ownsShortcut = true
    var isEditingText = false

    private var presentation: RunSheetStripPresentation { .init(sheet: editor.sheet) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current: \(presentation.current)")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityLabel("Current: \(presentation.current)")
            Text("Next: \(presentation.next)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Next: \(presentation.next)")
            HStack(spacing: 12) {
                if ownsShortcut && !isEditingText {
                    advanceButton
                        .keyboardShortcut(RunSheetAdvanceShortcut.key, modifiers: RunSheetAdvanceShortcut.modifiers)
                } else {
                    advanceButton
                }
                if let boundary = presentation.boundary {
                    Text(boundary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Shortcut \(RunSheetAdvanceShortcut.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleStyle.neutralFill)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ConsoleStyle.neutralBorder, lineWidth: 1)
        }
    }

    private var advanceButton: some View {
        Button("Advance") { editor.advance() }
            .disabled(!editor.canAdvance)
            .accessibilityLabel("Advance run sheet")
            .accessibilityHint("Moves to the next segment. Never advances automatically or wraps.")
    }
}
