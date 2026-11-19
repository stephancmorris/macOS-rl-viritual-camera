import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Decision core, stage 7: the second rule judge. People fit and segment fit
/// only remove options; the existing rules rank what is left. Synthetic
/// fixtures on this Mac; no figure here is a rig or service measurement.
@MainActor struct DirectorJudgeTwoTests {
    private typealias R = DirectorShadowRecord
    private static let parameters = DirectorJudgeTwo.Parameters(peopleFitSpan: 1.5, peopleMaximumAge: 0.5)

    private func people(_ positions: [CGFloat], subject: Int? = 1, width: CGFloat = 0.1,
                        coverage: WorldModel.Coverage = .fullFrame, at observedAt: TimeInterval? = 10) -> DirectorScene.People {
        .init(coverage: coverage, observedAt: observedAt, count: positions.count, positions: positions,
              subjectRank: subject, subjectWidth: subject == nil ? nil : width)
    }

    // MARK: People fit

    @Test func peopleFitAsksWhetherTheTightShotHoldsOnlyTheSubject() {
        let fit = { DirectorJudgeTwo.peopleFit($0, now: 10.2, parameters: Self.parameters) }
        #expect(fit(people([0.5], subject: 0)) == .clear)
        // Within 1.5 subject widths (0.15) of the subject: crowded.
        #expect(fit(people([0.4, 0.5, 0.6])) == .crowded)
        #expect(fit(people([0.2, 0.5, 0.8])) == .clear)
        // Unknown is never "clear": partial, old, missing, or no subject.
        #expect(fit(people([0.5], subject: 0, coverage: .region(.init(x: 0.4, y: 0, width: 0.2, height: 1)))) == .unknown)
        #expect(fit(people([0.5], subject: 0, coverage: .none)) == .unknown)
        #expect(fit(people([0.5], subject: 0, at: 9)) == .unknown)
        #expect(fit(people([0.5], subject: 0, at: nil)) == .unknown)
        #expect(fit(people([0.2, 0.8], subject: nil)) == .unknown)
        #expect(fit(nil) == .unknown)
        #expect(DirectorJudgeTwo.peopleFit(people([0.5], subject: 0), now: 10.2,
            parameters: .init(peopleFitSpan: .nan, peopleMaximumAge: 0.5)) == .unknown)
    }

    // MARK: The judge

    private func candidate(_ preset: ShotComposer.Config.ShotPreset) -> DirectorShotPolicy.Candidate {
        .init(channel: .b, shot: .init(preset: .stage(preset)), subjectConfidence: 1, movement: 0,
              isWide: preset == .wide)
    }
    private func context(_ candidates: [DirectorShotPolicy.Candidate]) -> DirectorJudgeContext {
        let timeline = DirectorShotPolicy.Timeline(programShot: .init(preset: .stage(.waistUp)), programStartedAt: 0,
            lastWideAt: 0, history: [], candidates: candidates, now: 30)
        return .init(timeline: timeline, preview: .b, parameters: .policyStudy, evidenceRevision: 1, now: 30)
    }
    private func ranked(_ judgement: DirectorJudgement) -> [DirectorShot] {
        if case .ranked(let items) = judgement.outcome { return items.map(\.candidate.shot) }
        return []
    }
    private func abstention(_ judgement: DirectorJudgement) -> DirectorJudgement.Abstention? {
        if case .abstain(let reason) = judgement.outcome { return reason }
        return nil
    }
    private var ladder: [DirectorShotPolicy.Candidate] { [candidate(.wide), candidate(.fullBody), candidate(.waistUp)] }

    /// The replay's "panel of three": the rules offer a tight shot of a
    /// subject with people beside them. The second judge offers the wide.
    @Test func thePanelOfThreeNoLongerGetsATightShot() {
        let rules = ranked(RuleJudge().judge(context(ladder)))
        #expect(rules.contains { !$0.isWide })
        let two = DirectorJudgeTwo(fits: [.b: .crowded], segment: .liveEvent).judge(context(ladder))
        #expect(ranked(two) == [.init(preset: .stage(.wide))])
        // The gate still checks it against what the rules allow.
        let allowed = DirectorShotPolicy.rank(context(ladder).timeline, preview: .b, parameters: .policyStudy)
        guard case .accepted = DirectorJudgeGate.accept(two, allowed: allowed, evidenceRevision: 1, now: 30,
                                                       maximumAge: 1) else { Issue.record("Gate refused the wide"); return }
        // Only tight shots on offer: it holds and says why.
        let tight = [candidate(.fullBody), candidate(.waistUp)]
        #expect(abstention(DirectorJudgeTwo(fits: [.b: .crowded], segment: .liveEvent).judge(context(tight))) == .peopleFit)
        #expect(abstention(DirectorJudgeTwo(fits: [.b: .unknown], segment: .liveEvent).judge(context(tight))) == .peopleUnknown)
        #expect(abstention(DirectorJudgeTwo(fits: [:], segment: .liveEvent).judge(context(tight))) == .peopleUnknown)
    }

    @Test func segmentFitNarrowsAndNeverAdds() {
        let clear: [ChannelID: DirectorJudgeTwo.Fit] = [.b: .clear]
        for segment in [SegmentType.panel, .performance] {
            #expect(ranked(DirectorJudgeTwo(fits: clear, segment: segment).judge(context(ladder))) == [.init(preset: .stage(.wide))])
            #expect(abstention(DirectorJudgeTwo(fits: clear, segment: segment)
                .judge(context([candidate(.waistUp)]))) == .segmentPrefersWide)
        }
        #expect(abstention(DirectorJudgeTwo(fits: clear, segment: .videoBreak).judge(context(ladder))) == .segmentHolds)
        // A clear view in a presenter or live-event segment changes nothing.
        for segment in [SegmentType.presenter, .liveEvent] {
            #expect(DirectorJudgeTwo(fits: clear, segment: segment).judge(context(ladder)) == RuleJudge().judge(context(ladder)))
        }
        // Nothing on offer stays the rules' own answer.
        #expect(DirectorJudgeTwo(fits: clear, segment: .liveEvent).judge(context([])) == RuleJudge().judge(context([])))
    }

    @Test func theReplaysPanelFixtureProposesNoTightShot() {
        let rules = DirectorReplay.run(DirectorReplayFixtures.panelOfThree, parameters: .policyStudy,
            maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .replayStudy)
        #expect(rules.wrongSubjectProposals == 1)
        let two = DirectorReplay.run(DirectorReplayFixtures.panelOfThree, parameters: .policyStudy,
            maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .replayStudy,
            sinkFactory: { SimulatedDirectorEffectSink(succeeds: $0) },
            judge: DirectorJudgeTwo(fits: [.b: .crowded], segment: .liveEvent))
        // The replay's only candidate is the tight shot, so the judge holds.
        #expect(two.wrongSubjectProposals == 0 && two.labelledSubjectProposals == 0)
        #expect(two.programChangesWithoutAuthority == 0)
    }

    @Test func theSceneGivesTheSubjectsRankNeverItsBox() {
        let subject = UUID()
        let camera = WorldModel.Camera(sourceGeneration: 1, role: .preview, isRunning: true, sourceMissing: false,
            lockPhase: .tracking, coverage: .fullFrame, observedAt: 10, people: [
            .init(track: UUID(), box: .init(x: 0.7, y: 0.2, width: 0.1, height: 0.5), confidence: 1, firstSeen: 9, lastSeen: 10, isLockSubject: false),
            .init(track: subject, box: .init(x: 0.45, y: 0.2, width: 0.12, height: 0.5), confidence: 1, firstSeen: 9, lastSeen: 10, isLockSubject: true),
            .init(track: UUID(), box: .init(x: 0.1, y: 0.2, width: 0.1, height: 0.5), confidence: 1, firstSeen: 9, lastSeen: 10, isLockSubject: false)],
            crop: .init(x: 0, y: 0, width: 1, height: 1), minimumCropHeight: 0)
        let people = try? #require(DirectorScene.People(camera))
        #expect(people?.subjectRank == 1 && people?.count == 3)
        #expect(abs((people?.subjectWidth ?? 0) - 0.12) < 1e-9)
        #expect(people?.positions == people?.positions.sorted())
    }

    // MARK: Reasons and schema 4

    @Test func theJudgesReasonsHaveCodesAndWordsInSchema4Only() {
        let reasons: [DirectorJudgement.Abstention] = [.peopleFit, .peopleUnknown, .segmentPrefersWide, .segmentHolds]
        let mapped = reasons.map(DirectorReason.init)
        #expect(Set(mapped).count == reasons.count && Set(mapped.map(\.words)).count == reasons.count)
        let fallback = DirectorReason.words(for: .init(.speech, .preferredLength))
        for reason in mapped {
            #expect(reason.record.isValid(in: 4) && !reason.record.isValid(in: 3), "\(reason)")
            #expect(reason.words != fallback && DirectorReason.all.contains(reason))
        }
    }

    private static let token = "ABCD1234-1234-4234-8234-123456789ABC"
    private func record(version: Int, evidence: [String: Any] = [:], parameters: [String: Any] = [:]) -> [String: Any] {
        var summary: [String: Any] = ["channel": "input-2", "lockPhase": "tracking", "trackingOwnsControl": true,
            "galleryReady": true, "hasLockedTarget": true, "holdingSteady": true, "cropConverged": true,
            "operatorGestureInProgress": false, "identity": "unavailable", "identitySource": "sampleClassifier"]
        summary.merge(evidence) { $1 }
        var context: [String: Any] = ["status": "available", "parametersVersion": "1", "preferencesVersion": 2,
            "resolvedStyle": ["minimumShotDuration": 1.0, "preferredShotDuration": 2.0, "softMaximumShotDuration": 3.0,
                "wideCadence": 4.0, "repetitionWindow": 5.0, "maximumMovement": 0.1, "settleTime": 6.0,
                "onAirMoveRate": 0.2, "cutOnMotionAllowed": false]]
        context.merge(parameters) { $1 }
        return ["schemaVersion": version, "recordID": Self.token, "sessionID": Self.token, "sequence": "1",
            "recordedAtUTC": "2026-11-18T04:00:00.123Z", "eventTime": 10.0, "evidenceClass": "synthetic",
            "executionMode": "shadow",
            "context": ["inputs": ["input-1", "input-2"], "program": "input-1", "preview": "input-2", "level": "off",
                "paused": false, "editLive": false, "running": true, "healthy": true, "evidenceAvailable": true,
                "mayPropose": false, "mayPrepare": false, "mayTake": false, "authorityEpoch": "1",
                "routeGeneration": "1", "policyRevision": "1", "nominationRevision": "1", "evidenceRevision": "1",
                "segmentType": "liveEvent"],
            "parameters": context, "evidence": [summary], "judgements": [],
            "event": ["kind": "wouldCut", "decisionID": Self.token, "target": "input-2",
                "shot": ["format": "stage", "preset": "wide"], "reason": ["domain": "selection", "code": "wideDue"]],
            "invalidFields": [], "droppedRecordsBefore": "0"]
    }
    private func valid(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(R.self, from: data) else { return false }
        return (try? decoded.validated()) != nil
    }

    @Test func peopleCountsAndARankAreValidOnlyInSchema4() {
        let people: [String: Any] = ["peopleCount": 3, "peopleCoverage": "fullFrame", "subjectRank": 1]
        let judge: [String: Any] = ["peopleFitSpan": 1.5, "peopleMaximumAge": 0.5]
        #expect(R.currentSchemaVersion == 4)
        #expect(valid(record(version: 4)))
        #expect(valid(record(version: 4, evidence: people, parameters: judge)))
        #expect(!valid(record(version: 3, evidence: people)))
        #expect(!valid(record(version: 3, parameters: judge)))
        #expect(valid(record(version: 3)))
        // A rank inside the count; coverage with the count; the judge's pair.
        #expect(!valid(record(version: 4, evidence: ["peopleCount": 2, "peopleCoverage": "region", "subjectRank": 2])))
        #expect(!valid(record(version: 4, evidence: ["subjectRank": 0])))
        #expect(!valid(record(version: 4, evidence: ["peopleCount": 1])))
        #expect(!valid(record(version: 4, parameters: ["peopleFitSpan": 1.5])))
        #expect(!valid(record(version: 4, parameters: ["peopleFitSpan": 0, "peopleMaximumAge": 0.5])))
        // Never a box.
        #expect(!valid(record(version: 4, evidence: people.merging(["subjectBox": [0.1, 0.2]]) { $1 })))
    }

    // MARK: The app path, with shadowV2

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
    @MainActor private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }

    /// The stage 3 fixture (Program wide on A, Preview waist-up on B, locked
    /// subjects), run with a named set, for ten seconds of ticks.
    private func shadowRecords(_ study: DirectorStudyParameters) async throws -> [R] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("judge-two-\(UUID())")
        let log = try DirectorShadowLog(directory: root, limits: .init(maximumRecordBytes: 16384,
            maximumQueuedBytes: 1_048_576, maximumFileBytes: 16_777_216, maximumStoreBytes: 33_554_432))
        let clock = Clock()
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: [Sink()]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "judge-two-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        for id in ChannelID.allCases {
            guard let camera = show.channel(id) else { continue }
            camera.setRunningForTesting(true)
            camera.shotComposer.lockTarget(UUID())
            camera.setOperationMode(.autoTracking)
            camera.directorPerceptionForTesting = .init(phase: .tracking, galleryReady: true, holdingSteady: true,
                                                        subjectSpeed: 0)
        }
        #expect(show.dispatch(show.makeCommand(.selectPreset(.stage(.waistUp)))).wasAccepted)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        let controller = DirectorController(show: show, ticker: Ticker(), clock: { clock.now },
                                            studyParameters: study, shadowLog: log, log: { _ in })
        controller.shadowRecorder?.provenanceForTesting = [.synthetic, .synthetic]
        controller.preferencesChanged(.init(styles: [.liveEvent: .init(minimumShotDuration: 2, preferredShotDuration: 6,
            softMaximumShotDuration: 30, wideCadence: 80, repetitionWindow: 5, maximumMovement: 0.2, settleTime: 0,
            onAirMoveRate: 0.2, cutOnMotionAllowed: false)]))
        controller.attach()
        while clock.now + DirectorController.tickInterval <= 110 + 1e-9 {
            clock.now += DirectorController.tickInterval
            for id in ChannelID.allCases {
                guard let camera = show.channel(id) else { continue }
                camera.recordObservationForTesting(capturedAt: clock.now, personCount: 1)
                camera.cropEngine?.jumpToTarget()
                camera.setLatestRenderedFrameForTesting(.init(channelID: id, revisions: camera.revisions,
                    sourceTimestamp: clock.now, processingStartedAt: clock.now, renderedAt: clock.now,
                    crop: .fullFrame, outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: pixels))
            }
            controller.tick()
        }
        await log.flush()
        let url = log.directory.appendingPathComponent("director_shadow_\(log.sessionID.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 10).map {
            let record = try JSONDecoder().decode(R.self, from: Data($0))
            _ = try record.validated()
            return record
        }
    }

    @Test func theSecondJudgeNamesItselfAndOffersNoTightShotItCannotCheck() async throws {
        let one = try await shadowRecords(.shadowV1)
        let two = try await shadowRecords(.shadowV2)
        #expect(!one.isEmpty && !two.isEmpty)
        #expect(one.allSatisfy { $0.parameters.peopleFitSpan == nil && $0.schemaVersion == 4 })
        let named = two.filter { $0.parameters.status == .available }
        #expect(!named.isEmpty && named.allSatisfy { $0.parameters.peopleFitSpan == 1.5 && $0.parameters.peopleMaximumAge == 0.5 })
        // A locked camera is watched in its subject's region only, so its view
        // is never whole: the second judge offers the wide and nothing tight.
        let prepared = two.filter { $0.event.kind == .wouldPrepare }.compactMap(\.event.shot)
        #expect(prepared.allSatisfy { $0.preset == .wide })
        #expect(!two.contains { $0.event.kind == .wouldCut && $0.event.shot?.preset != .wide })
        // Where a record evaluates Preview, it carries counts, never boxes.
        for record in two where !record.evidence.isEmpty {
            let e = record.evidence[0]
            #expect((e.peopleCount == nil) == (e.peopleCoverage == nil))
        }
    }

    @Test func theAppRunsTheFirstJudgeUnlessTheFlagIsOn() {
        #expect(DeveloperFlags.judgeTwo == false)
        #expect(DirectorStudyParameters.shadowV1.judgeTwo == nil)
        #expect(DirectorStudyParameters.shadowV2.judgeTwo == .init(peopleFitSpan: 1.5, peopleMaximumAge: 0.5))
        #expect(DirectorStudyParameters.shadowV2.adapter == DirectorStudyParameters.shadowV1.adapter)
    }
}
