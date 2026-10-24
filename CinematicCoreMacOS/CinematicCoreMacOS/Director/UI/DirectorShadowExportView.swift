import SwiftUI

/// The host supplies an explicitly chosen local destination. This component
/// does not open filesystem permissions or choose a destination automatically.
struct DirectorShadowExportView: View {
    @ObservedObject var model: DirectorShadowExportModel
    var destination: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shadow metadata export").font(.headline)
            Text("Local metadata only. Select sessions and an inclusive UTC time range, then export explicitly.")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.isConfigured ? model.message : "Shadow logging is not configured.")
                .font(.callout)
                .foregroundStyle(model.hasError ? ConsoleStyle.amber : .primary)
                .accessibilityLabel(model.isConfigured ? model.message : "Shadow logging is not configured.")
            Button("Load retained sessions") { Task { await model.load() } }
                .disabled(!model.isConfigured || model.isBusy)
                .accessibilityLabel("Load retained sessions")
            if let inventory = model.inventory {
                ForEach(inventory.sessions) { session in
                    Toggle(isOn: Binding(
                        get: { model.selectedSessions.contains(session.id) },
                        set: { selected in
                            if selected { model.selectedSessions.insert(session.id) }
                            else { model.selectedSessions.remove(session.id) }
                        })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.id.uuidString).font(.system(.caption, design: .monospaced))
                            Text("\(session.recordCount) records · \(session.evidenceClasses.map(\.rawValue).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(DirectorShadowLog.utcString(session.firstUTC)) through \(DirectorShadowLog.utcString(session.lastUTC))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Include session \(session.id.uuidString)")
                    .accessibilityValue("\(model.selectedSessions.contains(session.id) ? "Selected" : "Not selected"), \(session.recordCount) records, \(session.evidenceClasses.map(\.rawValue).joined(separator: ", ")), from \(DirectorShadowLog.utcString(session.firstUTC)) through \(DirectorShadowLog.utcString(session.lastUTC)) UTC")
                }
                Text("Excluded files: \(inventory.excludedFiles). Removed files: \(inventory.prunedFiles). Their record counts are unknown.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("From UTC (YYYY-MM-DDTHH:mm:ss.SSSZ)", text: $model.fromUTC)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Export from UTC")
                TextField("Through UTC (inclusive)", text: $model.throughUTC)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Export through UTC inclusive")
                Text(destination.map { "Destination: \($0.path)" } ?? "Choose a local destination to export.")
                    .font(.caption).textSelection(.enabled)
                Button("Export selected metadata") {
                    guard let destination else { return }
                    Task { await model.export(to: destination) }
                }
                .disabled(!model.canExport || destination == nil)
                .accessibilityLabel("Export selected metadata")
                .accessibilityHint("Creates a new local bundle. Existing destinations are never overwritten.")
            }
        }
        .disabled(model.isBusy)
        .frame(maxWidth: 760, alignment: .leading)
    }
}
