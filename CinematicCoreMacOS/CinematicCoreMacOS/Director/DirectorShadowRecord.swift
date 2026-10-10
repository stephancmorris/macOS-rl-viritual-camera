import Foundation

/// A-09 / D-02 schema 1. Passive metadata only; never restored as authority.
/// Construction must call validated(); encoding and decoding also validate.
/// B-04 owns bounded storage, 30-day expiry and explicit local export.
nonisolated struct DirectorShadowRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    enum ValidationError: Error, Equatable { case invalidRecord, mixedProvenance, unknownField }
    enum EvidenceClass: String, Codable, CaseIterable, Equatable, Sendable { case synthetic, recorded, live }
    enum ExecutionMode: String, Codable, CaseIterable, Equatable, Sendable { case shadow, observing }
    enum Level: String, Codable, CaseIterable, Equatable, Sendable { case off, suggest, assist, auto, backup }
    enum Format: String, Codable, CaseIterable, Equatable, Sendable { case stage, webcam }
    enum Preset: String, Codable, CaseIterable, Equatable, Sendable { case wide, fullBody, waistUp, tight }
    enum ParameterStatus: String, Codable, CaseIterable, Equatable, Sendable { case available, unavailable, invalid }
    enum LockPhase: String, Codable, CaseIterable, Equatable, Sendable { case inactive, acquiring, tracking, hold, wideWaiting }
    enum Identity: String, Codable, CaseIterable, Equatable, Sendable { case confirmed, acquiring, holding, lost, ambiguous, unavailable }
    enum IdentitySource: String, Codable, CaseIterable, Equatable, Sendable { case adapter, sampleClassifier }
    enum JudgeKind: String, Codable, CaseIterable, Equatable, Sendable { case rules, recorded, learned }
    enum GateResult: String, Codable, CaseIterable, Equatable, Sendable { case notEvaluated, accepted, abstained, stale }
    enum OutcomeKind: String, Codable, CaseIterable, Equatable, Sendable { case ranked, abstain }
    enum EventKind: String, Codable, CaseIterable, Equatable, Sendable { case wouldPrepare, wouldCut, abstention, operatorAction }
    enum Stage: String, Codable, CaseIterable, Equatable, Sendable { case prepare, cut, judge, validation }
    enum ActionPhase: String, Codable, CaseIterable, Equatable, Sendable { case attempt, result }
    enum TargetScope: String, Codable, CaseIterable, Equatable, Sendable { case session, channel }
    enum ActionOutcome: String, Codable, CaseIterable, Equatable, Sendable { case accepted, completed, refused, unobserved }
    enum OperatorAction: String, Codable, CaseIterable, Equatable, Sendable { case take, detect, cancelDetect, selectSubject, unlock, resumeTracking, setMode, selectPreset, beginZoom, endZoom, moveManualCenter, returnToWide, startSession, stopSession, settingsChanged, formatChanged, editLive, setLevel, handToAlfie, takeOver, cancelNextCut, advanceSegment, overrideSubject, otherManualAction }
    enum ReadinessReason: String, Codable, CaseIterable, Equatable, Sendable { case compositionUnavailable, evidenceUnavailable, takeUnavailable, invalidParameters, invalidEvidence, identityUncertain, framingUnsettled, moving, cropMoving }
    enum ReasonDomain: String, Codable, CaseIterable, Equatable, Sendable { case proposalStale, policy, judge, readiness, selection, observation, authorityRefusal }
    enum ReasonCode: String, Codable, CaseIterable, Equatable, Sendable { case authorityRevoked, routeChanged, sourceRestarted, shotChangedByOperator, targetBecameProgram, sourceMissing, expired, requestReplaced, policyChanged, nominationChanged, evidenceUnavailable, invalidInput, minimumDuration, noEligibleCandidate, repetition, movement, noPreview, lowConfidence, notRecorded, nothingAllowed, invalidJudgement, compositionUnavailable, takeUnavailable, invalidParameters, invalidEvidence, identityUncertain, framingUnsettled, moving, cropMoving, advisoryWideReminder, advisoryMaximumDwell, subjectEvidence, unclassified, parametersUnavailable, parametersInvalid, judgementStale, cutPolicyUnavailable, notQualified, prerequisites, paused, exhausted }
    struct Context: Codable, Equatable, Sendable {
        let inputs: [String]
        let program: String
        let preview: String?
        let programShot: Shot?
        let programStartedAt: Double?
        let lastWideAt: Double?
        let level: Level
        let paused: Bool
        let editLive: Bool
        let running: Bool
        let healthy: Bool
        let evidenceAvailable: Bool
        let mayPropose: Bool
        let mayPrepare: Bool
        let mayTake: Bool
        let pinnedInput: String?
        let authorityEpoch: Counter
        let routeGeneration: Counter
        let policyRevision: Counter
        let nominationRevision: Counter
        let evidenceRevision: Counter
        let segmentType: SegmentType
        let segmentToken: Token?
        enum CodingKeys: String, CodingKey, CaseIterable { case inputs, program, preview, programShot, programStartedAt, lastWideAt, level, paused, editLive, running, healthy, evidenceAvailable, mayPropose, mayPrepare, mayTake, pinnedInput, authorityEpoch, routeGeneration, policyRevision, nominationRevision, evidenceRevision, segmentType, segmentToken }
    }
    struct Shot: Codable, Equatable, Sendable {
        let format: Format
        let preset: Preset
        enum CodingKeys: String, CodingKey, CaseIterable { case format, preset }
    }
    struct ParameterContext: Codable, Equatable, Sendable {
        let status: ParameterStatus
        let parametersVersion: Counter?
        let preferencesVersion: Int?
        let resolvedStyle: Style?
        let readiness: ReadinessParameters?
        let adapter: AdapterParameters?
        let judgeMaximumAge: Double?
        let minimumProbability: Double?
        enum CodingKeys: String, CodingKey, CaseIterable { case status, parametersVersion, preferencesVersion, resolvedStyle, readiness, adapter, judgeMaximumAge, minimumProbability }
    }
    struct Style: Codable, Equatable, Sendable {
        let minimumShotDuration: Double
        let preferredShotDuration: Double
        let softMaximumShotDuration: Double
        let wideCadence: Double
        let repetitionWindow: Double
        let maximumMovement: Double
        let settleTime: Double
        let onAirMoveRate: Double
        let cutOnMotionAllowed: Bool
        enum CodingKeys: String, CodingKey, CaseIterable { case minimumShotDuration, preferredShotDuration, softMaximumShotDuration, wideCadence, repetitionWindow, maximumMovement, settleTime, onAirMoveRate, cutOnMotionAllowed }
    }
    struct ReadinessParameters: Codable, Equatable, Sendable {
        let minimumSettledTime: Double
        let minimumCutSettledTime: Double
        let maximumMotion: Double
        let maximumCutMotion: Double
        let cutOnMotionAllowed: Bool
        enum CodingKeys: String, CodingKey, CaseIterable { case minimumSettledTime, minimumCutSettledTime, maximumMotion, maximumCutMotion, cutOnMotionAllowed }
    }
    struct AdapterParameters: Codable, Equatable, Sendable {
        let maximumObservationAge: Double
        let debounce: Double
        let stillSpeed: Double
        enum CodingKeys: String, CodingKey, CaseIterable { case maximumObservationAge, debounce, stillSpeed }
    }
    struct EvidenceSummary: Codable, Equatable, Sendable {
        let channel: String
        let sampledAt: Double?
        let lockPhase: LockPhase
        let trackingOwnsControl: Bool
        let galleryReady: Bool
        let hasLockedTarget: Bool
        let observationAge: Double?
        let subjectSpeed: Double?
        let holdingSteady: Bool
        let cropConverged: Bool
        let operatorGestureInProgress: Bool
        let observedPersonCount: Int?
        let identity: Identity
        let identitySource: IdentitySource
        let adapterEvidenceAvailable: Bool?
        let settledSince: Double?
        let framingSettledFor: Double?
        let prepareReadiness: ReadinessSummary?
        let cutReadiness: ReadinessSummary?
        let revisions: Revisions?
        enum CodingKeys: String, CodingKey, CaseIterable { case channel, sampledAt, lockPhase, trackingOwnsControl, galleryReady, hasLockedTarget, observationAge, subjectSpeed, holdingSteady, cropConverged, operatorGestureInProgress, observedPersonCount, identity, identitySource, adapterEvidenceAvailable, settledSince, framingSettledFor, prepareReadiness, cutReadiness, revisions }
    }
    struct ReadinessSummary: Codable, Equatable, Sendable {
        let isReady: Bool
        let reasons: [ReadinessReason]
        enum CodingKeys: String, CodingKey, CaseIterable { case isReady, reasons }
    }
    struct Revisions: Codable, Equatable, Sendable {
        let sourceGeneration: Counter
        let controlEpoch: Counter
        let shotRevision: Counter
        enum CodingKeys: String, CodingKey, CaseIterable { case sourceGeneration, controlEpoch, shotRevision }
    }
    struct CandidateSummary: Codable, Equatable, Sendable {
        let channel: String
        let shot: Shot
        let isWide: Bool
        let subjectConfidence: Double?
        let movement: Double?
        enum CodingKeys: String, CodingKey, CaseIterable { case channel, shot, isWide, subjectConfidence, movement }
    }
    struct RankedSummary: Codable, Equatable, Sendable {
        let candidate: CandidateSummary
        let probability: Double?
        let reason: Reason
        enum CodingKeys: String, CodingKey, CaseIterable { case candidate, probability, reason }
    }
    struct JudgementSummary: Codable, Equatable, Sendable {
        let judgeKind: JudgeKind
        let modelVersion: String?
        let evidenceRevision: Counter
        let computedAt: Double?
        let outcome: Outcome
        let gateResult: GateResult
        let gateReason: Reason?
        let acceptedRank: Int?
        enum CodingKeys: String, CodingKey, CaseIterable { case judgeKind, modelVersion, evidenceRevision, computedAt, outcome, gateResult, gateReason, acceptedRank }
    }
    struct Outcome: Codable, Equatable, Sendable {
        let kind: OutcomeKind
        let ranked: [RankedSummary]?
        let reason: Reason?
        enum CodingKeys: String, CodingKey, CaseIterable { case kind, ranked, reason }
    }
    struct Reason: Codable, Equatable, Sendable {
        let domain: ReasonDomain
        let code: ReasonCode
        enum CodingKeys: String, CodingKey, CaseIterable { case domain, code }
    }
    struct Event: Codable, Equatable, Sendable {
        let kind: EventKind
        let decisionID: Token?
        let target: String?
        let shot: Shot?
        let reason: Reason?
        let proposalID: Token?
        let requestID: Token?
        let proposalCreatedAt: Double?
        let judgementIndex: Int?
        let stage: Stage?
        let reasons: [Reason]?
        let actionID: Token?
        let action: OperatorAction?
        let phase: ActionPhase?
        let targetScope: TargetScope?
        let outcome: ActionOutcome?
        let programAfter: String?
        let previewAfter: String?
        enum CodingKeys: String, CodingKey, CaseIterable { case kind, decisionID, target, shot, reason, proposalID, requestID, proposalCreatedAt, judgementIndex, stage, reasons, actionID, action, phase, targetScope, outcome, programAfter, previewAfter }
    }
    let schemaVersion: Int
    let recordID: Token
    let sessionID: Token
    let sequence: Counter
    let recordedAtUTC: String
    let eventTime: Double
    let evidenceClass: EvidenceClass
    let executionMode: ExecutionMode
    let context: Context
    let parameters: ParameterContext
    let evidence: [EvidenceSummary]
    let judgements: [JudgementSummary]
    let event: Event
    let invalidFields: [String]
    let droppedRecordsBefore: Counter
    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, recordID, sessionID, sequence, recordedAtUTC, eventTime, evidenceClass, executionMode, context, parameters, evidence, judgements, event, invalidFields, droppedRecordsBefore }

    /// Caller verifies the provenance of every contributing sample/history/judge input.
    /// A mixture cannot be given a single evidence class in schema 1.
    func validated(provenance: [EvidenceClass]) throws -> Self {
        guard !provenance.isEmpty, provenance.allSatisfy({ $0 == evidenceClass }) else {
            throw ValidationError.mixedProvenance
        }
        return try validated()
    }

    func validated() throws -> Self {
        func require(_ valid: Bool) throws { if !valid { throw ValidationError.invalidRecord } }
        func scalar(_ value: Double?) -> Bool { value.map { $0.isFinite && $0 >= 0 } ?? true }
        func probability(_ value: Double?) -> Bool { scalar(value) && (value.map { $0 <= 1 } ?? true) }
        func alias(_ value: String) -> Bool { Self.matches(value, pattern: "input-[1-9][0-9]*") }
        func shot(_ value: Shot) -> Bool {
            value.format == .stage ? [.wide, .fullBody, .waistUp].contains(value.preset) :
                [.wide, .tight].contains(value.preset)
        }
        func known(_ value: String?) -> Bool { value.map { context.inputs.contains($0) } ?? true }
        func readiness(_ value: ReadinessSummary?) -> Bool {
            value.map { $0.isReady == $0.reasons.isEmpty } ?? true
        }
        try require(schemaVersion == Self.currentSchemaVersion && scalar(eventTime))
        try require(Self.validUTC(recordedAtUTC))
        try require(!context.inputs.isEmpty && Set(context.inputs).count == context.inputs.count &&
                    context.inputs.allSatisfy(alias) && context.inputs.contains(context.program))
        try require(known(context.preview) && context.preview != context.program && known(context.pinnedInput))
        try require(context.programShot.map(shot) ?? true)
        try require(scalar(context.programStartedAt) && scalar(context.lastWideAt))
        if let version = parameters.preferencesVersion { try require(version == DirectorPreferences.currentVersion) }
        try require(scalar(parameters.judgeMaximumAge) && probability(parameters.minimumProbability))
        if parameters.status == .available {
            try require(parameters.parametersVersion != nil && parameters.preferencesVersion != nil && parameters.resolvedStyle != nil)
        } else { try require(parameters.resolvedStyle == nil) }
        if let s = parameters.resolvedStyle {
            try require([s.minimumShotDuration, s.preferredShotDuration, s.softMaximumShotDuration,
                         s.wideCadence, s.repetitionWindow, s.maximumMovement, s.settleTime, s.onAirMoveRate].allSatisfy { scalar($0) })
            try require(s.minimumShotDuration <= s.preferredShotDuration && s.preferredShotDuration <= s.softMaximumShotDuration && s.wideCadence > 0 && s.onAirMoveRate > 0)
        }
        if let p = parameters.readiness {
            try require([p.minimumSettledTime, p.minimumCutSettledTime, p.maximumMotion, p.maximumCutMotion].allSatisfy { scalar($0) })
            try require(p.minimumCutSettledTime >= p.minimumSettledTime && p.maximumCutMotion <= p.maximumMotion)
        }
        if let p = parameters.adapter { try require([p.maximumObservationAge, p.debounce, p.stillSpeed].allSatisfy { scalar($0) }) }
        // Only these paths can be marked invalid, and only when the scalar was omitted.
        var optionalNumbers: [String: Bool] = [:]
        func register(_ path: String, _ absent: Bool) { optionalNumbers[path] = absent }
        register("context.programStartedAt", context.programStartedAt == nil)
        register("context.lastWideAt", context.lastWideAt == nil)
        register("parameters.judgeMaximumAge", parameters.judgeMaximumAge == nil)
        register("parameters.minimumProbability", parameters.minimumProbability == nil)
        register("event.proposalCreatedAt", event.proposalCreatedAt == nil)
        try require(Set(evidence.map(\.channel)).count == evidence.count)
        for (i, e) in evidence.enumerated() {
            try require(context.inputs.contains(e.channel))
            try require([e.sampledAt, e.observationAge, e.subjectSpeed, e.settledSince, e.framingSettledFor].allSatisfy(scalar))
            try require(e.observedPersonCount.map { $0 >= 0 } ?? true)
            try require(readiness(e.prepareReadiness) && readiness(e.cutReadiness))
            register("evidence[\(i)].sampledAt", e.sampledAt == nil)
            register("evidence[\(i)].observationAge", e.observationAge == nil)
            register("evidence[\(i)].subjectSpeed", e.subjectSpeed == nil)
            register("evidence[\(i)].settledSince", e.settledSince == nil)
            register("evidence[\(i)].framingSettledFor", e.framingSettledFor == nil)
            register("evidence[\(i)].observedPersonCount", e.observedPersonCount == nil)
        }
        for (i, j) in judgements.enumerated() {
            try require(scalar(j.computedAt))
            register("judgements[\(i)].computedAt", j.computedAt == nil)
            if let token = j.modelVersion { try require(Self.matches(token, pattern: "[A-Za-z0-9][A-Za-z0-9._-]*")) }
            try require(j.judgeKind != .learned || j.modelVersion != nil)
            switch j.outcome.kind {
            case .ranked:
                try require(j.outcome.ranked != nil && j.outcome.reason == nil)
                for (k, item) in (j.outcome.ranked ?? []).enumerated() {
                    let c = item.candidate
                    try require(context.inputs.contains(c.channel) && shot(c.shot) && probability(c.subjectConfidence) && scalar(c.movement) && probability(item.probability))
                    try require(j.judgeKind != .rules || item.probability == nil)
                    try require(item.reason.isValid)
                    register("judgements[\(i)].outcome.ranked[\(k)].candidate.subjectConfidence", c.subjectConfidence == nil)
                    register("judgements[\(i)].outcome.ranked[\(k)].candidate.movement", c.movement == nil)
                    register("judgements[\(i)].outcome.ranked[\(k)].probability", item.probability == nil)
                }
            case .abstain:
                try require(j.outcome.ranked == nil && j.outcome.reason?.isValid == true)
            }
            try require((j.gateResult == .abstained) == (j.gateReason != nil))
            try require(j.gateReason.map { $0.isValid } ?? true)
            if j.gateResult == .accepted {
                guard let rank = j.acceptedRank, let items = j.outcome.ranked else { throw ValidationError.invalidRecord }
                try require(items.indices.contains(rank))
            } else { try require(j.acceptedRank == nil) }
        }
        try require(invalidFields == Array(Set(invalidFields)).sorted() && invalidFields.allSatisfy { optionalNumbers[$0] == true })
        try require(known(event.target) && known(event.programAfter) && known(event.previewAfter))
        try require(event.shot.map(shot) ?? true)
        try require(event.reason.map { $0.isValid } ?? true)
        try require(event.reasons.map { $0.allSatisfy(\.isValid) } ?? true)
        if let index = event.judgementIndex { try require(judgements.indices.contains(index)) }
        try require(scalar(event.proposalCreatedAt))
        // Non-payload optionals must be absent even for programmatic construction.
        let present: Set<String> = Set([
            event.decisionID == nil ? nil : "decisionID", event.target == nil ? nil : "target",
            event.shot == nil ? nil : "shot", event.reason == nil ? nil : "reason",
            event.proposalID == nil ? nil : "proposalID", event.requestID == nil ? nil : "requestID",
            event.proposalCreatedAt == nil ? nil : "proposalCreatedAt", event.judgementIndex == nil ? nil : "judgementIndex",
            event.stage == nil ? nil : "stage", event.reasons == nil ? nil : "reasons",
            event.actionID == nil ? nil : "actionID", event.action == nil ? nil : "action",
            event.phase == nil ? nil : "phase", event.targetScope == nil ? nil : "targetScope",
            event.outcome == nil ? nil : "outcome", event.programAfter == nil ? nil : "programAfter",
            event.previewAfter == nil ? nil : "previewAfter"].compactMap { $0 })
        try require(present.isSubset(of: event.allowedKeys))
        switch event.kind {
        case .wouldPrepare, .wouldCut:
            try require(event.decisionID != nil && event.target != nil && event.target == context.preview && event.shot != nil && event.reason != nil)
        case .abstention:
            try require(event.decisionID != nil && event.stage != nil && event.reasons?.isEmpty == false)
        case .operatorAction:
            try require(event.actionID != nil && event.action != nil && event.phase != nil && event.targetScope != nil)
            try require((event.targetScope == .channel) == (event.target != nil))
            try require((event.action == .selectPreset) == (event.shot != nil))
            try require((event.phase == .result) == (event.outcome != nil))
            if event.phase == .attempt { try require(event.programAfter == nil && event.previewAfter == nil) }
            try require(event.programAfter == nil || event.programAfter != event.previewAfter)
            if event.action == .take && event.outcome == .completed { try require(event.programAfter != nil) }
            let sessionActions: Set<OperatorAction> = [.take, .startSession, .stopSession, .settingsChanged, .formatChanged, .editLive, .setLevel, .handToAlfie, .takeOver, .cancelNextCut, .advanceSegment]
            let channelActions: Set<OperatorAction> = [.detect, .cancelDetect, .selectSubject, .unlock, .resumeTracking, .setMode, .selectPreset, .beginZoom, .endZoom, .moveManualCenter, .returnToWide, .overrideSubject]
            if let action = event.action {
                try require(!sessionActions.contains(action) || event.targetScope == .session)
                try require(!channelActions.contains(action) || event.targetScope == .channel)
            }
        }
        return self
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }
    private static func validUTC(_ value: String) -> Bool {
        guard matches(value, pattern: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z") else { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"; f.isLenient = false
        guard let date = f.date(from: value) else { return false }
        return f.string(from: date) == value
    }
}

