//
//  DirectorNextCutNotice.swift
//  CinematicCoreMacOS
//
//  C-06. Displays the controller's supplied notice without choosing its
//  duration. Cancel and Esc act on the current cancellable notice, even when
//  a countdown refresh or replacement arrived before the view refreshed.
//  B-08 owns deadline tokens and the atomic cancellation/Take boundary.
//

import SwiftUI

struct DirectorNextCutNotice<Controller: DirectorConsoleControlling & ObservableObject>: View {
    @ObservedObject var controller: Controller
    /// Exactly one interactive notice owns Esc; gallery snapshot cards do not.
    var ownsShortcut: Bool = true

    private var nextCut: NextShotStatus.DirectorSection.NextCut? {
        controller.directorSection.nextCut
    }

    /// Re-read at the action boundary: a removed or noncancellable notice
    /// must neither receive cancellation nor consume an otherwise unused Esc.
    @discardableResult
    func cancelCurrentCut() -> Bool {
        guard controller.directorSection.nextCut?.cancellable == true else { return false }
        controller.cancelNextCut()
        return true
    }

    var body: some View {
        Group {
            if let nextCut {
                HStack(spacing: 12) {
                    Text(nextCut.line)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AlfieColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel(nextCut.line)
                    Spacer(minLength: 0)
                    if nextCut.cancellable {
                        Button("Cancel") { cancelCurrentCut() }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Cancel next cut to \(nextCut.input.cameraLabel)")
                            .accessibilityHint(ownsShortcut ? "Shortcut Escape" : "Cancels this example's next cut")
                            .accessibilityIdentifier("director.cancelNextCut")
                    }
                }
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
                .accessibilityElement(children: .contain)
            }
        }
        .frame(width: 600)
        .background {
            if ownsShortcut, nextCut?.cancellable == true {
                DirectorEscapeCatcher { cancelCurrentCut() }
                    .frame(width: 600, height: 36)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Receives plain Esc only. Returning false lets normal window handling
/// continue once a notice was removed, replaced by Backup or dismantled.
final class DirectorEscapeKeyView: NSView {
    var onEscape: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53, !event.isARepeat,
              event.modifierFlags.intersection([.command, .option, .shift, .control]).isEmpty else {
            return super.performKeyEquivalent(with: event)
        }
        return onEscape?() ?? false
    }
}

private struct DirectorEscapeCatcher: NSViewRepresentable {
    var onEscape: () -> Bool

    func makeNSView(context: Context) -> DirectorEscapeKeyView {
        let view = DirectorEscapeKeyView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: DirectorEscapeKeyView, context: Context) {
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: DirectorEscapeKeyView, coordinator: ()) {
        nsView.onEscape = nil
    }
}
