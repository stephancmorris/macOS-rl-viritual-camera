import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Decision core, stage 3: with the scene in hand, the existing rules run
/// every tick and the shadow records what they would do. Nothing on air changes.
@MainActor struct DirectorShadowJudgeTests {
    @MainActor private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    @MainActor private final class Clock { var now: TimeInterval = 100 }
    private final class Sink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var isAvailable: Bool { true }
        var summary: String { "synthetic" }
        var detail: String { "synthetic" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
    }
    @MainActor private struct Rig {
        let root: URL
        let log: DirectorShadowLog
        let show: ShowCoordinator
        let controller: DirectorController
        let clock: Clock
        let pixels: CVPixelBuffer
        var a: CameraManager { show.channelA }
        var b: CameraManager { show.channel(.b)! }
    }

    /// Test style: a 2 s minimum shot and a 6 s preferred length.
    private static let style = DirectorStyle(minimumShotDuration: 2, preferredShotDuration: 6, softMaximumShotDuration: 30,
        wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.2, settleTime: 0, onAirMoveRate: 0.2,
        cutOnMotionAllowed: false)

    /// The fixture: Program wide on A, Preview waist-up on B. A locked subject
    /// on B, and on A unless `programLocked` is false.
    /// `study` is what the Director is built with; `appDirector` uses the
    /// show's own Director, built as the app builds it (never attached here,
    /// so its real ticker never runs).
    private func rig(programLocked: Bool = true, previewPhase: RecoveryState.Phase = .tracking,
                     capabilities: DirectorCapabilities = .full, study: String = "shadowV1",
                     appDirector: Bool = false) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-judge-\(UUID())")
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 16384,
            maximumQueuedBytes: 1_048_576, maximumFileBytes: 16_777_216, maximumStoreBytes: 33_554_432))
        let clock = Clock()
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: [Sink()]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "shadow-judge-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false),
            directorShadowLog: appDirector ? log : nil, directorCapabilities: capabilities)
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        for id in ChannelID.allCases {
            guard let camera = show.channel(id) else { continue }
            camera.setRunningForTesting(true)
            guard id == .b || programLocked else { continue }
            camera.shotComposer.lockTarget(UUID())
            camera.setOperationMode(.autoTracking)
            camera.directorPerceptionForTesting = .init(phase: id == .b ? previewPhase : .tracking,
                galleryReady: true, holdingSteady: true, subjectSpeed: 0)
        }
        #expect(show.dispatch(show.makeCommand(.selectPreset(.stage(.waistUp)))).wasAccepted)
        #expect(show.channel(.b)!.directorShot == .init(preset: .stage(.waistUp)))
        #expect(show.channelA.directorShot.isWide)
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        let shadowV1 = DirectorStudyParameters.shadowV1
        let controller: DirectorController
        if appDirector {
            controller = show.director
        } else if study == "shadowV1" {
            // The app's own named set.
            controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
                capabilities: capabilities, studyParameters: shadowV1, shadowLog: log, log: { _ in })
        } else if study == "sameValuesUnnamed" {
            controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
                capabilities: capabilities, adapterParameters: shadowV1.adapter,
                cutReadinessParameters: shadowV1.readiness, shadowLog: log, log: { _ in })
        } else {
            // Named, but the explicit adapter values differ from the set's.
            controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
                capabilities: capabilities, adapterParameters: .init(maximumObservationAge: 2, debounce: 0, stillSpeed: 0.2),
                studyParameters: shadowV1, shadowLog: log, log: { _ in })
        }
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.preferencesChanged(.init(styles: [.liveEvent: Self.style]))
        if !appDirector { controller.attach() }
        return .init(root: root, log: log, show: show, controller: controller, clock: clock, pixels: pixels)
    }

    /// One Director tick, with fresh synthetic perception and a fresh Preview frame.
    private func tick(_ r: Rig, _ count: Int = 1, each: ((Rig) -> Void)? = nil) {
        for _ in 0..<count {
            r.clock.now += DirectorController.tickInterval
            for id in ChannelID.allCases {
                guard let camera = r.show.channel(id) else { continue }
                camera.recordObservationForTesting(capturedAt: r.clock.now, personCount: 1)
                camera.cropEngine?.jumpToTarget()
                camera.setLatestRenderedFrameForTesting(.init(channelID: id, revisions: camera.revisions,
                    sourceTimestamp: r.clock.now, processingStartedAt: r.clock.now, renderedAt: r.clock.now,
                    crop: .fullFrame, outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: r.pixels))
            }
            r.controller.tick()
            each?(r)
        }
    }

    /// Ticks until the clock reaches `time` since attach (100).
    private func tick(_ r: Rig, until time: TimeInterval, each: ((Rig) -> Void)? = nil) {
        while r.clock.now + DirectorController.tickInterval <= 100 + time + 1e-9 { tick(r, each: each) }
    }

    private func records(_ r: Rig) async throws -> [DirectorShadowRecord] {
        await r.log.flush()
        let url = r.log.directory.appendingPathComponent("director_shadow_\(r.log.sessionID.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }

    private func fileBytes(_ r: Rig) async throws -> Int {
        await r.log.flush()
        let url = r.log.directory.appendingPathComponent("director_shadow_\(r.log.sessionID.uuidString).jsonl")
        return try Data(contentsOf: url).count
    }

    private func cuts(_ rows: [DirectorShadowRecord]) -> [DirectorShadowRecord] { rows.filter { $0.event.kind == .wouldCut } }
    private func prepares(_ rows: [DirectorShadowRecord]) -> [DirectorShadowRecord] { rows.filter { $0.event.kind == .wouldPrepare } }
    private func abstentions(_ rows: [DirectorShadowRecord], _ stage: DirectorShadowRecord.Stage,
                             _ code: DirectorShadowRecord.ReasonCode) -> [DirectorShadowRecord] {
        rows.filter { $0.event.kind == .abstention && $0.event.stage == stage && $0.event.reasons?.contains { $0.code == code } == true }
    }

    // MARK: Cut

    @Test func oneWouldCutAfterTheMinimumAndThePreferredLength() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 5.75)
        #expect(cuts(try await records(r)).isEmpty)
        tick(r, until: 6)
        var rows = try await records(r)
        #expect(cuts(rows).count == 1)
        let cut = try #require(cuts(rows).first)
        #expect(cut.event.target == "input-2")
        #expect(cut.event.shot == .init(.init(preset: .stage(.waistUp))))
        #expect(cut.eventTime == 106)
        #expect(cut.schemaVersion == 3)
        #expect(cut.event.reason == .init(domain: .selection, code: .preferredLength))
        #expect(cut.parameters.status == .available)
        #expect(cut.context.programStartedAt == 100 && cut.context.level == .off)
        #expect(cut.judgements.first?.judgeKind == .rules)
        // Not repeated on later ticks.
        tick(r, until: 30)
        rows = try await records(r)
        #expect(cuts(rows).count == 1)
        #expect(r.log.metrics.dropped == 0 && r.log.metrics.storageErrors == 0)
    }

    @Test func beforeTheMinimumTheCutAbstainsOnce() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 1.75)
        let rows = try await records(r)
        let dwell = abstentions(rows, .cut, .minimumDuration)
        #expect(dwell.count == 1)
        #expect(dwell.first?.event.reasons == [.init(domain: .policy, code: .minimumDuration)])
        #expect(cuts(rows).isEmpty)
        #expect(r.log.metrics.dropped == 0)
    }

    @Test func anUnconfirmedProgramSubjectCutsAtTheMinimum() async throws {
        let r = try rig(programLocked: false)
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 1.75)
        #expect(cuts(try await records(r)).isEmpty)
        tick(r, until: 2)
        let rows = try await records(r)
        #expect(cuts(rows).count == 1)
        #expect(cuts(rows).first?.eventTime == 102)
        #expect(cuts(rows).first?.event.reason == .init(domain: .selection, code: .programUncertain))
    }

    // MARK: Prepare

    @Test func learningTheSubjectAbstainsOnceThenOneWouldPrepare() async throws {
        let r = try rig(previewPhase: .acquiring)
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 4)
        var rows = try await records(r)
        #expect(r.controller.adapter?.state(for: .b)?.identity == .acquiring)
        let learning = abstentions(rows, .prepare, .learningSubject)
        #expect(learning.count == 1)
        #expect(learning.first?.event.reasons == [.init(domain: .readiness, code: .learningSubject)])
        #expect(prepares(rows).isEmpty)
        r.b.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true, holdingSteady: true, subjectSpeed: 0)
        tick(r, until: 8)
        rows = try await records(r)
        #expect(abstentions(rows, .prepare, .learningSubject).count == 1)
        #expect(prepares(rows).count == 1)
        let prepare = try #require(prepares(rows).first)
        #expect(prepare.event.target == "input-2")
        #expect(prepare.event.reason == .init(domain: .selection, code: .subjectEvidence))
        #expect(prepare.parameters.status == .available)
        #expect(r.log.metrics.dropped == 0)
    }

    // MARK: Operator

    @Test func anOperatorTakeRestartsTheTimingAndRestatesTheJudge() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 8)
        let before = try await records(r).count
        let take = r.show.take()
        #expect(take == .committed(newProgram: .b))
        tick(r)
        let scene = try #require(r.controller.latestScene)
        #expect(scene.program == .b && scene.programStartedAt == r.clock.now)
        let after = Array(try await records(r).dropFirst(before))
        #expect(after.prefix(2).allSatisfy { $0.event.kind == .operatorAction && $0.event.action == .take })
        let judge = after.dropFirst(2)
        // Both sides of the judge are written again, after the Take.
        #expect(judge.contains { $0.event.stage == .prepare || $0.event.kind == .wouldPrepare })
        #expect(judge.contains { $0.event.stage == .cut && $0.event.reasons == [.init(domain: .policy, code: .minimumDuration)] })
        #expect(judge.allSatisfy { $0.context.programStartedAt == r.clock.now })
        #expect(r.log.metrics.dropped == 0)
    }

    // MARK: Agreement and no effect

    /// The core's outcome equals the existing pure functions called directly
    /// with the same inputs, on every tick of each fixture.
    @Test(arguments: ["confirmed", "unconfirmedProgram", "learning"])
    func theCoreAgreesWithThePureFunctions(_ fixture: String) throws {
        let r = try rig(programLocked: fixture != "unconfirmedProgram",
                        previewPhase: fixture == "learning" ? .acquiring : .tracking)
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let study = DirectorStudyParameters.shadowV1
        var compared = 0, cutsSeen = 0, preparesSeen = 0
        tick(r, until: 12) { r in
            guard let scene = r.controller.latestScene, let style = scene.style, let programShot = scene.programShot,
                  let preview = scene.preview, let input = scene.input(preview) else { Issue.record("no scene"); return }
            let live = r.controller.currentTakeState(now: scene.now)
            var core = DirectorDecisionCore()
            let outcome = core.evaluate(scene, live: live, parameters: study, judge: RuleJudge())

            let timeline = DirectorShotPolicy.Timeline(programShot: programShot, programStartedAt: scene.programStartedAt,
                lastWideAt: scene.lastWideAt, history: scene.history, candidates: [], now: scene.now)
            let tenure = DirectorShotPolicy.PreviewTenure(id: UUID(), preview: preview,
                sourceGeneration: input.sourceGeneration, routeGeneration: scene.routeGeneration)
            let inputs = scene.inputs.map { i in
                DirectorShotPolicy.Input(sample: i.sample, sourceGeneration: i.sourceGeneration, format: i.format,
                    identity: i.state?.identity ?? .unavailable,
                    prepareReadiness: i.channel != preview ? nil : i.state.flatMap { state in
                        scene.previewTake.map { DirectorReadiness.evaluate(.init(take: $0, identity: state.identity,
                            framingSettledFor: i.settledFor, motion: state.subjectSpeed, cropConverged: state.cropConverged),
                            parameters: study.readiness, bar: .prepare) }
                    },
                    presetScores: Dictionary(uniqueKeysWithValues: i.format.ladder.map { ($0, 1.0) }))
            }
            let prepare = DirectorShotPolicy.assistPreparation(timeline, program: scene.program, preview: preview,
                inputs: inputs, previewIsSafeWide: false, tenure: tenure, preparationHistory: .init(tenure: tenure),
                parameters: study.assist(.init(style)), evidenceRevision: scene.evidenceRevision, judge: RuleJudge())
            let candidate = DirectorShotPolicy.Candidate(channel: preview, shot: input.shot,
                subjectConfidence: input.state?.identity == .confirmed ? 1 : 0, movement: input.sample.subjectSpeed,
                isWide: input.shot.isWide)
            let cut = CutPolicy.editorialDecision(live: live, timeline: .init(programShot: programShot,
                programStartedAt: scene.programStartedAt, lastWideAt: scene.lastWideAt, history: scene.history,
                candidates: [candidate], now: scene.now), prepared: candidate,
                programIdentity: scene.input(scene.program)?.state?.identity ?? .unavailable, style: style,
                evidenceRevision: scene.evidenceRevision, judge: RuleJudge(), judgeMaximumAge: study.judgeMaximumAge,
                minimumProbability: study.minimumProbability)
            #expect(outcome.prepare == prepare)
            #expect(outcome.cut == cut)
            compared += 1
            if case .cut = cut { cutsSeen += 1 }
            if case .chosen = prepare { preparesSeen += 1 }
            // Authority refuses the same cut in Manual: the split matters.
            #expect(CutPolicy.evaluate(live: live, timeline: .init(programShot: programShot,
                programStartedAt: scene.programStartedAt, lastWideAt: scene.lastWideAt, history: scene.history,
                candidates: [candidate], now: scene.now), prepared: candidate, programIdentity: .confirmed, style: style,
                evidenceRevision: scene.evidenceRevision, judge: RuleJudge(), judgeMaximumAge: 0.5,
                minimumProbability: nil) == .abstain(.authority))
        }
        #expect(compared == 48)
        if fixture == "learning" { #expect(preparesSeen == 0) } else { #expect(cutsSeen > 0 && preparesSeen > 0) }
    }

    @Test(arguments: ["confirmed", "unconfirmedProgram", "learning"])
    func theShadowJudgeHasNoEffect(_ fixture: String) async throws {
        let r = try rig(programLocked: fixture != "unconfirmedProgram",
                        previewPhase: fixture == "learning" ? .acquiring : .tracking)
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let revisions = ChannelID.allCases.compactMap { r.show.channel($0)?.revisions }
        let route = r.show.router.routeGeneration
        let before = try await records(r).count
        tick(r, until: 60)
        #expect(ChannelID.allCases.compactMap { r.show.channel($0)?.revisions } == revisions)
        #expect(r.show.router.routeGeneration == route && r.show.programChannel == .a && r.show.previewChannel == .b)
        #expect(r.controller.assistPreparation.preparation.request == nil)
        #expect(r.controller.assistPreparation.preparedShot == nil)
        #expect(!r.controller.cutExecution.isConfigured && r.controller.cutExecution.nextCut(now: r.clock.now) == nil)
        #expect(r.controller.authority.level == .off && r.controller.directorSection.level == .manual)
        // The only operator records are the fixture's own setup; the judge adds none.
        let rows = Array(try await records(r).dropFirst(before))
        #expect(rows.allSatisfy { $0.event.kind != .operatorAction })
        #expect(rows.allSatisfy { $0.executionMode == .shadow })
    }

    @Test func shadowOnlyCapabilitiesWriteTheSameRecords() async throws {
        func run(_ capabilities: DirectorCapabilities) async throws -> [String] {
            let r = try rig(capabilities: capabilities)
            defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
            tick(r, until: 20)
            return try await records(r).map {
                "\($0.eventTime) \($0.event.kind) \($0.event.stage.map { "\($0)" } ?? "-") \($0.event.target ?? "-") "
                    + "\($0.event.reasons ?? []) \($0.event.shot.map { "\($0)" } ?? "-")"
            }
        }
        let full = try await run(.full)
        let shadow = try await run(.shadowOnly)
        #expect(!full.isEmpty && full == shadow)
        #expect(full.contains { $0.contains("wouldCut") } && full.contains { $0.contains("wouldPrepare") })
    }

    // MARK: Which Directors run the judge

    @Test func theAppsOwnDirectorRunsTheJudge() async throws {
        let r = try rig(appDirector: true)
        defer { try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 8)
        let rows = try await records(r)
        #expect(cuts(rows).count == 1 && prepares(rows).count == 1)
        #expect(r.log.metrics.dropped == 0)
    }

    /// Studies that supply their own values and bindings see no judge records:
    /// a record must not name a set the Director is not running.
    @Test(arguments: ["sameValuesUnnamed", "namedButMismatched"])
    func withoutTheNamedSetOnlyTheOldAbstentionIsWritten(_ study: String) async throws {
        let r = try rig(study: study)
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, until: 30)
        let rows = try await records(r)
        #expect(rows.count == 1)
        #expect(rows.first?.event.reasons == [.init(domain: .observation, code: .cutPolicyUnavailable)])
        #expect(r.log.metrics.dropped == 0)
    }

    // MARK: Volume

    /// A synthetic measurement on this Mac, not a rig result.
    @Test func anIdleHourWritesFewerThan200Records() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        tick(r, 14_400)
        let rows = try await records(r)
        let bytes = try await fileBytes(r)
        print("[SHADOW-JUDGE-IDLE-HOUR] synthetic: \(rows.count) records, \(bytes) bytes over 14400 ticks")
        for row in rows {
            print("[SHADOW-JUDGE-IDLE-HOUR] t=\(row.eventTime - 100) \(row.event.kind.rawValue) "
                + "\(row.event.stage?.rawValue ?? "") \(row.event.target ?? "") "
                + "\((row.event.reasons ?? []).map { "\($0.domain.rawValue)/\($0.code.rawValue)" }) "
                + "\(row.event.reason.map { "\($0.domain.rawValue)/\($0.code.rawValue)" } ?? "")")
        }
        #expect(rows.count < 200)
        #expect(cuts(rows).count == 1)
        #expect(r.log.metrics.dropped == 0 && r.log.metrics.storageErrors == 0)
    }
}
