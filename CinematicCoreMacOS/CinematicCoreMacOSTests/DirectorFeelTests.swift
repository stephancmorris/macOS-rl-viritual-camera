//
//  DirectorFeelTests.swift
//  CinematicCoreMacOSTests
//
//  AD-STYLE-UX (SU-01, SU-02, SU-04, SU-05). Every feel maps to a valid
//  style and back; hand-edited values read as Custom; the Director starts
//  with saved styles, else the built-in feel, never a silent replacement for
//  an unreadable file; and Settings saves each change automatically.
//

import Foundation
import Testing
@testable import Alfie

struct DirectorFeelTableTests {
    @Test func everyFeelMakesAValidStyle() throws {
        #expect(DirectorFeel.all.count == 18)
        for feel in DirectorFeel.all {
            _ = try DirectorFeelTable.v1.style(for: feel).validated()
        }
    }

    @Test func feelsRoundTripThroughStyles() {
        for feel in DirectorFeel.all {
            #expect(DirectorFeel.matching(DirectorFeelTable.v1.style(for: feel)) == feel)
        }
    }

    @Test func tableV1MatchesTheRecordedValues() {
        let calm = DirectorFeelTable.v1.style(for: DirectorFeel(pace: .calm, wideShots: .rarely, movement: .waitUntilSettled))
        #expect(calm.minimumShotDuration == 12)
        #expect(calm.preferredShotDuration == 30)
        #expect(calm.softMaximumShotDuration == 60)
        #expect(calm.wideCadence == 120)
        #expect(calm.repetitionWindow == 60)
        #expect(calm.cutOnMotionAllowed == false)
        let lively = DirectorFeelTable.v1.style(for: DirectorFeel(pace: .lively, wideShots: .often, movement: .cutWhileMoving))
        #expect([lively.minimumShotDuration, lively.preferredShotDuration, lively.softMaximumShotDuration] == [5, 12, 25])
        #expect(lively.wideCadence == 40)
        #expect(lively.cutOnMotionAllowed)
    }

    @Test func aHandEditedStyleIsCustom() {
        let base = DirectorFeelTable.v1.style(for: .liveEventDefault)
        let edited = DirectorStyle(
            minimumShotDuration: base.minimumShotDuration + 1, preferredShotDuration: base.preferredShotDuration,
            softMaximumShotDuration: base.softMaximumShotDuration, wideCadence: base.wideCadence,
            repetitionWindow: base.repetitionWindow, maximumMovement: base.maximumMovement,
            settleTime: base.settleTime, onAirMoveRate: base.onAirMoveRate,
            cutOnMotionAllowed: base.cutOnMotionAllowed)
        #expect(DirectorFeel.matching(edited) == nil)
    }

    @Test func liveEventDefaultIsBalancedSometimesSettled() {
        #expect(DirectorFeel.liveEventDefault == DirectorFeel(pace: .balanced, wideShots: .sometimes, movement: .waitUntilSettled))
        #expect(DirectorPreferences.builtInDefault.styles.keys.sorted { $0.rawValue < $1.rawValue } == [.liveEvent])
    }
}

@MainActor
struct DirectorLaunchStyleTests {
    @Test func nothingSavedUsesTheBuiltInFeel() {
        #expect(DirectorPreferences.forLaunch(.empty) == DirectorPreferences.builtInDefault)
    }

    @Test func savedStylesWin() {
        let saved = DirectorPreferences(styles: [
            .liveEvent: DirectorFeelTable.v1.style(for: DirectorFeel(pace: .calm, wideShots: .often, movement: .waitUntilSettled))])
        #expect(DirectorPreferences.forLaunch(.loaded(saved)) == saved)
    }

    @Test func anUnreadableFileGivesNoStyles() {
        #expect(DirectorPreferences.forLaunch(.unreadable("bad")) == nil)
    }

