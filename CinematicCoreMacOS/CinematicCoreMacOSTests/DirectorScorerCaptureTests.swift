import Foundation
import Testing
@testable import Alfie

/// Actual bounded writer/export path with authored synthetic context and labels.
/// The optional export is a test dataset, never recorded/live training evidence.
@MainActor struct DirectorScorerCaptureTests {
    private final class Clock { var now: Double = 100 }
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private let style = DirectorStyle(minimumShotDuration: 1, preferredShotDuration: 2, softMaximumShotDuration: 30,
        wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.1, settleTime: 1, onAirMoveRate: 0.2, cutOnMotionAllowed: false)

    @Test func materializedHistorySurvivesBoundedStorageAndExplicitExport() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("scorer-capture-\(UUID())")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: scratch) }
        let destination: URL
        if let requested = ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_TRAINING_EXPORT"] {
            #expect(requested.hasPrefix("/") && !requested.isEmpty)
            destination = URL(fileURLWithPath: requested).standardizedFileURL
            guard requested.hasPrefix("/"), !fm.fileExists(atPath: destination.path) else {
                throw DirectorShadowLog.Failure.unavailable
            }
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        } else {
            destination = scratch.appendingPathComponent("dataset")
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        }
        let utc = try #require(DirectorShadowExportManifest.utcDate("2026-10-21T00:00:00.000Z"))
        let directory = scratch.appendingPathComponent("source")
        var sessions: [UUID] = []
        var lastLog: DirectorShadowLog?
        for session in 0..<3 {
            let clock = Clock(); clock.now = 100 + Double(session * 100)
            let log = try DirectorShadowLog(directory: directory, limits: .init(maximumRecordBytes: 16384,
                maximumQueuedBytes: 65536, maximumFileBytes: 131072, maximumStoreBytes: 524288), utcClock: { utc })
            let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
                qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
            show.clock = { clock.now }; show.channelA.setRunningForTesting(true); show.addChannel(.b).setRunningForTesting(true)
            let controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now }, shadowLog: log, log: { _ in })
            controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
            controller.preferencesChanged(.init(styles: [.liveEvent: style]))
            controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
                let context = DirectorJudgeContext(timeline: .init(programShot: show.channelA.directorShot,
                    programStartedAt: now - 20, lastWideAt: now - 30,
                    history: [.init(shot: .init(preset: .stage(.fullBody)), endedAt: now - 80),
                              .init(shot: .init(preset: .webcam(.wide)), endedAt: now - 70)],
                    candidates: [.init(channel: .b, shot: .init(preset: .stage(.fullBody)), subjectConfidence: 0.9, movement: 0.01, isWide: false),
                                 .init(channel: .b, shot: .init(preset: .stage(.waistUp)), subjectConfidence: 0.8, movement: 0.02, isWide: false)], now: now),
                    preview: .b, parameters: .init(style), evidenceRevision: revision, now: now)
                return .init(context: context, provenance: [.synthetic])
            }
            controller.attach()
            for _ in 0..<4 { controller.tick(); clock.now += 1 }
            controller.detach(); await log.flush()
            sessions.append(log.sessionID); lastLog = log
            #expect(log.metrics.dropped == 0)
        }
        let log = try #require(lastLog)
        let selection = DirectorShadowExportSelection(sessionIDs: Set(sessions), fromUTC: utc, throughUTC: utc)
        let exported = try await log.export(selection: selection, toNewBundle: destination.appendingPathComponent("bundle"))
        #expect(exported.manifest.recordSchemaVersions == [2] && exported.manifest.recordCount == 12)
        let bytes = try Data(contentsOf: destination.appendingPathComponent("bundle/records.jsonl"))
        let records = try bytes.split(separator: 10).map { try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0)) }
        #expect(records.count == 12 && records.allSatisfy { $0.evidenceClass == .synthetic })
        for record in records {
            let inputs = try #require(record.scorerInputs)
            #expect(inputs.count == 2 && inputs.map(\.candidateRank) == [0, 1])
            #expect(inputs.map { $0.features[4] } == [2, 2])
            #expect(inputs.map { $0.features[5] } == [1, 0])
            #expect(inputs.allSatisfy { $0.judgementIndex == 0 && $0.featureSchemaVersion == 1 && $0.features.count == 16 })
        }
        let labels: [[String: Any]] = records.map { ["recordID": $0.recordID.value.uuidString,
            "judgementIndex": 0, "chosenRank": Int($0.sequence.value % 2)] }
        let splits: [String: Any] = ["splitSchemaVersion": 1, "evidenceClass": "synthetic",
            "train": [sessions[0].uuidString], "validation": [sessions[1].uuidString], "test": [sessions[2].uuidString]]
        try JSONSerialization.data(withJSONObject: ["labelSchemaVersion": 1, "labels": labels], options: [.sortedKeys])
            .write(to: destination.appendingPathComponent("labels.json"), options: .withoutOverwriting)
        try JSONSerialization.data(withJSONObject: splits, options: [.sortedKeys])
            .write(to: destination.appendingPathComponent("splits.json"), options: .withoutOverwriting)
        try malformedInputsFailClosed(try #require(records.first))
    }

    private func malformedInputsFailClosed(_ original: DirectorShadowRecord) throws {
        typealias R = DirectorShadowRecord
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for change in ["version", "v1Null", "unknown", "featureVersion", "missingRank", "duplicate", "order", "learnedIndex", "nonFloat", "history", "onehot", "confidence", "future", "parameters"] {
            var row = object
            var inputs = try #require(row["scorerInputs"] as? [[String: Any]])
            var values = try #require(inputs[0]["features"] as? [Double])
            switch change {
            case "version": row["schemaVersion"] = 3
            case "v1Null": row["schemaVersion"] = 1; row["scorerInputs"] = NSNull()
            case "unknown": inputs[0]["personName"] = "PRIVATE-SENTINEL"
            case "featureVersion": inputs[0]["featureSchemaVersion"] = 2
            case "missingRank": inputs.removeLast()
            case "duplicate": inputs.append(inputs[0])
            case "order": inputs.reverse()
            case "learnedIndex": inputs[0]["judgementIndex"] = 99
            case "nonFloat": values[0] = 0.1
            case "history": values[5] = values[4] + 1
            case "onehot": values[6] = 1
            case "confidence": values[0] = 0
            case "future": row["eventTime"] = 0
            case "parameters": row["parameters"] = ["status": "unavailable"]
            default: break
            }
            if ["nonFloat", "history", "onehot", "confidence"].contains(change) { inputs[0]["features"] = values }
            if change != "v1Null" { row["scorerInputs"] = inputs }
            let bad = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(R.self, from: bad) }
        }
        var legacy = object; legacy["schemaVersion"] = 1; legacy.removeValue(forKey: "scorerInputs")
        let old = try JSONDecoder().decode(R.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.schemaVersion == 1 && old.scorerInputs == nil)
        var invalid = original
        let first = try #require(original.scorerInputs?.first)
        var values = first.features; values[0] = .nan
        invalid.scorerInputs = [.init(featureSchemaVersion: 1, judgementIndex: 0, candidateRank: 0, features: values)]
        #expect(throws: (any Error).self) { try invalid.validated() }
    }
}
