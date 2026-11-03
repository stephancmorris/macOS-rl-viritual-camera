import Combine
import Foundation

/// SU-09: the run sheet for the current show. A show is a persisted opaque
/// UUID, so its sheet survives relaunch. Defaults hold only the identities;
/// the sheet itself lives in `RunSheetStore`. Nothing here saves a level,
/// route or authority.
@MainActor
final class ShowRunSheet: ObservableObject {
    static let currentShowKey = "directorRunSheet.currentShowID"
    static let previousShowKey = "directorRunSheet.previousShowID"

    /// Replaced when a new show begins; views observe the editor itself.
    @Published private(set) var editor: RunSheetEditor
    let store: RunSheetStore
    /// Any screen can ask for the editor; ContentView presents it.
    @Published var isPresented = false
    /// A saved sheet the Director should use (empty when cleared).
    var onSaved: ((RunSheet) -> Void)?

    private let defaults: UserDefaults

    init(store: RunSheetStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        let showID = Self.identity(defaults.string(forKey: Self.currentShowKey)) ?? {
            let id = UUID()
            defaults.set(id.uuidString, forKey: Self.currentShowKey)
            return id
        }()
        editor = RunSheetEditor(store: store, showID: showID)
    }

    /// `~/Library/Application Support/Alfie/RunSheets`. The folder is
    /// created on first save, not on read.
    static func applicationSupport(defaults: UserDefaults = .standard) -> ShowRunSheet? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = base.appendingPathComponent("Alfie", isDirectory: true)
            .appendingPathComponent("RunSheets", isDirectory: true)
        return ShowRunSheet(store: RunSheetStore(directory: directory), defaults: defaults)
    }

    var showID: UUID { editor.showID }
    var previousShowID: UUID? { Self.identity(defaults.string(forKey: Self.previousShowKey)) }

    /// What the Director runs at launch: the saved sheet only, never unsaved edits.
    var savedSheet: RunSheet? {
        guard case .loaded(let sheet) = store.load(showID: showID), !sheet.segments.isEmpty else { return nil }
        return sheet
    }

    /// The last show's saved segments, when there are any to copy.
    var lastShowSheet: RunSheet? {
        guard let previousShowID, case .loaded(let sheet) = store.load(showID: previousShowID),
              !sheet.segments.isEmpty else { return nil }
        return sheet
    }

    @discardableResult
    func useLastShow() -> Bool {
        guard let sheet = lastShowSheet else { return false }
        return editor.adopt(sheet)
    }

    /// Saves, then hands the sheet to the Director.
    @discardableResult
    func save() -> Bool {
        guard editor.save() else { return false }
        onSaved?(editor.sheet)
        return true
    }

    /// Begins a new show with an empty sheet; this one becomes "last show".
    func startNewShow() {
        defaults.set(showID.uuidString, forKey: Self.previousShowKey)
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.currentShowKey)
        editor = RunSheetEditor(store: store, showID: id)
        onSaved?(editor.sheet)
    }

    private static func identity(_ text: String?) -> UUID? { text.flatMap(UUID.init(uuidString:)) }
}
