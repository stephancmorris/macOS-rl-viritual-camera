import Foundation
import Testing
@testable import Alfie

nonisolated struct DirectorShadowRecordTests {
    private typealias R = DirectorShadowRecord
    private static let token = "ABCD1234-1234-4234-8234-123456789ABC"
    private func fixture(kind: String = "wouldPrepare") -> [String: Any] {
        let reason: [String: Any] = ["domain": "selection", "code": "subjectEvidence"]
        let shot: [String: Any] = ["format": "stage", "preset": "waistUp"]
        let event: [String: Any]
        switch kind {
        case "wouldPrepare": event = ["kind": kind, "decisionID": Self.token, "target": "input-2", "shot": shot, "reason": reason, "proposalCreatedAt": 9.0]
        case "wouldCut": event = ["kind": kind, "decisionID": Self.token, "target": "input-2", "shot": shot, "reason": reason]
        case "abstention": event = ["kind": kind, "decisionID": Self.token, "stage": "cut", "reasons": [["domain": "observation", "code": "cutPolicyUnavailable"]]]
        default: event = ["kind": "operatorAction", "actionID": Self.token, "action": "take", "phase": "result", "targetScope": "session", "outcome": "completed", "programAfter": "input-2", "previewAfter": "input-1"]
        }
        return ["schemaVersion": 1, "recordID": Self.token, "sessionID": Self.token, "sequence": "18446744073709551615",
                "recordedAtUTC": "2026-10-10T04:00:00.123Z", "eventTime": 10.0, "evidenceClass": "synthetic", "executionMode": "shadow",
                "context": ["inputs": ["input-1", "input-2"], "program": "input-1", "preview": "input-2", "level": "assist", "paused": false, "editLive": false, "running": true, "healthy": true, "evidenceAvailable": true, "mayPropose": true, "mayPrepare": true, "mayTake": false, "authorityEpoch": "7", "routeGeneration": "8", "policyRevision": "9", "nominationRevision": "10", "evidenceRevision": "11", "segmentType": "liveEvent"],
                "parameters": ["status": "available", "parametersVersion": "37", "preferencesVersion": 2,
                    "resolvedStyle": ["minimumShotDuration": 1.0, "preferredShotDuration": 2.0, "softMaximumShotDuration": 3.0, "wideCadence": 4.0, "repetitionWindow": 5.0, "maximumMovement": 0.1, "settleTime": 6.0, "onAirMoveRate": 0.2, "cutOnMotionAllowed": false]],
                "evidence": [], "judgements": [], "event": event, "invalidFields": [], "droppedRecordsBefore": "0"]
    }
    private func decode(_ object: [String: Any]) throws -> R {
        try JSONDecoder().decode(R.self, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
    private func object(_ record: R) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    }
    @Test(arguments: ["wouldPrepare", "wouldCut", "abstention", "operatorAction"])
    func allEventKindsRoundTripWithoutActions(kind: String) throws {
        let record = try decode(fixture(kind: kind))
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(R.self, from: data) == record)
        #expect(record.sequence.value == UInt64.max && record.droppedRecordsBefore.value == 0)
        #expect(record.schemaVersion == 1 && record.parameters.preferencesVersion == 2)
        #expect(record.parameters.parametersVersion?.value == 37 && record.context.policyRevision.value == 9)
        #expect(record.evidenceClass == .synthetic && record.executionMode == .shadow)
        #expect(try object(record)["sequence"] as? String == "18446744073709551615")
    }

    @Test(arguments: ["schema", "envelopeKey", "contextKey", "styleKey", "eventKey", "nullWrongPayload", "unknownKind", "unknownLevel", "deprecatedLevel", "unknownReason", "wrongReasonDomain", "crossFormat", "malformedUUID", "lowercaseUUID", "numericCounter", "leadingZeroCounter", "counterOverflow", "negativeClock", "badUTC", "badCalendarDate", "badAlias", "duplicateInputs", "sameRoles", "notPreview", "missingPayload", "wrongPayload", "badMarker", "duplicateMarker", "markerForPresent", "invalidStyle", "unknownPreference", "missingVersion", "negativeProposalClock"])
    func malformedAndPrivacyBearingRecordsAreRejected(fault: String) throws {
        var o = fixture()
        var c = try #require(o["context"] as? [String: Any])
        var p = try #require(o["parameters"] as? [String: Any])
        var e = try #require(o["event"] as? [String: Any])
        var s = try #require(p["resolvedStyle"] as? [String: Any])
        switch fault {
        case "schema": o["schemaVersion"] = 2
        case "envelopeKey": o["frame"] = "pixels"
        case "contextKey": c["name"] = "person"
        case "styleKey": s["audio"] = true
        case "eventKey": e["path"] = "/Users/private"
        case "nullWrongPayload": e["actionID"] = NSNull()
        case "unknownKind": e["kind"] = "committedCut"
        case "unknownLevel": c["level"] = "qualified"
        case "deprecatedLevel": c["level"] = "autoDirect"
        case "unknownReason": e["reason"] = ["domain": "selection", "code": "personName"]
        case "wrongReasonDomain": e["reason"] = ["domain": "selection", "code": "expired"]
        case "crossFormat": e["shot"] = ["format": "webcam", "preset": "waistUp"]
        case "malformedUUID": o["recordID"] = "person"
        case "lowercaseUUID": o["recordID"] = Self.token.lowercased()
        case "numericCounter": o["sequence"] = 7
        case "leadingZeroCounter": o["sequence"] = "07"
        case "counterOverflow": o["sequence"] = "18446744073709551616"
        case "negativeClock": o["eventTime"] = -1.0
        case "badUTC": o["recordedAtUTC"] = "2026-10-10T04:00:00Z"
        case "badCalendarDate": o["recordedAtUTC"] = "2026-02-30T04:00:00.123Z"
        case "badAlias": c["inputs"] = ["input-01", "input-2"]
        case "duplicateInputs": c["inputs"] = ["input-1", "input-1", "input-2"]
        case "sameRoles": c["preview"] = "input-1"
        case "notPreview": e["target"] = "input-1"
        case "missingPayload": e.removeValue(forKey: "shot")
        case "wrongPayload": e["stage"] = "prepare"
        case "badMarker": o["invalidFields"] = ["context.name"]
        case "duplicateMarker": o["invalidFields"] = ["context.lastWideAt", "context.lastWideAt"]
        case "markerForPresent": o["invalidFields"] = ["event.proposalCreatedAt"]
        case "invalidStyle": s["onAirMoveRate"] = 0.0
        case "unknownPreference": p["preferencesVersion"] = 3
        case "missingVersion": p.removeValue(forKey: "parametersVersion")
        default: e["proposalCreatedAt"] = -1.0
        }
        p["resolvedStyle"] = s; o["context"] = c; o["parameters"] = p; o["event"] = e
        #expect(throws: (any Error).self) { try decode(o) }
    }

    @Test func missingZeroAndInvalidMeasurementsRemainDistinct() throws {
        var o = fixture()
        var c = try #require(o["context"] as? [String: Any])
        c["programStartedAt"] = 0.0; c["lastWideAt"] = NSNull(); o["context"] = c
        let missing = try decode(o)
        #expect(missing.context.programStartedAt == 0 && missing.context.lastWideAt == nil && missing.invalidFields.isEmpty)
        o["invalidFields"] = ["context.lastWideAt"]
        let invalid = try decode(o)
        #expect(invalid != missing && invalid.context.lastWideAt == nil)
        #expect(try JSONDecoder().decode(R.self, from: JSONEncoder().encode(invalid)) == invalid)
    }

    @Test(arguments: ["unavailable", "invalid"])
    func parameterAbsenceAndNoPreviewAllowOperatorAndAbstentionRecords(status: String) throws {
        var o = fixture(kind: "abstention")
        var c = try #require(o["context"] as? [String: Any]); c.removeValue(forKey: "preview"); o["context"] = c
        o["parameters"] = ["status": status]
        let r = try decode(o)
        #expect(r.context.preview == nil && r.parameters.resolvedStyle == nil && r.parameters.parametersVersion == nil)
        #expect(try JSONDecoder().decode(R.self, from: JSONEncoder().encode(r)) == r)
    }

    @Test(arguments: R.Level.allCases)
    private func actualLevelsRoundTrip(level: R.Level) throws {
        var o = fixture(); var c = try #require(o["context"] as? [String: Any]); c["level"] = level.rawValue; o["context"] = c
        #expect(try decode(o).context.level == level)
    }

    @Test(arguments: ["attempt", "accepted", "completed", "refused", "unobserved"])
    func takeAdmissionAndCompletionAreDistinct(state: String) throws {
        var o = fixture(kind: "operatorAction"), e = try #require(o["event"] as? [String: Any])
        if state == "attempt" {
            e["phase"] = "attempt"; e.removeValue(forKey: "outcome"); e.removeValue(forKey: "programAfter"); e.removeValue(forKey: "previewAfter")
        } else { e["outcome"] = state }
        o["event"] = e
        let r = try decode(o)
        #expect(r.event.phase == (state == "attempt" ? .attempt : .result))
        if state == "completed" {
            e.removeValue(forKey: "programAfter"); o["event"] = e
            #expect(throws: (any Error).self) { try decode(o) }
        }
    }

    @Test func mixedProvenanceIsRefusedAndFutureTimesRemainPassive() throws {
        var o = fixture(); var c = try #require(o["context"] as? [String: Any]); c["programStartedAt"] = 100.0; o["context"] = c
        let r = try decode(o)
        #expect(try r.validated(provenance: [.synthetic, .synthetic]) == r)
        #expect(throws: R.ValidationError.mixedProvenance) { try r.validated(provenance: [.synthetic, .live]) }
        #expect(throws: R.ValidationError.mixedProvenance) { try r.validated(provenance: []) }
        #expect(r.context.programStartedAt == 100 && r.eventTime == 10)
    }

    @Test func projectionScrubsInvalidNumbersIdentityTokensAndExplanationText() throws {
        let subjectID = UUID()
        let sample = ChannelEvidenceSample(channel: .b, sampledAt: .nan, lockPhase: .tracking,
            trackingOwnsControl: true, galleryReady: true, lockedTargetID: subjectID,
            observationAge: nil, subjectSpeed: .infinity, holdingSteady: true, cropConverged: false,
            operatorGestureInProgress: false, observedPersonCount: -1)
        var m = R.Measurements()
        let e = R.EvidenceSummary(sample, alias: "input-2", path: "evidence[0]", identity: .unavailable,
            identitySource: .adapter, adapterEvidenceAvailable: false, settledSince: nil, framingSettledFor: 0,
            prepareReadiness: .init(reasons: []), cutReadiness: .init(reasons: [.cropMoving]), revisions: nil, measurements: &m)
        #expect(e.hasLockedTarget && e.observationAge == nil && e.framingSettledFor == 0)
        #expect(e.prepareReadiness?.isReady == true && e.cutReadiness?.isReady == false)
        #expect(m.invalidFields == ["evidence[0].observedPersonCount", "evidence[0].sampledAt", "evidence[0].subjectSpeed"])
        var o = fixture(); o["evidence"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([e])); o["invalidFields"] = m.invalidFields
        let r = try decode(o), data = try JSONEncoder().encode(r), text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains(subjectID.uuidString) && !text.contains("lockedTargetID") && !text.contains("faceVisible"))
        let reason = R.Reason.selection("Person's name /Users/private/face.png audio pixels")
        #expect(reason == .init(domain: .selection, code: .unclassified))
        let reasonText = try #require(String(data: JSONEncoder().encode(reason), encoding: .utf8))
        #expect(!reasonText.contains("private") && !reasonText.contains("Person"))
    }

    @Test func everyCurrentEnumAndShotMapsWithoutInventedVocabulary() throws {
        let identities: [IdentityEvidence] = [.confirmed, .acquiring, .holding, .lost, .ambiguous, .unavailable]
        #expect(Set(identities.map { R.Identity($0).rawValue }) == Set(R.Identity.allCases.map(\.rawValue)))
        let phases: [RecoveryState.Phase] = [.inactive, .acquiring, .tracking, .hold, .wideWaiting]
        #expect(Set(phases.map { R.LockPhase($0).rawValue }) == Set(R.LockPhase.allCases.map(\.rawValue)))
        let shots: [DirectorShot] = [.init(preset: .stage(.wide)), .init(preset: .stage(.fullBody)), .init(preset: .stage(.waistUp)), .init(preset: .webcam(.wide)), .init(preset: .webcam(.tight))]
        for shot in shots {
            var o = fixture(), e = try #require(o["event"] as? [String: Any])
            e["shot"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(R.Shot(shot))); o["event"] = e
            #expect(try decode(o).event.shot == R.Shot(shot))
        }
        let stale: [DirectorProposalValidator.StaleReason] = [.authorityRevoked, .routeChanged, .sourceRestarted, .shotChangedByOperator, .targetBecameProgram, .sourceMissing, .expired, .requestReplaced, .policyChanged, .nominationChanged, .evidenceUnavailable]
        #expect(stale.map { R.Reason($0) }.allSatisfy { $0.isValid && $0.domain == .proposalStale })
        let policy: [DirectorShotPolicy.Abstention] = [.invalidInput, .minimumDuration, .noEligibleCandidate, .repetition, .movement, .noPreview]
        for p in policy { #expect(R.Reason(DirectorJudgement.Abstention.policy(p)) == R.Reason(p)) }
        let readiness: [DirectorReadiness.Reason] = [.compositionUnavailable, .evidenceUnavailable, .takeUnavailable, .invalidParameters, .invalidEvidence, .identityUncertain, .framingUnsettled, .moving, .cropMoving]
        #expect(Set(readiness.map { R.ReadinessReason($0).rawValue }) == Set(R.ReadinessReason.allCases.map(\.rawValue)))
    }

    @Test func judgeProjectionPreservesOriginalRankAgeProbabilityAndAdvisoryReason() throws {
        let a = DirectorJudgement.Ranked(candidate: .init(channel: .a, shot: .init(preset: .stage(.wide)), subjectConfidence: 1, movement: 0, isWide: false), probability: 0, reason: "private name")
        let b = DirectorJudgement.Ranked(candidate: .init(channel: .b, shot: .init(preset: .stage(.waistUp)), subjectConfidence: 0.8, movement: 0, isWide: true), probability: 1, reason: "subject evidence")
        var m = R.Measurements()
        let value = DirectorJudgement(outcome: .ranked([a, b]), evidenceRevision: UInt64.max, computedAt: 2)
        let j = try R.JudgementSummary(value, kind: .learned, modelVersion: "model-1", aliases: [.a: "input-1", .b: "input-2"], path: "judgements[0]", gate: .accepted(b), measurements: &m)
        #expect(j.acceptedRank == 1 && j.computedAt == 2 && j.evidenceRevision.value == UInt64.max)
        #expect(j.outcome.ranked?[0].candidate.isWide == false && j.outcome.ranked?[1].candidate.isWide == true)
        #expect(j.outcome.ranked?[0].probability == 0 && j.outcome.ranked?[1].probability == 1)
        #expect(j.outcome.ranked?[0].reason.code == .unclassified)
        var o = fixture(); o["judgements"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([j]))
        let r = try decode(o)
        #expect(try JSONDecoder().decode(R.self, from: JSONEncoder().encode(r)) == r)
        let rules = try R.JudgementSummary(.init(outcome: .ranked([.init(candidate: b.candidate, probability: nil, reason: "subject evidence")]), evidenceRevision: 3, computedAt: 4), kind: .rules, modelVersion: nil, aliases: [.b: "input-2"], path: "judgements[0]", gate: .stale, measurements: &m)
        #expect(rules.outcome.ranked?.first?.probability == nil && rules.gateResult == .stale && rules.computedAt == 4)
    }

    @Test(arguments: ["rank", "gateReason", "readiness", "evidenceKey", "outcomeKey", "candidateKey", "ruleProbability", "learnedVersion", "negativeMeasurement"])
    func nestedSemanticAndPrivacyFailuresAreRejected(fault: String) throws {
        var o = fixture()
        var j: [String: Any] = ["judgeKind": "learned", "modelVersion": "model-1", "evidenceRevision": "4", "computedAt": 1.0, "gateResult": "accepted", "acceptedRank": 0,
            "outcome": ["kind": "ranked", "ranked": [["candidate": ["channel": "input-2", "shot": ["format": "stage", "preset": "wide"], "isWide": true, "subjectConfidence": 0.9, "movement": 0.0], "probability": 1.0, "reason": ["domain": "selection", "code": "subjectEvidence"]]]]]
        var evidence: [String: Any] = ["channel": "input-2", "sampledAt": 1.0, "lockPhase": "tracking", "trackingOwnsControl": true, "galleryReady": true, "hasLockedTarget": true, "holdingSteady": true, "cropConverged": true, "operatorGestureInProgress": false, "identity": "confirmed", "identitySource": "adapter"]
        switch fault {
        case "rank": j["acceptedRank"] = 1
        case "gateReason": j["gateReason"] = ["domain": "judge", "code": "lowConfidence"]
        case "readiness": evidence["cutReadiness"] = ["isReady": true, "reasons": ["moving"]]
        case "evidenceKey": evidence["lockedTargetID"] = Self.token
        case "outcomeKey": j["outcome"] = ["kind": "ranked", "ranked": [], "reason": NSNull()]
        case "candidateKey": j["outcome"] = ["kind": "ranked", "ranked": [["candidate": ["channel": "input-2", "shot": ["format": "stage", "preset": "wide"], "isWide": true, "name": "person"], "reason": ["domain": "selection", "code": "unclassified"]]]]
        case "ruleProbability": j["judgeKind"] = "rules"
        case "learnedVersion": j["modelVersion"] = "/Users/private/model"
        default: evidence["subjectSpeed"] = -1.0
        }
        o["judgements"] = [j]; o["evidence"] = [evidence]
        #expect(throws: (any Error).self) { try decode(o) }
    }
    @Test func encodingRejectsInvalidProgrammaticRecordsAndParametersKeepTheirUnits() throws {
        let valid = try decode(fixture())
        let invalid = R(schemaVersion: valid.schemaVersion, recordID: valid.recordID,
            sessionID: valid.sessionID, sequence: valid.sequence, recordedAtUTC: valid.recordedAtUTC,
            eventTime: .nan, evidenceClass: valid.evidenceClass, executionMode: valid.executionMode,
            context: valid.context, parameters: valid.parameters, evidence: valid.evidence,
            judgements: valid.judgements, event: valid.event, invalidFields: valid.invalidFields,
            droppedRecordsBefore: valid.droppedRecordsBefore)
        #expect(throws: (any Error).self) { try JSONEncoder().encode(invalid) }
        let readiness = R.ReadinessParameters(DirectorReadiness.Parameters(minimumSettledTime: 1,
            maximumMotion: 0.2, cutOnMotionAllowed: true, minimumCutSettledTime: 2, maximumCutMotion: 0.1))
        let adapter = R.AdapterParameters(DirectorEvidenceAdapter.Parameters(maximumObservationAge: 3,
            debounce: 4, stillSpeed: 0.3))
        var o = fixture(), p = try #require(o["parameters"] as? [String: Any])
        p["readiness"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(readiness))
        p["adapter"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(adapter))
        p["minimumProbability"] = 0.0; p["judgeMaximumAge"] = 5.0; o["parameters"] = p
        let projected = try decode(o)
        #expect(projected.parameters.readiness == readiness && projected.parameters.adapter == adapter)
        #expect(projected.parameters.minimumProbability == 0 && projected.parameters.judgeMaximumAge == 5)
        p["readiness"] = ["minimumSettledTime": 2.0, "minimumCutSettledTime": 1.0,
            "maximumMotion": 0.2, "maximumCutMotion": 0.1, "cutOnMotionAllowed": false]; o["parameters"] = p
        #expect(throws: (any Error).self) { try decode(o) }
    }

}