nonisolated extension DirectorShadowRecord {
    struct Counter: Codable, Equatable, Sendable {
        let value: UInt64
        init(_ value: UInt64) { self.value = value }
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer(), s = try c.decode(String.self)
            guard Self.valid(s), let value = UInt64(s) else { throw ValidationError.invalidRecord }
            self.value = value
        }
        private static func valid(_ s: String) -> Bool {
            s == "0" || (!s.isEmpty && s.first != "0" && s.utf8.allSatisfy { (48...57).contains($0) })
        }
        func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(String(value)) }
    }
    struct Token: Codable, Equatable, Sendable {
        let value: UUID
        init(_ value: UUID) { self.value = value }
        init(from decoder: any Decoder) throws {
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let id = UUID(uuidString: s), id.uuidString == s else { throw ValidationError.invalidRecord }
            value = id
        }
        func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value.uuidString) }
    }
    private struct AnyKey: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func rejectUnknownKeys(_ decoder: any Decoder, allowed: Set<String>) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard c.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw ValidationError.unknownField }
    }
}

nonisolated extension DirectorShadowRecord.Context {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputs = try c.decode([String].self, forKey: .inputs)
        program = try c.decode(String.self, forKey: .program)
        preview = try c.decodeIfPresent(String.self, forKey: .preview)
        programShot = try c.decodeIfPresent(DirectorShadowRecord.Shot.self, forKey: .programShot)
        programStartedAt = try c.decodeIfPresent(Double.self, forKey: .programStartedAt)
        lastWideAt = try c.decodeIfPresent(Double.self, forKey: .lastWideAt)
        level = try c.decode(DirectorShadowRecord.Level.self, forKey: .level)
        paused = try c.decode(Bool.self, forKey: .paused)
        editLive = try c.decode(Bool.self, forKey: .editLive)
        running = try c.decode(Bool.self, forKey: .running)
        healthy = try c.decode(Bool.self, forKey: .healthy)
        evidenceAvailable = try c.decode(Bool.self, forKey: .evidenceAvailable)
        mayPropose = try c.decode(Bool.self, forKey: .mayPropose)
        mayPrepare = try c.decode(Bool.self, forKey: .mayPrepare)
        mayTake = try c.decode(Bool.self, forKey: .mayTake)
        pinnedInput = try c.decodeIfPresent(String.self, forKey: .pinnedInput)
        authorityEpoch = try c.decode(DirectorShadowRecord.Counter.self, forKey: .authorityEpoch)
        routeGeneration = try c.decode(DirectorShadowRecord.Counter.self, forKey: .routeGeneration)
        policyRevision = try c.decode(DirectorShadowRecord.Counter.self, forKey: .policyRevision)
        nominationRevision = try c.decode(DirectorShadowRecord.Counter.self, forKey: .nominationRevision)
        evidenceRevision = try c.decode(DirectorShadowRecord.Counter.self, forKey: .evidenceRevision)
        segmentType = try c.decode(SegmentType.self, forKey: .segmentType)
        segmentToken = try c.decodeIfPresent(DirectorShadowRecord.Token.self, forKey: .segmentToken)
    }
}

