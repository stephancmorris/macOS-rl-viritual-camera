import Foundation
import Testing
@testable import Alfie

/// Synthetic bounded-log regressions. No camera, training data or permission
/// to operate a Director level is supplied by these fixtures.
@MainActor struct DirectorJudgeShadowProvenanceTests {
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private struct Rig {
        let directory: URL
        let log: DirectorShadowLog
        let show: ShowCoordinator
        let controller: DirectorController
    }

    private func style(movement: Double = 0.1) -> DirectorStyle {
        .init(minimumShotDuration: 1, preferredShotDuration: 2, softMaximumShotDuration: 30,
              wideCadence: 80, repetitionWindow: 5, maximumMovement: movement,
              settleTime: 1, onAirMoveRate: 0.2, cutOnMotionAllowed: false)
    }
    private func rig() throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("judge-provenance-\(UUID())")
        let utc = try #require(DirectorShadowExportManifest.utcDate("2026-10-21T00:00:00.000Z"))
        let log = try DirectorShadowLog(directory: directory, limits: .init(maximumRecordBytes: 16384,
            maximumQueuedBytes: 65536, maximumFileBytes: 65536, maximumStoreBytes: 131072), utcClock: { utc })
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { 100 }, shadowLog: log, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.preferencesChanged(.init(styles: [.liveEvent: style(), .presenter: style()]))
        controller.attach()
        controller.tick() // A valid baseline row makes later absence assertions nonvacuous.
        return .init(directory: directory, log: log, show: show, controller: controller)
    }
    private func sample(_ rig: Rig, now: Double, revision: UInt64, style: DirectorStyle,
                        provenance: [DirectorShadowRecord.EvidenceClass] = [.synthetic],
                        movement: Double = 0) -> DirectorJudgeShadow.Sample {
        .init(context: .init(timeline: .init(programShot: rig.show.channelA.directorShot,
            programStartedAt: 80, lastWideAt: 75, history: [], candidates: [
                .init(channel: .b, shot: .init(preset: .stage(.fullBody)), subjectConfidence: 0.9,
                      movement: movement, isWide: false)
            ], now: now), preview: .b, parameters: .init(style), evidenceRevision: revision, now: now),
            provenance: provenance)
    }
    private func rows(_ rig: Rig) async throws -> [DirectorShadowRecord] {
        await rig.log.flush()
        let file = rig.directory.appendingPathComponent("director_shadow_\(rig.log.sessionID.uuidString).jsonl")
        let data = try Data(contentsOf: file)
        return try data.split(separator: 10).map { try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0)) }
    }

    @Test(arguments: ["runSheet", "style"])
    func synchronousProviderMutationCannotStampOldComparisonWithNewContext(_ mutation: String) async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        let oldStyle = style(), oldPolicy = rig.controller.policyRevision
        let sheet = try RunSheet(segments: [.init(type: .presenter)])
        var called = false
        rig.controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            called = true
            let old = sample(rig, now: now, revision: revision, style: oldStyle)
            if mutation == "runSheet" {
                _ = rig.controller.setRunSheet(sheet) // Same style, different policy/segment binding.
            } else {
                rig.controller.preferencesChanged(.init(styles: [.liveEvent: style(movement: 0.2)]))
            }
            return old
        }
        rig.controller.tick()
        let records = try await rows(rig)
        #expect(called && !records.isEmpty)
        #expect(records.allSatisfy { $0.judgements.isEmpty })
        if mutation == "runSheet" { #expect(rig.controller.policyRevision == oldPolicy + 1) }
        else { #expect(rig.controller.effectiveStyle != oldStyle) }
        #expect(records.allSatisfy { $0.evidenceClass == .synthetic })
        #expect(rig.show.programChannel == .a && rig.controller.authority.level == .off)
    }

    @Test(arguments: ["missing", "mixed", "mismatched", "mixedCameras"])
    func missingOrMixedContributingProvenanceCannotReachComparisonLog(_ kind: String) async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        let inputClasses: [DirectorShadowRecord.EvidenceClass]
        switch kind {
        case "missing": inputClasses = []
        case "mixed": inputClasses = [.synthetic, .recorded]
        case "mismatched": inputClasses = [.recorded]
        default:
            inputClasses = [.synthetic]
            rig.controller.shadowRecorder?.provenanceForTesting = [.synthetic, .recorded]
        }
        var called = false
        rig.controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            called = true
            return sample(rig, now: now, revision: revision, style: style(), provenance: inputClasses)
        }
        rig.controller.tick()
        let records = try await rows(rig)
        #expect(called && !records.isEmpty)
        #expect(records.allSatisfy { $0.evidenceClass == .synthetic && $0.judgements.isEmpty })
    }

    @Test(arguments: [-0.1, 1.1, Double.nan, Double.infinity])
    func invalidTrialThresholdCannotBeRecordedAsRules(_ threshold: Double) async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        var called = false
        rig.controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: threshold), maximumAge: 1)) { now, revision in
            called = true
            return sample(rig, now: now, revision: revision, style: style())
        }
        rig.controller.tick()
        let records = try await rows(rig)
        #expect(!called && !records.isEmpty)
        #expect(records.allSatisfy { $0.judgements.isEmpty && $0.parameters.minimumProbability == nil })
    }

    @Test func invalidFeatureEvaluationCannotBeMislabelledAsRules() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            sample(rig, now: now, revision: revision, style: style(), movement: Double(Float.greatestFiniteMagnitude) * 2)
        }
        rig.controller.tick()
        let records = try await rows(rig)
        #expect(!records.isEmpty && records.allSatisfy { $0.judgements.isEmpty })
    }
}
