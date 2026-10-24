import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Synthetic MainActor replays through the actual permit/Take/router boundary.
/// These settings, timelines and confidence values are test facts, not defaults.
@MainActor struct DirectorCutExecutionTests {
    private final class Facts {
        var now = 1000.0
        var qualified = true
        var available = true
        var confidence = 0.9
        var candidate: DirectorShot?
        var contextCalls = 0
    }
    private final class Scheduler: DirectorCutDeadlineScheduling {
        var deadlines: [TimeInterval] = []
        var callbacks: [@MainActor () -> Void] = []
        var cancellations = 0
        func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void) {
            deadlines.append(deadline); callbacks.append(action)
        }
        func cancel() { cancellations += 1 }
        func fire(_ index: Int? = nil) { callbacks[index ?? (callbacks.count - 1)]() }
    }
    private final class InlineScheduler: DirectorCutDeadlineScheduling {
        func schedule(deadline: TimeInterval, _ action: @escaping @MainActor () -> Void) { action() }
        func cancel() {}
    }
    private final class Sink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var accepts = true
        var sent = 0
        var isAvailable: Bool { true }
        var summary: String { "synthetic" }
        var detail: String { "synthetic" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
            guard accepts else { return false }
            sent += 1; return true
        }
    }
    private struct Rig {
        let show: ShowCoordinator
        let facts: Facts
        let sink: Sink
        let scheduler: Scheduler
    }
    private func style(minimum: Double = 5, preferred: Double = 10) -> DirectorStyle {
        .init(minimumShotDuration: minimum, preferredShotDuration: preferred, softMaximumShotDuration: 40,
              wideCadence: 20, repetitionWindow: 4, maximumMovement: 0.2, settleTime: 1,
              onAirMoveRate: 0.1, cutOnMotionAllowed: false)
    }
    private func configuration(notice: Double = 2) -> DirectorCutExecution.Configuration {
        .init(autoNoticeLength: notice, maximumLateness: 1, permitValidity: 0,
              judgeMaximumAge: 1, minimumProbability: nil, judge: RuleJudge())
    }
    private func rig(level: NextShotStatus.DirectorSection.Level = .auto,
                     widePreview: Bool = false) -> Rig {
        let facts = Facts(), sink = Sink(), scheduler = Scheduler()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "b08-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { facts.now }; show.router.clock = { facts.now }
        show.addChannel(.b)
        show.channelA.setRunningForTesting(true); show.channel(.b)!.setRunningForTesting(true)
        show.channelA.shotComposer.config.shotPreset = widePreview ? .waistUp : .wide
        show.channel(.b)!.shotComposer.config.shotPreset = widePreview ? .wide : .waistUp
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        let controller = show.director
        controller.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                  outputHealthy: true, admissionCurrent: true,
                  qualifiedLevels: facts.qualified ? [.auto, .backup] : [])
        }
        controller.cutReadinessForTesting = .init(reasons: [])
        controller.attach()
        controller.preferencesChanged(.init(styles: [.liveEvent: style()]))
        #expect(controller.setLevel(level) == .accepted)
        return .init(show: show, facts: facts, sink: sink, scheduler: scheduler)
    }
    private func context(_ r: Rig) -> DirectorCutExecution.ContextProvider {
        { [weak show = r.show, weak facts = r.facts] now in
            guard let show, let facts else { return nil }
            facts.contextCalls += 1
            guard facts.available, let preview = show.previewChannel,
                  let b = show.channel(preview), let a = show.channel(show.programChannel) else { return nil }
            let shot = facts.candidate ?? b.directorShot
            let candidate = DirectorShotPolicy.Candidate(channel: preview, shot: shot,
                subjectConfidence: facts.confidence, movement: b.evidenceReadings(now: now).subjectSpeed,
                isWide: shot.isWide)
            return .init(timeline: .init(programShot: a.directorShot, programStartedAt: 980,
                lastWideAt: 980, history: [], candidates: [candidate], now: now),
                prepared: candidate, programIdentity: .confirmed, program: show.programChannel,
                programRevisions: a.revisions, previewRevisions: b.revisions,
                routeGeneration: show.router.routeGeneration)
        }
    }
    private func configure(_ r: Rig) {
        r.show.director.configureAutomaticCuts(configuration(), context: context(r), scheduler: r.scheduler)
    }
    private func prepare(_ r: Rig) throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer), b = try #require(r.show.channel(r.show.previewChannel ?? .b))
        b.setLatestRenderedFrameForTesting(.init(channelID: b.channelID, revisions: b.revisions,
            sourceTimestamp: 1, processingStartedAt: r.facts.now, renderedAt: r.facts.now,
            crop: .fullFrame, outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
    }

    @Test func absentConfigurationAndMissingProviderOrSchedulerNeverSchedule() {
        let r = rig()
        r.show.director.evaluateAutomaticCuts()
        #expect(r.scheduler.callbacks.isEmpty && r.show.director.directorSection.nextCut == nil)
        r.show.director.configureAutomaticCuts(configuration(), context: context(r))
        r.show.director.evaluateAutomaticCuts()
        #expect(r.scheduler.callbacks.isEmpty && r.show.programChannel == .a && r.sink.sent == 0)
    }

    @Test func deadlineReevaluatesAndCutsOnceThroughTheExistingTake() throws {
        let r = rig(); configure(r); try prepare(r)
        r.show.director.evaluateAutomaticCuts()
        let token = try #require(r.show.director.cutExecution.pending)
        #expect(r.show.director.directorSection.nextCut?.countdown == 2)
        #expect(r.show.take(origin: .director) == .rejected(.directorNotAuthorized))
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
        r.facts.now = 1001
        r.show.director.evaluateAutomaticCuts()
        #expect(r.show.director.cutExecution.pending == token && r.scheduler.deadlines == [1002])
        r.facts.now = 1002; try prepare(r); r.scheduler.fire()
        #expect(r.facts.contextCalls == 3)
        #expect(r.show.director.cutExecution.lastResult == .committed(newProgram: .b))
        #expect(r.show.programChannel == .b && r.sink.sent == 1)
        #expect(r.show.director.directorSection.nextCut == nil)
        r.scheduler.fire()
        #expect(r.sink.sent == 1 && !r.show.director.appliedEvents.contains(.operatorTake))
    }

    @Test(arguments: [1000.0, 1001.999, 1002.0])
    func cancellationHandledBeforeDeadlineAlwaysWinsAndStartsDwell(now: Double) throws {
        let r = rig(); configure(r); r.show.director.evaluateAutomaticCuts()
        r.facts.now = now
        r.show.director.cancelNextCut()
        #expect(r.show.director.authority.nudgeHold == .until(now + 5))
        #expect(!r.show.director.authority.paused)
        try prepare(r); r.scheduler.fire()
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
        #expect(r.show.director.directorSection.nextCut == nil)
        #expect(!r.show.director.appliedEvents.contains(.operatorTake))
    }

    @Test func staleCallbackCannotRetireOrConsumeAReplacement() throws {
        let r = rig(); configure(r); r.show.director.evaluateAutomaticCuts()
        r.show.director.cancelNextCut()
        r.facts.now = 1005; r.show.director.evaluateAutomaticCuts()
        let replacement = try #require(r.show.director.cutExecution.pending)
        r.scheduler.fire(0)
        #expect(r.show.director.cutExecution.pending == replacement)
        r.facts.now = 1007; try prepare(r); r.scheduler.fire(1)
        #expect(r.show.programChannel == .b && r.sink.sent == 1)
    }

    @Test(arguments: ["manual", "editLive", "source", "style", "segment", "detach", "readiness", "qualification", "roles", "context"])
    func currentInvalidationPreventsAnyDeadlineEffect(change: String) throws {
        let r = rig(), controller = r.show.director
        #expect(controller.setRunSheet(try RunSheet(segments: [.init(type: .presenter), .init(type: .panel)])))
        configure(r); controller.evaluateAutomaticCuts()
        let original = try #require(controller.cutExecution.pending)
        switch change {
        case "manual": controller.takeOver()
        case "editLive": r.show.setEditLive(true)
        case "source": r.show.channel(.b)!.setSourceMissingForTesting(true)
        case "style": controller.preferencesChanged(.init(styles: [.liveEvent: style(preferred: 30)]))
        case "segment": controller.advanceSegment()
        case "detach": controller.detach()
        case "readiness": controller.cutReadinessForTesting = .init(reasons: [.moving])
        case "qualification": r.facts.qualified = false
        case "roles": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
        default: r.facts.available = false
        }
        // Segment advance retires old work without taking authority away.
        // A separate current evaluation may legitimately create a fresh notice.
        if change == "segment" { #expect(controller.cutExecution.pending == nil) }
        controller.evaluateAutomaticCuts()
        let current = controller.cutExecution.pending
        if change == "segment" {
            #expect(current != nil && current != original)
        } else { #expect(current == nil) }
        let program = r.show.programChannel
        r.facts.now = 1002; try prepare(r); r.scheduler.fire(0)
        #expect(r.show.programChannel == program && r.sink.sent == 0)
        #expect(controller.cutExecution.pending == current)
    }

    @Test func technicalRefusalIsTerminalAndCannotCutWhenAnOldCallbackReturns() throws {
        let r = rig(); configure(r); r.show.director.evaluateAutomaticCuts()
        r.facts.now = 1002; try prepare(r); r.sink.accepts = false; r.scheduler.fire()
        #expect(r.show.director.cutExecution.lastResult == .rejected(.outputRefused))
        #expect(r.show.director.cutExecution.pending == nil)
        r.sink.accepts = true; r.scheduler.fire()
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
    }

    @Test func interventionInTakeObserverRevokesTheJustIssuedPermitBeforeEffect() throws {
        let r = rig(); configure(r); r.show.director.evaluateAutomaticCuts()
        r.show.takeAttemptObserver = { [weak show = r.show] origin in
            if origin == .director { show?.director.takeOver() }
        }
        r.facts.now = 1002; try prepare(r); r.scheduler.fire()
        #expect(r.show.director.cutExecution.lastResult == .rejected(.directorNotAuthorized))
        #expect(r.show.director.authority.paused && r.show.programChannel == .a && r.sink.sent == 0)
    }

    @Test func backupPublishesUncancellableNextCutBeforeDeferredDeadline() throws {
        let r = rig(level: .backup); configure(r); try prepare(r)
        r.show.director.evaluateAutomaticCuts()
        let next = try #require(r.show.director.directorSection.nextCut)
        #expect(next.countdown == nil && !next.cancellable && r.scheduler.deadlines == [1000])
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
        r.show.director.cancelNextCut()
        #expect(r.show.director.cutExecution.pending != nil)
        r.scheduler.fire()
        #expect(r.show.programChannel == .b && r.sink.sent == 1)
    }

    @Test func backupManualTakeoverStillRetiresAZeroCountdownCut() throws {
        let r = rig(level: .backup); configure(r); r.show.director.evaluateAutomaticCuts()
        r.show.director.takeOver(); try prepare(r); r.scheduler.fire()
        #expect(r.show.director.authority.paused && r.show.programChannel == .a && r.sink.sent == 0)
    }

    @Test(arguments: [SegmentType.panel, .performance, .videoBreak])
    func backupGroupSegmentsOnlyScheduleActualWideShots(segment: SegmentType) throws {
        let tight = rig(level: .backup)
        #expect(tight.show.director.setRunSheet(try RunSheet(segments: [.init(type: segment)])))
        configure(tight); tight.show.director.evaluateAutomaticCuts()
        #expect(tight.scheduler.callbacks.isEmpty && tight.show.director.directorSection.nextCut == nil)
        let wide = rig(level: .backup, widePreview: true)
        #expect(wide.show.director.setRunSheet(try RunSheet(segments: [.init(type: segment)])))
        configure(wide); wide.show.director.evaluateAutomaticCuts()
        #expect(wide.scheduler.callbacks.count == 1)
        try prepare(wide); wide.scheduler.fire()
        #expect(wide.show.programChannel == .b && wide.sink.sent == 1)
    }

    @Test func candidateMustMatchTheActualPreparedPreviewShot() {
        let r = rig(); r.facts.candidate = .init(preset: .stage(.fullBody)); configure(r)
        r.show.director.evaluateAutomaticCuts()
        #expect(r.scheduler.callbacks.isEmpty && r.show.programChannel == .a)
    }

    @Test func currentSegmentStyleIsReadRatherThanCapturedConfiguration() throws {
        let r = rig(), controller = r.show.director
        controller.preferencesChanged(.init(styles: [.liveEvent: style(), .panel: style(minimum: 20, preferred: 30)]))
        #expect(controller.handToAlfie() == .accepted)
        #expect(controller.setRunSheet(try RunSheet(segments: [.init(type: .presenter), .init(type: .panel)])))
        configure(r); controller.evaluateAutomaticCuts()
        #expect(controller.cutExecution.pending != nil)
        controller.advanceSegment(); controller.evaluateAutomaticCuts()
        #expect(controller.cutExecution.pending == nil && !controller.authority.paused)
        r.facts.now = 1010; controller.evaluateAutomaticCuts()
        #expect(controller.cutExecution.pending != nil)
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidNoticeParametersNeverSchedule(value: Double) {
        let r = rig()
        r.show.director.configureAutomaticCuts(configuration(notice: value), context: context(r), scheduler: r.scheduler)
        r.show.director.evaluateAutomaticCuts()
        #expect(r.scheduler.callbacks.isEmpty && r.show.programChannel == .a)
    }

    @Test(arguments: [999.0, 1003.001, Double.nan])
    func backwardInvalidOrExpiredDeadlineRetiresWithoutRetry(now: Double) throws {
        let r = rig(); configure(r); r.show.director.evaluateAutomaticCuts()
        r.facts.now = now; r.scheduler.fire()
        #expect(r.show.director.cutExecution.pending == nil && r.show.programChannel == .a && r.sink.sent == 0)
    }

    @Test func anEarlyWakeCannotCutBeforeTheNoticeDeadline() throws {
        let r = rig(); configure(r); r.show.director.evaluateAutomaticCuts()
        r.facts.now = 1001; try prepare(r); r.scheduler.fire()
        #expect(r.show.programChannel == .a && r.show.director.cutExecution.pending != nil)
        r.facts.now = 1002; try prepare(r); r.scheduler.fire()
        #expect(r.show.programChannel == .b && r.sink.sent == 1)
    }

    @Test func inlineSchedulerCannotBypassThePublishedNoticeTurn() {
        let r = rig(level: .backup)
        r.show.director.configureAutomaticCuts(configuration(), context: context(r), scheduler: InlineScheduler())
        r.show.director.evaluateAutomaticCuts()
        #expect(r.show.director.cutExecution.pending == nil && r.show.programChannel == .a && r.sink.sent == 0)
    }
}
