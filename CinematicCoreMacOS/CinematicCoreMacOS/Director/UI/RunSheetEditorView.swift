//
//  RunSheetEditorView.swift
//  CinematicCoreMacOS
//
//  C-07. Explicit add/apply actions preserve names while the operator types.
//  This editor has no Director authority or live-controller integration.
//

import SwiftUI

struct RunSheetEditorView: View {
    @ObservedObject var editor: RunSheetEditor
    var onTextEditingChanged: (Bool) -> Void = { _ in }
    /// SU-09: the host's save (for example, one that also updates the Director).
    var onSave: (() -> Void)? = nil
    /// SU-09: a line under each segment, such as its feel.
    var segmentNote: (RunSheet.Segment) -> String? = { _ in nil }

    @State private var newType: SegmentType = .presenter
    @State private var newName = ""
    @State private var newPosition: RunSheet.PositionHint?
    @State private var editingID: UUID?
    @State private var editedType: SegmentType = .presenter
    @State private var editedName = ""
    @State private var editedPosition: RunSheet.PositionHint?
    @FocusState private var focusedName: NameField?

    private enum NameField: Hashable { case newSegment, editedSegment }
    private static let segmentTypes: [SegmentType] = [.presenter, .panel, .performance, .videoBreak]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editor.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(editor.hasError ? ConsoleStyle.amber : .primary)
                .accessibilityLabel(editor.message)

            if editor.sheet.segments.isEmpty {
                Text("No segments. Live event is the fallback style.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(editor.sheet.segments.enumerated()), id: \.element.id) { index, segment in
                    segmentRow(segment, index: index)
                }
            }

            Divider()
            Text("Add segment").font(.system(size: 13, weight: .semibold))
            fields(type: $newType, name: $newName, position: $newPosition, focus: .newSegment)
            Button("Add segment") {
                guard editor.add(type: newType, name: newName, position: newPosition) else { return }
                newName = ""
                newPosition = nil
                focusedName = nil
            }
            .accessibilityLabel("Add run sheet segment")

            if editingID != nil {
                Divider()
                Text("Edit segment").font(.system(size: 13, weight: .semibold))
                fields(type: $editedType, name: $editedName, position: $editedPosition, focus: .editedSegment)
                HStack(spacing: 12) {
                    Button("Apply segment") {
                        guard let id = editingID,
                              editor.update(id: id, type: editedType, name: editedName, position: editedPosition) else { return }
                        finishEditing()
                    }
                    Button("Cancel edit") { finishEditing() }
                }
                Text("Apply or cancel the segment edit before saving.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack(spacing: 12) {
                Button("Save run sheet") { if let onSave { onSave() } else { editor.save() } }
                    .disabled(!editor.canSave || editingID != nil)
                Button("Reload run sheet") {
                    editor.reload()
                    finishEditing()
                }
            }
            Text("Saved for this show only. Segments guide style and never grant authority.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .onChange(of: focusedName) { _, field in onTextEditingChanged(field != nil) }
        .onChange(of: editor.sheet.segments.map(\.id)) { _, ids in
            if let editingID, !ids.contains(editingID) { finishEditing() }
        }
        .onDisappear { onTextEditingChanged(false) }
    }

    private func segmentRow(_ segment: RunSheet.Segment, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1). \(RunSheetSegmentText.title(segment))")
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let note = segmentNote(segment) {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if segment.id == editor.sheet.currentSegmentID {
                    Text("Current").font(.system(size: 11, weight: .semibold))
                }
                Button("Edit") {
                    editingID = segment.id
                    editedType = segment.type
                    editedName = segment.name ?? ""
                    editedPosition = segment.positionHint
                }
                .disabled(editingID != nil)
                .accessibilityLabel("Edit segment \(index + 1)")
                Button("Move up") { editor.move(id: segment.id, offset: -1) }
                    .disabled(index == 0)
                    .accessibilityLabel("Move segment \(index + 1) up")
                Button("Move down") { editor.move(id: segment.id, offset: 1) }
                    .disabled(index == editor.sheet.segments.count - 1)
                    .accessibilityLabel("Move segment \(index + 1) down")
                Button("Remove") { editor.remove(id: segment.id) }
                    .accessibilityLabel("Remove segment \(index + 1)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleStyle.neutralFill)
    }

    private func fields(type: Binding<SegmentType>, name: Binding<String>,
                        position: Binding<RunSheet.PositionHint?>, focus: NameField) -> some View {
        HStack(spacing: 12) {
            Picker("Type", selection: type) {
                ForEach(Self.segmentTypes, id: \.self) { type in
                    Text(type.styleTitle).tag(type)
                }
            }
            .frame(width: 180)
            TextField("Name (optional)", text: name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(focus == .newSegment ? "New segment name (optional)" : "Edited segment name (optional)")
                .focused($focusedName, equals: focus)
            Picker("Position", selection: position) {
                Text("None").tag(Optional<RunSheet.PositionHint>.none)
                ForEach(RunSheet.PositionHint.allCases, id: \.self) { position in
                    Text(position.title).tag(Optional(position))
                }
            }
            .frame(width: 180)
        }
    }

    private func finishEditing() {
        editingID = nil
        focusedName = nil
    }
}
