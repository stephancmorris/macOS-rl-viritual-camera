import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Synthetic acceptance/refusal evidence only. No live rig qualification.
@MainActor struct DirectorBackupExecutionTests {
    private final class Clock { var now = 1000.0 }
    private final class Gates {
        var fallbackQualified = true
        var backupQualified = true
        var admitted = true
        var prerequisites: DirectorAuthority.Prerequisites {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                outputHealthy: true, admissionCurrent: admitted,
                qualifiedLevels: backupQualified ? [.backup] : [])
        }
    }
    private final class Sink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var accepts = true
        var available = true { didSet { onStateChange?() } }
        var sent: [CVPixelBuffer] = []
        var isAvailable: Bool { available }
        var summary: String { "synthetic" }
        var detail: String { "synthetic" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
            guard accepts else { return false }
            sent.append(pixelBuffer)
            return true
        }
    }
    private struct Rig {
        let show: ShowCoordinator
        let clock: Clock
        let gates: Gates
        let sink: Sink
        let programPixels: CVPixelBuffer
        let previewPixels: CVPixelBuffer
    }
    private func pixels() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }
    private func rig(configured: Bool = true) throws -> Rig {
        let sink = Sink(), clock = Clock(), gates = Gates()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "b12-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { clock.now }
        show.router.clock = { clock.now }
        show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        let b = try #require(show.channel(.b))
        b.setRunningForTesting(true)
        b.shotComposer.config.shotPreset = .wide
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        show.director.prerequisitesOverride = { gates.prerequisites }
        show.director.cutReadinessForTesting = .init(reasons: [])
        show.director.attach()
        let r = Rig(show: show, clock: clock, gates: gates, sink: sink,
                    programPixels: try pixels(), previewPixels: try pixels())
        show.channelA.outputPort.sendFrame(r.programPixels, timestamp: 1)
        refreshPreview(r)
        #expect(show.director.setLevel(.backup) == .accepted)
        if configured { configure(r) }
        return r
    }
    private func configure(_ r: Rig, verified: Bool = true, age: Double = 0.5) {
        let b = r.show.channel(.b)!
        var revisions = b.revisions
        if !verified { revisions.shotRevision &+= 1 }
        let gates = r.gates
        r.show.director.backupExecution.configure(.init(
            verifiedSafeWide: .init(channel: .b, revisions: revisions, shot: b.directorShot),
            maximumFrameAge: age, fallbackQualified: { gates.fallbackQualified }))
    }
    private func refreshPreview(_ r: Rig, held: Bool = false) {
        guard let b = r.show.channel(.b) else { return }
        b.setLatestRenderedFrameForTesting(.init(channelID: .b, revisions: b.revisions,
            sourceTimestamp: 1, processingStartedAt: r.clock.now, renderedAt: r.clock.now,
            crop: .fullFrame, outputSize: .init(width: 1920, height: 1080), isRepeat: held,
            pixelBuffer: r.previewPixels))
    }
    private func enterHold(_ r: Rig, freshPreview: Bool = true) {
        r.clock.now += ProgramRouter.sourceLossAfter + 0.1
        if freshPreview { refreshPreview(r) }
        r.show.router.checkSourceHealth()
    }
    private var style: DirectorPreferences {
        .init(styles: [.liveEvent: .init(minimumShotDuration: 1, preferredShotDuration: 2,
            softMaximumShotDuration: 8, wideCadence: 5, repetitionWindow: 1,
            maximumMovement: 0.2, settleTime: 1, onAirMoveRate: 0.1, cutOnMotionAllowed: false)])
    }

    @Test func cameraLossImmediatelyPausesThenOnlyActualHoldCanCommitTheRenderedWide() throws {
        let r = try rig()
        let old = try #require(r.show.director.issueTakePermit(now: r.clock.now, validity: 10))
        r.show.channelA.setSourceMissingForTesting(true)
        #expect(r.show.director.authority.paused && !r.show.director.authority.healthy)
        #expect(r.show.router.state == .routed && r.sink.sent.count == 1)
        #expect(r.show.take(origin: .director, permit: old) == .rejected(.directorNotAuthorized))
        enterHold(r)
        #expect(r.show.director.backupExecution.lastResult == .committed(newProgram: .b))
        #expect(r.show.programChannel == .b && r.show.router.state == .routed)
        #expect(r.sink.sent.count == 2 && r.sink.sent.last === r.previewPixels)
        #expect(r.show.director.authority.paused && !r.show.director.authority.mayIssueTake(at: r.clock.now))
        #expect(r.show.director.backupExecution.alert == .switchedTo(.b))
        r.show.router.faultTick()
        #expect(r.sink.sent.count == 2) // The hold observer left no stale fault send.
    }

    @Test func routerLossBeforeCameraNotificationAlsoCutsExactlyOnceAndReconnectStaysPaused() throws {
        let r = try rig()
        enterHold(r)
        #expect(r.show.programChannel == .b && r.sink.sent.count == 2)
        r.show.channelA.setSourceMissingForTesting(true)
        r.show.channelA.setSourceMissingForTesting(false)
        r.show.router.checkSourceHealth()
        #expect(r.show.director.authority.paused && r.sink.sent.count == 2)
        #expect(!r.show.director.authority.mayIssueTake(at: r.clock.now))
    }

    @Test func noConfigurationKeepsTheOriginalHoldThenBlackStandbyRoute() throws {
        let r = try rig(configured: false)
        r.show.channelA.setSourceMissingForTesting(true)
        enterHold(r)
        #expect(r.show.programChannel == .a)
        r.show.router.faultTick()
        #expect(r.sink.sent.last === r.programPixels)
        r.clock.now += ProgramRouter.holdDuration
        r.show.router.faultTick()
        #expect(r.show.router.state == .standby && r.show.programChannel == .a)
        #expect(r.sink.sent.last !== r.programPixels && r.sink.sent.last !== r.previewPixels)
        #expect(r.show.director.backupExecution.lastResult == nil)
    }

    @Test(arguments: ["manual", "editLive", "rebind", "role", "style", "qualification", "fallbackQualification", "admission", "destination", "gesture", "stale", "unverified", "tight", "invalidAge"])
    func currentBindingsAndFaultPermutationsRefuseWithoutALaterRetry(change: String) throws {
        let r = try rig()
        r.show.channelA.setSourceMissingForTesting(true)
        switch change {
        case "manual": r.show.director.takeOver()
        case "editLive": r.show.setEditLive(true)
        case "rebind":
            r.show.channel(.b)!.setSourceMissingForTesting(true)
            r.show.channel(.b)!.setSourceMissingForTesting(false)
        case "role": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
        case "style": r.show.director.preferencesChanged(style)
        case "qualification": r.gates.backupQualified = false
        case "fallbackQualification": r.gates.fallbackQualified = false
        case "admission": r.gates.admitted = false
        case "destination": r.sink.available = false
        case "gesture": r.show.channel(.b)!.setOperatorGestureForTesting(true)
        case "unverified": configure(r, verified: false)
        case "tight": r.show.channel(.b)!.shotComposer.config.shotPreset = .waistUp
        case "invalidAge": configure(r, age: .nan)
        default: break
        }
        enterHold(r, freshPreview: change != "stale")
        #expect(r.sink.sent.count == 1)
        #expect(r.show.director.authority.paused)
        r.gates.backupQualified = true; r.gates.fallbackQualified = true
        r.gates.admitted = true; r.sink.available = true
        refreshPreview(r)
        _ = r.show.director.backupExecution.routerStateChanged(r.show.router.state)
        #expect(r.sink.sent.count == 1)
    }

    @Test func heldOrBothMissingPreviewNeverFallbackAndBothStaleHasAnAlert() throws {
        for bothMissing in [false, true] {
            let r = try rig()
            r.show.channelA.setSourceMissingForTesting(true)
            r.clock.now += ProgramRouter.sourceLossAfter + 0.1
            if bothMissing { r.show.channel(.b)!.setSourceMissingForTesting(true) }
            refreshPreview(r, held: !bothMissing)
            r.show.router.checkSourceHealth()
            #expect(r.sink.sent.count == 1 && r.show.programChannel == .a)
            #expect(r.show.director.backupExecution.alert == .bothInputsStale)
        }
    }

    @Test func refusedSinkConsumesTheAttemptAndDuplicateFaultCannotCutLater() throws {
        let r = try rig()
        r.show.channelA.setSourceMissingForTesting(true)
        r.sink.accepts = false
        enterHold(r)
        #expect(r.show.director.backupExecution.lastResult == .rejected(.outputRefused))
        r.sink.accepts = true
        refreshPreview(r)
        #expect(r.show.director.backupExecution.sourceLoss(.a))
        _ = r.show.director.backupExecution.routerStateChanged(r.show.router.state)
        #expect(r.sink.sent.count == 1 && r.show.programChannel == .a)
    }

    @Test func operatorTakeDuringPreHoldReservationWinsWithoutAnAutomaticFollowup() throws {
        let r = try rig()
        r.show.channelA.setSourceMissingForTesting(true)
        #expect(r.show.take() == .committed(newProgram: .b))
        #expect(r.sink.sent.count == 2 && r.show.director.authority.paused)
        r.clock.now += 0.6
        r.show.router.checkSourceHealth()
        #expect(r.show.director.backupExecution.lastResult == nil)
        #expect(r.sink.sent.count == 2)
    }

    @Test func fallbackEffectRefusesAtAbsoluteDeadlineEvenBeforeWatchdogPublishesStandby() throws {
        let r = try rig(configured: false)
        enterHold(r)
        let window = try #require(r.show.router.holdWindow)
        r.clock.now = window.deadline
        refreshPreview(r)
        let frame = try #require(r.show.channel(.b)!.latestRenderedFrame)
        #expect(!r.show.router.commitTake(frame, to: .b,
            expectedRouteGeneration: r.show.router.routeGeneration, fallbackWindow: window))
        #expect(r.sink.sent.count == 1 && r.show.programChannel == .a)
        r.show.router.faultTick()
        #expect(r.show.router.state == .standby && r.show.programChannel == .a)
    }
}