nonisolated extension DirectorShadowRecord.Shot {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(DirectorShadowRecord.Format.self, forKey: .format)
        preset = try c.decode(DirectorShadowRecord.Preset.self, forKey: .preset)
    }
}

nonisolated extension DirectorShadowRecord.ParameterContext {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(DirectorShadowRecord.ParameterStatus.self, forKey: .status)
        parametersVersion = try c.decodeIfPresent(DirectorShadowRecord.Counter.self, forKey: .parametersVersion)
        preferencesVersion = try c.decodeIfPresent(Int.self, forKey: .preferencesVersion)
        resolvedStyle = try c.decodeIfPresent(DirectorShadowRecord.Style.self, forKey: .resolvedStyle)
        readiness = try c.decodeIfPresent(DirectorShadowRecord.ReadinessParameters.self, forKey: .readiness)
        adapter = try c.decodeIfPresent(DirectorShadowRecord.AdapterParameters.self, forKey: .adapter)
        judgeMaximumAge = try c.decodeIfPresent(Double.self, forKey: .judgeMaximumAge)
        minimumProbability = try c.decodeIfPresent(Double.self, forKey: .minimumProbability)
    }
}

nonisolated extension DirectorShadowRecord.Style {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minimumShotDuration = try c.decode(Double.self, forKey: .minimumShotDuration)
        preferredShotDuration = try c.decode(Double.self, forKey: .preferredShotDuration)
        softMaximumShotDuration = try c.decode(Double.self, forKey: .softMaximumShotDuration)
        wideCadence = try c.decode(Double.self, forKey: .wideCadence)
        repetitionWindow = try c.decode(Double.self, forKey: .repetitionWindow)
        maximumMovement = try c.decode(Double.self, forKey: .maximumMovement)
        settleTime = try c.decode(Double.self, forKey: .settleTime)
        onAirMoveRate = try c.decode(Double.self, forKey: .onAirMoveRate)
        cutOnMotionAllowed = try c.decode(Bool.self, forKey: .cutOnMotionAllowed)
    }
}

