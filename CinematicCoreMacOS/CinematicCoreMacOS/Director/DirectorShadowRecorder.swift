import Foundation

/// B-04 projection of facts the controller currently owns. It does not invent
/// proposals, parameter snapshots, face visibility or operator completion.
final class DirectorShadowRecorder {
    typealias R = DirectorShadowRecord
    private(set) var log: DirectorShadowLog
    private var sequence: UInt64 = 0
    private var exhausted = false
    #if DEBUG
    var provenanceForTesting: [R.EvidenceClass]?
    #endif
    init(log: DirectorShadowLog) { self.log = log }

    func restart() {
        do { log = try log.renewed(); sequence = 0; exhausted = false }
        catch { log.noteDropped() }
    }

    func emit(_ event: R.Event, show: ShowCoordinator, authority a: DirectorAuthority,
              policy: UInt64, nomination: UInt64, evidence: UInt64, preferences: DirectorPreferences?) {
        guard !exhausted else { log.noteDropped(); return }
        let number = sequence
        if sequence == .max { exhausted = true } else { sequence += 1 }
        let channels = ChannelID.allCases.compactMap { show.channel($0) }
        var provenance: [R.EvidenceClass] = channels.compactMap { camera in
            guard camera.isRunning, let source = camera.sourceIdentity else { return nil }
            switch camera.activeInputSource {
            case .liveCamera: return source.inputKind == "Live camera" ? .live : nil
            case .validationClip: return source.inputKind == "Validation clip" ? .recorded : nil
            }
        }
        #if DEBUG
        if let override = provenanceForTesting { provenance = override }
        #endif
        let now = show.clock()
        guard provenance.count == channels.count, let kind = provenance.first,
              provenance.allSatisfy({ $0 == kind }), now.isFinite, now >= 0 else {
            log.noteDropped(); return
        }
        func alias(_ id: ChannelID) -> String { "input-\((ChannelID.allCases.firstIndex(of: id) ?? 0) + 1)" }
        let level: R.Level
        switch a.level { case .off: level = .off; case .suggest: level = .suggest; case .assist: level = .assist; case .auto: level = .auto; case .backup: level = .backup }
        let context = R.Context(inputs: channels.map { alias($0.channelID) }, program: alias(show.programChannel),
            preview: show.previewChannel.map(alias), programShot: nil, programStartedAt: nil, lastWideAt: nil,
            level: level, paused: a.paused, editLive: a.editLive, running: a.running, healthy: a.healthy,
            evidenceAvailable: a.evidenceAvailable, mayPropose: a.mayPropose, mayPrepare: a.mayPrepare, mayTake: a.mayTake,
            pinnedInput: a.pinnedShot.map(alias), authorityEpoch: .init(a.epoch), routeGeneration: .init(show.router.routeGeneration),
            policyRevision: .init(policy), nominationRevision: .init(nomination), evidenceRevision: .init(evidence),
            segmentType: .liveEvent, segmentToken: nil)
        let validPreferences = preferences.flatMap { try? $0.validated() }
        let record = R(schemaVersion: R.currentSchemaVersion, recordID: .init(UUID()), sessionID: .init(log.sessionID),
            sequence: .init(number), recordedAtUTC: log.recordingUTC(), eventTime: now, evidenceClass: kind,
            executionMode: a.level == .off || a.level == .suggest ? .shadow : .observing, context: context,
            parameters: .init(status: preferences != nil && validPreferences == nil ? .invalid : .unavailable,
                parametersVersion: nil, preferencesVersion: validPreferences?.version, resolvedStyle: nil,
                readiness: nil, adapter: nil, judgeMaximumAge: nil, minimumProbability: nil),
            evidence: [], judgements: [], event: event, invalidFields: [], droppedRecordsBefore: .init(0))
        log.append(record, provenance: provenance)
    }

    static func action(_ action: R.OperatorAction, id: UUID = UUID(), outcome: R.ActionOutcome? = nil,
                       programAfter: String? = nil, previewAfter: String? = nil) -> R.Event {
        .init(kind: .operatorAction, decisionID: nil, target: nil, shot: nil, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: nil, reasons: nil,
            actionID: .init(id), action: action, phase: outcome == nil ? .attempt : .result, targetScope: .session,
            outcome: outcome, programAfter: programAfter, previewAfter: previewAfter)
    }
    static var noCutPolicy: R.Event {
        .init(kind: .abstention, decisionID: .init(UUID()), target: nil, shot: nil, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: .cut,
            reasons: [.init(domain: .observation, code: .cutPolicyUnavailable)], actionID: nil, action: nil,
            phase: nil, targetScope: nil, outcome: nil, programAfter: nil, previewAfter: nil)
    }
    static func command(_ command: OperatorCommand, outcome: R.ActionOutcome? = nil) -> R.Event {
        let action: R.OperatorAction
        var shot: R.Shot?
        switch command.action {
        case .detect: action = .detect
        case .cancelDetect: action = .cancelDetect
        case .selectSubject: action = .selectSubject
        case .unlock: action = .unlock
        case .resumeTracking: action = .resumeTracking
        case .setMode: action = .setMode
        case .selectPreset(let preset): action = .selectPreset; shot = .init(DirectorShot(preset: preset))
        case .beginZoom: action = .beginZoom
        case .endZoom: action = .endZoom
        case .moveManualCenter: action = .moveManualCenter
        case .returnToWide: action = .returnToWide
        case .startSession: action = .startSession
        case .stopSession: action = .stopSession
        }
        let target: String?
        switch command.target {
        case .channel(let id): target = "input-\((ChannelID.allCases.firstIndex(of: id) ?? 0) + 1)"
        case .session: target = nil
        }
        return .init(kind: .operatorAction, decisionID: nil, target: target, shot: shot, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: nil, reasons: nil,
            actionID: .init(command.id), action: action, phase: outcome == nil ? .attempt : .result,
            targetScope: target == nil ? .session : .channel, outcome: outcome, programAfter: nil, previewAfter: nil)
    }

}
