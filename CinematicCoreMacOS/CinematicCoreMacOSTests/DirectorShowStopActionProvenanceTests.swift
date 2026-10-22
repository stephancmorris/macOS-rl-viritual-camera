import Combine
import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorShowStopActionProvenanceTests {
    @MainActor private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    @MainActor private struct Rig {
        let root: URL
        let log: DirectorShadowLog
        let show: ShowCoordinator
        let controller: DirectorController
        var a: CameraManager { show.channelA }
        var b: CameraManager { show.channel(.b)! }
    }
    private func source(_ name: String = "show-stop-private-device", recorded: Bool = false) -> DiagnosticsSessionIdentity.Source {
        .init(inputKind: recorded ? "Validation clip" : "Live camera", deviceName: name,
            deviceModelID: "show-stop-private-model", belowShowRate: false)
    }
    private func rig(pair: Bool = true, recorded: Bool = false) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("show-stop-provenance-\(UUID())")
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 8192,
            maximumQueuedBytes: 262144, maximumFileBytes: 262144, maximumStoreBytes: 524288))
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }
        if pair { show.addChannel(.b) }
        for id in ChannelID.allCases {
            guard let camera = show.channel(id) else { continue }
            // Exercise the actual synchronous Stop effect without AVCapture.
            camera.sessionStopRunningForTesting = {}
            if recorded {
                camera.preferredInputSource = .validationClip
                camera.stopCapture()
            }
            camera.setRunningForTesting(true)
            camera.setSourceIdentityForTesting(source(recorded: recorded))
        }
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { 100 }, shadowLog: log, log: { _ in })
        controller.attach()
        return .init(root: root, log: log, show: show, controller: controller)
    }
    private func records(_ log: DirectorShadowLog) throws -> [DirectorShadowRecord] {
        let url = log.directory.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }

    @Test(arguments: ["single", "pairA", "pairB", "pairBEditLive", "recordedPair", "changedPreferred"])
    func explicitShowStopRecordsOneSourceBoundLogicalResult(_ setup: String) async throws {
        let r = try rig(pair: setup != "single", recorded: setup == "recordedPair")
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        if setup == "pairB" || setup == "pairBEditLive" {
            #expect(r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration))
        }
        if setup == "pairBEditLive" { r.show.setEditLive(true) }
        if setup == "changedPreferred" { r.a.preferredInputSource = .validationClip }
        let cameras = ChannelID.allCases.compactMap { r.show.channel($0) }
        let before = cameras.map(\.revisions), route = r.show.router.routeGeneration
        let control = r.show.controlTargetRevision, program = r.show.programChannel
        r.show.stopShow(origin: .operatorUI)
        for (camera, previous) in zip(cameras, before) {
            #expect(!camera.isRunning && !camera.isStartingSession && !camera.sourceMissing)
            #expect(camera.revisions == .init(sourceGeneration: previous.sourceGeneration + 1,
                controlEpoch: previous.controlEpoch + 1, shotRevision: previous.shotRevision))
            #expect(camera.activeInputSource == camera.preferredInputSource)
        }
        #expect(r.show.programChannel == .a && !r.show.editLive)
        #expect(r.show.controlTarget == (setup == "single" ? .a : .b))
        #expect(r.show.controlTargetRevision == control + 1)
        #expect(r.show.router.routeGeneration == route + (program == .a ? 0 : 1))
        #expect(r.controller.appliedEvents.last == .stopShow)
        await r.log.flush()
        let rows = try records(r.log)
        #expect(rows.count == 2 && r.log.metrics.dropped == 0)
        #expect(rows.map(\.event.phase) == [.attempt, .result])
        #expect(rows.allSatisfy { $0.event.action == .stopSession && $0.event.targetScope == .session && $0.event.target == nil })
        #expect(rows.first?.event.actionID == rows.last?.event.actionID)
        #expect(rows.last?.event.outcome == .accepted)
        #expect(rows.first?.context.program == (program == .a ? "input-1" : "input-2"))
        #expect(rows.last?.context.program == "input-1" && rows.last?.context.running == false)
        #expect(rows.last?.event.programAfter == "input-1")
        #expect(rows.last?.event.previewAfter == (setup == "single" ? nil : "input-2"))
        #expect(rows.allSatisfy { $0.evidenceClass == (setup == "recordedPair" ? .recorded : .live) && $0.evidence.isEmpty && $0.judgements.isEmpty })
        let json = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
        #expect(!json.contains("show-stop-private") && !json.contains("deviceName") && !json.contains("ObjectIdentifier"))
        if setup == "pairB", let requested = ProcessInfo.processInfo.environment["ALFIE_DIRECTOR_SHOW_STOP_EXPORT"] {
            #expect(requested.hasPrefix("/") && !FileManager.default.fileExists(atPath: requested))
            guard requested.hasPrefix("/"), !FileManager.default.fileExists(atPath: requested) else {
                throw DirectorShadowLog.Failure.unavailable
            }
            let firstUTC = try #require(rows.first.flatMap { DirectorShadowExportManifest.utcDate($0.recordedAtUTC) })
            let lastUTC = try #require(rows.last.flatMap { DirectorShadowExportManifest.utcDate($0.recordedAtUTC) })
            _ = try await r.log.export(selection: .init(sessionIDs: [r.log.sessionID], fromUTC: firstUTC, throughUTC: lastUTC),
                toNewBundle: URL(fileURLWithPath: requested))
        }
    }

    @Test func consoleStopSelectsExplicitOperatorOrigin() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let console = LiveConsoleModel(show: r.show)
        console.stopShow()
        await r.log.flush()
        let rows = try records(r.log)
        #expect(!r.a.isRunning && !r.b.isRunning)
        #expect(rows.count == 2 && rows.last?.event.action == .stopSession && rows.last?.event.outcome == .accepted)
    }

    @Test(arguments: [false, true])
    func lifecycleStopPreservesEffectsWithoutHumanAttribution(_ explicit: Bool) async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        if explicit { r.show.stopShow(origin: .lifecycle) } else { r.show.stopShow() }
        await r.log.flush()
        #expect(!r.a.isRunning && !r.b.isRunning)
        #expect(r.controller.appliedEvents.last == .stopShow)
        #expect(try records(r.log).isEmpty)
        #expect(r.log.metrics.dropped == 0)
    }

    @Test(arguments: ["targetIdentity", "peerIdentity", "generation", "epoch", "roles", "route", "preferred", "missing", "actionID", "newAttempt", "removedInput", "replacementInput", "detach", "restart"])
    func changedWorldCannotBorrowShowStopSourceOrigin(_ change: String) async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let deliver = try #require(r.show.stopResultObserver)
        r.show.stopResultObserver = { action in
            switch change {
            case "targetIdentity": r.a.setSourceIdentityForTesting(self.source("replacement-target"))
            case "peerIdentity": r.b.setSourceIdentityForTesting(self.source("replacement-peer"))
            case "generation": r.a.stopCapture()
            case "epoch": r.b.cancelOperatorMotion()
            case "roles": r.show.setEditLive(true)
            case "route": _ = r.show.router.setProgram(.b, expectedRouteGeneration: r.show.router.routeGeneration)
            case "preferred": r.a.preferredInputSource = .validationClip
            case "missing": r.b.setSourceMissingForTesting(true)
            case "newAttempt": r.a.manualActionObserver?(.command(r.a.makeCommand(.cancelDetect)))
            case "removedInput": r.show.removeChannel(.b)
            case "replacementInput":
                r.show.removeChannel(.b)
                let replacement = r.show.addChannel(.b)
                replacement.sessionStopRunningForTesting = {}
                replacement.setSourceIdentityForTesting(self.source())
            case "detach": r.controller.detach()
            case "restart": r.controller.shadowRecorder?.restart()
            case "actionID": deliver(.init(id: UUID(), origin: .operatorUI)); return
            default: break
            }
            deliver(action)
        }
        r.show.stopShow(origin: .operatorUI)
        await r.log.flush()
        await r.controller.shadowRecorder?.log.flush()
        let rows = try records(r.log)
        #expect(rows.filter { $0.event.action == .stopSession && $0.event.phase == .attempt }.count == 1)
        #expect(!rows.contains { $0.event.action == .stopSession && $0.event.phase == .result })
        if change == "restart", let renewed = r.controller.shadowRecorder?.log {
            #expect(renewed.sessionID != r.log.sessionID)
            #expect(try records(renewed).isEmpty && renewed.metrics.dropped == 1)
        } else { #expect(r.log.metrics.dropped == (change == "newAttempt" ? 2 : 1)) }
    }

    @Test func duplicateAndLaterStoppedWorldCannotReuseShowStopOrigin() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let deliver = try #require(r.show.stopResultObserver)
        r.show.stopResultObserver = { action in deliver(action); deliver(action) }
        r.show.stopShow(origin: .operatorUI)
        r.show.stopResultObserver = deliver
        r.show.stopShow(origin: .operatorUI)
        await r.log.flush()
        #expect(try records(r.log).count == 2)
        #expect(r.log.metrics.dropped == 3)
    }

    @Test(arguments: ["unknownSource", "kindMismatch", "mixedSources", "stoppedPeer", "startingPeer"])
    func unknownOrMixedAttemptWorldCannotCreateShowStopEvidence(_ bad: String) async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        switch bad {
        case "unknownSource": r.a.setSourceIdentityForTesting(.unrecorded)
        case "kindMismatch": r.a.setSourceIdentityForTesting(source(recorded: true))
        case "mixedSources":
            r.b.preferredInputSource = .validationClip
            r.b.stopCapture()
            r.b.setRunningForTesting(true)
            r.b.setSourceIdentityForTesting(source(recorded: true))
        case "stoppedPeer": r.b.setRunningForTesting(false)
        case "startingPeer": r.b.setStartingForTesting(true)
        default: break
        }
        r.show.stopShow(origin: .operatorUI)
        await r.log.flush()
        #expect(try records(r.log).isEmpty)
        #expect(r.log.metrics.dropped == 2)
    }

    @Test func showStopAvailabilityObservesOnlyAttachedChannelLiveness() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        var changes = 0
        let subscription = show.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        #expect(!show.isAnyChannelLive)
        show.channelA.setRunningForTesting(true)
        #expect(show.isAnyChannelLive && changes == 1)
        show.channelA.setRunningForTesting(true)
        #expect(changes == 1)
        show.channelA.setRunningForTesting(false)
        #expect(!show.isAnyChannelLive && changes == 2)
        let b = show.addChannel(.b)
        var before = changes
        b.setRunningForTesting(true)
        #expect(!show.channelA.isRunning && show.isAnyChannelLive && changes == before + 1)
        b.setRunningForTesting(false)
        #expect(!show.isAnyChannelLive && changes == before + 2)
        before = changes
        b.setStartingForTesting(true)
        #expect(!b.isRunning && show.isAnyChannelLive && changes == before + 1)
        b.setStartingForTesting(true)
        #expect(changes == before + 1)
        b.setStartingForTesting(false)
        #expect(!show.isAnyChannelLive && changes == before + 2)
        before = changes
        b.setSourceMissingForTesting(true)
        b.preferredInputSource = .validationClip
        #expect(changes == before)
        b.sessionStopRunningForTesting = {}
        show.removeChannel(.b)
        before = changes
        b.setRunningForTesting(true)
        b.setStartingForTesting(true)
        #expect(show.channel(.b) == nil && !show.isAnyChannelLive && changes == before)
    }

    @Test func failedAttemptCannotBorrowFreshSourcesAtResult() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        r.a.setSourceIdentityForTesting(.unrecorded)
        let deliver = try #require(r.show.stopResultObserver)
        r.show.stopResultObserver = { action in
            for camera in [r.a, r.b] {
                camera.setSourceIdentityForTesting(self.source("fresh-source"))
                camera.setRunningForTesting(true)
            }
            deliver(action)
        }
        r.show.stopShow(origin: .operatorUI)
        await r.log.flush()
        #expect(try records(r.log).isEmpty)
        #expect(r.log.metrics.dropped == 2)
    }
}
