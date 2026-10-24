import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorRunSheetShadowTests {
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }

    @Test func logsActualSegmentWithFreshSessionTokensWithoutNamesOrPersistedIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("segment-shadow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let utc = try #require(DirectorShadowExportManifest.utcDate("2026-10-20T00:00:00.000Z"))
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 8192,
            maximumQueuedBytes: 65536, maximumFileBytes: 65536, maximumStoreBytes: 131072), utcClock: { utc })
        let first = RunSheet.Segment(type: .presenter, name: "PRIVATE-OPENING-NAME", positionHint: .lectern)
        let second = RunSheet.Segment(type: .panel, name: "PRIVATE-PANEL-NAME", positionHint: .right)
        let sheet = try RunSheet(segments: [first, second])
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { 100 }
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { 100 },
            shadowLog: log, runSheet: sheet, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic]
        controller.attach()
        controller.tick()
        controller.advanceSegment()
        controller.tick()
        await log.flush()
        let source = root.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl")
        let data = try Data(contentsOf: source)
        let rows = try data.split(separator: 10).map { try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0)) }
        #expect(rows.map(\.context.segmentType) == [.presenter, .presenter, .panel, .panel])
        let firstToken = try #require(rows[0].context.segmentToken?.value)
        let secondToken = try #require(rows[2].context.segmentToken?.value)
        #expect(firstToken != first.id && secondToken != second.id && firstToken != secondToken)
        #expect(rows[1].context.segmentToken?.value == firstToken)
        #expect(rows[3].context.segmentToken?.value == secondToken)
        #expect(rows[1].event.action == .advanceSegment && rows[1].event.phase == .attempt)
        #expect(rows[2].event.actionID == rows[1].event.actionID && rows[2].event.phase == .result)
        #expect(rows[2].event.outcome == .accepted)
        #expect(rows[2].context.policyRevision.value == rows[1].context.policyRevision.value + 1)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("PRIVATE-") && !text.contains(first.id.uuidString) && !text.contains(second.id.uuidString))
        #expect(controller.authority.level == .off)

        show.prepareForNewShow()
        controller.shadowRecorder?.provenanceForTesting = [.synthetic]
        controller.tick()
        let renewed = try #require(controller.shadowRecorder?.log)
        await renewed.flush()
        #expect(renewed.sessionID != log.sessionID)
        let renewedData = try Data(contentsOf: root.appendingPathComponent("director_shadow_\(renewed.sessionID.uuidString).jsonl"))
        let renewedRow = try JSONDecoder().decode(DirectorShadowRecord.self, from: Data(try #require(renewedData.split(separator: 10).first)))
        #expect(renewedRow.context.segmentType == .panel)
        #expect(renewedRow.context.segmentToken?.value != secondToken)
    }
}