nonisolated extension DirectorShadowRecord.ReadinessParameters {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minimumSettledTime = try c.decode(Double.self, forKey: .minimumSettledTime)
        minimumCutSettledTime = try c.decode(Double.self, forKey: .minimumCutSettledTime)
        maximumMotion = try c.decode(Double.self, forKey: .maximumMotion)
        maximumCutMotion = try c.decode(Double.self, forKey: .maximumCutMotion)
        cutOnMotionAllowed = try c.decode(Bool.self, forKey: .cutOnMotionAllowed)
    }
}

nonisolated extension DirectorShadowRecord.AdapterParameters {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maximumObservationAge = try c.decode(Double.self, forKey: .maximumObservationAge)
        debounce = try c.decode(Double.self, forKey: .debounce)
        stillSpeed = try c.decode(Double.self, forKey: .stillSpeed)
    }
}

nonisolated extension DirectorShadowRecord.EvidenceSummary {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel = try c.decode(String.self, forKey: .channel)
        sampledAt = try c.decodeIfPresent(Double.self, forKey: .sampledAt)
        lockPhase = try c.decode(DirectorShadowRecord.LockPhase.self, forKey: .lockPhase)
        trackingOwnsControl = try c.decode(Bool.self, forKey: .trackingOwnsControl)
        galleryReady = try c.decode(Bool.self, forKey: .galleryReady)
        hasLockedTarget = try c.decode(Bool.self, forKey: .hasLockedTarget)
        observationAge = try c.decodeIfPresent(Double.self, forKey: .observationAge)
        subjectSpeed = try c.decodeIfPresent(Double.self, forKey: .subjectSpeed)
        holdingSteady = try c.decode(Bool.self, forKey: .holdingSteady)
        cropConverged = try c.decode(Bool.self, forKey: .cropConverged)
        operatorGestureInProgress = try c.decode(Bool.self, forKey: .operatorGestureInProgress)
        observedPersonCount = try c.decodeIfPresent(Int.self, forKey: .observedPersonCount)
        identity = try c.decode(DirectorShadowRecord.Identity.self, forKey: .identity)
        identitySource = try c.decode(DirectorShadowRecord.IdentitySource.self, forKey: .identitySource)
        adapterEvidenceAvailable = try c.decodeIfPresent(Bool.self, forKey: .adapterEvidenceAvailable)
        settledSince = try c.decodeIfPresent(Double.self, forKey: .settledSince)
        framingSettledFor = try c.decodeIfPresent(Double.self, forKey: .framingSettledFor)
        prepareReadiness = try c.decodeIfPresent(DirectorShadowRecord.ReadinessSummary.self, forKey: .prepareReadiness)
        cutReadiness = try c.decodeIfPresent(DirectorShadowRecord.ReadinessSummary.self, forKey: .cutReadiness)
        revisions = try c.decodeIfPresent(DirectorShadowRecord.Revisions.self, forKey: .revisions)
    }
}

