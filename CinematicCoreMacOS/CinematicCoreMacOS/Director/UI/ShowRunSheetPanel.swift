//
//  ShowRunSheetPanel.swift
//  CinematicCoreMacOS
//
//  SU-09/SU-10. The show's run sheet as a sheet over Show setup, the
//  standby screen or the live console. Saving hands it to the Director; a
//  changed sheet while Alfie is directing pauses until handed back (F2).
//

import SwiftUI

struct ShowRunSheetPanel: View {
    @ObservedObject var model: ShowRunSheet
    /// Each segment's feel from Settings › Director, when the Director has styles.
    var feel: (SegmentType) -> String? = { _ in nil }
    var isLive = false
    var onDone: () -> Void

    @State private var confirmingNewShow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Run sheet")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
            Text("Optional. With no segments, Alfie uses the Live event feel. Each segment uses its feel from Settings › Director.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if isLive {
                Text("The show is live. Saving changed segments while Alfie is directing pauses Alfie until you hand back.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ConsoleStyle.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                RunSheetEditorView(editor: model.editor, onSave: { model.save() },
                                   segmentNote: { segment in feel(segment.type).map { "Feel: \($0)" } })
                    .padding(.vertical, 4)
            }

            Divider()
            HStack(spacing: 12) {
                Button("Use last show's") { model.useLastShow() }
                    .disabled(model.lastShowSheet == nil)
                    .help("Copy the previous show's segments. Save to use them.")
                Button("New show…") { confirmingNewShow = true }
                    .disabled(isLive)
                    .help("Start an empty run sheet. This one becomes the last show's.")
                Spacer()
                SaveButton(editor: model.editor) { model.save() }
            }
        }
        .padding(24)
        .frame(width: 720, height: 620)
        .confirmationDialog("Start a new show's run sheet?", isPresented: $confirmingNewShow) {
            Button("New show") { model.startNewShow() }
        } message: {
            Text("This run sheet stays saved and can be copied with \"Use last show's\".")
        }
    }
}

/// Observes the current editor, which `ShowRunSheet` replaces on a new show.
private struct SaveButton: View {
    @ObservedObject var editor: RunSheetEditor
    var save: () -> Void

    var body: some View {
        Button("Save run sheet", action: save)
            .disabled(!editor.canSave)
    }
}

/// Presents the show's run sheet whenever any screen asks for it.
struct ShowRunSheetPresenter: ViewModifier {
    let show: ShowCoordinator?

    func body(content: Content) -> some View {
        if let show, let model = show.showRunSheet {
            content.modifier(Presenting(show: show, model: model))
        } else {
            content
        }
    }

    private struct Presenting: ViewModifier {
        let show: ShowCoordinator
        @ObservedObject var model: ShowRunSheet

        func body(content: Content) -> some View {
            content.sheet(isPresented: $model.isPresented) {
                ShowRunSheetPanel(model: model, feel: { show.directorFeelSummary(for: $0) },
                                  isLive: show.isAnyChannelLive) { model.isPresented = false }
            }
        }
    }
}
