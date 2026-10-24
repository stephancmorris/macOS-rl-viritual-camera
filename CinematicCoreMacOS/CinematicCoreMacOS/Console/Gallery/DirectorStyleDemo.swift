//
//  DirectorStyleDemo.swift
//  CinematicCoreMacOS
//
//  C-04 gallery uses an isolated temporary store for manual validation.
//  Its explicit example values are synthetic fixtures, not product defaults.
//

#if DEBUG
import Foundation
import SwiftUI

struct DirectorStyleDemo: View {
    @StateObject private var editor: DirectorStyleEditor

    init() {
        let scratchURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Alfie-style-gallery-\(UUID().uuidString).json")
        _editor = StateObject(wrappedValue: DirectorStyleEditor(
            store: DirectorPreferencesStore(fileURL: scratchURL)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synthetic style editor. Saves use a unique temporary gallery file. Live preferences and rig qualification are unchanged.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Load synthetic example") {
                    editor.drafts = [.liveEvent: DirectorStyleDraft(
                        minimumShotDuration: "8", preferredShotDuration: "20", softMaximumShotDuration: "40",
                        wideCadence: "90", repetitionWindow: "10", maximumMovement: "0.2",
                        settleTime: "1", onAirMoveRate: "0.1", cutOnMotionAllowed: false)]
                    editor.selected = .liveEvent
                }
                Button("Reload scratch styles") { editor.reload() }
            }
            DirectorStyleSettingsView(editor: editor)
                .frame(height: 620)
                .background(ConsoleStyle.neutralFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ConsoleStyle.neutralBorder, lineWidth: 1)
                }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }
}
#endif