nonisolated extension DirectorShadowRecord.ReadinessSummary {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isReady = try c.decode(Bool.self, forKey: .isReady)
        reasons = try c.decode([DirectorShadowRecord.ReadinessReason].self, forKey: .reasons)
    }
}

nonisolated extension DirectorShadowRecord.Revisions {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceGeneration = try c.decode(DirectorShadowRecord.Counter.self, forKey: .sourceGeneration)
        controlEpoch = try c.decode(DirectorShadowRecord.Counter.self, forKey: .controlEpoch)
        shotRevision = try c.decode(DirectorShadowRecord.Counter.self, forKey: .shotRevision)
    }
}

nonisolated extension DirectorShadowRecord.CandidateSummary {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel = try c.decode(String.self, forKey: .channel)
        shot = try c.decode(DirectorShadowRecord.Shot.self, forKey: .shot)
        isWide = try c.decode(Bool.self, forKey: .isWide)
        subjectConfidence = try c.decodeIfPresent(Double.self, forKey: .subjectConfidence)
        movement = try c.decodeIfPresent(Double.self, forKey: .movement)
    }
}

nonisolated extension DirectorShadowRecord.RankedSummary {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        candidate = try c.decode(DirectorShadowRecord.CandidateSummary.self, forKey: .candidate)
        probability = try c.decodeIfPresent(Double.self, forKey: .probability)
        reason = try c.decode(DirectorShadowRecord.Reason.self, forKey: .reason)
    }
}

