import Combine
import Foundation

/// Explicit local selection only. Loading this model never creates a writer,
/// chooses storage budgets, grants a Director level, or exports in the background.
final class DirectorShadowExportModel: ObservableObject {
    @Published private(set) var inventory: DirectorShadowInventory?
    @Published var selectedSessions: Set<UUID> = []
    @Published var fromUTC = ""
    @Published var throughUTC = ""
    @Published private(set) var isBusy = false
    @Published private(set) var message = "Load retained sessions to choose an export."
    @Published private(set) var hasError = false
    var logProvider: () -> DirectorShadowLog? { didSet { objectWillChange.send() } }
    private var inventoryLog: DirectorShadowLog?

    init(logProvider: @escaping () -> DirectorShadowLog? = { nil }) {
        self.logProvider = logProvider
    }

    var isConfigured: Bool { logProvider() != nil }
    var canExport: Bool {
        guard !isBusy, selection != nil, let inventoryLog, let current = logProvider() else { return false }
        return current === inventoryLog
    }

    private var selection: DirectorShadowExportSelection? {
        guard let inventory, !selectedSessions.isEmpty,
              selectedSessions.isSubset(of: Set(inventory.sessions.map(\.id))),
              let from = Self.date(fromUTC), let through = Self.date(throughUTC), from <= through else { return nil }
        return .init(sessionIDs: selectedSessions, fromUTC: from, throughUTC: through)
    }

    /// Exact wire UTC keeps visible bounds and the exported selection identical.
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let value = formatter.date(from: text), value.timeIntervalSince1970.isFinite,
              DirectorShadowLog.utcString(value) == text else { return nil }
        return value
    }

    func load() async {
        guard !isBusy else { return }
        guard let log = logProvider() else {
            inventory = nil
            inventoryLog = nil
            selectedSessions = []
            message = "Shadow logging is not configured."
            hasError = false
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await log.retainedSessions()
            guard let current = logProvider(), current === log else {
                inventory = nil
                inventoryLog = nil
                selectedSessions = []
                message = "Logging configuration changed. Reload retained sessions."
                hasError = true
                return
            }
            inventory = next
            inventoryLog = log
            selectedSessions.formIntersection(Set(next.sessions.map(\.id)))
            if fromUTC.isEmpty, let first = next.sessions.map(\.firstUTC).min() {
                fromUTC = DirectorShadowLog.utcString(first)
            }
            if throughUTC.isEmpty, let last = next.sessions.map(\.lastUTC).max() {
                throughUTC = DirectorShadowLog.utcString(last)
            }
            message = next.sessions.isEmpty ? "No retained sessions are available."
                : "Choose sessions and inclusive UTC bounds. Incomplete selections may not be scoreable."
            hasError = false
        } catch {
            inventory = nil
            inventoryLog = nil
            selectedSessions = []
            message = "Retained sessions could not be read. No export was created."
            hasError = true
        }
    }

    func export(to destination: URL) async {
        guard !isBusy else { return }
        guard let selection, let inventoryLog, let current = logProvider(), current === inventoryLog else {
            message = "Reload sessions, choose at least one, and enter valid inclusive UTC bounds."
            hasError = true
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await inventoryLog.export(selection: selection, toNewBundle: destination)
            message = "Exported \(result.manifest.recordCount) records. \(result.omittedOutsideSelection) valid records were outside the selection. Excluded files: \(result.excludedFiles). Removed files: \(result.prunedFiles)."
            hasError = false
        } catch {
            message = "Export failed. The selection may have expired or changed, or the destination is unavailable. Reload and choose a new destination."
            hasError = true
        }
    }
}
