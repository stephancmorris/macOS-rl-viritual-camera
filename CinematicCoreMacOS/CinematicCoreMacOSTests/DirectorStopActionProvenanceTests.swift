import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorStopActionProvenanceTests {
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
    private func source(_ name: String = "stop-private-device") -> DiagnosticsSessionIdentity.Source {
        .init(inputKind: "Live camera", deviceName: name, deviceModelID: "stop-private-model", belowShowRate: false)
    }
    private func rig() throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stop-provenance-\(UUID())")
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 8192,
            maximumQueuedBytes: 262144, maximumFileBytes: 262144, maximumStoreBytes: 524288))
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }
        let b = show.addChannel(.b)
        for camera in [show.channelA, b] {
            camera.setRunningForTesting(true)
            camera.setSourceIdentityForTesting(source())
            // Stop uses the real synchronous effect, without touching AVCapture.
            camera.sessionStopRunningForTesting = {}
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

    @Test func dispatchedStopKeepsItsActualSourceOriginAfterRetiringCapture() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let before = r.a.revisions, command = r.a.makeCommand(.stopSession)
        #expect(r.a.dispatch(command) == .accepted)
        #expect(!r.a.isRunning && r.b.isRunning)
        #expect(r.a.revisions == .init(sourceGeneration: before.sourceGeneration + 1,
            controlEpoch: before.controlEpoch + 2, shotRevision: before.shotRevision))
        await r.log.flush()
        let rows = try records(r.log)
        #expect(rows.count == 2 && r.log.metrics.dropped == 0)
        #expect(rows.map(\.event.phase) == [.attempt, .result])
        #expect(rows.allSatisfy { $0.event.action == .stopSession && $0.event.actionID?.value == command.id })
        #expect(rows.last?.event.outcome == .accepted)
        #expect(rows.allSatisfy { $0.evidenceClass == .live && $0.evidence.isEmpty && $0.judgements.isEmpty })
        let data = try JSONEncoder().encode(rows)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("stop-private") && !json.contains("deviceName") && !json.contains("ObjectIdentifier"))
        // A duplicate result and a new attempt from the stopped camera cannot
        // turn that historical origin into evidence of a currently live source.
        r.a.manualResultObserver?(command, .accepted)
        _ = r.a.dispatch(r.a.makeCommand(.stopSession))
        await r.log.flush()
        #expect(try records(r.log).count == 2)
        #expect(r.log.metrics.dropped == 3)
    }

    @Test func refusedStopUsesOnlyItsUnchangedAttemptWorld() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let before = r.a.revisions
        let command = OperatorCommand(target: .session, epoch: before.controlEpoch, expiry: -1, action: .stopSession)
        #expect(!r.a.dispatch(command).wasAccepted)
        await r.log.flush()
        let rows = try records(r.log)
        #expect(r.a.isRunning && r.a.revisions == before)
        #expect(rows.count == 2 && rows.last?.event.outcome == .refused && r.log.metrics.dropped == 0)
        #expect(rows.allSatisfy { $0.evidenceClass == .live && $0.event.actionID?.value == command.id })
    }

    @Test(arguments: ["targetIdentity", "peerIdentity", "generation", "epoch", "roles", "preferred", "actionID", "channel", "newAttempt", "detach", "restart"])
    func changedWorldCannotBorrowTheStopOrigin(_ change: String) async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let deliver = try #require(r.a.manualResultObserver)
        let peerDeliver = try #require(r.b.manualResultObserver)
        r.a.manualResultObserver = { command, result in
            switch change {
            case "targetIdentity": r.a.setSourceIdentityForTesting(self.source("replacement-target"))
            case "peerIdentity": r.b.setSourceIdentityForTesting(self.source("replacement-peer"))
            case "generation": r.a.stopCapture()
            case "epoch": r.a.cancelOperatorMotion()
            case "roles": r.show.setEditLive(true)
            case "preferred": r.a.preferredInputSource = .validationClip
            case "newAttempt": r.b.manualActionObserver?(.command(r.b.makeCommand(.cancelDetect)))
            case "detach": r.controller.detach()
            case "restart": r.controller.shadowRecorder?.restart()
            case "actionID":
                deliver(OperatorCommand(target: .session, epoch: command.epoch, expiry: command.expiry, action: .stopSession), result)
                return
            case "channel": peerDeliver(command, result); return
            default: break
            }
            deliver(command, result)
        }
        #expect(r.a.dispatch(r.a.makeCommand(.stopSession)) == .accepted)
        await r.log.flush()
        await r.controller.shadowRecorder?.log.flush()
        let rows = try records(r.log)
        #expect(!rows.contains { $0.event.action == .stopSession && $0.event.phase == .result })
        #expect(rows.filter { $0.event.action == .stopSession && $0.event.phase == .attempt }.count == 1)
        if change == "restart", let renewed = r.controller.shadowRecorder?.log {
            #expect(renewed.sessionID != r.log.sessionID)
            #expect(try records(renewed).isEmpty)
            #expect(renewed.metrics.dropped == 1)
        } else { #expect(r.log.metrics.dropped == (change == "newAttempt" ? 2 : 1)) }
    }

    @Test func failedAttemptCannotBorrowFreshlyBoundRunningSourcesForItsResult() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        r.a.setSourceIdentityForTesting(.unrecorded)
        let deliver = try #require(r.a.manualResultObserver)
        r.a.manualResultObserver = { command, result in
            r.a.setSourceIdentityForTesting(self.source("fresh-source"))
            r.a.setRunningForTesting(true)
            deliver(command, result)
        }
        #expect(r.a.dispatch(r.a.makeCommand(.stopSession)) == .accepted)
        await r.log.flush()
        #expect(try records(r.log).isEmpty)
        #expect(r.log.metrics.dropped == 2)
    }

    @Test func refusedResultAlsoRejectsIdentityChangeAndDuplicateDelivery() async throws {
        let r = try rig(); defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        let deliver = try #require(r.a.manualResultObserver)
        r.a.manualResultObserver = { command, result in
            r.a.setSourceIdentityForTesting(self.source("rebound-after-refusal"))
            deliver(command, result)
            deliver(command, result)
        }
        let command = OperatorCommand(target: .session, epoch: r.a.revisions.controlEpoch, expiry: -1, action: .stopSession)
        #expect(!r.a.dispatch(command).wasAccepted)
        await r.log.flush()
        #expect(try records(r.log).count == 1)
        #expect(r.log.metrics.dropped == 2)
    }
}
