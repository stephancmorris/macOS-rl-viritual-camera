import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Decision core, stage 6: in Debug, Assist prepares the core's chosen shot
/// and Auto cuts with its context read from the scene. Synthetic cameras on
/// this Mac only; no figure here is a rig result.
@MainActor struct DirectorLiveDirectingTests {
    @MainActor private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    @MainActor private final class Clock { var now: TimeInterval = 100 }
    @MainActor private final class Scheduler: DirectorCutDeadlineScheduling {
        var deadlines: [TimeInterval] = []
        var callbacks: [@MainActor () -> Void] = []
        func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void) {
            deadlines.append(deadline); callbacks.append(action)
        }
        func cancel() {}
        func fireLast() { callbacks.last?() }
    }
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
    @MainActor private final class Counter { var preparations = 0 }
    @MainActor private struct Rig {
        let root: URL
        let log: DirectorShadowLog
        let show: ShowCoordinator
        let controller: DirectorController
        let clock: Clock
        let pixels: CVPixelBuffer
        let scheduler: Scheduler
        let counter: Counter
    }

    /// A 2 s minimum shot and a 6 s preferred length.
    private static let style = DirectorStyle(minimumShotDuration: 2, preferredShotDuration: 6, softMaximumShotDuration: 30,
        wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.2, settleTime: 0, onAirMoveRate: 0.2,
        cutOnMotionAllowed: false)

    /// Program wide on A, Preview waist-up on B, a locked subject on both.
    private func rig(level: DirectorAuthority.Level = .off, capabilities: DirectorCapabilities = .full,
                     named: Bool = true) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-directing-\(UUID())")
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 16384,
            maximumQueuedBytes: 1_048_576, maximumFileBytes: 16_777_216, maximumStoreBytes: 33_554_432))
        let clock = Clock()
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: [Sink()]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "live-directing-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false),
            directorShadowLog: named ? log : nil, directorCapabilities: capabilities)
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        for id in ChannelID.allCases {
            guard let camera = show.channel(id) else { continue }
            camera.setRunningForTesting(true)
            camera.shotComposer.lockTarget(UUID())
            camera.setOperationMode(.autoTracking)
            camera.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true, holdingSteady: true,
                                                        subjectSpeed: 0)
        }
        #expect(show.dispatch(show.makeCommand(.selectPreset(.stage(.waistUp)))).wasAccepted)
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        let study = DirectorStudyParameters.shadowV1
        // The show's own Director, built as the app builds it (the router only
        // takes a Director cut from it), or one without the named set.
        let controller = named
            ? show.director
            : DirectorController(show: show, ticker: Ticker(), clock: { clock.now }, capabilities: capabilities,
                                 adapterParameters: study.adapter, cutReadinessParameters: study.readiness,
                                 shadowLog: log, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true,
                  admissionCurrent: true, qualifiedLevels: [.assist, .auto])
        }
        controller.preferencesChanged(.init(styles: [.liveEvent: Self.style]))
        controller.attach()
        let counter = Counter()
        controller.assistPreparation.readinessForTesting = .init(reasons: [])
        controller.assistPreparation.dispatchForTesting = { camera, command in
            counter.preparations += 1
            return camera.dispatch(command)
        }
        if level != .off {
            let section: NextShotStatus.DirectorSection.Level = level == .auto ? .auto : .assist
            #expect((controller.setLevel(section) == .accepted) == capabilities.assist)
        }
        return .init(root: root, log: log, show: show, controller: controller, clock: clock, pixels: pixels,
                     scheduler: Scheduler(), counter: counter)
    }

    /// One Director tick with fresh synthetic perception and fresh frames.
    private func tick(_ r: Rig, until time: TimeInterval) {
        while r.clock.now + DirectorController.tickInterval <= 100 + time + 1e-9 {
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
        }
    }

    private func records(_ r: Rig) async throws -> [DirectorShadowRecord] {
        await r.log.flush()
        let url = r.log.directory.appendingPathComponent("director_shadow_\(r.log.sessionID.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }

    // MARK: Off unless asked for

    @Test func theAppsDirectorNeverRunsLiveDirecting() {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []))
        #expect(show.director.liveDirecting == nil)
        #expect(!show.director.cutExecution.isConfigured && !show.director.cutExecution.usesScene)
    }

    @Test func refusedWithoutTheNamedSetOrInAShadowOnlyBuild() throws {
        let unnamed = try rig(named: false)
        #expect(!unnamed.controller.configureLiveDirecting(.rehearsalV1, scheduler: unnamed.scheduler))
        #expect(unnamed.controller.liveDirecting == nil && !unnamed.controller.cutExecution.isConfigured)

        let watching = try rig(capabilities: .shadowOnly)
        #expect(!watching.controller.configureLiveDirecting(.rehearsalV1, scheduler: watching.scheduler))
        #expect(watching.controller.liveDirecting == nil && !watching.controller.cutExecution.isConfigured)

        let invalid = try rig()
        let bad = DirectorController.LiveDirecting(study: .shadowV1, autoNoticeLength: .nan, maximumLateness: 1,
                                                   permitValidity: 0, maximumRequestAge: 0.5)
        #expect(!invalid.controller.configureLiveDirecting(bad, scheduler: invalid.scheduler))

        // Turning it off clears the scene-backed cut path it installed.
        let r = try rig()
        #expect(r.controller.configureLiveDirecting(.rehearsalV1, scheduler: r.scheduler))
        #expect(r.controller.cutExecution.usesScene)
        #expect(!r.controller.configureLiveDirecting(nil))
        #expect(r.controller.liveDirecting == nil && !r.controller.cutExecution.isConfigured)
    }

    // MARK: Manual

    @Test func atManualNothingIsPreparedOrCutAndTheShadowStillRecords() async throws {
        let r = try rig()
        #expect(r.controller.configureLiveDirecting(.rehearsalV1, scheduler: r.scheduler))
        tick(r, until: 10)
        #expect(r.counter.preparations == 0 && r.scheduler.callbacks.isEmpty)
        #expect(r.show.programChannel == .a && r.controller.directorSection.prepared == nil)
        let rows = try await records(r)
        #expect(rows.contains { $0.event.kind == .wouldCut })
    }

    // MARK: Assist

    @Test func assistPreparesTheCoresShotOncePerTenureAndNeverCuts() throws {
        let r = try rig(level: .assist)
        #expect(r.controller.configureLiveDirecting(.rehearsalV1, scheduler: r.scheduler))
        tick(r, until: 3)
        #expect(r.counter.preparations == 1)
        #expect(r.controller.directorSection.prepared != nil)
        let revisions = r.show.channel(.b)!.revisions
        tick(r, until: 20)
        // One preparation for this Preview tenure, and Assist never Takes.
        #expect(r.counter.preparations == 1 && r.show.channel(.b)!.revisions == revisions)
        #expect(r.show.programChannel == .a && r.scheduler.callbacks.isEmpty)
    }

    @Test func aPausedAssistPreparesNothing() throws {
        let r = try rig(level: .assist)
        #expect(r.controller.configureLiveDirecting(.rehearsalV1, scheduler: r.scheduler))
        r.controller.takeOver()
        tick(r, until: 5)
        #expect(r.counter.preparations == 0 && r.controller.directorSection.prepared == nil)
    }

    // MARK: Auto

    @Test func autoCutsFromTheSceneThroughTheNoticeAndPermit() throws {
        let r = try rig(level: .auto)
        #expect(r.controller.configureLiveDirecting(.rehearsalV1, scheduler: r.scheduler))
        tick(r, until: 1.5)
        // Inside the minimum shot nothing is scheduled.
        #expect(r.scheduler.callbacks.isEmpty && r.show.programChannel == .a)
        tick(r, until: 8)
        let deadline = try #require(r.scheduler.deadlines.last)
        #expect(r.controller.directorSection.nextCut?.input == .b)
        // Fresh evidence up to the deadline, as the 4 Hz tick gives it.
        tick(r, until: deadline - 100)
        #expect(r.scheduler.deadlines.last == deadline)
        r.scheduler.fireLast()
        #expect(r.show.programChannel == .b)
        #expect(r.controller.cutExecution.lastResult == .committed(newProgram: .b))
    }

    @Test func aManualTakeOverCancelsTheNotice() throws {
        let r = try rig(level: .auto)
        #expect(r.controller.configureLiveDirecting(.rehearsalV1, scheduler: r.scheduler))
        tick(r, until: 8)
        let deadline = try #require(r.scheduler.deadlines.last)
        r.controller.takeOver()
        r.clock.now = deadline
        r.scheduler.fireLast()
        #expect(r.show.programChannel == .a && r.controller.directorSection.nextCut == nil)
    }

    // MARK: The context is the scene's

    @Test func theCutContextIsReadFromTheScene() throws {
        let r = try rig()
        tick(r, until: 3)
        let scene = try #require(r.controller.latestScene)
        let context = try #require(DirectorController.cutContext(scene, provenance: .synthetic))
        let preview = try #require(scene.input(.b)), program = try #require(scene.input(.a))
        #expect(context.program == .a && context.prepared.channel == .b && context.prepared.shot == preview.shot)
        #expect(context.programRevisions == program.revisions && context.previewRevisions == preview.revisions)
        #expect(context.routeGeneration == scene.routeGeneration && context.provenance == [.synthetic])
        #expect(context.timeline.programStartedAt == scene.programStartedAt && context.timeline.now == scene.now)
        #expect(context.timeline.candidates == [context.prepared])
    }

    // MARK: Replay

    private static let replayStyle = DirectorStyle(minimumShotDuration: 2, preferredShotDuration: 6,
        softMaximumShotDuration: 30, wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.2, settleTime: 0,
        onAirMoveRate: 0.2, cutOnMotionAllowed: false)
    private static let takeFixture = DirectorReplay.Fixture(name: "director take", duration: 60, events: [
        .init(at: 1, action: .enable(.auto)),
        .init(at: 9, action: .render(channel: .b)),
        .init(at: 9, action: .subject(channel: .b, present: true, identity: .confirmed, intended: true,
                                      framingReady: true, movement: 0)),
        .init(at: 10, action: .directorTake)])

    @Test func theReplaysDirectorTakeCutsOnlyWithAuthority() {
        let allowed = DirectorReplay.run(Self.takeFixture, parameters: .policyStudy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy, cutStyle: Self.replayStyle,
            qualifiedLevels: [.assist, .auto])
        #expect(allowed.directorCuts == 1 && allowed.operatorCuts == 0)
        #expect(allowed.programChangesWithoutAuthority == 0 && allowed.minimumDurationViolations == 0)

        // Not qualified for Auto: the level is refused and the rules say no.
        let refused = DirectorReplay.run(Self.takeFixture, parameters: .policyStudy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy, cutStyle: Self.replayStyle,
            qualifiedLevels: [.assist])
        #expect(refused.directorCuts == 0 && refused.directorTakeAbstentions == [.authority: 1])

        // No cut style: the entry cannot cut.
        let noStyle = DirectorReplay.run(Self.takeFixture, parameters: .policyStudy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy)
        #expect(noStyle.directorCuts == 0 && noStyle.directorTakeAbstentions == [.invalidInput: 1])
    }

    @Test func theExistingFixturesStillReportNoDirectorCuts() {
        for fixture in DirectorReplayFixtures.all {
            let report = DirectorReplay.run(fixture, parameters: .policyStudy, maximumProposalAge: 5,
                maximumEvidenceAge: 5, readinessParameters: .replayStudy)
            #expect(report.directorCuts == 0 && report.directorTakeAbstentions.isEmpty, "\(fixture.name)")
        }
    }
}
