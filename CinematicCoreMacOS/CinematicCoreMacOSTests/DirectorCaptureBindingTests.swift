import Foundation
import Testing
@testable import Alfie

/// Authored synthetic study settings through the real bounded recorder. These
/// observations provide no qualification, independent labels or camera effects.
@MainActor struct DirectorCaptureBindingTests {
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private final class Scheduler: DirectorCutDeadlineScheduling {
        func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void) {}
        func cancel() {}
    }
    private struct Rig {
        let directory: URL
        let log: DirectorShadowLog
        let show: ShowCoordinator
        let controller: DirectorController
        let scheduler: Scheduler
    }
    private let readiness = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 0.2,
        cutOnMotionAllowed: false, minimumCutSettledTime: 0, maximumCutMotion: 0.1)
    private let adapter = DirectorEvidenceAdapter.Parameters(maximumObservationAge: 2, debounce: 0, stillSpeed: 0.2)
    private func style(_ minimum: Double) -> DirectorStyle {
        .init(minimumShotDuration: minimum, preferredShotDuration: minimum + 1,
            softMaximumShotDuration: 30, wideCadence: 80, repetitionWindow: 5,
            maximumMovement: 0.2, settleTime: 0, onAirMoveRate: 0.2, cutOnMotionAllowed: false)
    }
    private func binding(_ version: UInt64) -> DirectorShadowRecorder.CaptureBinding {
        .init(parametersVersion: version, provenance: [.synthetic])
    }
    private func rig(sameStyle: Bool = false) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("capture-binding-\(UUID())")
        let utc = try #require(DirectorShadowExportManifest.utcDate("2026-10-22T00:00:00.000Z"))
        let log = try DirectorShadowLog(directory: directory, limits: .init(maximumRecordBytes: 16384,
            maximumQueuedBytes: 262144, maximumFileBytes: 262144, maximumStoreBytes: 524288), utcClock: { utc })
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }; show.router.clock = { 100 }
        show.addChannel(.b)
        for id in ChannelID.allCases {
            guard let channel = show.channel(id) else { continue }
            channel.setRunningForTesting(true)
            channel.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true,
                holdingSteady: true, subjectSpeed: 0)
        }
        let sheet = try RunSheet(segments: [.init(type: .presenter), .init(type: .panel)])
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { 100 },
            adapterParameters: adapter, cutReadinessParameters: readiness,
            shadowLog: log, runSheet: sheet, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.preferencesChanged(.init(styles: [.liveEvent: style(1), .presenter: style(1),
            .panel: style(sameStyle ? 1 : 2)]))
        controller.attach()
        return .init(directory: directory, log: log, show: show, controller: controller, scheduler: Scheduler())
    }
    private func configureCuts(_ r: Rig) {
        r.controller.configureAutomaticCuts(.init(autoNoticeLength: 2, maximumLateness: 1, permitValidity: 0,
            judgeMaximumAge: 1, minimumProbability: 0.7, judge: RuleJudge()), context: { now in
                guard let preview = r.show.previewChannel, let channel = r.show.channel(preview),
                      let program = r.show.channel(r.show.programChannel) else { return nil }
                let candidate = DirectorShotPolicy.Candidate(channel: preview, shot: channel.directorShot,
                    subjectConfidence: 0.9, movement: channel.evidenceReadings(now: now).subjectSpeed,
                    isWide: channel.directorShot.isWide)
                return .init(timeline: .init(programShot: program.directorShot, programStartedAt: 80,
                    lastWideAt: 70, history: [], candidates: [candidate], now: now), prepared: candidate,
                    programIdentity: .confirmed, program: r.show.programChannel,
                    programRevisions: program.revisions, previewRevisions: channel.revisions,
                    routeGeneration: r.show.router.routeGeneration, provenance: [.synthetic])
            }, scheduler: r.scheduler)
    }
    private func configureComparison(_ r: Rig) {
        r.controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            guard let style = r.controller.effectiveStyle, let preview = r.show.previewChannel,
                  let channel = r.show.channel(preview) else { return nil }
            return .init(context: .init(timeline: .init(programShot: r.show.channelA.directorShot,
                programStartedAt: 80, lastWideAt: 70, history: [], candidates: [
                    .init(channel: preview, shot: channel.directorShot, subjectConfidence: 0.9,
                        movement: 0, isWide: channel.directorShot.isWide)
                ], now: now), preview: preview, parameters: .init(style), evidenceRevision: revision, now: now),
                provenance: [.synthetic])
        }
    }
    private func rows(_ r: Rig) async throws -> [DirectorShadowRecord] {
        await r.log.flush()
        let file = r.directory.appendingPathComponent("director_shadow_\(r.log.sessionID.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try Data(contentsOf: file).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }

    @Test func actualCompleteGroupsBindSegmentAndComparisonAlongsideCutCapture() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.directory) }
        r.controller.configureCaptureForStudy { key in
            if key.style == style(1) { return binding(10) }
            if key.style == style(2) { return binding(11) }
            return nil
        }
        configureCuts(r); configureComparison(r)
        r.controller.tick(); r.controller.advanceSegment(); r.controller.tick()
        let records = try await rows(r)
        let advances = records.filter { $0.event.action == .advanceSegment }
        #expect(advances.count == 2)
        #expect(advances.map { $0.parameters.parametersVersion?.value } == [10, 11])
        #expect(advances[0].event.phase == .attempt && advances[1].event.phase == .result)
        #expect(advances[1].event.outcome == .accepted)
        #expect(advances[1].context.policyRevision.value == advances[0].context.policyRevision.value + 1)
        #expect(records.allSatisfy { $0.parameters.status == .available && $0.parameters.readiness == .init(readiness)
            && $0.parameters.adapter == .init(adapter) && $0.parameters.judgeMaximumAge == 1
            && $0.parameters.minimumProbability == 0.7 })
        #expect(Set(records.filter { $0.event.stage == .cut }.compactMap { $0.parameters.parametersVersion?.value }) == [10, 11])
        #expect(Set(records.filter { $0.event.stage == .judge }.compactMap { $0.parameters.parametersVersion?.value }) == [10, 11])
        #expect(r.log.metrics.dropped == 0 && r.show.programChannel == .a && r.controller.authority.level == .off)
        if let requested = ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_BINDING_EXPORT"] {
            #expect(requested.hasPrefix("/") && !FileManager.default.fileExists(atPath: requested))
            guard requested.hasPrefix("/"), !FileManager.default.fileExists(atPath: requested) else {
                throw DirectorShadowLog.Failure.unavailable
            }
            let utc = try #require(DirectorShadowExportManifest.utcDate("2026-10-22T00:00:00.000Z"))
            _ = try await r.log.export(selection: .init(sessionIDs: [r.log.sessionID], fromUTC: utc, throughUTC: utc),
                toNewBundle: URL(fileURLWithPath: requested))
        }
        r.controller.detach()
    }

    @Test func identicalSegmentGroupsCanReuseTheSameSuppliedVersion() async throws {
        let r = try rig(sameStyle: true); defer { try? FileManager.default.removeItem(at: r.directory) }
        r.controller.configureCaptureForStudy { _ in binding(10) }
        configureCuts(r)
        r.controller.advanceSegment()
        let records = try await rows(r)
        #expect(records.count == 2 && records.map { $0.parameters.parametersVersion?.value } == [10, 10])
        #expect(records[0].parameters == records[1].parameters && r.log.metrics.dropped == 0)
        r.controller.detach()
    }

    @Test func missingProviderBindingCannotFallBackToStaticBindingOrLegacyComparison() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.directory) }
        r.controller.configureCaptureForStudy { _ in nil }
        #expect(r.controller.captureParameters(binding(10), readiness: readiness) == nil)
        configureComparison(r)
        r.controller.tick()
        #expect(try await rows(r).isEmpty)
        #expect(r.log.metrics.dropped == 1)
        r.controller.detach()
    }

    @Test(arguments: ["policy", "provider", "judge", "cut", "source"])
    func reentrantProviderCannotBindAnEarlierActualGroup(_ change: String) throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.directory) }
        var calls = 0
        r.controller.configureCaptureForStudy { key in
            calls += 1
            #expect(key.style == style(1) && DirectorShadowRecord.ReadinessParameters(key.readiness) == .init(readiness) && key.adapter == adapter)
            #expect(key.preferencesVersion == DirectorPreferences.currentVersion)
            switch change {
            case "policy": _ = r.controller.setRunSheet(try? RunSheet(segments: [.init(type: .presenter)]))
            case "provider": r.controller.configureCaptureForStudy(nil)
            case "judge": r.controller.configureJudgeShadow(nil)
            case "source": r.show.channelA.setRunningForTesting(false)
            default: r.controller.configureAutomaticCuts(nil)
            }
            return binding(10)
        }
        #expect(r.controller.captureParameters(nil, readiness: readiness, judgeMaximumAge: 1,
            minimumProbability: 0.7) == nil)
        #expect(calls == 1)
        r.controller.detach()
    }
}
