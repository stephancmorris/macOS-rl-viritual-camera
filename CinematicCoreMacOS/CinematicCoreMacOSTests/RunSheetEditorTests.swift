import Foundation
import Testing
@testable import Alfie

/// C-07 synthetic local authoring/storage checks. No camera, runtime level or
/// qualification is created by loading, editing or advancing a run sheet.
@MainActor
struct RunSheetEditorTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("run-sheet-editor-\(UUID().uuidString)", isDirectory: true)
    }

    private func authored() throws -> RunSheet {
        try RunSheet(segments: [
            .init(type: .presenter, name: "Opening", positionHint: .lectern),
            .init(type: .panel, name: "Discussion", positionHint: .centre),
            .init(type: .videoBreak)
        ])
    }

    @Test func missingStorageIsEmptyAndSavingIsIsolatedByOpaqueShowID() throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let store = RunSheetStore(directory: base), first = UUID(), second = UUID()
        #expect(store.load(showID: first) == .empty)
        let editor = RunSheetEditor(store: store, showID: first)
        #expect(editor.sheet.segments.isEmpty && !editor.canAdvance && editor.canSave && !editor.hasError)
        #expect(editor.add(type: .presenter, name: "../../An operator show name", position: .lectern))
        editor.save()
        #expect(!editor.hasError)
        #expect(store.load(showID: first) == .loaded(editor.sheet))
        #expect(store.load(showID: second) == .empty)
        let names = try FileManager.default.contentsOfDirectory(atPath: base.path)
        #expect(names == ["run-sheet-\(first.uuidString).json"])
        #expect(store.fileURL(for: first).deletingLastPathComponent() == base.standardizedFileURL)
    }

    @Test func addingAndUpdatingUseTypedFieldsAndPreserveSegmentIdentity() throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let editor = RunSheetEditor(store: .init(directory: base), showID: UUID())
        #expect(editor.add(type: .presenter, name: "  Opening \n", position: .lectern))
        let id = try #require(editor.sheet.currentSegmentID)
        #expect(editor.sheet.current?.name == "Opening")
        #expect(editor.update(id: id, type: .performance, name: " \n ", position: .right))
        #expect(editor.sheet.current?.id == id && editor.sheet.current?.name == nil)
        #expect(editor.sheet.current?.type == .performance && editor.sheet.current?.positionHint == .right)
        let before = editor.sheet
        #expect(!editor.update(id: id, type: .liveEvent))
        #expect(editor.sheet == before && editor.hasError)
        #expect(!editor.update(id: UUID(), type: .panel))
        #expect(!editor.add(type: .liveEvent))
        #expect(editor.sheet == before)
    }

    @Test func reorderingMovesStableCurrentIdentityAndDoesNotWrap() throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let store = RunSheetStore(directory: base), showID = UUID()
        var saved = try authored(); saved.advance()
        try store.save(saved, showID: showID)
        let editor = RunSheetEditor(store: store, showID: showID)
        let currentID = try #require(saved.currentSegmentID)
        #expect(editor.move(id: currentID, offset: -1))
        #expect(editor.sheet.currentSegmentID == currentID && editor.sheet.currentIndex == 0)
        let before = editor.sheet
        #expect(!editor.move(id: currentID, offset: -1))
        #expect(!editor.move(id: currentID, offset: 0))
        #expect(!editor.move(id: currentID, offset: 2))
        #expect(!editor.move(id: UUID(), offset: 1))
        #expect(editor.sheet == before)
        editor.save()
        editor.reload()
        #expect(editor.sheet.currentSegmentID == currentID && editor.sheet.currentIndex == 0)
        #expect(editor.sheet.segments.map(\.id) == [saved.segments[1].id, saved.segments[0].id, saved.segments[2].id])
    }

    @Test(arguments: [0, 1, 2])
    func removingCurrentChoosesFollowingThenPrecedingWithoutLosingSelection(index: Int) throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let store = RunSheetStore(directory: base), showID = UUID(), source = try authored()
        let sheet = try RunSheet(segments: source.segments, currentSegmentID: source.segments[index].id)
        try store.save(sheet, showID: showID)
        let editor = RunSheetEditor(store: store, showID: showID)
        #expect(editor.remove(id: sheet.segments[index].id))
        let expected = index < 2 ? sheet.segments[index + 1].id : sheet.segments[index - 1].id
        #expect(editor.sheet.currentSegmentID == expected)
        editor.save(); editor.reload()
        #expect(editor.sheet.currentSegmentID == expected)
        let selected = editor.sheet.currentSegmentID
        if let other = editor.sheet.segments.first(where: { $0.id != selected }) {
            #expect(editor.remove(id: other.id))
            #expect(editor.sheet.currentSegmentID == selected)
        }
        #expect(editor.remove(id: try #require(selected)))
        #expect(editor.sheet.segments.isEmpty && editor.sheet.currentSegmentID == nil)
        #expect(!editor.canAdvance && !editor.advance())
        #expect(!editor.remove(id: UUID()))
    }

    @Test func explicitAdvanceDoesNotWrapAndRoundTripsCurrentAndOptionalMetadata() throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let store = RunSheetStore(directory: base), showID = UUID()
        let editor = RunSheetEditor(store: store, showID: showID)
        editor.add(type: .presenter, name: "Opening", position: .left)
        editor.add(type: .panel)
        #expect(editor.canAdvance && editor.advance())
        let currentID = editor.sheet.currentSegmentID
        #expect(!editor.canAdvance && !editor.advance())
        editor.save()
        #expect(!editor.hasError)
        let reloaded = RunSheetEditor(store: store, showID: showID)
        #expect(reloaded.sheet == editor.sheet && reloaded.sheet.currentSegmentID == currentID)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL(for: showID))) as? [String: Any])
        #expect(Set(object.keys) == ["version", "segments", "currentSegmentID"])
        let segments = try #require(object["segments"] as? [[String: Any]])
        #expect(segments.allSatisfy { Set($0.keys).isSubset(of: ["id", "type", "name", "positionHint"]) })
    }

    @Test(arguments: ["corrupt", "future", "extraAuthority", "invalidCurrent", "duplicateIDs", "invalidType"])
    func unreadableSavedDataIsNeverUsedOrOverwritten(variant: String) throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = RunSheetStore(directory: base), showID = UUID(), source = try authored()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        switch variant {
        case "future": object["version"] = RunSheet.currentVersion + 1
        case "extraAuthority": object["level"] = "auto"
        case "invalidCurrent": object["currentSegmentID"] = UUID().uuidString
        case "duplicateIDs":
            var segments = try #require(object["segments"] as? [[String: Any]])
            segments[1]["id"] = segments[0]["id"]; object["segments"] = segments
        case "invalidType":
            var segments = try #require(object["segments"] as? [[String: Any]])
            segments[0]["type"] = "liveEvent"; object["segments"] = segments
        default: break
        }
        let data = variant == "corrupt" ? Data("not a run sheet".utf8) : try JSONSerialization.data(withJSONObject: object)
        try data.write(to: store.fileURL(for: showID))
        let editor = RunSheetEditor(store: store, showID: showID)
        #expect(editor.sheet.segments.isEmpty && editor.hasError && !editor.canSave)
        #expect(editor.add(type: .presenter))
        let draft = editor.sheet
        #expect(editor.hasError && !editor.canSave)
        editor.save()
        #expect(editor.sheet == draft && editor.hasError && !editor.canSave)
        #expect(try Data(contentsOf: store.fileURL(for: showID)) == data)
        #expect(throws: RunSheetStore.Failure.unreadableExistingFile) { try store.save(source, showID: showID) }
    }

    @Test func aNewUnreadableFileAtSaveTimePreservesBothStoredBytesAndUnsavedDraft() throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let store = RunSheetStore(directory: base), showID = UUID()
        let editor = RunSheetEditor(store: store, showID: showID)
        editor.add(type: .performance, name: "Draft")
        let draft = editor.sheet, data = Data("future or corrupt file".utf8)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try data.write(to: store.fileURL(for: showID))
        editor.save()
        #expect(editor.sheet == draft && editor.hasError && !editor.canSave)
        #expect(try Data(contentsOf: store.fileURL(for: showID)) == data)
        try FileManager.default.removeItem(at: store.fileURL(for: showID))
        editor.reload()
        #expect(editor.sheet.segments.isEmpty && !editor.hasError && editor.canSave)
    }

    @Test(arguments: [false, true])
    func symlinkTargetsAndDirectoriesRefuseSavingWithoutChangingTheirTargets(directoryLink: Bool) throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let target = base.appendingPathComponent("target", isDirectory: directoryLink)
        let location = base.appendingPathComponent("store", isDirectory: true)
        let showID = UUID(), original = Data("keep unrelated content".utf8)
        if directoryLink {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: location, withDestinationURL: target)
        } else {
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            try original.write(to: target)
            try FileManager.default.createSymbolicLink(at: RunSheetStore(directory: location).fileURL(for: showID), withDestinationURL: target)
        }
        let store = RunSheetStore(directory: location)
        guard case .unreadable = store.load(showID: showID) else { Issue.record("A symbolic link was accepted as run-sheet storage"); return }
        #expect(throws: RunSheetStore.Failure.unreadableExistingFile) { try store.save(authored(), showID: showID) }
        if directoryLink {
            #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        } else {
            #expect(try Data(contentsOf: target) == original)
        }
    }

    @Test func aDirectoryAtTheSheetPathIsPreservedAndAFileAsStorageDirectoryRefusesSaving() throws {
        let base = root(); defer { try? FileManager.default.removeItem(at: base) }
        let store = RunSheetStore(directory: base), showID = UUID()
        try FileManager.default.createDirectory(at: store.fileURL(for: showID), withIntermediateDirectories: true)
        guard case .unreadable = store.load(showID: showID) else { Issue.record("A directory was accepted as a sheet"); return }
        #expect(throws: RunSheetStore.Failure.unreadableExistingFile) { try store.save(authored(), showID: showID) }
        #expect(try store.fileURL(for: showID).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        let blocked = base.appendingPathComponent("not-a-directory")
        let original = Data("keep".utf8); try original.write(to: blocked)
        let editor = RunSheetEditor(store: .init(directory: blocked), showID: UUID())
        editor.add(type: .panel); let draft = editor.sheet
        editor.save()
        #expect(editor.hasError && !editor.canSave && editor.sheet == draft)
        #expect(try Data(contentsOf: blocked) == original)
    }
}
