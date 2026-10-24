import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Synthetic clocks/geometry only: no live route, scan or N2 qualification.
@MainActor struct DirectorOnAirMoveExecutionTests {
    private final class Clock { var now = 100.0 }
    private struct Rig {
        let show: ShowCoordinator
        let clock: Clock
        let subject: UUID
        let execution: DirectorOnAirMoveExecution
    }
    private var configuration: DirectorOnAirMoveExecution.Configuration {
        .init(readiness: .init(minimumSettledTime: 0, maximumMotion: 0.2, cutOnMotionAllowed: false,
            minimumCutSettledTime: 0, maximumCutMotion: 0.1), maximumSampleAge: 1)
    }
    private func style(rate: Double = 0.25) -> DirectorStyle {
        .init(minimumShotDuration: 5, preferredShotDuration: 10, softMaximumShotDuration: 30,
            wideCadence: 20, repetitionWindow: 4, maximumMovement: 0.2, settleTime: 1,
            onAirMoveRate: rate, cutOnMotionAllowed: false)
    }
    private func rig() throws -> Rig {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        let clock = Clock(), channel = show.channelA, subject = UUID()
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b).setRunningForTesting(true)
        channel.setRunningForTesting(true)
        channel.shotComposer.config.cinematicFormat = .stage
        channel.selectPreset(.stage(.wide))
        channel.shotComposer.lockTarget(subject)
        channel.setOperationMode(.autoTracking)
        let person = PersonDetector.DetectedPerson(id: subject,
            boundingBox: CGRect(x: 0.4, y: 0.1, width: 0.2, height: 0.2), confidence: 0.95,
            timestamp: 100, poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        let crop = try #require(channel.shotComposer.compose(person: person, observationTimestamp: clock.now))
        let engine = try #require(channel.cropEngine)
        engine.qualityFloor = .forSource(height: 2160)
        engine.setTargetCrop(crop); engine.jumpToTarget()
        show.director.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.auto, .backup])
        }
        show.director.attach()
        show.director.preferencesChanged(.init(styles: [.liveEvent: style()]))
        #expect(show.director.setLevel(.auto) == .accepted)
        let execution = DirectorOnAirMoveExecution(show: show, controller: show.director)
        execution.programReadinessForTesting = .init(reasons: [])
        execution.betterInputCutReadyForTesting = .some(false)
        return .init(show: show, clock: clock, subject: subject, execution: execution)
    }
    private func request(_ rig: Rig) throws -> OnAirMovePolicy.Plan {
        try #require(rig.execution.enqueue(.init(preset: .stage(.fullBody)), programStartedAt: 90,
            configuration: configuration))
    }

    @Test func actualProgramMoveUsesOneRungWithoutChangingLockModeOrPreview() throws {
        let r = try rig(), a = r.show.channelA, engine = try #require(a.cropEngine)
        let origin = engine.currentCrop, before = a.revisions, preview = r.show.channel(.b)!.revisions
        let destination = try #require(a.shotComposer.destinationHeight(for: .stage(.fullBody)))
        let plan = try request(r)
        #expect(r.execution.commit(plan) == .started(plan.id))
        #expect(a.revisions.controlEpoch == before.controlEpoch + 1 && a.revisions.shotRevision == before.shotRevision + 1)
        #expect(a.revisions.sourceGeneration == before.sourceGeneration)
        #expect(engine.currentCrop == origin && !a.operatorGestureInProgress)
        #expect(a.hasDirectorShotMove(id: plan.id))
        var previous = Double(origin.size.height)
        let distance = abs(log(Double(destination / origin.size.height)))
        a.advanceShotMove(now: r.clock.now)
        for frame in 1...400 {
            r.clock.now = 100 + Double(frame) / 50
            a.advanceShotMove(now: r.clock.now)
            let next = Double(engine.currentCrop.size.height)
            #expect(abs(log(next / previous)) / distance <= plan.maximumRate / 50 + 0.00000001)
            previous = next
        }
        #expect(a.directorShot == plan.to && !a.hasDirectorShotMove(id: plan.id))
        #expect(abs(engine.currentCrop.size.height - destination) < 0.000001)
        #expect(a.manualLockedTargetID == r.subject && a.activeMode == .autoTracking && a.recoveryState.trackingOwnsControl)
        #expect(r.show.channel(.b)!.revisions == preview && r.show.programChannel == .a)
        #expect(r.execution.commit(plan) == .rejected)
    }

    @Test(arguments: ["manual", "editLive", "source", "gesture", "readiness", "roles", "subject", "expired"])
    func pendingPlanNeverSurvivesChangedAuthorityOrBindings(event: String) throws {
        let r = try rig(), plan = try request(r), channel = r.show.channelA
        let before = channel.revisions
        switch event {
        case "manual": r.show.director.takeOver()
        case "editLive": r.show.setEditLive(true)
        case "source": channel.setSourceMissingForTesting(true)
        case "gesture": channel.setOperatorGestureForTesting(true)
        case "readiness": r.execution.programReadinessForTesting = .init(reasons: [.identityUncertain])
        case "roles": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
        case "subject": channel.shotComposer.lockTarget(UUID())
        default: r.clock.now += 1.001
        }
        #expect(r.execution.commit(plan) == .rejected)
        #expect(channel.revisions == before && !channel.hasDirectorShotMove(id: plan.id))
    }

    @Test(arguments: ["manual", "editLive", "source", "gesture", "roles", "subject", "style", "readiness"])
    func activeMoveStopsBeforeTheNextFrameAdvance(event: String) throws {
        let r = try rig(), channel = r.show.channelA, engine = try #require(channel.cropEngine), plan = try request(r)
        #expect(r.execution.commit(plan) == .started(plan.id))
        channel.advanceShotMove(now: 100)
        r.clock.now = 100.1; channel.advanceShotMove(now: 100.1)
        let visible = engine.currentCrop
        switch event {
        case "manual": r.show.director.takeOver()
        case "editLive": r.show.setEditLive(true)
        case "source": channel.setSourceMissingForTesting(true)
        case "gesture": channel.setOperatorGestureForTesting(true)
        case "roles": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
        case "subject": channel.shotComposer.lockTarget(UUID())
        case "style": r.show.director.preferencesChanged(.init(styles: [.liveEvent: style(rate: 0.2)]))
        default: r.execution.programReadinessForTesting = .init(reasons: [.identityUncertain])
        }
        r.clock.now = 100.2; channel.advanceShotMove(now: 100.2)
        #expect(engine.currentCrop == visible && !channel.hasDirectorShotMove(id: plan.id))
        #expect(channel.directorShot == plan.from)
    }

    @Test func retirementCannotStopTheOperatorMoveThatSupersededAlfie() throws {
        let r = try rig(), channel = r.show.channelA, plan = try request(r)
        #expect(r.execution.commit(plan) == .started(plan.id))
        // The actual dispatcher reports manual intervention before admission.
        #expect(channel.dispatch(channel.makeCommand(.beginZoom(.pullOut))) == .accepted)
        #expect(channel.zoomMoveDirection == .pullOut && channel.operatorGestureInProgress)
        r.execution.retire()
        #expect(channel.zoomMoveDirection == .pullOut && channel.operatorGestureInProgress)
    }

    @Test func capturedMoveCannotCrossDetachAndFreshDetachedRequestsRefuse() throws {
        let r = try rig(), controller = r.show.director, channel = r.show.channelA
        let captured = try request(r), before = channel.revisions
        controller.detach()
        #expect(r.execution.commit(captured) == .rejected)
        #expect(channel.revisions == before && !channel.hasDirectorShotMove(id: captured.id))
        #expect(controller.handToAlfie() == .accepted)
        #expect(r.execution.enqueue(.init(preset: .stage(.fullBody)), programStartedAt: 90,
            configuration: configuration) == nil)
        controller.attach()
        #expect(controller.authority.paused)
        #expect(r.execution.commit(captured) == .rejected)
        #expect(controller.handToAlfie() == .accepted)
        let fresh = try request(r)
        #expect(r.execution.commit(captured) == .rejected)
        #expect(r.execution.commit(fresh) == .started(fresh.id))
    }

    @Test func detachedMoveOwnerStopsBeforeItsNextFrameEvenOutsideTheControllerAdapter() throws {
        let r = try rig(), channel = r.show.channelA, engine = try #require(channel.cropEngine)
        let plan = try request(r)
        #expect(r.execution.commit(plan) == .started(plan.id))
        channel.advanceShotMove(now: 100)
        r.clock.now = 100.1; channel.advanceShotMove(now: 100.1)
        let held = engine.currentCrop
        r.show.director.detach()
        // This independently retained adapter is not the controller-owned
        // adapter retired by detach; its frame owner must reject detached use.
        #expect(r.show.director.handToAlfie() == .accepted)
        r.clock.now = 100.2; channel.advanceShotMove(now: 100.2)
        #expect(engine.currentCrop == held && !channel.hasDirectorShotMove(id: plan.id))
        #expect(channel.directorShot == plan.from)
    }

    @Test func actualControllerManualReversalKeepsTheInterruptedRungGeometry() throws {
        let r = try rig(), controller = r.show.director, channel = r.show.channelA
        controller.onAirMoves.programReadinessForTesting = .init(reasons: [])
        controller.onAirMoves.betterInputCutReadyForTesting = .some(false)
        guard case .started(let id) = controller.moveProgram(.init(preset: .stage(.fullBody)),
            programStartedAt: 90, configuration: configuration) else { Issue.record("Expected owned Director move"); return }
        channel.advanceShotMove(now: 100)
        r.clock.now = 100.1; channel.advanceShotMove(now: 100.1)
        #expect(channel.dispatch(channel.makeCommand(.beginZoom(.pullOut))) == .accepted)
        #expect(controller.authority.paused && !channel.hasDirectorShotMove(id: id))
        #expect(channel.zoomMoveDirection == .pullOut && channel.operatorGestureInProgress)
        controller.onAirMoves.retire()
        #expect(channel.zoomMoveDirection == .pullOut)
        for frame in 0...500 { channel.advanceShotMove(now: 100.1 + Double(frame) / 50) }
        #expect(channel.directorShot == .init(preset: .stage(.wide)))
        #expect(channel.manualLockedTargetID == r.subject && channel.activeMode == .autoTracking)
    }

    @Test func zeroDistanceRungsAreRefusedWithoutInventingMovement() throws {
        let r = try rig(), channel = r.show.channelA
        let large = PersonDetector.DetectedPerson(id: r.subject,
            boundingBox: .init(x: 0.4, y: 0.1, width: 0.2, height: 0.6), confidence: 0.95,
            timestamp: 100, poseKeypoints: nil, faceBoundingBox: nil, faceLandmarkRatios: nil)
        let crop = try #require(channel.shotComposer.compose(person: large, observationTimestamp: 100))
        let engine = try #require(channel.cropEngine)
        engine.setTargetCrop(crop); engine.jumpToTarget()
        #expect(channel.shotComposer.destinationHeight(for: .stage(.wide)) == channel.shotComposer.destinationHeight(for: .stage(.fullBody)))
        let plan = try request(r), before = channel.revisions
        #expect(r.execution.commit(plan) == .failed)
        #expect(channel.revisions == before && channel.zoomMoveDirection == nil)
        #expect(r.execution.policy.lastMoveAt == 100)
        #expect(r.execution.commit(plan) == .rejected)
    }

    @Test func configuredTwoInputRawEvidenceReachesTheProductionReadinessPath() throws {
        let r = try rig(), show = r.show, channel = show.channelA, preview = try #require(show.channel(.b))
        show.director.detach()
        let thresholds = DirectorReadiness.Parameters(minimumSettledTime: 0, maximumMotion: 0.2,
            cutOnMotionAllowed: false, minimumCutSettledTime: 1, maximumCutMotion: 0.1)
        let controller = DirectorController(show: show, clock: { r.clock.now }, qualifiedLevels: { [.auto] },
            adapterParameters: .init(maximumObservationAge: 2, debounce: 0, stillSpeed: 0.2),
            cutReadinessParameters: thresholds, log: { _ in })
        controller.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.auto])
        }
        preview.shotComposer.lockTarget(UUID()); preview.setOperationMode(.autoTracking)
        channel.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true, holdingSteady: true, subjectSpeed: 0)
        preview.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true, holdingSteady: false, subjectSpeed: 0)
        controller.attach()
        controller.preferencesChanged(.init(styles: [.liveEvent: style()]))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        for time in [100.0, 101.0] {
            r.clock.now = time
            for input in [channel, preview] {
                input.recordObservationForTesting(capturedAt: time, personCount: 1)
                input.setLatestRenderedFrameForTesting(.init(channelID: input.channelID, revisions: input.revisions,
                    sourceTimestamp: time, processingStartedAt: time, renderedAt: time, crop: .fullFrame,
                    outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
            }
            controller.tick()
        }
        #expect(controller.adapter?.state(for: .a)?.identity == .confirmed)
        #expect(controller.adapter?.settledFor(.a, now: 101) == 1)
        #expect(controller.currentTakeState(now: 101).cutReadiness.reasons == [.framingUnsettled])
        #expect(controller.setLevel(.auto) == .accepted)
        // No programReadiness/alternative-ready override is installed here.
        guard case .started = controller.moveProgram(.init(preset: .stage(.fullBody)), programStartedAt: 90,
            configuration: .init(readiness: thresholds, maximumSampleAge: 1)) else {
            Issue.record("Configured raw evidence did not reach production readiness"); return
        }
        #expect(channel.manualLockedTargetID == r.subject && channel.zoomMoveDirection == .pushIn)
        controller.detach()
    }

    @Test func noDefaultsOrUnknownAlternativeCanAuthorizeAnEffect() throws {
        let r = try rig(), channel = r.show.channelA, before = channel.revisions
        let empty = DirectorOnAirMoveExecution(show: r.show, controller: r.show.director)
        #expect(empty.enqueue(.init(preset: .stage(.fullBody)), programStartedAt: 90, configuration: configuration) == nil)
        r.execution.betterInputCutReadyForTesting = .some(nil)
        #expect(r.execution.enqueue(.init(preset: .stage(.fullBody)), programStartedAt: 90, configuration: configuration) == nil)
        r.execution.betterInputCutReadyForTesting = .some(true)
        #expect(r.execution.enqueue(.init(preset: .stage(.fullBody)), programStartedAt: 90, configuration: configuration) == nil)
        #expect(channel.dispatch(channel.makeCommand(.beginZoom(.pushIn), origin: .director)) == .rejected("Director moves require slow admission"))
        #expect(channel.dispatch(channel.makeCommand(.endZoom, origin: .director)) == .rejected("Director moves require slow admission"))
        #expect(channel.revisions == before)
    }

    @Test(arguments: [0.05, 0.2, 1.0])
    func trajectoryBoundsActualLogGeometryAtSeveralRates(rate: Double) throws {
        for heights in [(0.9, 0.62), (0.52, 0.8)] {
            let path = try #require(DirectorShotMoveTrajectory(originHeight: heights.0, destinationHeight: heights.1, maximumRate: rate))
            #expect(path.duration >= 1 / rate)
            let delta = path.duration / 1000, distance = abs(log(heights.1 / heights.0))
            var previous = path.height(at: 0)
            for tick in 1...1000 {
                let next = path.height(at: Double(tick) * delta)
                #expect(abs(log(next / previous)) / distance <= rate * delta + 0.000000001)
                previous = next
            }
            #expect(path.height(at: path.duration) == heights.1)
        }
    }

    @Test func engineRetiresChangedGeometryAndDoesNotCatchUpAfterAStall() throws {
        let engine = try #require(CropEngine())
        engine.qualityFloor = .forSource(height: 2160)
        let visible = CropEngine.CropRect(center: .init(x: 0.5, y: 0.5), size: .init(width: 0.9, height: 0.9))
        #expect(engine.beginDirectorZoom(.pushIn, to: 0.6, maximumRate: 0.2, visibleCrop: visible))
        engine.advanceZoom(now: 100, aspect: 1)
        engine.advanceZoom(now: 200, aspect: 1)
        let path = try #require(DirectorShotMoveTrajectory(originHeight: 0.9, destinationHeight: 0.6, maximumRate: 0.2))
        #expect(abs(Double(engine.currentCrop.size.height) - path.height(at: 0.1)) < 0.000000001)
        let held = engine.currentCrop
        engine.advanceZoom(now: 200.1, aspect: 0.8)
        #expect(engine.currentCrop == held && engine.zoomDirection == nil)
        for invalid in [Double.nan, .infinity, -1, 0] {
            #expect(DirectorShotMoveTrajectory(originHeight: 0.9, destinationHeight: 0.6, maximumRate: invalid) == nil)
        }
    }
}
