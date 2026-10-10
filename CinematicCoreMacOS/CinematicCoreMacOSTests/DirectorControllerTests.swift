import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// B-03: the Director controller in shadow. Every ingress in plan §5.3 reaches
/// the authority, every launch and restart is Manual, and the controller never
/// moves a camera or cuts.
@MainActor struct DirectorControllerTests {
    typealias Section = NextShotStatus.DirectorSection

    @MainActor private final class FakeTicker: DirectorTicker {
        var tick: (@MainActor () -> Bool)?
        var interval: TimeInterval?
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {
            self.interval = interval; self.tick = tick
        }
        func stop() { tick = nil }
        @discardableResult func fire() -> Bool { tick?() ?? false }
    }

    @MainActor private struct Rig {
        let show: ShowCoordinator
        let controller: DirectorController
        let ticker: FakeTicker
        var a: CameraManager { show.channelA }
        var b: CameraManager { show.channel(.b)! }
    }

    private static let ready = DirectorAuthority.Prerequisites(
        nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true,
        admissionCurrent: true, qualifiedLevels: [.assist, .auto, .backup])

    private func rig(qualified: Set<DirectorAuthority.Level> = [.assist, .auto, .backup]) -> Rig {
        let show = ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-director-\(UUID().uuidString)")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        let b = show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        b.setRunningForTesting(true)
        let ticker = FakeTicker()
        let controller = DirectorController(show: show, ticker: ticker, clock: { 100 },
                                            qualifiedLevels: { qualified }, log: { _ in })
        controller.prerequisitesOverride = { Self.ready }
        controller.attach()
        return Rig(show: show, controller: controller, ticker: ticker)
    }

    /// A rig already directing at `level`.
    private func directing(_ level: Section.Level) -> Rig {
        let rig = rig()
        #expect(rig.controller.setLevel(level) == .accepted)
        #expect(rig.controller.directorSection.level == level && rig.controller.directorSection.handedToAlfie)
        return rig
    }

    // MARK: Launch and lifecycle

    @Test func launchIsManualEvenWhenQualified() {
        let rig = rig()
        #expect(rig.controller.directorSection == .atLaunch(qualified: .init(assist: true, auto: true, backup: true)))
        #expect(rig.controller.authority.level == .off)
        #expect(rig.ticker.interval == DirectorController.tickInterval)
    }

    @Test func stopThenNewShowStaysManual() {
        let rig = directing(.auto)
        rig.show.stopShow()
        #expect(rig.controller.directorSection.level == .manual)
        #expect(rig.controller.directorSection.activity == .paused(.showStopped))
        rig.show.prepareForNewShow()
        #expect(rig.controller.authority.level == .off && rig.controller.authority.running)
        #expect(rig.controller.directorSection.level == .manual)
        #expect(rig.controller.directorSection.statusLine == "Manual · Alfie is not directing")
    }

    @Test func tickerStopsOnceTheControllerIsGone() {
        let ticker = FakeTicker()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        var controller: DirectorController? = DirectorController(show: show, ticker: ticker, log: { _ in })
        controller?.attach()
        #expect(ticker.fire())
        controller = nil
        #expect(!ticker.fire())
    }

    // MARK: Console control

