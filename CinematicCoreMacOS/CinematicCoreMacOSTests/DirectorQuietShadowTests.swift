import Foundation
import Testing
@testable import Alfie

/// Stage 1 of the decision core: the shadow writes an abstention when its
/// reason changes, not on every tick. Operator actions are never deduplicated.
@MainActor struct DirectorQuietShadowTests {
    @MainActor private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    @MainActor private final class Clock { var now: TimeInterval = 100 }
    @MainActor private struct Rig {
        let root: URL
        let log: DirectorShadowLog
        let show: ShowCoordinator
        let controller: DirectorController
        let clock: Clock
    }

    private func rig() throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-shadow-\(UUID())")
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 8192,
            maximumQueuedBytes: 1_048_576, maximumFileBytes: 8_388_608, maximumStoreBytes: 16_777_216))
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        let clock = Clock()
        show.clock = { clock.now }
        show.addChannel(.b)
        // Cameras need a live source identity, or the recorder writes nothing.
        for id in ChannelID.allCases {
            guard let camera = show.channel(id) else { continue }
            camera.setRunningForTesting(true)
            camera.setSourceIdentityForTesting(.init(inputKind: "Live camera", deviceName: "quiet-shadow-device",
                deviceModelID: "quiet-shadow-model", belowShowRate: false))
        }
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
                                            shadowLog: log, log: { _ in })
        controller.attach()
        return .init(root: root, log: log, show: show, controller: controller, clock: clock)
    }

    private func records(_ log: DirectorShadowLog) throws -> [DirectorShadowRecord] {
        let url = log.directory.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
    }

    private func ticks(_ r: Rig, _ count: Int) {
        for _ in 0..<count {
            r.clock.now += DirectorController.tickInterval
            r.controller.tick()
        }
    }

    private func abstentions(_ rows: [DirectorShadowRecord]) -> [DirectorShadowRecord] {
        rows.filter { $0.event.kind == .abstention }
    }

    @Test func idleTicksWriteOneAbstention() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        ticks(r, 2400)
        await r.log.flush()
        let rows = try records(r.log)
        let quiet = abstentions(rows)
        #expect(rows.count == 1)
        #expect(quiet.count == 1)
        #expect(quiet.first?.event.stage == .cut)
        #expect(quiet.first?.event.reasons == [.init(domain: .observation, code: .cutPolicyUnavailable)])
        #expect(r.log.metrics.dropped == 0 && r.log.metrics.storageErrors == 0)
    }

    @Test func operatorActionIsFollowedByOneMoreAbstention() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        ticks(r, 1200)
        r.controller.setLevel(.manual)
        ticks(r, 1200)
        await r.log.flush()
        let rows = try records(r.log)
        let actions = rows.filter { $0.event.kind == .operatorAction }
        // The operator's own attempt and result are both written; never deduplicated.
        #expect(actions.count == 2)
        #expect(actions.allSatisfy { $0.event.action == .setLevel })
        #expect(abstentions(rows).count == 2)
        #expect(rows.map(\.event.kind) == [.abstention, .operatorAction, .operatorAction, .abstention])
        #expect(r.log.metrics.dropped == 0 && r.log.metrics.storageErrors == 0)
    }

    @Test func repeatedOperatorActionsAreNeverDeduplicated() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        for _ in 0..<3 { r.controller.setLevel(.manual) }
        ticks(r, 10)
        await r.log.flush()
        let rows = try records(r.log)
        #expect(rows.filter { $0.event.kind == .operatorAction }.count == 6)
        #expect(abstentions(rows).count == 1)
    }

    @Test func detachAndAttachWritesOneMore() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        ticks(r, 600)
        r.controller.detach()
        r.controller.attach()
        ticks(r, 600)
        await r.log.flush()
        let rows = try records(r.log)
        #expect(rows.count == 2)
        #expect(abstentions(rows).count == 2)
        #expect(r.log.metrics.dropped == 0 && r.log.metrics.storageErrors == 0)
    }

    @Test func aDroppedAbstentionIsTriedAgain() async throws {
        let r = try rig()
        defer { r.controller.detach(); try? FileManager.default.removeItem(at: r.root) }
        // A stopped camera has no source kind, so the recorder refuses the record.
        r.show.channel(.b)?.setRunningForTesting(false)
        ticks(r, 3)
        let refused = r.log.metrics.dropped
        #expect(refused == 3)
        r.show.channel(.b)?.setRunningForTesting(true)
        ticks(r, 100)
        await r.log.flush()
        #expect(abstentions(try records(r.log)).count == 1)
        #expect(r.log.metrics.dropped == refused)
    }
}
