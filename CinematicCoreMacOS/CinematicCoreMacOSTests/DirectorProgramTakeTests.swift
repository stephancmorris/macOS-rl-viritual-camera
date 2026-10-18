import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorProgramTakeTests {
    private final class Clock { var now = 1000.0 }
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
            guard accepts else { return false }; sent += 1; return true
        }
    }
    private struct Rig { let show: ShowCoordinator; let clock: Clock; let sink: Sink }
    private var ready: DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.auto, .backup])
    }
    private func rig(style: Bool = false) -> Rig {
        let sink = Sink(), clock = Clock()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "b07-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        show.channelA.setRunningForTesting(true); show.channel(.b)!.setRunningForTesting(true)
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        show.director.prerequisitesOverride = { ready }
        show.director.cutReadinessForTesting = .init(reasons: [])
        show.director.attach()
        if style {
            show.director.preferencesChanged(.init(styles: [.liveEvent: .init(minimumShotDuration: 5,
                preferredShotDuration: 10, softMaximumShotDuration: 30, wideCadence: 20,
                repetitionWindow: 4, maximumMovement: 0.2, settleTime: 1, onAirMoveRate: 0.1, cutOnMotionAllowed: false)]))
        }
        #expect(show.director.setLevel(.auto) == .accepted)
        return .init(show: show, clock: clock, sink: sink)
    }
    private func prepare(_ rig: Rig) throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer), b = rig.show.channel(.b)!
        b.setLatestRenderedFrameForTesting(.init(channelID: .b, revisions: b.revisions, sourceTimestamp: 1,
            processingStartedAt: rig.clock.now, renderedAt: rig.clock.now, crop: .fullFrame,
            outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
    }
    private func permit(_ rig: Rig) throws -> TakePermit {
        try #require(rig.show.director.issueTakePermit(now: rig.clock.now, validity: 1))
    }
    @Test func directorRequiresPermitAndFallbackCannotBorrowANormalPermit() throws {
        let r = rig(); try prepare(r)
        #expect(r.show.take(origin: .director) == .rejected(.directorNotAuthorized))
        #expect(r.show.take(origin: .fallback) == .rejected(.directorNotAuthorized))
        let p = try permit(r)
        #expect(r.show.take(origin: .fallback, permit: p) == .rejected(.directorNotAuthorized))
        #expect(r.show.take(origin: .director, permit: p) == .rejected(.directorNotAuthorized))
        #expect(r.show.programChannel == .a && r.sink.sent == 0)
    }
    @Test func validPermitCutsOnlyOnceThroughTheExistingTechnicalPath() throws {
        let r = rig(); try prepare(r)
        let p = try permit(r)
        #expect(r.show.take(origin: .director, permit: p) == .committed(newProgram: .b))
        #expect(r.show.programChannel == .b && r.show.previewChannel == .a && r.sink.sent == 1)
        #expect(r.show.take(origin: .director, permit: p) == .rejected(.directorNotAuthorized))
        #expect(r.sink.sent == 1)
        #expect(!r.show.director.appliedEvents.contains(.operatorTake))
    }
    @Test func technicalRefusalConsumesThePermitAndNeverArmsALaterCut() throws {
        let r = rig(), p = try permit(r)
        guard case .rejected(.notEligible) = r.show.take(origin: .director, permit: p) else {
            Issue.record("Expected missing frame refusal"); return
        }
        try prepare(r)
        #expect(r.show.take(origin: .director, permit: p) == .rejected(.directorNotAuthorized))
        #expect(r.show.programChannel == .a)
    }
    @Test func supersededRequestAndOutputRefusalAlsoConsumeBeforeTheirChecks() throws {
        let r = rig(); try prepare(r)
        let p = try permit(r)
        #expect(r.show.take(.init(expectedProgram: .b, expectedPreview: .a, routeGeneration: 0),
                           origin: .director, permit: p) == .rejected(.superseded))
        #expect(r.show.take(origin: .director, permit: p) == .rejected(.directorNotAuthorized))
        let next = try permit(r); r.sink.accepts = false
        #expect(r.show.take(origin: .director, permit: next) == .rejected(.outputRefused))
        r.sink.accepts = true
        #expect(r.show.take(origin: .director, permit: next) == .rejected(.directorNotAuthorized))
    }
    @Test func stalePermitCannotConsumeReplacement() throws {
        let r = rig(); try prepare(r)
        let old = try permit(r), next = try permit(r)
        #expect(r.show.take(origin: .director, permit: old) == .rejected(.directorNotAuthorized))
        #expect(r.show.take(origin: .director, permit: next) == .committed(newProgram: .b))
    }
    @Test(arguments: ["readiness", "manual", "editLive", "source", "roles", "expired"])
    func finalStateIsRecheckedBeforeProgramChanges(change: String) throws {
        let r = rig(); try prepare(r)
        let p = try permit(r)
        switch change {
        case "readiness": r.show.director.cutReadinessForTesting = .init(reasons: [.identityUncertain])
        case "manual": r.show.director.takeOver()
        case "editLive": r.show.setEditLive(true)
        case "source": r.show.channel(.b)!.setSourceMissingForTesting(true)
        case "roles": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
        default: r.clock.now += 1.001
        }
        let before = r.show.programChannel
        #expect(r.show.take(origin: .director, permit: p) == .rejected(.directorNotAuthorized))
        #expect(r.show.programChannel == before && r.sink.sent == 0)
    }
    @Test func operatorTakeRemainsAvailableWhenDirectorReadinessIsMissing() throws {
        let r = rig(); try prepare(r)
        r.show.director.cutReadinessForTesting = nil
        #expect(r.show.director.issueTakePermit(now: r.clock.now, validity: 1) == nil)
        #expect(r.show.take() == .committed(newProgram: .b))
    }
    @Test func operatorAttemptUsesSuppliedStyleDwellOnTheSameClock() throws {
        let r = rig(style: true)
        _ = r.show.take() // Refused for missing render; still an operator nudge.
        #expect(!r.show.director.authority.paused)
        #expect(r.show.director.authority.nudgeHold == .until(1005))
        r.clock.now = 1004.999
        #expect(r.show.director.issueTakePermit(now: r.clock.now, validity: 1) == nil)
        r.clock.now = 1005
        #expect(r.show.director.issueTakePermit(now: r.clock.now, validity: 1) != nil)
    }
    @Test func finalCutInputsUseFreshMotionAndCropInsteadOfCachedTickValues() throws {
        let id = UUID()
        func sample(at: Double, speed: Double, converged: Bool) -> ChannelEvidenceSample {
            .init(channel: .b, sampledAt: at, lockPhase: .tracking, trackingOwnsControl: true,
                  galleryReady: true, lockedTargetID: id, observationAge: 0, subjectSpeed: speed,
                  holdingSteady: true, cropConverged: converged, operatorGestureInProgress: false,
                  observedPersonCount: 1)
        }
        var adapter = DirectorEvidenceAdapter(parameters: .init(maximumObservationAge: 2, debounce: 0, stillSpeed: 0.2))
        adapter.ingest(sample(at: 10, speed: 0, converged: true))
        let availability = TakeAvailability.evaluate(take: .init(sourcePresent: true, supportedAtStandard: true,
            hasFreshRender: true, matchesSourceGeneration: true, matchesShotRevision: true,
            legalGeometry: true, isHeldFrame: false, takePending: false), program: .a, preview: .b,
            standard: .p50, editLive: false)
        let moving = try #require(DirectorController.currentCutInputs(sample: sample(at: 11, speed: 1, converged: true),
            adapter: adapter, take: availability, now: 11))
        #expect(moving.motion == 1 && moving.framingSettledFor == 0)
        let crop = try #require(DirectorController.currentCutInputs(sample: sample(at: 11, speed: 0, converged: false),
            adapter: adapter, take: availability, now: 11))
        #expect(!crop.cropConverged && crop.framingSettledFor == 0)
        #expect(DirectorController.currentCutInputs(sample: sample(at: 13, speed: 0, converged: true),
            adapter: adapter, take: availability, now: 13) == nil)
    }

}
