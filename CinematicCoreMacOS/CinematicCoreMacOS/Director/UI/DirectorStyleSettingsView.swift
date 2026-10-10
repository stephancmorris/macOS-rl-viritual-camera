//
//  DirectorStyleSettingsView.swift
//  CinematicCoreMacOS
//
//  C-04 settings. Fields start empty. Live event is required to save.
//  A file Alfie cannot read shows a message and is not used.
//

import SwiftUI

struct DirectorStyleSettingsView: View {
    @ObservedObject var editor: DirectorStyleEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(editor.message.isEmpty ? "Using the saved styles." : editor.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(editor.message == DirectorPreferencesStore.unreadableMessage
                                     || editor.message == DirectorStyleEditor.cannotSaveMessage
                                     ? ConsoleStyle.amber : .primary)
                    .accessibilityLabel(editor.message.isEmpty ? "Using the saved styles." : editor.message)

                Picker("Segment", selection: $editor.selected) {
                    ForEach(SegmentType.allCases, id: \.self) { segment in
                        Text(segment.styleTitle).tag(segment)
                    }
                }
                .accessibilityLabel("Segment")

                styleFields(editor.binding(for: editor.selected))

                Button("Save styles") { editor.save() }
                    .accessibilityLabel("Save styles")
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func styleFields(_ draft: Binding<DirectorStyleDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Minimum shot length", text: draft.minimumShotDuration)
            field("Preferred shot length", text: draft.preferredShotDuration)
            field("Soft maximum shot length", text: draft.softMaximumShotDuration)
            field("Wide cadence", text: draft.wideCadence)
            field("Repetition window", text: draft.repetitionWindow)
            field("Maximum movement", text: draft.maximumMovement)
            field("Settle time", text: draft.settleTime)
            field("On-air move rate", text: draft.onAirMoveRate)
            Picker("Cut while moving", selection: cutChoice(draft)) {
                Text("Not set").tag(CutChoice.notSet)
                Text("No").tag(CutChoice.no)
                Text("Yes").tag(CutChoice.yes)
            }
            .accessibilityLabel("Cut while moving")
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .frame(width: 220, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
        }
    }

    private func cutChoice(_ draft: Binding<DirectorStyleDraft>) -> Binding<CutChoice> {
        Binding(
            get: {
                switch draft.wrappedValue.cutOnMotionAllowed {
                case nil: .notSet
                case false: .no
                case true: .yes
                }
            },
            set: { choice in
                draft.wrappedValue.cutOnMotionAllowed = switch choice {
                case .notSet: nil
                case .no: false
                case .yes: true
                }
            })
    }
}

private enum CutChoice: Hashable {
    case notSet, no, yes
}