nonisolated extension DirectorShadowRecord.JudgementSummary {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        judgeKind = try c.decode(DirectorShadowRecord.JudgeKind.self, forKey: .judgeKind)
        modelVersion = try c.decodeIfPresent(String.self, forKey: .modelVersion)
        evidenceRevision = try c.decode(DirectorShadowRecord.Counter.self, forKey: .evidenceRevision)
        computedAt = try c.decodeIfPresent(Double.self, forKey: .computedAt)
        outcome = try c.decode(DirectorShadowRecord.Outcome.self, forKey: .outcome)
        gateResult = try c.decode(DirectorShadowRecord.GateResult.self, forKey: .gateResult)
        gateReason = try c.decodeIfPresent(DirectorShadowRecord.Reason.self, forKey: .gateReason)
        acceptedRank = try c.decodeIfPresent(Int.self, forKey: .acceptedRank)
    }
}

nonisolated extension DirectorShadowRecord.Outcome {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(DirectorShadowRecord.OutcomeKind.self, forKey: .kind)
        ranked = try c.decodeIfPresent([DirectorShadowRecord.RankedSummary].self, forKey: .ranked)
        reason = try c.decodeIfPresent(DirectorShadowRecord.Reason.self, forKey: .reason)
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: kind == .ranked ? ["kind", "ranked"] : ["kind", "reason"])
    }
}

nonisolated extension DirectorShadowRecord.Reason {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domain = try c.decode(DirectorShadowRecord.ReasonDomain.self, forKey: .domain)
        code = try c.decode(DirectorShadowRecord.ReasonCode.self, forKey: .code)
    }
}

nonisolated extension DirectorShadowRecord.Event {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(DirectorShadowRecord.EventKind.self, forKey: .kind)
        decisionID = try c.decodeIfPresent(DirectorShadowRecord.Token.self, forKey: .decisionID)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        shot = try c.decodeIfPresent(DirectorShadowRecord.Shot.self, forKey: .shot)
        reason = try c.decodeIfPresent(DirectorShadowRecord.Reason.self, forKey: .reason)
        proposalID = try c.decodeIfPresent(DirectorShadowRecord.Token.self, forKey: .proposalID)
        requestID = try c.decodeIfPresent(DirectorShadowRecord.Token.self, forKey: .requestID)
        proposalCreatedAt = try c.decodeIfPresent(Double.self, forKey: .proposalCreatedAt)
        judgementIndex = try c.decodeIfPresent(Int.self, forKey: .judgementIndex)
        stage = try c.decodeIfPresent(DirectorShadowRecord.Stage.self, forKey: .stage)
        reasons = try c.decodeIfPresent([DirectorShadowRecord.Reason].self, forKey: .reasons)
        actionID = try c.decodeIfPresent(DirectorShadowRecord.Token.self, forKey: .actionID)
        action = try c.decodeIfPresent(DirectorShadowRecord.OperatorAction.self, forKey: .action)
        phase = try c.decodeIfPresent(DirectorShadowRecord.ActionPhase.self, forKey: .phase)
        targetScope = try c.decodeIfPresent(DirectorShadowRecord.TargetScope.self, forKey: .targetScope)
        outcome = try c.decodeIfPresent(DirectorShadowRecord.ActionOutcome.self, forKey: .outcome)
        programAfter = try c.decodeIfPresent(String.self, forKey: .programAfter)
        previewAfter = try c.decodeIfPresent(String.self, forKey: .previewAfter)
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: allowedKeys.union(["kind"]))
    }
}

nonisolated extension DirectorShadowRecord {
    init(from decoder: any Decoder) throws {
        try DirectorShadowRecord.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        recordID = try c.decode(DirectorShadowRecord.Token.self, forKey: .recordID)
        sessionID = try c.decode(DirectorShadowRecord.Token.self, forKey: .sessionID)
        sequence = try c.decode(DirectorShadowRecord.Counter.self, forKey: .sequence)
        recordedAtUTC = try c.decode(String.self, forKey: .recordedAtUTC)
        eventTime = try c.decode(Double.self, forKey: .eventTime)
        evidenceClass = try c.decode(DirectorShadowRecord.EvidenceClass.self, forKey: .evidenceClass)
        executionMode = try c.decode(DirectorShadowRecord.ExecutionMode.self, forKey: .executionMode)
        context = try c.decode(DirectorShadowRecord.Context.self, forKey: .context)
        parameters = try c.decode(DirectorShadowRecord.ParameterContext.self, forKey: .parameters)
        evidence = try c.decode([DirectorShadowRecord.EvidenceSummary].self, forKey: .evidence)
        judgements = try c.decode([DirectorShadowRecord.JudgementSummary].self, forKey: .judgements)
        event = try c.decode(DirectorShadowRecord.Event.self, forKey: .event)
        invalidFields = try c.decode([String].self, forKey: .invalidFields)
        droppedRecordsBefore = try c.decode(DirectorShadowRecord.Counter.self, forKey: .droppedRecordsBefore)
        _ = try validated()
    }
    func encode(to encoder: any Encoder) throws {
        _ = try validated()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(recordID, forKey: .recordID)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(sequence, forKey: .sequence)
        try c.encode(recordedAtUTC, forKey: .recordedAtUTC)
        try c.encode(eventTime, forKey: .eventTime)
        try c.encode(evidenceClass, forKey: .evidenceClass)
        try c.encode(executionMode, forKey: .executionMode)
        try c.encode(context, forKey: .context)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(evidence, forKey: .evidence)
        try c.encode(judgements, forKey: .judgements)
        try c.encode(event, forKey: .event)
        try c.encode(invalidFields, forKey: .invalidFields)
        try c.encode(droppedRecordsBefore, forKey: .droppedRecordsBefore)
    }
}