    @Test func showLoadsSavedStylesIntoTheDirector() throws {
        let url = tempFile()
        let saved = DirectorPreferences(styles: [
            .liveEvent: DirectorFeelTable.v1.style(for: DirectorFeel(pace: .lively, wideShots: .rarely, movement: .cutWhileMoving))])
        try DirectorPreferencesStore(fileURL: url).save(saved)
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        show.loadDirectorStyles(store: DirectorPreferencesStore(fileURL: url))
        #expect(show.director.preferences == saved)
    }

    @Test func showKeepsAnUnreadableFileAndStartsWithoutStyles() throws {
        let url = tempFile()
        try Data("{\"version\":99}".utf8).write(to: url)
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        show.loadDirectorStyles(store: DirectorPreferencesStore(fileURL: url))
        #expect(show.director.preferences == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
struct DirectorFeelEditorTests {
    @Test func aFreshInstallShowsTheBuiltInFeel() {
        let editor = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: tempFile()))
        #expect(editor.message == DirectorFeelEditor.builtInMessage)
        #expect(editor.feel(for: .liveEvent) == .liveEventDefault)
        #expect(editor.summary(for: .presenter) == "Same as Live event")
    }

    @Test func choosingAFeelSavesAndTellsTheDirector() throws {
        let url = tempFile()
        var pushed: [DirectorPreferences] = []
        let editor = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: url)) { pushed.append($0) }
        editor.choose(pace: .calm, for: .presenter)
        let expected = DirectorFeel(pace: .calm, wideShots: .sometimes, movement: .waitUntilSettled)
        #expect(editor.feel(for: .presenter) == expected)
        #expect(editor.message == DirectorFeelEditor.savedMessage)
        #expect(pushed.count == 1)
        guard case .loaded(let stored) = DirectorPreferencesStore(fileURL: url).load() else {
            Issue.record("nothing saved"); return
        }
        #expect(stored.styles[.presenter] == DirectorFeelTable.v1.style(for: expected))
        #expect(stored.styles[.liveEvent] != nil)
    }

    @Test func anExactEditMakesTheFeelCustom() {
        let editor = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: tempFile()))
        editor.setValue(9, .minimumShot, for: .liveEvent)
        #expect(editor.feel(for: .liveEvent) == nil)
        #expect(editor.summary(for: .liveEvent) == "Custom")
        #expect(editor.value(.minimumShot, for: .liveEvent) == 9)
    }

    @Test func aRuleBreakingEditIsRefusedAndNotSaved() {
        let url = tempFile()
        let editor = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: url))
        editor.setValue(500, .minimumShot, for: .liveEvent)
        #expect(editor.exactValueIssue == "Minimum shot can't be longer than preferred.")
        #expect(editor.value(.minimumShot, for: .liveEvent) == 8)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aSegmentCanFollowLiveEventAgain() {
        let editor = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: tempFile()))
        editor.choose(wideShots: .often, for: .panel)
        #expect(editor.hasOwnStyle(.panel))
        editor.followLiveEvent(.panel)
        #expect(!editor.hasOwnStyle(.panel))
        #expect(editor.feel(for: .panel) == editor.feel(for: .liveEvent))
    }

    @Test func choicesSurviveAReload() {
        let url = tempFile()
        DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: url)).choose(pace: .lively, for: .performance)
        let reopened = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: url))
        #expect(reopened.feel(for: .performance)?.pace == .lively)
    }

    @Test func anUnreadableFileIsKeptWhenANewStyleIsSaved() throws {
        let url = tempFile()
        try Data("{\"version\":99}".utf8).write(to: url)
        let editor = DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: url))
        #expect(editor.hasError)
        editor.choose(pace: .calm, for: .liveEvent)
        #expect(editor.message == DirectorFeelEditor.keptUnreadableMessage)
        let folder = url.deletingLastPathComponent()
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(url.deletingPathExtension().lastPathComponent + ".unreadable-") }
        #expect(kept.count == 1)
    }

    @Test func directorIsHiddenWhenTheDirectorDoesNotRun() {
        #expect(SettingsTab.available.contains(.director) == DeveloperFlags.runDirectorShadow)
    }
}

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("alfie-feel-\(UUID().uuidString).json")
}
