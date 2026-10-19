//
//  DirectorStyleSettingsTests.swift
//  CinematicCoreMacOSTests
//
//  C-04: nothing stored means "No style set". A bad file is not used.
//  Saving writes only a validated style file, and never an authority level.
//

import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct DirectorStyleSettingsTests {
    @Test func aMissingFileShowsNoStyleSet() {
        let editor = makeEditor()
        #expect(editor.message == DirectorStyleEditor.emptyMessage)
        #expect(editor.draft(for: .liveEvent).isBlank)
    }

    @Test func anUnknownVersionIsNotUsed() throws {
        let url = tempFile()
        try Data("{\"version\":99}".utf8).write(to: url)
        let editor = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url))
        #expect(editor.message == DirectorPreferencesStore.unreadableMessage)
        #expect(editor.draft(for: .liveEvent).isBlank)
    }

    @Test func corruptJSONIsNotUsed() throws {
        let url = tempFile()
        try Data("not json".utf8).write(to: url)
        let result = DirectorPreferencesStore(fileURL: url).load()
        #expect(result == .unreadable(DirectorPreferencesStore.unreadableMessage))
    }

    @Test func savingRequiresALiveEventStyleAndDoesNotInventNumbers() {
        let editor = makeEditor()
        editor.save()
        #expect(editor.message == DirectorStyleEditor.liveEventRequiredMessage)
        #expect(editor.store.load() == .empty)
        #expect(editor.draft(for: .liveEvent).minimumShotDuration.isEmpty)
    }

    @Test func aWhitespaceOnlyLiveEventStillNeedsTheRequiredProfile() {
        let editor = makeEditor()
        editor.selected = .panel
        editor.drafts[.liveEvent] = DirectorStyleDraft(minimumShotDuration: " \n\t ")
        editor.save()
        #expect(editor.message == DirectorStyleEditor.liveEventRequiredMessage)
        #expect(editor.selected == .liveEvent)
        #expect(editor.hasError)
        #expect(editor.store.load() == .empty)
    }

    @Test func missingAndUnparseableFieldsNameTheValueToFix() throws {
        let fields: [(WritableKeyPath<DirectorStyleDraft, String>, String)] = [
            (\.minimumShotDuration, "Minimum shot length"),
            (\.preferredShotDuration, "Preferred shot length"),
            (\.softMaximumShotDuration, "Soft maximum shot length"),
            (\.wideCadence, "Wide cadence"),
            (\.repetitionWindow, "Repetition window"),
            (\.maximumMovement, "Maximum movement"),
            (\.settleTime, "Settle time"),
            (\.onAirMoveRate, "On-air move rate")
        ]
        for (field, title) in fields {
            for text in ["", "not a number"] {
                var draft = DirectorStyleDraft.from(fixtureStyle)
                draft[keyPath: field] = text
                let reason = text.isEmpty ? "is required" : "must be a finite number"
                try expectRefused(draft, message: "Live event: \(title) \(reason).")
            }
        }
        for text in ["nan", "inf", "-inf"] {
            var draft = DirectorStyleDraft.from(fixtureStyle)
            draft.maximumMovement = text
            try expectRefused(draft, message: "Live event: Maximum movement must be a finite number.")
        }
    }

    @Test func invalidBoundsNameTheFieldAndItsConstraint() throws {
        let fields: [(WritableKeyPath<DirectorStyleDraft, String>, String, String, String)] = [
            (\.minimumShotDuration, "-1", "Minimum shot length", "0 seconds or greater"),
            (\.preferredShotDuration, "-1", "Preferred shot length", "0 seconds or greater"),
            (\.softMaximumShotDuration, "-1", "Soft maximum shot length", "0 seconds or greater"),
            (\.wideCadence, "0", "Wide cadence", "greater than 0 seconds"),
            (\.repetitionWindow, "-1", "Repetition window", "0 seconds or greater"),
            (\.maximumMovement, "-1", "Maximum movement", "0 or greater"),
            (\.settleTime, "-1", "Settle time", "0 seconds or greater"),
            (\.onAirMoveRate, "0", "On-air move rate", "greater than 0")
        ]
        for (field, text, title, constraint) in fields {
            var draft = DirectorStyleDraft.from(fixtureStyle)
            draft[keyPath: field] = text
            try expectRefused(draft, message: "Live event: \(title) must be \(constraint).")
        }
    }

    @Test func inconsistentLengthsAndAnUnchosenCutPolicyExplainTheFix() throws {
        var draft = DirectorStyleDraft.from(fixtureStyle)
        draft.minimumShotDuration = "21"
        try expectRefused(draft, message: "Live event: Minimum shot length must be less than or equal to Preferred shot length.")
        draft = DirectorStyleDraft.from(fixtureStyle)
        draft.preferredShotDuration = "41"
        try expectRefused(draft, message: "Live event: Preferred shot length must be less than or equal to Soft maximum shot length.")
        draft = DirectorStyleDraft.from(fixtureStyle)
        draft.cutOnMotionAllowed = nil
        try expectRefused(draft, message: "Live event: Choose Yes or No for Cut while moving.")
    }

    @Test func anIncompleteOptionalProfileSelectsThatSegmentWithoutLosingDrafts() throws {
        let draft = DirectorStyleDraft(minimumShotDuration: "8")
        try expectRefused(draft, segment: .panel, message: "Panel: Preferred shot length is required.")
    }

    @Test func correctingARefusedDraftSavesTheEnteredBoundaryValues() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        var changed: DirectorPreferences?
        let editor = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url)) { changed = $0 }
        var draft = DirectorStyleDraft(
            minimumShotDuration: "0", preferredShotDuration: "0", softMaximumShotDuration: "0",
            wideCadence: "0", repetitionWindow: "0", maximumMovement: "0", settleTime: "0",
            onAirMoveRate: "0.000001", cutOnMotionAllowed: true)
        editor.drafts[.liveEvent] = draft
        editor.save()
        #expect(editor.hasError)
        #expect(changed == nil && editor.store.load() == .empty)
        draft.wideCadence = "0.000001"
        editor.drafts[.liveEvent] = draft
        editor.drafts[.panel] = DirectorStyleDraft(minimumShotDuration: " \n")
        editor.save()
        #expect(editor.message == DirectorStyleEditor.savedMessage)
        #expect(!editor.hasError)
        let preferences = try #require(changed)
        #expect(preferences.styles[.liveEvent] == (try draft.makeStyle()))
        #expect(preferences.styles[.panel] == nil)
        #expect(editor.draft(for: .liveEvent) == draft)
        #expect(try DirectorPreferences.migrate(Data(contentsOf: url)) == preferences)
    }

    @Test func reloadingPreservesTinyAndLargeFiniteValuesWithoutRoundingOrTrapping() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let style = DirectorStyle(
            minimumShotDuration: 1.0000001, preferredShotDuration: 1e20, softMaximumShotDuration: 1e21,
            wideCadence: 1e-9, repetitionWindow: 1e20, maximumMovement: Double.greatestFiniteMagnitude,
            settleTime: 1e-9, onAirMoveRate: 1e-9, cutOnMotionAllowed: false)
        let preferences = DirectorPreferences(styles: [.liveEvent: style])
        let store = DirectorPreferencesStore(fileURL: url)
        try store.save(preferences)
        let editor = DirectorStyleEditor(store: store)
        #expect(try editor.draft(for: .liveEvent).makeStyle() == style)
        editor.save()
        #expect(editor.message == DirectorStyleEditor.savedMessage)
        #expect(store.load() == .loaded(preferences))
    }

    @Test func aSavedStyleRoundTripsAndOmitsTheLevel() throws {
        let url = tempFile()
        var saved: DirectorPreferences?
        let editor = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url)) { saved = $0 }
        editor.drafts[.liveEvent] = DirectorStyleDraft.from(fixtureStyle)
        editor.save()
        #expect(editor.message == DirectorStyleEditor.savedMessage)
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\"level\""))
        #expect(!text.contains("authority"))
        #expect(!text.contains("manual"))
        let loaded = try DirectorPreferences.migrate(data)
        #expect(loaded.styles[.liveEvent] == fixtureStyle)
        #expect(saved == loaded)
        let reopened = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url))
        #expect(reopened.draft(for: .liveEvent).minimumShotDuration == DirectorStyleDraft.text(fixtureStyle.minimumShotDuration))
        #expect(reopened.message.isEmpty)
    }

    @Test func withoutStorageSavingIsRefusedNotReportedAsSaved() {
        var saved = false
        let editor = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: tempFile()), canSave: false) { _ in saved = true }
        #expect(editor.message == DirectorStyleEditor.noStorageMessage)
        editor.drafts[.liveEvent] = DirectorStyleDraft.from(fixtureStyle)
        editor.save()
        #expect(editor.message == DirectorStyleEditor.noStorageMessage)
        #expect(!saved && editor.store.load() == .empty)
    }

    @Test func savingOverAnUnreadableFileKeepsItBeside() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-style-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("DirectorPreferences.json")
        let newer = Data("{\"version\":99,\"fromANewerAlfie\":true}".utf8)
        try newer.write(to: url)
        let editor = DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url))
        #expect(editor.message == DirectorPreferencesStore.unreadableMessage)
        editor.drafts[.liveEvent] = DirectorStyleDraft.from(fixtureStyle)
        editor.save()
        #expect(editor.message == DirectorStyleEditor.keptUnreadableMessage)
        let kept = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("unreadable-") }
        #expect(kept.count == 1)
        #expect(try Data(contentsOf: try #require(kept.first)) == newer)
        guard case .loaded = editor.store.load() else { Issue.record("new styles not saved"); return }
        // A second save has nothing unreadable to keep.
        editor.save()
        #expect(editor.message == DirectorStyleEditor.savedMessage)
    }

    @Test func rendersEmptyCorruptAndSaved() throws {
        let empty = DirectorStyleSettingsView(editor: makeEditor())
        let badURL = tempFile()
        try Data("{\"version\":1}".utf8).write(to: badURL)
        let bad = DirectorStyleSettingsView(editor: DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: badURL)))
        let filledEditor = makeEditor()
        filledEditor.drafts[.liveEvent] = DirectorStyleDraft.from(fixtureStyle)
        filledEditor.save()
        let filled = DirectorStyleSettingsView(editor: filledEditor)
        try render(empty, name: "style-empty.png")
        try render(bad, name: "style-unreadable.png")
        try render(filled, name: "style-entered.png")
    }

    /// Exercise the actual save path against an existing valid file. Every
    /// invalid edit must keep both the saved bytes and all entered drafts.
    private func expectRefused(_ draft: DirectorStyleDraft, segment: SegmentType = .liveEvent,
                               message: String) throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DirectorPreferencesStore(fileURL: url)
        let original = DirectorPreferences(styles: [.liveEvent: fixtureStyle])
        try store.save(original)
        let savedBytes = try Data(contentsOf: url)
        var changes = 0
        let editor = DirectorStyleEditor(store: store) { _ in changes += 1 }
        editor.selected = .performance
        editor.drafts[.presenter] = DirectorStyleDraft.from(fixtureStyle)
        editor.drafts[segment] = draft
        let enteredDrafts = editor.drafts
        editor.save()
        #expect(editor.message == message)
        #expect(editor.hasError)
        #expect(editor.selected == segment)
        #expect(editor.drafts == enteredDrafts)
        #expect(changes == 0)
        #expect(try Data(contentsOf: url) == savedBytes)
        #expect(store.load() == .loaded(original))
    }

    private func render<V: View>(_ view: V, name: String) throws {
        let root = view
            .frame(width: 640, height: 720)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 720)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 640)
        guard ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1",
              let path = ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try data.write(to: dir.appendingPathComponent(name))
    }

    private func makeEditor() -> DirectorStyleEditor {
        DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: tempFile()))
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-style-\(UUID().uuidString).json")
    }

    /// Fixture numbers for the round trip. Not a product default.
    private var fixtureStyle: DirectorStyle {
        DirectorStyle(
            minimumShotDuration: 8,
            preferredShotDuration: 20,
            softMaximumShotDuration: 40,
            wideCadence: 90,
            repetitionWindow: 10,
            maximumMovement: 0.2,
            settleTime: 1,
            onAirMoveRate: 0.1,
            cutOnMotionAllowed: false)
    }
}
