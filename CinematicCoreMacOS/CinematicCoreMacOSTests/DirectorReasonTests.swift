import CoreGraphics
import Foundation
import Testing
@testable import Alfie

/// Decision core, stage 4: every refusal, abstention and stale result has one
/// code and one sentence. The mappings are exhaustive switches, so the compiler
/// proves no case is unmapped; these tests prove each maps to a valid code with
/// its own sentence.
nonisolated struct DirectorReasonTests {
    private typealias R = DirectorShadowRecord
    private static let fallback = DirectorReason.words(for: .init(.speech, .preferredLength))

    // Every case of every source enum, listed by hand.
    private static let stale: [DirectorProposalValidator.StaleReason] = [.authorityRevoked, .routeChanged, .sourceRestarted,
        .shotChangedByOperator, .targetBecameProgram, .sourceMissing, .expired, .requestReplaced, .policyChanged,
        .nominationChanged, .evidenceUnavailable]
    private static let readiness: [DirectorReadiness.Reason] = [.compositionUnavailable, .evidenceUnavailable,
        .takeUnavailable, .invalidParameters, .invalidEvidence, .identityUncertain, .framingUnsettled, .moving, .cropMoving]
    private static let policy: [DirectorShotPolicy.Abstention] = [.invalidInput, .minimumDuration, .noEligibleCandidate,
        .repetition, .movement, .noPreview]
    private static let judgement: [DirectorJudgement.Abstention] = policy.map { .policy($0) } +
        [.lowConfidence, .notRecorded, .nothingAllowed, .invalidJudgement]
    private static let assist: [DirectorShotPolicy.AssistAbstention] = [.invalidInput, .noPreview, .previewIsSafeWide,
        .alreadyPrepared, .operatorAdjusting, .learningSubject, .recoveringSubject, .evidenceUnavailable,
        .notReady([]), .notReady(readiness), .movement, .judgementStale]
        + policy.map { .policy($0) } + judgement.map { .judge($0) }
    private static let cutAbstention: [CutPolicy.Abstention] = [.invalidInput, .authority, .minimumDwell, .notReady,
        .nothingBetter, .judge]
    private static let cutReason: [CutPolicy.Reason] = [.preferredLength, .programUncertain, .wideDue]
    private static let speech: [SpeechRejection] = [.noWakePrefix, .unrecognized, .subjectNotLocked, .lowConfidence,
        .duplicateUtterance, .cancelledByManualCommand, .targetUnavailable, .missingUtteranceStart, .invalidToken, .muted,
        .stopped, .sessionChanged, .roleChanged, .targetRebound, .sourceChanged, .expired, .cancelledByWide,
        .cancelledByTake, .cancelledByMute]
    private static let world: [WorldModel.Unknown] = [.notAssigned, .sourceMissing, .notObserved,
        .partialView(.init(x: 0.4, y: 0.2, width: 0.2, height: 0.5)), .stale(age: 2), .ambiguous([UUID(), UUID()])]

    private static var everyMapped: [DirectorReason] {
        stale.map(DirectorReason.init) + readiness.map(DirectorReason.init) + policy.map(DirectorReason.init)
            + judgement.map(DirectorReason.init) + assist.flatMap(DirectorReason.reasons)
            + cutAbstention.map(DirectorReason.init) + cutReason.map(DirectorReason.init)
            + speech.map(DirectorReason.init) + world.map(DirectorReason.init)
    }

    @Test func everyCaseMapsToAValidCodeAndASentence() {
        #expect(Self.stale.count == 11 && Self.readiness.count == 9 && Self.speech.count == 19 && Self.world.count == 6)
        for reason in Self.everyMapped {
            #expect(reason.record.isValid(in: R.currentSchemaVersion), "\(reason)")
            #expect(!reason.words.isEmpty && reason.words != Self.fallback, "\(reason)")
        }
        #expect(Self.assist.allSatisfy { !DirectorReason.reasons($0).isEmpty })
    }

    @Test func noTwoDifferentReasonsShareASentence() {
        let all = DirectorReason.all
        #expect(Set(all).count == all.count)
        #expect(Set(all.map(\.words)).count == all.count)
        #expect(all.allSatisfy { !$0.words.isEmpty && $0.words != Self.fallback })
        // Every mapped reason is one the record accepts.
        #expect(Set(Self.everyMapped).isSubset(of: Set(all)))
    }

    /// Different causes within a source never share a code. The same cause
    /// from two sources may (a cut's minimum dwell is the policy's minimum).
    @Test func differentCausesHaveDifferentCodes() {
        func distinct<T>(_ cases: [T], _ map: (T) -> DirectorReason) -> Bool { Set(cases.map(map)).count == cases.count }
        #expect(distinct(Self.stale, DirectorReason.init))
        #expect(distinct(Self.readiness, DirectorReason.init))
        #expect(distinct(Self.policy, DirectorReason.init))
        #expect(distinct(Self.judgement, DirectorReason.init))
        #expect(distinct(Self.cutAbstention, DirectorReason.init))
        #expect(distinct(Self.cutReason, DirectorReason.init))
        #expect(distinct(Self.speech, DirectorReason.init))
        #expect(distinct(Self.world, DirectorReason.init))
        #expect(DirectorReason(CutPolicy.Abstention.minimumDwell) == DirectorReason(DirectorShotPolicy.Abstention.minimumDuration))
        #expect(DirectorReason.reasons(.learningSubject) != DirectorReason.reasons(.recoveringSubject))
        #expect(DirectorReason.reasons(.notReady([.moving, .cropMoving])) == [.init(.readiness, .moving), .init(.readiness, .cropMoving)])
    }

    @Test func existingWordsAreReused() {
        #expect(Self.speech.filter { $0 != .cancelledByMute }.allSatisfy { DirectorReason($0).words == $0.message })
        #expect(DirectorReason(.policy, .repetition).words == "Holding off: that shot was just used.")
    }

    @Test func aWouldCutCarriesItsRealReason() {
        let event = DirectorShadowRecorder.cut(.abstain(.nothingBetter))
        #expect(event.reasons == [.init(domain: .policy, code: .noCutDue)])
        #expect(DirectorShadowRecorder.cut(.abstain(.judge)).reasons == [.init(domain: .judge, code: .judgeDeclined)])
        #expect(DirectorShadowRecorder.preparationAbstention(.learningSubject).reasons ==
            [.init(domain: .readiness, code: .learningSubject)])
    }

    // MARK: Schema

    private static let token = "ABCD1234-1234-4234-8234-123456789ABC"
    private func record(version: Int, reason: [String: String]) -> [String: Any] {
        ["schemaVersion": version, "recordID": Self.token, "sessionID": Self.token, "sequence": "1",
         "recordedAtUTC": "2026-11-16T04:00:00.123Z", "eventTime": 10.0, "evidenceClass": "synthetic", "executionMode": "shadow",
         "context": ["inputs": ["input-1", "input-2"], "program": "input-1", "preview": "input-2", "level": "off", "paused": false,
            "editLive": false, "running": true, "healthy": true, "evidenceAvailable": true, "mayPropose": false, "mayPrepare": false,
            "mayTake": false, "authorityEpoch": "1", "routeGeneration": "1", "policyRevision": "1", "nominationRevision": "1",
            "evidenceRevision": "1", "segmentType": "liveEvent"],
         "parameters": ["status": "available", "parametersVersion": "1", "preferencesVersion": 2,
            "resolvedStyle": ["minimumShotDuration": 1.0, "preferredShotDuration": 2.0, "softMaximumShotDuration": 3.0,
                "wideCadence": 4.0, "repetitionWindow": 5.0, "maximumMovement": 0.1, "settleTime": 6.0,
                "onAirMoveRate": 0.2, "cutOnMotionAllowed": false]],
         "evidence": [], "judgements": [],
         "event": ["kind": "wouldCut", "decisionID": Self.token, "target": "input-2",
            "shot": ["format": "stage", "preset": "waistUp"], "reason": reason],
         "invalidFields": [], "droppedRecordsBefore": "0"]
    }
    private func valid(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(R.self, from: data) else { return false }
        return (try? decoded.validated()) != nil
    }

    @Test func aVersion2FileStillValidates() {
        #expect(R.currentSchemaVersion == 4)
        let original = ["domain": "observation", "code": "unclassified"]
        #expect(valid(record(version: 2, reason: original)))
        #expect(valid(record(version: 1, reason: original)))
        #expect(valid(record(version: 3, reason: original)))
    }

    @Test func newCodesAreValidOnlyInSchema3() {
        for reason in [["domain": "selection", "code": "preferredLength"], ["domain": "selection", "code": "wideDue"]] {
            #expect(!valid(record(version: 1, reason: reason)))
            #expect(!valid(record(version: 2, reason: reason)))
            #expect(valid(record(version: 3, reason: reason)))
        }
        #expect(!valid(record(version: 3, reason: ["domain": "speech", "code": "preferredLength"])))
        #expect(!valid(record(version: 5, reason: ["domain": "selection", "code": "subjectEvidence"])))
    }
}
