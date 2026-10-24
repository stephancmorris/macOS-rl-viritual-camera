//
//  DirectorRunSheetDemo.swift
//  CinematicCoreMacOS
//
//  C-07 uses two independent, temporary per-show stores. No live controller,
//  production preferences or qualification records are touched.
//

#if DEBUG
import Combine
import Foundation
import SwiftUI

private enum SyntheticRunSheetShow: String, CaseIterable, Identifiable {
    case first, second
    var id: String { rawValue }
    var title: String { self == .first ? "Show A (synthetic)" : "Show B (synthetic)" }
}

@MainActor
private final class DirectorRunSheetGallery: ObservableObject {
    let first: RunSheetEditor
    let second: RunSheetEditor

    init() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Alfie-run-sheet-gallery-\(UUID().uuidString)", isDirectory: true)
        first = RunSheetEditor(store: RunSheetStore(directory: root.appendingPathComponent("Show-A", isDirectory: true)),
                              showID: UUID())
        second = RunSheetEditor(store: RunSheetStore(directory: root.appendingPathComponent("Show-B", isDirectory: true)),
                               showID: UUID())
    }

    func editor(for show: SyntheticRunSheetShow) -> RunSheetEditor { show == .first ? first : second }
}

struct DirectorRunSheetDemo: View {
    @StateObject private var gallery = DirectorRunSheetGallery()
    @State private var show: SyntheticRunSheetShow = .first

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Synthetic run sheets. Each show has its own UUID and temporary store. No live preferences, Director authority or rig qualification is changed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Synthetic show", selection: $show) {
                ForEach(SyntheticRunSheetShow.allCases) { show in
                    Text(show.title).tag(show)
                }
            }
            .pickerStyle(.segmented)
            DirectorRunSheetEditorPanel(editor: gallery.editor(for: show), showTitle: show.title)
                .id(show)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct DirectorRunSheetEditorPanel: View {
    @ObservedObject var editor: RunSheetEditor
    let showTitle: String
    @State private var isEditingText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(showTitle).font(.system(size: 13, weight: .semibold))
            Button("Load synthetic run sheet") {
                for id in editor.sheet.segments.map(\.id) { editor.remove(id: id) }
                editor.add(type: .presenter, name: "Opening", position: .lectern)
                editor.add(type: .panel, name: "Discussion", position: .centre)
                editor.add(type: .performance, name: "Performance", position: nil)
                editor.add(type: .videoBreak, name: "Break", position: nil)
            }
            Text("The example replaces this show's unsaved draft. Save explicitly to keep it in this gallery session. The Advance shortcut is suspended while a name field is focused.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RunSheetStrip(editor: editor, ownsShortcut: true, isEditingText: isEditingText)
            RunSheetEditorView(editor: editor) { isEditingText = $0 }
        }
    }
}
#endif
