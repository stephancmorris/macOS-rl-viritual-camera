import Foundation
import Testing
@testable import Alfie

/// SU-09: a show's run sheet survives relaunch under a persisted opaque show
/// identity. Defaults hold only identities; no level, route or authority.
@MainActor
struct ShowRunSheetTests {
    private struct Fixture {
        let directory: URL
        let defaults: UserDefaults
        var store: RunSheetStore { RunSheetStore(directory: directory) }
        @MainActor func launch() -> ShowRunSheet { ShowRunSheet(store: store, defaults: defaults) }
    }

    private func fixture() -> Fixture {
        Fixture(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("show-run-sheet-\(UUID().uuidString)", isDirectory: true),
                defaults: UserDefaults(suiteName: "alfie-show-run-sheet-\(UUID().uuidString)")!)
    }

    @Test func theShowIdentityAndItsSheetSurviveRelaunch() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let first = f.launch()
        #expect(first.editor.add(type: .presenter, name: "Welcome"))
        #expect(first.save())
        let relaunched = f.launch()
        #expect(relaunched.showID == first.showID)
        #expect(relaunched.editor.sheet == first.editor.sheet)
        #expect(relaunched.savedSheet?.current?.name == "Welcome")
    }

    @Test func unsavedEditsAreNotWhatTheDirectorRuns() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let model = f.launch()
        #expect(model.savedSheet == nil)
        #expect(model.editor.add(type: .panel))
        #expect(model.savedSheet == nil)
    }

    @Test func savingHandsTheSheetToTheDirector() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let model = f.launch()
        var handed: [RunSheet] = []
        model.onSaved = { handed.append($0) }
        #expect(model.editor.add(type: .performance, name: "Band"))
        #expect(model.save())
        #expect(handed == [model.editor.sheet])
    }

    @Test func aNewShowStartsEmptyAndCanCopyTheLastShow() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let model = f.launch()
        #expect(model.lastShowSheet == nil)
        #expect(model.editor.add(type: .presenter, name: "Welcome"))
        #expect(model.editor.add(type: .panel, name: "Q&A"))
        #expect(model.editor.advance())
        #expect(model.save())
        let firstShow = model.showID

        model.startNewShow()
        #expect(model.showID != firstShow)
        #expect(model.previousShowID == firstShow)
        #expect(model.editor.sheet.segments.isEmpty)
        #expect(model.useLastShow())
        #expect(model.editor.sheet.segments.map(\.name) == ["Welcome", "Q&A"])
        #expect(model.editor.sheet.current?.name == "Welcome", "a copied sheet starts at the top")
        #expect(model.savedSheet == nil, "copied segments stay unsaved until Save")
        #expect(f.launch().previousShowID == firstShow)
    }

    @Test func anUnreadableSheetIsKeptWithAVisibleError() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let showID = f.launch().showID
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: true)
        let file = f.store.fileURL(for: showID)
        try Data("{\"version\":99}".utf8).write(to: file)
        let model = f.launch()
        #expect(model.editor.hasError && !model.editor.canSave)
        #expect(model.savedSheet == nil)
        #expect(!model.save())
        #expect(try Data(contentsOf: file) == Data("{\"version\":99}".utf8))
    }

    @Test func defaultsHoldOnlyShowIdentities() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let model = f.launch()
        #expect(model.editor.add(type: .presenter))
        #expect(model.save())
        model.startNewShow()
        #expect(UUID(uuidString: f.defaults.string(forKey: ShowRunSheet.currentShowKey) ?? "") != nil)
        #expect(UUID(uuidString: f.defaults.string(forKey: ShowRunSheet.previousShowKey) ?? "") != nil)
        let saved = try String(contentsOf: f.store.fileURL(for: model.previousShowID!), encoding: .utf8)
        for word in ["level", "authority", "route", "qualified"] { #expect(!saved.lowercased().contains(word)) }
    }
}
