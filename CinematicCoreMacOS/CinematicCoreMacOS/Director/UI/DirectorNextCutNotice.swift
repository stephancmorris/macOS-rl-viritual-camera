//
//  DirectorNextCutNotice.swift
//  CinematicCoreMacOS
//
//  C-06. Shows the status model's next-cut line. Esc calls cancelNextCut
//  when that cut can be cancelled. The countdown length is whatever the
//  section was given; this view does not choose one.
//

import SwiftUI

struct DirectorNextCutNotice: View {
    @ObservedObject var controller: FakeNextCutConsole
    /// The live notice owns Esc. Snapshot cards leave it off.
    var ownsShortcut: Bool = true

    private var nextCut: NextShotStatus.DirectorSection.NextCut? {
        controller.directorSection.nextCut
    }

    var body: some View {
        Group {
            if let line = nextCut?.line {
                Text(line)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ConsoleStyle.neutralFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ConsoleStyle.previewGreen, lineWidth: 2)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: 600)
        .background {
            if ownsShortcut, nextCut?.cancellable == true {
                DirectorEscapeCatcher { controller.cancelNextCut() }
                    .frame(width: 600, height: 36)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Receives Esc for the next-cut notice and calls cancel.
final class DirectorEscapeKeyView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53 else {
            return super.performKeyEquivalent(with: event)
        }
        onEscape?()
        return true
    }
}

private struct DirectorEscapeCatcher: NSViewRepresentable {
    var onEscape: () -> Void

    func makeNSView(context: Context) -> DirectorEscapeKeyView {
        let view = DirectorEscapeKeyView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: DirectorEscapeKeyView, context: Context) {
        nsView.onEscape = onEscape
    }
}
