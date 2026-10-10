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
