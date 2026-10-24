import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Authored synthetic perception through the real adapter, readiness, policy,
/// bounded writer and exporter. No independent labels or live evidence.
@MainActor struct DirectorDecisionCaptureTests {
    private final class Clock { var now = 100.0 }
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private final class Scheduler: DirectorCutDeadlineScheduling {
        var scheduled = 0
        func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void) { scheduled += 1 }
        func cancel() {}
    }
    private final class Sink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var sent = 0
        var isAvailable: Bool { true }
        var summary: String { "synthetic" }
        var detail: String { "synthetic" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { sent += 1; return true }
    }
    private struct Rig {
        let base: URL
        let show: ShowCoordinator
        let controller: DirectorController
        let clock: Clock
        let log: DirectorShadowLog
        let scheduler: Scheduler
        let sink: Sink
    }
    private var style: DirectorStyle {
        .init(minimumShotDuration: 1, preferredShotDuration: 2, softMaximumShotDuration: 30,
            wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.2, settleTime: 0,
            onAirMoveRate: 0.2, cutOnMotionAllowed: false)
    }
    private var readiness: DirectorReadiness.Parameters {
        .init(minimumSettledTime: 0, maximumMotion: 0.2, cutOnMotionAllowed: false,
              minimumCutSettledTime: 0, maximumCutMotion: 0.1)
    }
    private var utc: Date { DirectorShadowExportManifest.utcDate("2026-10-22T00:00:00.000Z")! }
    private func binding(_ version: UInt64 = 10) -> DirectorShadowRecorder.CaptureBinding {
        .init(parametersVersion: version, provenance: [.synthetic])
    }
    private func rig() throws -> Rig {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("decision-capture-\(UUID())")
        let date = utc
        let log = try DirectorShadowLog(directory: base.appendingPathComponent("source"),
            limits: .init(maximumRecordBytes: 16384, maximumQueuedBytes: 262144,
                maximumFileBytes: 262144, maximumStoreBytes: 524288), utcClock: { date })
        let clock = Clock(), sink = Sink(), scheduler = Scheduler()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        for id in ChannelID.allCases {
            guard let channel = show.channel(id) else { continue }
            channel.setRunningForTesting(true)
            channel.shotComposer.lockTarget(UUID()); channel.setOperationMode(.autoTracking)
            channel.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true,
                holdingSteady: true, subjectSpeed: 0)
            channel.cropEngine?.jumpToTarget()
        }
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
            qualifiedLevels: { [.assist, .auto] },
            adapterParameters: .init(maximumObservationAge: 2, debounce: 0, stillSpeed: 0.2),
            cutReadinessParameters: readiness, shadowLog: log, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist, .auto])
        }
        controller.preferencesChanged(.init(styles: [.liveEvent: style]))
        controller.attach()
        let result = Rig(base: base, show: show, controller: controller, clock: clock,
            log: log, scheduler: scheduler, sink: sink)
        try refresh(result)
        controller.tick()
        #expect(controller.setLevel(.assist) == .accepted)
        return result
    }
    private func refresh(_ r: Rig) throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        for id in ChannelID.allCases {
            guard let channel = r.show.channel(id) else { continue }
            channel.cropEngine?.jumpToTarget()
            channel.recordObservationForTesting(capturedAt: r.clock.now, personCount: 1)
            channel.setLatestRenderedFrameForTesting(.init(channelID: id, revisions: channel.revisions,
                sourceTimestamp: r.clock.now, processingStartedAt: r.clock.now, renderedAt: r.clock.now,
                crop: .fullFrame, outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
        }
    }
    private func prepare(_ r: Rig, capture: DirectorShadowRecorder.CaptureBinding? = nil) -> DirectorPreparationEffect {
        r.controller.preparePreview(.init(preset: .stage(.fullBody)), configuration: .init(readiness: readiness,
            maximumRequestAge: 1, onePreparationPerTenure: true, capture: capture))
    }
    private func configureCuts(_ r: Rig, version: UInt64 = 11,
                               provenance: [DirectorShadowRecord.EvidenceClass]? = [.synthetic],
                               contextChange: String? = nil) {
        r.controller.configureAutomaticCuts(.init(autoNoticeLength: 2, maximumLateness: 1, permitValidity: 0,
            judgeMaximumAge: 1, minimumProbability: nil, judge: RuleJudge(), capture: binding(version)),
            context: { now in
                guard let preview = r.show.previewChannel, let offAir = r.show.channel(preview),
                      let program = r.show.channel(r.show.programChannel) else { return nil }
                let shot = contextChange == "shot" ? DirectorShot(preset: .stage(.waistUp)) : offAir.directorShot
                let candidate = DirectorShotPolicy.Candidate(channel: preview, shot: shot, subjectConfidence: 0.9,
                    movement: offAir.evidenceReadings(now: now).subjectSpeed, isWide: shot.isWide)
                return .init(timeline: .init(programShot: program.directorShot, programStartedAt: now - 20,
                    lastWideAt: now - 30, history: [], candidates: [candidate], now: contextChange == "clock" ? now - 1 : now), prepared: candidate,
                    programIdentity: .confirmed, program: r.show.programChannel, programRevisions: program.revisions,
                    previewRevisions: offAir.revisions, routeGeneration: r.show.router.routeGeneration + (contextChange == "route" ? 1 : 0),
                    provenance: provenance)
            }, scheduler: r.scheduler)
    }
    private func rows(_ log: DirectorShadowLog) throws -> [DirectorShadowRecord] {
        let source = log.directory.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl")
        return try Data(contentsOf: source).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }

    @Test func actualDecisionExportKeepsPreparationIntentAndScoresOneManualTake() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        let before = try #require(r.show.channel(.b)).revisions
        guard case .committed = prepare(r, capture: binding()) else { Issue.record("Raw preparation refused"); return }
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
        r.clock.now += 1; try refresh(r); r.controller.tick()
        configureCuts(r)
        #expect(r.controller.setLevel(.auto) == .accepted)
        r.controller.evaluateAutomaticCuts()
        #expect(r.scheduler.scheduled == 1 && r.show.programChannel == .a && r.sink.sent == 0)
        #expect(r.show.take() == .committed(newProgram: .b))
        #expect(r.sink.sent == 1 && r.controller.cutExecution.lastResult == nil)
        await r.log.flush()
        let records = try rows(r.log)
        let preparation = try #require(records.first { $0.event.kind == .wouldPrepare })
        let cut = try #require(records.first { $0.event.kind == .wouldCut })
        #expect(records.filter { $0.event.kind == .wouldPrepare }.count == 1)
        #expect(records.filter { $0.event.kind == .wouldCut }.count == 1)
        #expect(preparation.event.proposalCreatedAt == 100 && preparation.eventTime == 100)
        #expect(preparation.event.proposalID != nil && preparation.event.requestID != nil)
        #expect(preparation.evidence.first?.revisions == .init(before))
        #expect(preparation.evidence.first?.prepareReadiness?.isReady == true)
        #expect(preparation.evidence.first?.cutReadiness == nil && preparation.context.programStartedAt == nil)
        #expect(preparation.parameters.parametersVersion?.value == 10)
        #expect(cut.parameters.parametersVersion?.value == 11 && cut.parameters.readiness == .init(readiness))
        #expect(cut.parameters.adapter == .init(try #require(r.controller.adapter).parameters))
        #expect(cut.parameters.resolvedStyle == .init(style) && cut.parameters.judgeMaximumAge == 1)
        #expect(cut.eventTime == 101 && cut.context.programStartedAt == 81 && cut.context.lastWideAt == 71)
        #expect(cut.evidence.first?.cutReadiness?.isReady == true && cut.evidence.first?.prepareReadiness == nil)
        #expect(cut.judgements.isEmpty && cut.scorerInputs == nil)
        let takes = records.filter { $0.event.action == .take }
        #expect(takes.count == 2 && takes[0].parameters == takes[1].parameters)
        #expect(takes[1].event.outcome == .completed && takes[1].context.programShot == cut.event.shot)
        #expect(takes.allSatisfy { $0.context.programStartedAt == nil && $0.context.lastWideAt == nil })
        #expect(r.log.metrics.dropped == 0 && records.allSatisfy { $0.evidenceClass == .synthetic })
        let destination = ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_DECISION_EXPORT"].map { URL(fileURLWithPath: $0) }
            ?? r.base.appendingPathComponent("bundle")
        let exported = try await r.log.export(selection: .init(sessionIDs: [r.log.sessionID], fromUTC: utc, throughUTC: utc),
            toNewBundle: destination)
        #expect(exported.manifest.recordCount == records.count && exported.manifest.recordSchemaVersions == [2])
        r.controller.detach()
    }

    @Test func absentBindingPreservesPreparationAndDoesNotInventDecisions() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        guard case .committed = prepare(r) else { Issue.record("Existing preparation changed"); return }
        await r.log.flush()
        #expect(try rows(r.log).allSatisfy { $0.event.kind != .wouldPrepare && $0.event.kind != .wouldCut && $0.parameters.status == .unavailable })
        #expect(r.log.metrics.dropped == 0)
        r.controller.detach()
    }

    @Test func preparationIntentDoesNotClaimTheLaterRefusedEffect() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        let before = try #require(r.show.channel(.b)).revisions
        r.controller.assistPreparation.dispatchForTesting = { _, _ in .rejected("synthetic refusal") }
        #expect(prepare(r, capture: binding()) == .failed)
        await r.log.flush()
        let intents = try rows(r.log).filter { $0.event.kind == .wouldPrepare }
        #expect(intents.count == 1 && intents[0].event.outcome == nil)
        #expect(r.show.channel(.b)?.revisions == before && r.show.programChannel == .a)
        r.controller.detach()
    }

    @Test(arguments: ["absent", "mixed", "mismatched"])
    func missingOrMixedContextProvenanceNeverProducesACutRecord(kind: String) async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        configureCuts(r, provenance: kind == "absent" ? nil : (kind == "mixed" ? [.synthetic, .recorded] : [.recorded]))
        #expect(r.controller.setLevel(.auto) == .accepted)
        r.controller.evaluateAutomaticCuts()
        await r.log.flush()
        #expect(try rows(r.log).allSatisfy { $0.event.kind != .wouldCut })
        #expect(r.log.metrics.dropped == 1 && r.show.programChannel == .a && r.sink.sent == 0)
        r.controller.detach()
    }

    @Test func overriddenReadinessIsNeverExportedAsAMeasuredBar() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        r.controller.assistPreparation.readinessForTesting = .init(reasons: [])
        guard case .committed = prepare(r, capture: binding()) else { Issue.record("Override preparation refused"); return }
        await r.log.flush()
        let intent = try #require(try rows(r.log).first { $0.event.kind == .wouldPrepare })
        #expect(intent.evidence.first?.prepareReadiness == nil)
        #expect(intent.parameters.readiness == .init(readiness))
        r.controller.detach()
    }

    @Test(arguments: ["clock", "route", "shot"])
    func reboundContextIsDroppedWithoutScheduling(kind: String) async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        configureCuts(r, contextChange: kind)
        #expect(r.controller.setLevel(.auto) == .accepted)
        r.controller.evaluateAutomaticCuts()
        await r.log.flush()
        #expect(try rows(r.log).allSatisfy { $0.event.kind != .wouldCut })
        #expect(r.log.metrics.dropped == 1 && r.scheduler.scheduled == 0)
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
        r.controller.detach()
    }

    @Test func decisionClockComesFromTheEvaluationInsteadOfASecondShowClockRead() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        configureCuts(r)
        #expect(r.controller.setLevel(.auto) == .accepted)
        r.show.clock = { r.clock.now + 0.001 }
        r.controller.evaluateAutomaticCuts()
        await r.log.flush()
        // Both cameras are wide here: policy may abstain. This assertion
        // selects the actual evaluated policy record, not the generic tick.
        let cut = try #require(try rows(r.log).first {
            $0.parameters.parametersVersion?.value == 11 && $0.event.stage == .cut
        })
        #expect(cut.eventTime == 100 && cut.evidence.first?.sampledAt == 100)
        #expect(cut.context.programStartedAt == 80)
        r.controller.detach()
    }

    @Test func parameterVersionReuseAndRollbackDropUntilAFreshVersionOrSession() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        let recorder = try #require(r.controller.shadowRecorder)
        func emit(_ version: UInt64, maximumAge: Double = 1) {
            let parameters = r.controller.captureParameters(binding(version), readiness: readiness, judgeMaximumAge: maximumAge)
            recorder.emit(DirectorShadowRecorder.noCutPolicy, show: r.show, authority: r.controller.authority,
                policy: r.controller.policyRevision, nomination: r.controller.nominationRevision,
                evidence: r.controller.evidenceRevision, preferences: r.controller.preferences,
                eventTime: r.clock.now, studyParameters: parameters)
        }
        emit(10); emit(10); emit(10, maximumAge: 2); emit(9); emit(11, maximumAge: 2); emit(10)
        await r.log.flush()
        #expect(r.log.metrics.dropped == 3)
        let available = try rows(r.log).filter { $0.parameters.status == .available }
        #expect(available.map { $0.parameters.parametersVersion?.value } == [10, 10, 11])
        recorder.restart(); emit(1)
        await recorder.log.flush()
        #expect(try rows(recorder.log).map { $0.parameters.parametersVersion?.value } == [1])
        r.controller.detach()
    }

    @Test func legacyComparisonCollisionReportsLossUntilTheSessionIsRenewed() async throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.base) }
        let recorder = try #require(r.controller.shadowRecorder)
        recorder.emit(DirectorShadowRecorder.noCutPolicy, show: r.show, authority: r.controller.authority,
            policy: r.controller.policyRevision, nomination: r.controller.nominationRevision,
            evidence: r.controller.evidenceRevision, preferences: r.controller.preferences,
            eventTime: r.clock.now, studyParameters: r.controller.captureParameters(binding(), readiness: readiness))
        r.controller.configureJudgeShadow(.init(judge: .init(model: nil, minimumProbability: 0.7), maximumAge: 1)) { now, revision in
            .init(context: .init(timeline: .init(programShot: r.show.channelA.directorShot,
                programStartedAt: now - 20, lastWideAt: now - 30, history: [],
                candidates: [.init(channel: .b, shot: .init(preset: .stage(.fullBody)), subjectConfidence: 0.9,
                    movement: 0, isWide: false)], now: now), preview: .b, parameters: .init(style),
                evidenceRevision: revision, now: now), provenance: [.synthetic])
        }
        r.controller.tick()
        await r.log.flush()
        #expect(r.log.metrics.dropped == 1)
        #expect(try rows(r.log).allSatisfy { $0.judgements.isEmpty })
        recorder.restart()
        r.controller.tick()
        await recorder.log.flush()
        let renewed = try rows(recorder.log)
        #expect(renewed.count == 1 && renewed[0].judgements.count == 2)
        #expect(renewed[0].parameters.parametersVersion?.value == r.controller.policyRevision)
        #expect(renewed[0].parameters.readiness == nil && renewed[0].parameters.adapter == nil)
        r.controller.detach()
    }
}