    @Test func unqualifiedLevelIsRefusedNeverSubstituted() {
        let rig = rig(qualified: [.assist])
        rig.controller.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true,
                  admissionCurrent: true, qualifiedLevels: [.assist])
        }
        #expect(rig.controller.setLevel(.auto) == .refused(Section.notQualifiedCaption))
        #expect(rig.controller.directorSection.level == .manual)
        #expect(!rig.controller.directorSection.canSelect(.auto))
        #expect(rig.controller.setLevel(.assist) == .accepted)
    }

    @Test func takeOverThenHandBack() {
        let rig = directing(.auto)
        rig.controller.takeOver()
        #expect(rig.controller.directorSection.activity == .paused(.operatorTookOver))
        #expect(!rig.controller.directorSection.handedToAlfie)
        #expect(rig.controller.handToAlfie() == .accepted)
        #expect(rig.controller.directorSection.handedToAlfie)
    }

    @Test func handBackIsRefusedWhenPrerequisitesFail() {
        let rig = directing(.auto)
        rig.controller.takeOver()
        rig.controller.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: false, outputHealthy: true,
                  admissionCurrent: true, qualifiedLevels: [.auto])
        }
        guard case .refused(let message) = rig.controller.handToAlfie() else {
            Issue.record("Hand back accepted with an unhealthy source"); return
        }
        #expect(message == Section.PauseReason.operatorTookOver.text)
        #expect(!rig.controller.directorSection.handedToAlfie)
    }

    @Test func manualClearsEverything() {
        let rig = directing(.assist)
        #expect(rig.controller.setLevel(.manual) == .accepted)
        #expect(rig.controller.directorSection == .atLaunch(qualified: .init(assist: true, auto: true, backup: true)))
    }

    // MARK: §5.3 ingress hooks

    @Test func admittedCameraCommandIsATakeover() {
        let rig = directing(.auto)
        #expect(rig.show.dispatch(rig.show.makeCommand(.returnToWide)) == .accepted)
        #expect(rig.controller.appliedEvents.last == .manualCommand)
        #expect(rig.controller.directorSection.activity == .paused(.operatorTookOver))
    }

    @Test func refusedCameraCommandIsStillATakeover() {
        let rig = directing(.auto)
        rig.b.setRunningForTesting(false)
        #expect(rig.b.dispatch(rig.b.makeCommand(.returnToWide)) == .rejected("Session is stopped"))
        #expect(rig.controller.appliedEvents.last == .manualCommand)
        #expect(rig.controller.authority.paused)
    }

    @Test func settingsChangeIsATakeover() {
        let rig = directing(.auto)
        rig.b.shotComposer.config.shotPreset = .fullBody
        #expect(rig.controller.appliedEvents.last == .manualCommand)
        #expect(rig.controller.authority.paused)
    }

    @Test func operatorActivityInManualIsNotAnIntervention() {
        let rig = rig()
        _ = rig.show.dispatch(rig.show.makeCommand(.returnToWide))
        rig.show.take()
        rig.show.setEditLive(true)
        #expect(rig.controller.appliedEvents.isEmpty)
        rig.show.setEditLive(false)
        // Nothing left paused behind Manual, so choosing a level still works.
        #expect(rig.controller.setLevel(.assist) == .accepted)
    }

    @Test func refusedOperatorTakeInAutoPauses() {
        let rig = directing(.auto)
        // No rendered Preview frame: the Take is refused, but the operator acted.
        guard case .rejected = rig.show.take() else { Issue.record("Take unexpectedly committed"); return }
        #expect(rig.controller.appliedEvents.last == .operatorTake)
        #expect(rig.controller.directorSection.activity == .paused(.operatorTookOver))
    }

    @Test func operatorTakeInAssistRetiresWithoutPausing() {
        let rig = directing(.assist)
        let epoch = rig.controller.authority.epoch
        rig.show.take()
        #expect(rig.controller.appliedEvents.last == .operatorTake)
        #expect(!rig.controller.authority.paused && rig.controller.authority.epoch == epoch + 1)
        #expect(rig.controller.directorSection.handedToAlfie)
    }

    @Test func directorAndFallbackTakesAreNotOperatorActions() {
        let rig = directing(.auto)
        rig.show.take(origin: .director)
        rig.show.take(origin: .fallback)
        #expect(!rig.controller.appliedEvents.contains(.operatorTake))
        #expect(!rig.controller.authority.paused)
    }

    @Test func editLiveIsATakeover() {
        let rig = directing(.auto)
        rig.show.setEditLive(true)
        #expect(rig.controller.appliedEvents.last == .editLive(true))
        #expect(rig.controller.directorSection.activity == .paused(.editLive))
        rig.show.setEditLive(false)
        #expect(rig.controller.appliedEvents.last == .editLive(false))
    }

    @Test func addingAndRemovingAnInputChangesTheSetup() {
        let rig = directing(.auto)
        rig.show.removeChannel(.b)
        #expect(rig.controller.appliedEvents.last == .sourceLoss(.b))
        #expect(rig.controller.directorSection.activity == .paused(.setupChanged))
        rig.show.addChannel(.b)
        #expect(rig.controller.appliedEvents.last == .sourceRebound(.b))
    }

    @Test func sourceMissingAndReconnect() {
        let rig = directing(.auto)
        rig.b.setSourceMissingForTesting(true)
        #expect(rig.controller.appliedEvents.last == .sourceLoss(.b))
        #expect(rig.controller.directorSection.activity == .paused(.sourceLost(.b)))
        rig.b.setSourceMissingForTesting(false)
        #expect(rig.controller.appliedEvents.last == .sourceRebound(.b))
    }

    @Test func routerHoldIsAnOutputFault() throws {
        let rig = directing(.auto)
        var now: TimeInterval = 10
        rig.show.router.clock = { now }
        rig.a.outputPort.start()
        rig.a.outputPort.updateCaptureStatus(isRunning: true)
        rig.show.router.submit(try Self.buffer(), from: .a, isRepeat: false,
                               routeGeneration: rig.show.router.routeGeneration)
        #expect(rig.show.router.state == .routed)
        #expect(!rig.controller.authority.paused)
        now += ProgramRouter.sourceLossAfter + 0.1
        rig.show.router.checkSourceHealth()
        #expect(rig.controller.appliedEvents.last == .outputFault)
        #expect(rig.controller.directorSection.activity == .paused(.outputProblem))
    }

    @Test func admissionRefusalIsSeenOnTheTick() {
        let rig = directing(.auto)
        rig.show.admissionRecords.record(
            .unsupported([AdmissionReason(code: "test", bottleneck: .cpu, message: "synthetic")]),
            for: rig.show.admissionFingerprint())
        rig.ticker.fire()
        #expect(rig.controller.appliedEvents.contains(.admissionLost))
        #expect(rig.controller.directorSection.activity == .paused(.setupChanged))
        let count = rig.controller.appliedEvents.count
        rig.ticker.fire()
        #expect(rig.controller.appliedEvents.count == count, "reported once per transition")
    }

    @Test func savedStylesPauseForTheNewPolicy() throws {
        let rig = directing(.assist)
        // Test fixture values only.
        let style = DirectorStyle(minimumShotDuration: 8, preferredShotDuration: 15, softMaximumShotDuration: 35,
            wideCadence: 60, repetitionWindow: 20, maximumMovement: 0.1, settleTime: 1, onAirMoveRate: 0.5,
            cutOnMotionAllowed: false)
        rig.controller.preferencesChanged(DirectorPreferences(styles: [.liveEvent: style]))
        #expect(rig.controller.appliedEvents.last == .policyChanged)
        #expect(rig.controller.directorSection.activity == .paused(.styleChanged))
        #expect(rig.controller.preferences != nil)
    }

    @Test func healthReturnsOnTheTickButNeverClearsPause() {
        let rig = directing(.auto)
        rig.b.setSourceMissingForTesting(true)
        rig.b.setSourceMissingForTesting(false)
        #expect(!rig.controller.authority.healthy)
        rig.ticker.fire()
        #expect(rig.controller.authority.healthy && rig.controller.authority.paused)
        #expect(rig.controller.handToAlfie() == .accepted)
    }

    // MARK: Shadow: no camera effects

    @Test func shadowNeverMovesACameraOrCuts() {
        let rig = directing(.auto)
        let before = (a: rig.a.revisions, b: rig.b.revisions, program: rig.show.programChannel,
                      route: rig.show.router.routeGeneration)
        var takes: [TakeOrigin] = []
        let director = rig.show.takeAttemptObserver
        rig.show.takeAttemptObserver = { origin in takes.append(origin); director?(origin) }
        for _ in 0..<40 { rig.ticker.fire() }
        rig.controller.cancelNextCut()
        rig.controller.advanceSegment()
        rig.controller.overrideSubject(on: .b, at: CGPoint(x: 0.5, y: 0.5))
        #expect(rig.a.revisions == before.a && rig.b.revisions == before.b)
        #expect(rig.show.programChannel == before.program && rig.show.router.routeGeneration == before.route)
        #expect(takes.isEmpty)
        #expect(rig.controller.directorSection.prepared == nil && rig.controller.directorSection.nextCut == nil)
        #expect(rig.controller.directorSection.alfieSetShot.isEmpty)
    }

    // MARK: Evidence and status

    @Test func withoutAdapterParametersAlfieCannotDecide() {
        let rig = directing(.assist)
        rig.ticker.fire()
        #expect(rig.controller.directorSection.activity == .abstaining(.cannotDecide))
    }

    @Test func evidenceWithoutASubjectWaitsForAView() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.addChannel(.b)
        let ticker = FakeTicker()
        let controller = DirectorController(show: show, ticker: ticker, clock: { 100 },
            qualifiedLevels: { [.assist] },
            adapterParameters: .init(maximumObservationAge: 0.5, debounce: 0.5, stillSpeed: 0.05), log: { _ in })
        controller.prerequisitesOverride = { Self.ready }
        controller.attach()
        #expect(controller.setLevel(.assist) == .accepted)
        ticker.fire()
        #expect(controller.adapter?.state(for: .b)?.identity == .unavailable)
        #expect(controller.directorSection.activity == .inhibited(.noFreshView(.b)))
    }

    @Test func readingsMapFieldForField() {
        let id = UUID()
        let readings = ChannelEvidenceReadings(channel: .b, sampledAt: 7, isRunning: true, sourceMissing: false,
            mode: .autoTracking, revisions: .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3),
            lockPhase: .tracking, galleryReady: true, trackingOwnsControl: true, lockedTargetID: id,
            subjectSpeed: 0.02, holdingSteady: true, cropConverged: false, observationAge: 0.1,
            observedPersonCount: 2, operatorGestureInProgress: true)
        #expect(DirectorController.sample(readings) == ChannelEvidenceSample(channel: .b, sampledAt: 7,
            lockPhase: .tracking, trackingOwnsControl: true, galleryReady: true, lockedTargetID: id,
            observationAge: 0.1, subjectSpeed: 0.02, holdingSteady: true, cropConverged: false,
            operatorGestureInProgress: true, observedPersonCount: 2))
    }

    @Test func levelsMapBothWays() {
        for level in Section.Level.allCases {
            #expect(DirectorController.consoleLevel(DirectorController.authorityLevel(level)) == level)
        }
        #expect(DirectorController.consoleLevel(.suggest) == .manual)
    }

    @Test func routerReportsTransitionsOnly() throws {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        var states: [ProgramRouter.State] = []
        show.router.stateObserver = { states.append($0) }
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        let buffer = try Self.buffer()
        for _ in 0..<5 {
            show.router.submit(buffer, from: .a, isRepeat: false, routeGeneration: show.router.routeGeneration)
        }
        #expect(states.filter { $0 == .routed }.count == 1)
    }

    private static func buffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }
}
