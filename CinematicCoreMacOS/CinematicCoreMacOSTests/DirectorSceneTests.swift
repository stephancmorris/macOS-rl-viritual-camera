import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Decision core, stage 2: once per tick the Director builds one frozen
/// picture of the show. It has no effect on any camera or on Program.
@MainActor struct DirectorSceneTests {
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
        let show: ShowCoordinator
        let controller: DirectorController
        let clock: Clock
        var a: CameraManager { show.channelA }
        var b: CameraManager { show.channel(.b)! }
    }

    private func rig(adapter: DirectorEvidenceAdapter.Parameters? = DirectorStudyParameters.shadowV1.adapter,
                     tracking: Bool = false) -> Rig {
        let clock = Clock()
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: [Sink()]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "scene-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        for id in ChannelID.allCases {
            guard let camera = show.channel(id) else { continue }
            camera.setRunningForTesting(true)
        }
        if tracking {
            let b = show.channel(.b)!
            b.shotComposer.lockTarget(UUID())
            b.setOperationMode(.autoTracking)
            b.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true, holdingSteady: true, subjectSpeed: 0)
            b.cropEngine?.jumpToTarget()
        }
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
            adapterParameters: adapter, cutReadinessParameters: adapter == nil ? nil : DirectorStudyParameters.shadowV1.readiness,
            log: { _ in })
        controller.attach()
        return .init(show: show, controller: controller, clock: clock)
    }

    private func tick(_ r: Rig, _ count: Int = 1, observe: Bool = false) {
        for _ in 0..<count {
            r.clock.now += DirectorController.tickInterval
            if observe { r.b.recordObservationForTesting(capturedAt: r.clock.now, personCount: 1) }
            r.controller.tick()
        }
    }

    private func render(_ r: Rig, _ camera: CameraManager) throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        camera.setLatestRenderedFrameForTesting(.init(channelID: camera.channelID, revisions: camera.revisions,
            sourceTimestamp: r.clock.now, processingStartedAt: r.clock.now, renderedAt: r.clock.now,
            crop: .fullFrame, outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
    }

    /// Change Program's own preset through the operator's Edit Live path.
    private func setProgramPreset(_ r: Rig, _ preset: OperatorCommand.Preset) {
        r.show.setEditLive(true)
        #expect(r.show.dispatch(r.show.makeCommand(.selectPreset(preset))).wasAccepted)
        r.show.setEditLive(false)
    }

    @Test func sceneListsEveryAssignedInput() throws {
        let r = rig()
        defer { r.controller.detach() }
        tick(r)
        let scene = try #require(r.controller.latestScene)
        #expect(scene.now == r.clock.now)
        #expect(scene.evidenceRevision == r.controller.evidenceRevision)
        #expect(scene.program == r.show.programChannel && scene.preview == r.show.previewChannel)
        #expect(scene.routeGeneration == r.show.router.routeGeneration)
        #expect(scene.inputs.map(\.channel) == [.a, .b])
        for input in scene.inputs {
            let camera = try #require(r.show.channel(input.channel))
            #expect(input.shot == camera.directorShot)
            #expect(input.format == .init(camera.directorShot.preset))
            #expect(input.revisions == camera.revisions)
            #expect(input.sourceGeneration == camera.revisions.sourceGeneration)
            #expect(input.running == camera.isRunning && input.sourceMissing == camera.sourceMissing)
            #expect(input.sample == DirectorController.sample(camera.evidenceReadings(now: r.clock.now)))
            #expect(input.state == r.controller.adapter?.state(for: input.channel))
        }
        #expect(scene.segmentType == .liveEvent)
    }

    @Test func programStartRestartsOnATakeAndOnAPresetChange() throws {
        let r = rig()
        defer { r.controller.detach() }
        let attachedAt = r.clock.now
        tick(r, 8)
        var scene = try #require(r.controller.latestScene)
        #expect(scene.programStartedAt == attachedAt)
        #expect(scene.history.isEmpty)
        let firstShot = r.a.directorShot

        try render(r, r.b)
        let take = r.show.take()
        #expect(take == .committed(newProgram: .b), "\(take)")
        tick(r)
        scene = try #require(r.controller.latestScene)
        #expect(scene.program == .b)
        #expect(scene.programStartedAt == r.clock.now)
        #expect(scene.history == [.init(shot: firstShot, endedAt: r.clock.now)])
        let takeTick = r.clock.now

        tick(r, 8)
        scene = try #require(r.controller.latestScene)
        #expect(scene.programStartedAt == takeTick)
        #expect(scene.history.count == 1)

        let before = r.b.directorShot
        setProgramPreset(r, .stage(.waistUp))
        #expect(r.b.directorShot != before)
        tick(r)
        scene = try #require(r.controller.latestScene)
        #expect(scene.programStartedAt == r.clock.now)
        #expect(scene.history.count == 2)
        #expect(scene.history.last == .init(shot: before, endedAt: r.clock.now))
    }

    @Test func historyKeepsTheNewest32() throws {
        let r = rig()
        defer { r.controller.detach() }
        let presets: [OperatorCommand.Preset] = [.stage(.fullBody), .stage(.waistUp)]
        for index in 0..<40 {
            setProgramPreset(r, presets[index % 2])
            tick(r)
        }
        let scene = try #require(r.controller.latestScene)
        #expect(scene.history.count == DirectorSceneBuilder.historyLimit)
        #expect(scene.history.last?.endedAt == r.clock.now)
    }

    @Test func lastWideFollowsAWideProgramAndStopsWhenItGoesTight() throws {
        let r = rig()
        defer { r.controller.detach() }
        #expect(r.a.directorShot.isWide)
        tick(r, 4)
        var scene = try #require(r.controller.latestScene)
        #expect(scene.lastWideAt == r.clock.now)
        let lastWide = r.clock.now

        setProgramPreset(r, .stage(.waistUp))
        tick(r, 12)
        scene = try #require(r.controller.latestScene)
        #expect(scene.lastWideAt == lastWide)
        #expect(scene.programStartedAt == lastWide + DirectorController.tickInterval)

        setProgramPreset(r, .stage(.wide))
        tick(r)
        scene = try #require(r.controller.latestScene)
        #expect(scene.lastWideAt == r.clock.now)
    }

    @Test func unknownCoverageStaysUnknown() throws {
        let r = rig()
        defer { r.controller.detach() }
        let region = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.5)
        r.b.setWorldObservationForTesting(.init(sourceGeneration: r.b.revisions.sourceGeneration,
            coverage: .region(region), observedAt: r.clock.now,
            sightings: [.init(track: UUID(), box: CGRect(x: 0.45, y: 0.25, width: 0.1, height: 0.4), confidence: 0.9)]))
        tick(r)
        let scene = try #require(r.controller.latestScene)
        let b = try #require(scene.input(.b)?.people)
        #expect(b.coverage == .region(region))
        #expect(b.count == 1)
        #expect(b.positions == [0.5])
        // A camera that has not scanned keeps "not scanned": it is not "nobody".
        let a = try #require(scene.input(.a)?.people)
        #expect(a.coverage == .none && a.observedAt == nil)
        // No world-model row gives no people at all.
        #expect(DirectorScene.People(nil) == nil)
        #expect(DirectorScene.People(r.show.worldModel.camera(.c)) == nil)
    }

    /// Run the same subject loss and recovery with the adapter off (the app
    /// before this change) and on (shadowV1). At level off, what the console
    /// shows must be identical on every tick.
    @Test func adapterOnDoesNotChangeTheConsoleAtLevelOff() throws {
        let off = rig(adapter: nil, tracking: true), on = rig(tracking: true)
        defer { off.controller.detach(); on.controller.detach() }
        var sections: [[NextShotStatus.DirectorSection]] = [[], []]
        func step(_ phase: RecoveryState.Phase, ticks: Int) {
            for (index, r) in [off, on].enumerated() {
                r.b.directorPerceptionForTesting = .init(phase: phase, galleryReady: true, holdingSteady: true, subjectSpeed: 0)
                for _ in 0..<ticks {
                    tick(r, observe: true)
                    sections[index].append(r.controller.sampleSectionForConsole())
                    #expect(r.controller.directorSection.level == .manual)
                    #expect(!r.controller.authority.paused)
                }
            }
        }
        step(.tracking, ticks: 12)
        #expect(on.controller.adapter?.state(for: .b)?.identity == .confirmed)
        step(.wideWaiting, ticks: 8)
        #expect(on.controller.adapter?.state(for: .b)?.identity == .lost)
        step(.tracking, ticks: 12)
        #expect(sections[0].count == 32 && sections[0] == sections[1])
        #expect(sections[1].allSatisfy { $0 == sections[1][0] })
        // The adapter really was on: it saw the loss and forwarded its events.
        #expect(on.controller.appliedEvents.contains(.evidenceAvailable(false)))
        #expect(off.controller.appliedEvents.allSatisfy { if case .evidenceAvailable = $0 { false } else { true } })
    }

    @Test func aBadClockGivesNoScene() throws {
        let r = rig()
        defer { r.controller.detach() }
        tick(r)
        #expect(r.controller.latestScene != nil)
        for bad in [TimeInterval.nan, .infinity, -1] {
            r.clock.now = bad
            r.controller.tick()
            #expect(r.controller.latestScene == nil)
        }
        let builder = DirectorSceneBuilder(show: r.show)
        builder.begin(at: 100)
        #expect(builder.build(now: .nan, evidenceRevision: 1, samples: [:], adapter: nil,
                              segmentType: .liveEvent, style: nil) == nil)
        #expect(builder.build(now: 101, evidenceRevision: 1, samples: [:], adapter: nil,
                              segmentType: .liveEvent, style: nil) != nil)
        // A clock that runs backwards cannot be placed after the facts kept so far.
        #expect(builder.build(now: 100.5, evidenceRevision: 2, samples: [:], adapter: nil,
                              segmentType: .liveEvent, style: nil) == nil)
    }

    @Test func buildingTheSceneChangesNoCameraAndNotProgram() throws {
        let r = rig(tracking: true)
        defer { r.controller.detach() }
        let revisions = ChannelID.allCases.compactMap { r.show.channel($0)?.revisions }
        let route = r.show.router.routeGeneration, program = r.show.programChannel
        tick(r, 40, observe: true)
        #expect(ChannelID.allCases.compactMap { r.show.channel($0)?.revisions } == revisions)
        #expect(r.show.router.routeGeneration == route && r.show.programChannel == program)
    }

    @Test func theAppsDirectorRunsWithShadowV1() {
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        #expect(show.director.adapter?.parameters == DirectorStudyParameters.shadowV1.adapter)
        let readiness = show.director.captureCutReadinessParameters
        #expect(readiness?.minimumSettledTime == 0.2 && readiness?.maximumCutMotion == 0.1)
    }
}