nonisolated extension DirectorShadowRecord.Event {
    var allowedKeys: Set<String> {
        switch kind {
        case .wouldPrepare: ["decisionID", "target", "shot", "reason", "proposalID", "requestID", "proposalCreatedAt", "judgementIndex"]
        case .wouldCut: ["decisionID", "target", "shot", "reason", "judgementIndex"]
        case .abstention: ["decisionID", "stage", "reasons", "target", "proposalID", "requestID", "judgementIndex"]
        case .operatorAction: ["actionID", "action", "phase", "targetScope", "target", "shot", "outcome", "reasons", "programAfter", "previewAfter"]
        }
    }
}
nonisolated extension DirectorShadowRecord.Reason {
    var isValid: Bool {
        let allowed: Set<DirectorShadowRecord.ReasonCode>
        switch domain {
        case .proposalStale: allowed = [.authorityRevoked, .routeChanged, .sourceRestarted, .shotChangedByOperator, .targetBecameProgram, .sourceMissing, .expired, .requestReplaced, .policyChanged, .nominationChanged, .evidenceUnavailable]
        case .policy: allowed = [.invalidInput, .minimumDuration, .noEligibleCandidate, .repetition, .movement, .noPreview]
        case .judge: allowed = [.lowConfidence, .notRecorded, .nothingAllowed, .invalidJudgement]
        case .readiness: allowed = [.compositionUnavailable, .evidenceUnavailable, .takeUnavailable, .invalidParameters, .invalidEvidence, .identityUncertain, .framingUnsettled, .moving, .cropMoving]
        case .selection: allowed = [.advisoryWideReminder, .advisoryMaximumDwell, .subjectEvidence, .unclassified]
        case .observation: allowed = [.parametersUnavailable, .parametersInvalid, .judgementStale, .cutPolicyUnavailable, .unclassified]
        case .authorityRefusal: allowed = [.notQualified, .prerequisites, .paused, .exhausted]
        }
        return allowed.contains(code)
    }
    static func selection(_ text: String) -> Self {
        switch text {
        case "advisory wide reminder": .init(domain: .selection, code: .advisoryWideReminder)
        case "advisory maximum dwell": .init(domain: .selection, code: .advisoryMaximumDwell)
        case "subject evidence": .init(domain: .selection, code: .subjectEvidence)
        default: .init(domain: .selection, code: .unclassified)
        }
    }
}

