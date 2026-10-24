#if DEBUG
import Combine
import Foundation
import SwiftUI

/// All records and limits here are synthetic gallery inputs, never production defaults.
private final class DirectorShadowExportGallery: ObservableObject {
    let model = DirectorShadowExportModel()
    @Published private(set) var destination: URL
    @Published private(set) var preparing = false
    @Published private(set) var setupMessage = "No sessions created."
    private var logs: [DirectorShadowLog] = []
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Alfie-shadow-export-gallery-\(UUID())")
        destination = root.appendingPathComponent("metadata-\(UUID()).alfieshadow")
    }

    func newDestination() {
        destination = root.appendingPathComponent("metadata-\(UUID()).alfieshadow")
    }

    func createSessions() async {
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        do {
            let now = Date()
            let limits = DirectorShadowLog.Limits(maximumRecordBytes: 4096, maximumQueuedBytes: 32768,
                maximumFileBytes: 32768, maximumStoreBytes: 131072)
            for _ in 0..<2 {
                let log = try DirectorShadowLog(directory: root.appendingPathComponent("ordinary-logs"),
                    limits: limits)
                for sequence in 0..<3 {
                    let data: [String: Any] = [
                        "schemaVersion": 1, "recordID": UUID().uuidString, "sessionID": log.sessionID.uuidString,
                        "sequence": String(sequence), "recordedAtUTC": DirectorShadowLog.utcString(now.addingTimeInterval(Double(sequence) - 2)),
                        "eventTime": Double(sequence), "evidenceClass": "synthetic", "executionMode": "shadow",
                        "context": ["inputs": ["input-1"], "program": "input-1", "level": "off", "paused": false,
                            "editLive": false, "running": true, "healthy": true, "evidenceAvailable": false,
                            "mayPropose": false, "mayPrepare": false, "mayTake": false, "authorityEpoch": "0",
                            "routeGeneration": "0", "policyRevision": "0", "nominationRevision": "0", "evidenceRevision": "0",
                            "segmentType": "liveEvent"],
                        "parameters": ["status": "unavailable"], "evidence": [], "judgements": [],
                        "event": ["kind": "abstention", "decisionID": UUID().uuidString, "stage": "cut",
                            "reasons": [["domain": "observation", "code": "cutPolicyUnavailable"]]],
                        "invalidFields": [], "droppedRecordsBefore": "0"]
                    let record = try JSONDecoder().decode(DirectorShadowRecord.self,
                        from: JSONSerialization.data(withJSONObject: data))
                    guard log.append(record, provenance: [.synthetic]) else { throw DirectorShadowLog.Failure.unavailable }
                }
                await log.flush()
                guard log.metrics.written == 3 else { throw DirectorShadowLog.Failure.unavailable }
                logs.append(log)
            }
            model.logProvider = { [weak self] in self?.logs.first }
            await model.load()
            setupMessage = "Synthetic metadata sessions created. No camera, authority or qualification was used."
        } catch {
            setupMessage = "Synthetic setup failed. No export was created."
        }
    }
}

struct DirectorShadowExportDemo: View {
    @StateObject private var gallery = DirectorShadowExportGallery()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Synthetic export rehearsal. The visible destination is a new folder inside this app's temporary container.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Create synthetic export sessions") { Task { await gallery.createSessions() } }
                    .disabled(gallery.preparing || gallery.model.isBusy)
                    .accessibilityLabel("Create synthetic export sessions")
                Button("Use a new synthetic destination") { gallery.newDestination() }
                    .accessibilityLabel("Use a new synthetic destination")
                    .disabled(gallery.preparing || gallery.model.isBusy)
            }
            Text(gallery.setupMessage).font(.caption).foregroundStyle(.secondary)
            DirectorShadowExportView(model: gallery.model, destination: gallery.destination)
        }
    }
}
#endif
