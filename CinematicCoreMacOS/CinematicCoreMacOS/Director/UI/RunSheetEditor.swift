import Combine
import Foundation

/// C-07 authoring state only. Advancing selects A-13's current style context;
/// this editor has no camera, controller, qualification or authority hooks.
@MainActor
final class RunSheetEditor: ObservableObject {
    @Published private(set) var sheet = try! RunSheet(segments: [])
    @Published private(set) var message = ""
    @Published private(set) var hasError = false
    @Published private(set) var canSave = true

    let store: RunSheetStore
    let showID: UUID

    var canAdvance: Bool { sheet.next != nil }

    init(store: RunSheetStore, showID: UUID) {
        self.store = store
        self.showID = showID
        reload()
    }

    func reload() {
        canSave = true
        hasError = false
        switch store.load(showID: showID) {
        case .empty:
            sheet = try! RunSheet(segments: [])
            message = "No run sheet. Alfie uses the Live event style."
        case .loaded(let saved):
            sheet = saved
            message = "Run sheet loaded."
        case .unreadable(let reason):
            sheet = try! RunSheet(segments: [])
            message = reason
            hasError = true
            canSave = false
        }
    }

    @discardableResult
    func add(type: SegmentType, name: String? = nil, position: RunSheet.PositionHint? = nil) -> Bool {
        replace(segments: sheet.segments + [.init(type: type, name: Self.name(name), positionHint: position)],
                currentID: sheet.currentSegmentID)
    }

    @discardableResult
    func update(id: UUID, type: SegmentType, name: String? = nil, position: RunSheet.PositionHint? = nil) -> Bool {
        guard let index = sheet.segments.firstIndex(where: { $0.id == id }) else { return false }
        var segments = sheet.segments
        segments[index] = .init(id: id, type: type, name: Self.name(name), positionHint: position)
        return replace(segments: segments, currentID: sheet.currentSegmentID)
    }

    /// Move one row at a time. Selection follows the stable segment identity,
    /// never its old numeric index, and boundary moves never wrap.
    @discardableResult
    func move(id: UUID, offset: Int) -> Bool {
        guard offset == -1 || offset == 1,
              let index = sheet.segments.firstIndex(where: { $0.id == id }),
              sheet.segments.indices.contains(index + offset) else { return false }
        var segments = sheet.segments
        segments.swapAt(index, index + offset)
        return replace(segments: segments, currentID: sheet.currentSegmentID)
    }

    /// Removing current selects the following row at the same index, or the
    /// preceding final row when current was last. Removing all rows clears it.
    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let index = sheet.segments.firstIndex(where: { $0.id == id }) else { return false }
        var segments = sheet.segments
        segments.remove(at: index)
        let currentID = sheet.currentSegmentID == id
            ? (segments.isEmpty ? nil : segments[min(index, segments.count - 1)].id)
            : sheet.currentSegmentID
        return replace(segments: segments, currentID: currentID)
    }

    @discardableResult
    func advance() -> Bool {
        var next = sheet
        guard next.advance() else { return false }
        sheet = next
        changed()
        return true
    }

    func save() {
        do {
            try store.save(sheet, showID: showID)
            canSave = true
            hasError = false
            message = "Run sheet saved for this show."
        } catch RunSheetStore.Failure.unreadableExistingFile {
            canSave = false
            hasError = true
            message = RunSheetStore.unreadableMessage
        } catch {
            hasError = true
            message = "This run sheet can't be saved. Your changes are still here."
        }
    }

    private func replace(segments: [RunSheet.Segment], currentID: UUID?) -> Bool {
        do {
            sheet = try RunSheet(segments: segments, currentSegmentID: currentID)
            changed()
            return true
        } catch {
            hasError = true
            message = "Choose Presenter, Panel, Performance or Video break. The run sheet hasn't changed."
            return false
        }
    }

    private func changed() {
        // An in-memory edit cannot remove the saved-file warning or make an
        // unreadable/future file eligible for overwrite.
        guard canSave else { return }
        hasError = false
        message = "Unsaved run sheet changes."
    }

    private static func name(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