/// Typed projections intentionally exclude UUID identity, raw explanations and media.
nonisolated extension DirectorShadowRecord {
    struct Measurements: Sendable {
        private(set) var invalidFields: [String] = []
        mutating func nonnegative(_ value: Double?, path: String) -> Double? {
            guard let value else { return nil }
            guard value.isFinite, value >= 0 else { mark(path); return nil }
            return value
        }
        mutating func probability(_ value: Double?, path: String) -> Double? {
            guard let value else { return nil }
            guard value.isFinite, (0...1).contains(value) else { mark(path); return nil }
            return value
        }
        mutating func count(_ value: Int?, path: String) -> Int? {
            guard let value else { return nil }
            guard value >= 0 else { mark(path); return nil }
            return value
        }
        private mutating func mark(_ path: String) { invalidFields = Array(Set(invalidFields + [path])).sorted() }
    }
}
nonisolated extension DirectorShadowRecord.Shot {
    init(_ value: DirectorShot) {
        switch value.preset {
        case .stage(.wide): format = .stage; preset = .wide
        case .stage(.fullBody): format = .stage; preset = .fullBody
        case .stage(.waistUp): format = .stage; preset = .waistUp
        case .webcam(.wide): format = .webcam; preset = .wide
        case .webcam(.tight): format = .webcam; preset = .tight
        }
    }
}
nonisolated extension DirectorShadowRecord.Identity {
    init(_ value: IdentityEvidence) {
        switch value {
        case .confirmed: self = .confirmed
        case .acquiring: self = .acquiring
        case .holding: self = .holding
        case .lost: self = .lost
        case .ambiguous: self = .ambiguous
        case .unavailable: self = .unavailable
        }
    }
}
nonisolated extension DirectorShadowRecord.LockPhase {
    init(_ value: RecoveryState.Phase) {
        switch value {
        case .inactive: self = .inactive
        case .acquiring: self = .acquiring
        case .tracking: self = .tracking
        case .hold: self = .hold
        case .wideWaiting: self = .wideWaiting
        }
    }
}
nonisolated extension DirectorShadowRecord.Level {
    init(_ value: DirectorAuthority.Level) {
        switch value {
        case .off: self = .off
        case .suggest: self = .suggest
        case .assist: self = .assist
        case .auto: self = .auto
        case .backup: self = .backup
        }
    }
}
nonisolated extension DirectorShadowRecord.ReadinessReason {
    init(_ value: DirectorReadiness.Reason) {
        switch value {
        case .compositionUnavailable: self = .compositionUnavailable
        case .evidenceUnavailable: self = .evidenceUnavailable
        case .takeUnavailable: self = .takeUnavailable
        case .invalidParameters: self = .invalidParameters
        case .invalidEvidence: self = .invalidEvidence
        case .identityUncertain: self = .identityUncertain
        case .framingUnsettled: self = .framingUnsettled
        case .moving: self = .moving
        case .cropMoving: self = .cropMoving
        }
    }
}
nonisolated extension DirectorShadowRecord.Reason {
    init(_ value: DirectorProposalValidator.StaleReason) {
        domain = .proposalStale
        switch value {
        case .authorityRevoked: code = .authorityRevoked
        case .routeChanged: code = .routeChanged
        case .sourceRestarted: code = .sourceRestarted
        case .shotChangedByOperator: code = .shotChangedByOperator
        case .targetBecameProgram: code = .targetBecameProgram
        case .sourceMissing: code = .sourceMissing
        case .expired: code = .expired
        case .requestReplaced: code = .requestReplaced
        case .policyChanged: code = .policyChanged
        case .nominationChanged: code = .nominationChanged
        case .evidenceUnavailable: code = .evidenceUnavailable
        }
    }
}
nonisolated extension DirectorShadowRecord.Reason {
    init(_ value: DirectorShotPolicy.Abstention) {
        domain = .policy
        switch value {
        case .invalidInput: code = .invalidInput
        case .minimumDuration: code = .minimumDuration
        case .noEligibleCandidate: code = .noEligibleCandidate
        case .repetition: code = .repetition
        case .movement: code = .movement
        case .noPreview: code = .noPreview
        }
    }
}
nonisolated extension DirectorShadowRecord.Reason {
    init(_ value: DirectorAuthority.Refusal) {
        domain = .authorityRefusal
        switch value {
        case .notQualified: code = .notQualified
        case .prerequisites: code = .prerequisites
        case .paused: code = .paused
        case .exhausted: code = .exhausted
        }
    }
}
nonisolated extension DirectorShadowRecord.Reason {
    init(_ value: DirectorJudgement.Abstention) {
        switch value {
        case .policy(let reason): self.init(reason)
        case .lowConfidence: self.init(domain: .judge, code: .lowConfidence)
        case .notRecorded: self.init(domain: .judge, code: .notRecorded)
        case .nothingAllowed: self.init(domain: .judge, code: .nothingAllowed)
        case .invalidJudgement: self.init(domain: .judge, code: .invalidJudgement)
        }
    }
}
nonisolated extension DirectorShadowRecord.ReadinessSummary {
    init(_ value: DirectorReadiness) { isReady = value.isReady; reasons = value.reasons.map { .init($0) } }
}
nonisolated extension DirectorShadowRecord.Revisions {
    init(_ value: ChannelRevisions) {
        sourceGeneration = .init(value.sourceGeneration); controlEpoch = .init(value.controlEpoch); shotRevision = .init(value.shotRevision)
    }
}
nonisolated extension DirectorShadowRecord.CandidateSummary {
    init(_ value: DirectorShotPolicy.Candidate, alias: String, path: String,
         measurements: inout DirectorShadowRecord.Measurements) {
        channel = alias; shot = .init(value.shot); isWide = value.isWide
        subjectConfidence = measurements.probability(value.subjectConfidence, path: path + ".subjectConfidence")
        movement = measurements.nonnegative(value.movement, path: path + ".movement")
    }
}
nonisolated extension DirectorShadowRecord.EvidenceSummary {
    /// Identity and each evaluated bar are supplied independently by their actual owners.
    /// Invalid measurements are omitted and marked, not replaced with plausible values.
    init(_ sample: ChannelEvidenceSample, alias: String, path: String,
         identity: IdentityEvidence, identitySource: DirectorShadowRecord.IdentitySource,
         adapterEvidenceAvailable: Bool?, settledSince: Double?, framingSettledFor: Double?,
         prepareReadiness: DirectorReadiness?, cutReadiness: DirectorReadiness?, revisions: ChannelRevisions?,
         measurements: inout DirectorShadowRecord.Measurements) {
        channel = alias; self.identity = .init(identity); self.identitySource = identitySource
        sampledAt = measurements.nonnegative(sample.sampledAt, path: path + ".sampledAt")
        observationAge = measurements.nonnegative(sample.observationAge, path: path + ".observationAge")
        subjectSpeed = measurements.nonnegative(sample.subjectSpeed, path: path + ".subjectSpeed")
        observedPersonCount = measurements.count(sample.observedPersonCount, path: path + ".observedPersonCount")
        self.settledSince = measurements.nonnegative(settledSince, path: path + ".settledSince")
        self.framingSettledFor = measurements.nonnegative(framingSettledFor, path: path + ".framingSettledFor")
        lockPhase = .init(sample.lockPhase); trackingOwnsControl = sample.trackingOwnsControl
        galleryReady = sample.galleryReady; hasLockedTarget = sample.lockedTargetID != nil
        holdingSteady = sample.holdingSteady; cropConverged = sample.cropConverged
        operatorGestureInProgress = sample.operatorGestureInProgress
        self.adapterEvidenceAvailable = adapterEvidenceAvailable
        self.prepareReadiness = prepareReadiness.map { .init($0) }; self.cutReadiness = cutReadiness.map { .init($0) }
        self.revisions = revisions.map { .init($0) }
    }
}
nonisolated extension DirectorShadowRecord.Style {
    init(_ value: DirectorStyle) {
        minimumShotDuration = value.minimumShotDuration
        preferredShotDuration = value.preferredShotDuration
        softMaximumShotDuration = value.softMaximumShotDuration
        wideCadence = value.wideCadence
        repetitionWindow = value.repetitionWindow
        maximumMovement = value.maximumMovement
        settleTime = value.settleTime
        onAirMoveRate = value.onAirMoveRate
        cutOnMotionAllowed = value.cutOnMotionAllowed
    }
}
nonisolated extension DirectorShadowRecord.ReadinessParameters {
    init(_ value: DirectorReadiness.Parameters) {
        minimumSettledTime = value.minimumSettledTime
        minimumCutSettledTime = value.minimumCutSettledTime
        maximumMotion = value.maximumMotion
        maximumCutMotion = value.maximumCutMotion
        cutOnMotionAllowed = value.cutOnMotionAllowed
    }
}
nonisolated extension DirectorShadowRecord.AdapterParameters {
    init(_ value: DirectorEvidenceAdapter.Parameters) {
        maximumObservationAge = value.maximumObservationAge
        debounce = value.debounce
        stillSpeed = value.stillSpeed
    }
}
nonisolated extension DirectorShadowRecord.JudgementSummary {
    /// Preserve original rank, computedAt and evidence revision. A gate result is observed,
    /// never rerun by logging. An accepted item is indexed after the gate's filter.
    init(_ value: DirectorJudgement, kind: DirectorShadowRecord.JudgeKind, modelVersion: String?,
         aliases: [ChannelID: String], path: String, gate: DirectorJudgeGate.Result?,
         measurements: inout DirectorShadowRecord.Measurements) throws {
        judgeKind = kind; self.modelVersion = modelVersion; evidenceRevision = .init(value.evidenceRevision)
        computedAt = measurements.nonnegative(value.computedAt, path: path + ".computedAt")
        switch value.outcome {
        case .abstain(let reason): outcome = .init(kind: .abstain, ranked: nil, reason: .init(reason))
        case .ranked(let items):
            var ranked: [DirectorShadowRecord.RankedSummary] = []
            for (index, item) in items.enumerated() {
                guard let alias = aliases[item.candidate.channel] else { throw DirectorShadowRecord.ValidationError.invalidRecord }
                let itemPath = path + ".outcome.ranked[\(index)]"
                let candidate = DirectorShadowRecord.CandidateSummary(item.candidate, alias: alias,
                    path: itemPath + ".candidate", measurements: &measurements)
                ranked.append(.init(candidate: candidate,
                    probability: measurements.probability(item.probability, path: itemPath + ".probability"),
                    reason: .selection(item.reason)))
            }
            outcome = .init(kind: .ranked, ranked: ranked, reason: nil)
        }
        switch gate {
        case nil: gateResult = .notEvaluated; gateReason = nil; acceptedRank = nil
        case .stale: gateResult = .stale; gateReason = nil; acceptedRank = nil
        case .abstain(let reason): gateResult = .abstained; gateReason = .init(reason); acceptedRank = nil
        case .accepted(let item):
            guard case .ranked(let items) = value.outcome, let rank = items.firstIndex(of: item) else {
                throw DirectorShadowRecord.ValidationError.invalidRecord
            }
            gateResult = .accepted; gateReason = nil; acceptedRank = rank
        }
    }
}
