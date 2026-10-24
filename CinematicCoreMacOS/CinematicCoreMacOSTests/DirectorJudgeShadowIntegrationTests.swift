import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorJudgeShadowIntegrationTests {
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private struct Model: DirectorScoringModel {
        let featureSchemaVersion = 1
        let modelVersion = "synthetic-ab-1"
        func probability(for features: DirectorJudgeFeatures) throws -> Double { 0.8 }
    }
    private let style = DirectorStyle(minimumShotDuration: 1, preferredShotDuration: 2, softMaximumShotDuration: 30,
        wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.1, settleTime: 1, onAirMoveRate: 0.2,
        cutOnMotionAllowed: false)

    @Test(arguments: [true, false])
    func actualBoundedLogContainsBaselineAndEffectiveJudgeWithoutEffects(_ modelPresent: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("judge-shadow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let utc = try #require(DirectorShadowExportManifest.utcDate("2026-10-21T00:00:00.000Z"))
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 16384,
            maximumQueuedBytes: 65536, maximumFileBytes: 65536, maximumStoreBytes: 131072), utcClock: { utc })
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }; show.channelA.setRunningForTesting(true); show.addChannel(.b).setRunningForTesting(true)
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { 100 }, shadowLog: log, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.preferencesChanged(.init(styles: [.liveEvent: style]))
        controller.configureJudgeShadow(.init(judge: LearnedJudge(model: modelPresent ? Model() : nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            .init(context: .init(timeline: .init(programShot: show.channelA.directorShot, programStartedAt: 80,
                lastWideAt: 75, history: [], candidates: [.init(channel: .b, shot: .init(preset: .stage(.fullBody)),
                    subjectConfidence: 0.9, movement: 0, isWide: false)], now: now),
                preview: .b, parameters: .init(style), evidenceRevision: revision, now: now), provenance: [.synthetic])
        }
        controller.attach(); controller.tick(); await log.flush()
        let data = try Data(contentsOf: root.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl"))
        let row = try JSONDecoder().decode(DirectorShadowRecord.self, from: Data(try #require(data.split(separator: 10).last)))
        #expect(row.evidenceClass == .synthetic && row.judgements.count == 2)
        #expect(row.judgements[0].judgeKind == .rules)
        #expect(row.judgements[1].judgeKind == (modelPresent ? .learned : .rules))
        #expect(row.judgements.allSatisfy { $0.gateResult == .notEvaluated && $0.acceptedRank == nil })
        #expect(row.context.programStartedAt == 80 && row.context.lastWideAt == 75 && row.parameters.status == .available)
        #expect(row.judgements[1].modelVersion == (modelPresent ? "synthetic-ab-1" : nil))
        #expect(show.programChannel == .a && controller.authority.level == .off)
        #expect(show.channel(.b)?.manualLockedTargetID == nil)
    }

    @Test(arguments: ["missing", "wrongPreview", "oldEvidence", "future", "wrongProgram", "wrongParameters"])
    func incompatibleContextCannotBeRecordedAsABEvidence(_ bad: String) {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }; show.channelA.setRunningForTesting(true); show.addChannel(.b).setRunningForTesting(true)
        let trial = DirectorJudgeShadow()
        trial.configure(.init(judge: .init(model: Model(), minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            if bad == "missing" { return nil }
            return .init(context: .init(timeline: .init(programShot: bad == "wrongProgram" ? .init(preset: .stage(.waistUp)) : show.channelA.directorShot,
                programStartedAt: 80, lastWideAt: 75, history: [], candidates: [], now: now),
                preview: bad == "wrongPreview" ? .a : .b,
                parameters: bad == "wrongParameters" ? .init(minimumShotDuration: 0, maximumShotDuration: 1,
                    wideCadence: 1, repetitionWindow: 0, maximumMovement: 0, cutOnMotionAllowed: false) : .init(style),
                evidenceRevision: bad == "oldEvidence" ? revision - 1 : revision,
                now: bad == "future" ? now + 1 : now), provenance: [.synthetic])
        }
        #expect(trial.observe(show: show, now: 100, evidenceRevision: 3, style: style, policyRevision: 2) == nil)
    }
}
