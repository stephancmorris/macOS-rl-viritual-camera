import AppKit
import Foundation
import SwiftUI
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

    // MARK: RUNSHEET-FOLLOWUPS

    @Test func theCurrentMarkerFollowsTheDirectorAfterAdvanceWithoutAnUnsavedEdit() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let model = f.launch()
        #expect(model.editor.add(type: .presenter, name: "Welcome"))
        #expect(model.editor.add(type: .performance, name: "Band"))
        #expect(model.editor.add(type: .panel, name: "Q&A"))
        #expect(model.save())
        let saved = model.editor.message

        // The Director advances its own copy of the saved sheet (⌘⇧↩).
        var director = try #require(model.savedSheet)
        var advanced = director.advance()
        #expect(advanced)
        model.followDirector(currentSegmentID: director.currentSegmentID)
        #expect(model.editor.sheet.currentSegmentID == director.currentSegmentID)
        #expect(model.editor.sheet.current?.name == "Band")
        #expect(model.editor.message == saved)          // following is not an edit
        #expect(model.editor.canSave)

        advanced = director.advance()
        #expect(advanced)
        model.followDirector(currentSegmentID: director.currentSegmentID)
        #expect(model.editor.sheet.current?.name == "Q&A")
    }

    @Test func aSegmentTheEditorNoLongerHasLeavesTheMarkerAlone() throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let model = f.launch()
        #expect(model.editor.add(type: .presenter, name: "Welcome"))
        #expect(model.editor.add(type: .panel, name: "Q&A"))
        #expect(model.save())
        let before = model.editor.sheet
        model.followDirector(currentSegmentID: UUID())
        model.followDirector(currentSegmentID: nil)
        #expect(model.editor.sheet == before)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func thePanelIsOpaqueInLightAndDark(_ appearance: NSAppearance.Name) throws {
        let f = fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let host = NSHostingView(rootView: ShowRunSheetPanel(model: f.launch(), onDone: {}))
        host.frame = CGRect(x: 0, y: 0, width: 720, height: 620)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        // A corner outside every control: transparent before the fix.
        let corner = try #require(rep.colorAt(x: 4, y: 4))
        #expect(corner.alphaComponent > 0.99, "\(appearance.rawValue) corner alpha \(corner.alphaComponent)")
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: dir.appendingPathComponent("run-sheet-\(appearance.rawValue).png"))
        }
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
