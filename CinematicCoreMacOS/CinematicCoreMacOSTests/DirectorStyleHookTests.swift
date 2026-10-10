//
//  DirectorStyleHookTests.swift
//  CinematicCoreMacOSTests
//
//  CR-037: a style saved in Settings reaches the show's running Director.
//

import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorStyleHookTests {
    // Test fixture values only.
    private let style = DirectorStyle(minimumShotDuration: 8, preferredShotDuration: 15, softMaximumShotDuration: 35,
        wideCadence: 60, repetitionWindow: 20, maximumMovement: 0.1, settleTime: 1, onAirMoveRate: 0.5,
        cutOnMotionAllowed: false)

    @Test func savedStylesReachTheShowsDirector() throws {
        guard DeveloperFlags.runDirectorShadow else { return }
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let preferences = DirectorPreferences(styles: [.liveEvent: style])
        show.directorPreferencesChanged(preferences)
        // Stored even in Manual; the pause for new styles applies only while
        // directing (DirectorControllerTests covers that).
        #expect(show.director.preferences == preferences)
    }

    @Test func settingsEditorSaveIsForwardedThroughTheHook() throws {
        guard DeveloperFlags.runDirectorShadow else { return }
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-style-hook-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let editor = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url)) {
            show.directorPreferencesChanged($0)
        }
        editor.drafts[.liveEvent] = DirectorStyleDraft.from(style)
        editor.save()
        #expect(editor.message == DirectorStyleEditor.savedMessage)
        #expect(show.director.preferences?.styles[.liveEvent] == style)
    }
}
