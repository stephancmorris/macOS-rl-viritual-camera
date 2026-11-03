import Foundation

/// B-04 projection of facts the controller currently owns. Decisions remain
/// intents, never evidence of a camera effect or operator completion.
final class DirectorShadowRecorder {
    typealias R = DirectorShadowRecord
    nonisolated struct CaptureBinding: Sendable {
        /// Shared session namespace, including legacy comparison producers.
        /// Reuse requires the identical materialized group; changes require
        /// a greater version. Restarting the log resets this bounded binding.
        let parametersVersion: UInt64
        /// Every contributing input, including supplied history and confidence.
        let provenance: [R.EvidenceClass]
    }
    struct Parameters {
        let binding: CaptureBinding
        let style: DirectorStyle
        let readiness: DirectorReadiness.Parameters
        let adapter: DirectorEvidenceAdapter.Parameters
        let judgeMaximumAge: Double?
        let minimumProbability: Double?
    }
    struct Evaluation {
        let now: TimeInterval
        let parameters: Parameters
        let sample: ChannelEvidenceSample?
        let revisions: ChannelRevisions?
        let adapter: DirectorEvidenceAdapter?
        let readinessInputs: DirectorReadiness.Inputs?
        /// Only the actually evaluated bar; test authorization overrides are omitted.
        let prepareReadiness: DirectorReadiness?
        let cutReadiness: DirectorReadiness?
        let timeline: DirectorShotPolicy.Timeline?
        var cutJudgeObservation: CutPolicy.JudgeObservation? = nil
    }
    /// In-memory origin of one synchronous Stop attempt. It is never encoded
    /// and cannot be reused as evidence that a retired source is still running.
    struct StopActionCapture {
        struct Input {
            let channel: ChannelID
            let camera: UUID
            let source: DiagnosticsSessionIdentity.Source
            let active: CameraManager.InputSource
            let preferred: CameraManager.InputSource
            let revisions: ChannelRevisions
            let missing: Bool
            let kind: R.EvidenceClass
        }
        let session: UUID
        let resultSequence: UInt64
        let action: UUID
        let channel: ChannelID
        let commandEpoch: UInt64
        let inputs: [Input]
        let program: ChannelID
        let preview: ChannelID?
        let controlTarget: ChannelID
        let controlRevision: UInt64
        let route: UInt64
    }

    /// Separate from a per-camera command: every attached input retires and
    /// the show resets its roles. Source identities remain in memory only.
    struct ShowStopActionCapture {
        let session: UUID
        let resultSequence: UInt64
        let action: UUID
        let inputs: [StopActionCapture.Input]
        let program: ChannelID
        let controlRevision: UInt64
        let route: UInt64
    }

    private static func sourceKind(_ camera: CameraManager) -> R.EvidenceClass? {
        guard camera.isRunning, !camera.isStartingSession, let source = camera.sourceIdentity else { return nil }
        switch camera.activeInputSource {
        case .liveCamera: return source.inputKind == "Live camera" ? .live : nil
        case .validationClip: return source.inputKind == "Validation clip" ? .recorded : nil
        }
    }

    func captureStopAttempt(_ command: OperatorCommand, on channel: ChannelID,
                            show: ShowCoordinator) -> StopActionCapture? {
        guard command.origin == .operatorUI, command.target == .session,
              case .stopSession = command.action, !exhausted, sequence < .max else { return nil }
        #if DEBUG
        guard provenanceForTesting == nil else { return nil }
        #endif
        let channels = ChannelID.allCases.compactMap { show.channel($0) }
        let inputs = channels.compactMap { camera -> StopActionCapture.Input? in
            guard let kind = Self.sourceKind(camera), let source = camera.sourceIdentity,
                  !camera.isStartingSession else { return nil }
            return .init(channel: camera.channelID, camera: camera.lifetimeID, source: source,
                         active: camera.activeInputSource, preferred: camera.preferredInputSource,
                         revisions: camera.revisions, missing: camera.sourceMissing, kind: kind)
        }
        guard inputs.count == channels.count, let kind = inputs.first?.kind,
              inputs.allSatisfy({ $0.kind == kind }), inputs.contains(where: { $0.channel == channel }) else { return nil }
        return .init(session: log.sessionID, resultSequence: sequence + 1, action: command.id,
            channel: channel, commandEpoch: command.epoch, inputs: inputs, program: show.programChannel,
            preview: show.previewChannel, controlTarget: show.controlTarget,
            controlRevision: show.controlTargetRevision, route: show.router.routeGeneration)
    }

    func captureShowStopAttempt(_ action: ShowCoordinator.StopAction,
                                show: ShowCoordinator) -> ShowStopActionCapture? {
        guard action.origin == .operatorUI, !exhausted, sequence < .max else { return nil }
        #if DEBUG
        guard provenanceForTesting == nil else { return nil }
        #endif
        let channels = ChannelID.allCases.compactMap { show.channel($0) }
        let inputs = channels.compactMap { camera -> StopActionCapture.Input? in
            guard let kind = Self.sourceKind(camera), let source = camera.sourceIdentity,
                  !camera.isStartingSession else { return nil }
            return .init(channel: camera.channelID, camera: camera.lifetimeID, source: source,
                         active: camera.activeInputSource, preferred: camera.preferredInputSource,
                         revisions: camera.revisions, missing: camera.sourceMissing, kind: kind)
        }
        guard inputs.count == channels.count, let kind = inputs.first?.kind,
              inputs.allSatisfy({ $0.kind == kind }) else { return nil }
        return .init(session: log.sessionID, resultSequence: sequence + 1, action: action.id,
            inputs: inputs, program: show.programChannel, controlRevision: show.controlTargetRevision,
            route: show.router.routeGeneration)
    }

    private func showStopProvenance(_ capture: ShowStopActionCapture?, event: R.Event,
                                    show: ShowCoordinator, sequence: UInt64) -> [R.EvidenceClass]? {
        guard let capture, capture.session == log.sessionID, capture.resultSequence == sequence,
              capture.action == event.actionID?.value, event.targetScope == .session, event.target == nil,
              event.outcome == .accepted,
              capture.inputs.map(\.channel) == ChannelID.allCases.filter({ show.channel($0) != nil }) else { return nil }
        let route = capture.route.addingReportingOverflow(capture.program == .a ? 0 : 1)
        let control = capture.controlRevision.addingReportingOverflow(1)
        let preview = capture.inputs.first(where: { $0.channel != .a })?.channel
        guard !route.overflow, !control.overflow, show.programChannel == .a, !show.editLive,
              show.previewChannel == preview, show.controlTarget == (preview ?? .a),
              event.programAfter == Self.alias(.a), event.previewAfter == preview.map(Self.alias),
              show.router.routeGeneration == route.partialValue,
              show.controlTargetRevision == control.partialValue else { return nil }
        for input in capture.inputs {
            let generation = input.revisions.sourceGeneration.addingReportingOverflow(1)
            let epoch = input.revisions.controlEpoch.addingReportingOverflow(1)
            guard let camera = show.channel(input.channel), camera.lifetimeID == input.camera,
                  camera.sourceIdentity == input.source, camera.preferredInputSource == input.preferred,
                  !generation.overflow, !epoch.overflow, !camera.isRunning, !camera.isStartingSession,
                  !camera.sourceMissing, camera.activeInputSource == input.preferred,
                  camera.revisions == ChannelRevisions(sourceGeneration: generation.partialValue,
                      controlEpoch: epoch.partialValue, shotRevision: input.revisions.shotRevision) else { return nil }
        }
        return capture.inputs.map(\.kind)
    }

    private func stopProvenance(_ capture: StopActionCapture?, event: R.Event,
                                channel: ChannelID?, show: ShowCoordinator, sequence: UInt64) -> [R.EvidenceClass]? {
        guard let capture, capture.session == log.sessionID, capture.resultSequence == sequence,
              capture.action == event.actionID?.value, capture.channel == channel,
              event.targetScope == .session, event.target == nil,
              show.programChannel == capture.program, show.previewChannel == capture.preview,
              show.controlTarget == capture.controlTarget, show.controlTargetRevision == capture.controlRevision,
              show.router.routeGeneration == capture.route,
              capture.inputs.map(\.channel) == ChannelID.allCases.filter({ show.channel($0) != nil }),
              event.outcome == .accepted || event.outcome == .refused else { return nil }
        for input in capture.inputs {
            guard let camera = show.channel(input.channel), camera.lifetimeID == input.camera,
                  camera.sourceIdentity == input.source, camera.preferredInputSource == input.preferred,
                  !camera.isStartingSession else { return nil }
            if input.channel == capture.channel, event.outcome == .accepted {
                let generation = input.revisions.sourceGeneration.addingReportingOverflow(1)
                let epoch = input.revisions.controlEpoch.addingReportingOverflow(2)
                guard !generation.overflow, !epoch.overflow, capture.commandEpoch == input.revisions.controlEpoch,
                      !camera.isRunning, !camera.sourceMissing, camera.activeInputSource == input.preferred,
                      camera.revisions == ChannelRevisions(sourceGeneration: generation.partialValue,
                          controlEpoch: epoch.partialValue, shotRevision: input.revisions.shotRevision) else { return nil }
            } else {
                guard camera.isRunning, camera.sourceMissing == input.missing,
                      camera.activeInputSource == input.active, camera.revisions == input.revisions else { return nil }
            }
        }
        return capture.inputs.map(\.kind)
    }

    private(set) var log: DirectorShadowLog
    private var sequence: UInt64 = 0
    private var exhausted = false
    private let segmentAliases = DirectorSegmentAliases()
    private var latestParameters: R.ParameterContext?
    #if DEBUG
    var provenanceForTesting: [R.EvidenceClass]?
    #endif
    init(log: DirectorShadowLog) { self.log = log }

    func restart() {
        do { log = try log.renewed(); sequence = 0; exhausted = false; segmentAliases.renew(); latestParameters = nil }
        catch { log.noteDropped() }
    }

    @discardableResult func emit(_ event: R.Event, show: ShowCoordinator, authority a: DirectorAuthority,
              policy: UInt64, nomination: UInt64, evidence: UInt64, preferences: DirectorPreferences?, segment: RunSheet.Segment? = nil,
              judgeObservation: DirectorJudgeShadow.Observation? = nil, eventTime: TimeInterval? = nil,
              studyParameters: Parameters? = nil, evaluation: Evaluation? = nil,
              stopActionCapture: StopActionCapture? = nil, stopActionChannel: ChannelID? = nil,
              showStopActionCapture: ShowStopActionCapture? = nil) -> Bool {
        guard !exhausted else { log.noteDropped(); return false }
        let number = sequence
        if sequence == .max { exhausted = true } else { sequence += 1 }
        let channels = ChannelID.allCases.compactMap { show.channel($0) }
        var provenance = channels.compactMap { Self.sourceKind($0) }
        if event.action == .stopSession, event.phase == .result {
            let origin: [R.EvidenceClass]?
            if let showStopActionCapture {
                origin = showStopProvenance(showStopActionCapture, event: event, show: show, sequence: number)
            } else {
                origin = stopProvenance(stopActionCapture, event: event, channel: stopActionChannel,
                                        show: show, sequence: number)
            }
            guard let origin else { log.noteDropped(); return false }
            provenance = origin
        } else {
            #if DEBUG
            if let override = provenanceForTesting { provenance = override }
            #endif
        }
        let now = evaluation?.now ?? eventTime ?? show.clock()
        let supplied = evaluation?.parameters ?? studyParameters
        guard provenance.count == channels.count, let kind = provenance.first,
              provenance.allSatisfy({ $0 == kind }),
              judgeObservation.map({ !$0.provenance.isEmpty && $0.provenance.allSatisfy { $0 == kind } }) ?? true,
              supplied.map({ !$0.binding.provenance.isEmpty && $0.binding.provenance.allSatisfy { $0 == kind } }) ?? true,
              evaluation.map({ $0.sample.map { $0.sampledAt == now } ?? true }) ?? true,
              evaluation?.timeline.map({ $0.now == now }) ?? true,
              now.isFinite, now >= 0 else {
            log.noteDropped(); return false
        }
        func alias(_ id: ChannelID) -> String { "input-\((ChannelID.allCases.firstIndex(of: id) ?? 0) + 1)" }
        let level: R.Level
        switch a.level { case .off: level = .off; case .suggest: level = .suggest; case .assist: level = .assist; case .auto: level = .auto; case .backup: level = .backup }
        let segmentToken: R.Token?
        if let segment {
            segmentToken = .init(segmentAliases.token(for: segment.id))
        } else { segmentToken = nil }
        let context = R.Context(inputs: channels.map { alias($0.channelID) }, program: alias(show.programChannel),
            preview: show.previewChannel.map(alias), programShot: (evaluation?.timeline?.programShot ?? judgeObservation?.context.timeline.programShot ?? show.channel(show.programChannel)?.directorShot).map { .init($0) },
            programStartedAt: evaluation?.timeline?.programStartedAt ?? judgeObservation?.context.timeline.programStartedAt,
            lastWideAt: evaluation?.timeline?.lastWideAt ?? judgeObservation?.context.timeline.lastWideAt,
            level: level, paused: a.paused, editLive: a.editLive, running: a.running, healthy: a.healthy,
            evidenceAvailable: a.evidenceAvailable, mayPropose: a.mayPropose, mayPrepare: a.mayPrepare, mayTake: a.mayTake,
            pinnedInput: a.pinnedShot.map(alias), authorityEpoch: .init(a.epoch), routeGeneration: .init(show.router.routeGeneration),
            policyRevision: .init(policy), nominationRevision: .init(nomination), evidenceRevision: .init(evidence),
            segmentType: segment?.type ?? .liveEvent, segmentToken: segmentToken)
        let validPreferences = preferences.flatMap { try? $0.validated() }
        let parameters: R.ParameterContext
        if let supplied {
            guard let validPreferences, (try? supplied.style.validated()) != nil,
                  supplied.readiness.isValid, supplied.adapter.isValid,
                  judgeObservation.map({ supplied.style == $0.style && supplied.judgeMaximumAge == $0.maximumAge
                      && supplied.minimumProbability == $0.minimumProbability }) ?? true else { log.noteDropped(); return false }
            parameters = .init(status: .available, parametersVersion: .init(supplied.binding.parametersVersion),
                preferencesVersion: validPreferences.version, resolvedStyle: .init(supplied.style),
                readiness: .init(supplied.readiness), adapter: .init(supplied.adapter),
                judgeMaximumAge: supplied.judgeMaximumAge, minimumProbability: supplied.minimumProbability)
        } else {
            parameters = .init(status: judgeObservation != nil ? .available : (preferences != nil && validPreferences == nil ? .invalid : .unavailable),
                parametersVersion: judgeObservation.map { .init($0.parametersVersion) }, preferencesVersion: validPreferences?.version,
                resolvedStyle: judgeObservation.map { .init($0.style) }, readiness: nil, adapter: nil,
                judgeMaximumAge: judgeObservation?.maximumAge,
                minimumProbability: judgeObservation.flatMap { (0...1).contains($0.minimumProbability) && $0.minimumProbability.isFinite ? $0.minimumProbability : nil })
        }
        if parameters.status == .available, let version = parameters.parametersVersion?.value {
            if let latest = latestParameters, let previous = latest.parametersVersion?.value {
                guard version > previous || (version == previous && parameters == latest) else {
                    log.noteDropped(); return false
                }
            }
            latestParameters = parameters
        }
        var measurements = R.Measurements()
        var evidenceSummaries: [R.EvidenceSummary] = []
        if let evaluation, let sample = evaluation.sample {
            let state = evaluation.adapter?.state(for: sample.channel)
            evidenceSummaries.append(.init(sample, alias: alias(sample.channel), path: "evidence[0]",
                identity: evaluation.readinessInputs?.identity ?? state?.identity ?? .unavailable,
                identitySource: evaluation.readinessInputs != nil || state == nil ? .sampleClassifier : .adapter,
                adapterEvidenceAvailable: state?.evidenceAvailable, settledSince: state?.settledSince,
                framingSettledFor: evaluation.readinessInputs?.framingSettledFor,
                prepareReadiness: evaluation.prepareReadiness, cutReadiness: evaluation.cutReadiness,
                revisions: evaluation.revisions, measurements: &measurements))
        }
        var judgements: [R.JudgementSummary] = []
        var scorerInputs: [R.ScorerInput]?
        if let comparison = judgeObservation {
            let aliases = Dictionary(uniqueKeysWithValues: channels.map { ($0.channelID, alias($0.channelID)) })
            do {
                judgements.append(try .init(comparison.evaluation.rules, kind: .rules, modelVersion: nil,
                    aliases: aliases, path: "judgements[0]", gate: nil, measurements: &measurements))
                let learned = comparison.evaluation.source == .learned
                judgements.append(try .init(comparison.evaluation.judgement, kind: learned ? .learned : .rules,
                    modelVersion: learned ? comparison.evaluation.modelVersion : nil,
                    aliases: aliases, path: "judgements[1]", gate: nil, measurements: &measurements))
                if case .ranked(let ranked) = comparison.evaluation.rules.outcome, !ranked.isEmpty {
                    var inputs: [R.ScorerInput] = []
                    for (rank, item) in ranked.enumerated() {
                        guard let features = DirectorJudgeFeatures.extract(item.candidate, context: comparison.context) else {
                            log.noteDropped(); return false
                        }
                        inputs.append(.init(featureSchemaVersion: DirectorJudgeFeatures.schemaVersion,
                            judgementIndex: 0, candidateRank: rank, features: features.values.map(Double.init)))
                    }
                    scorerInputs = inputs
                }
            } catch { log.noteDropped(); return false }
        }
        // Only explicit identity from this exact invocation is attributable.
        // Missing/invalid model identity does not invent a rules/learned label.
        if judgeObservation == nil, let evaluation, let observed = evaluation.cutJudgeObservation,
           observed.context.now == now, observed.context.evidenceRevision == evidence,
           observed.context.preview == show.previewChannel,
           observed.context.parameters == DirectorShotPolicy.Parameters(evaluation.parameters.style),
           let identity = observed.attribution {
            let kind: R.JudgeKind
            let model: String?
            switch identity {
            case .rules: kind = .rules; model = nil
            case .recorded: kind = .recorded; model = nil
            case .learned(let version): kind = .learned; model = version
            }
            let validIdentity = model.map {
                LearnedJudge.validModelVersion($0)
            } ?? true
            if validIdentity {
                let aliases = Dictionary(uniqueKeysWithValues: channels.map { ($0.channelID, alias($0.channelID)) })
                do {
                    judgements.append(try .init(observed.judgement, kind: kind, modelVersion: model,
                        aliases: aliases, path: "judgements[0]", gate: observed.gate, measurements: &measurements))
                } catch { log.noteDropped(); return false }
            }
        }
        let capturedEvent: R.Event
        if evaluation?.cutJudgeObservation != nil, !judgements.isEmpty {
            capturedEvent = .init(kind: event.kind, decisionID: event.decisionID, target: event.target,
                shot: event.shot, reason: event.reason, proposalID: event.proposalID, requestID: event.requestID,
                proposalCreatedAt: event.proposalCreatedAt, judgementIndex: 0, stage: event.stage, reasons: event.reasons,
                actionID: event.actionID, action: event.action, phase: event.phase, targetScope: event.targetScope,
                outcome: event.outcome, programAfter: event.programAfter, previewAfter: event.previewAfter)
        } else { capturedEvent = event }
        let record = R(schemaVersion: R.currentSchemaVersion, recordID: .init(UUID()), sessionID: .init(log.sessionID),
            sequence: .init(number), recordedAtUTC: log.recordingUTC(), eventTime: now, evidenceClass: kind,
            executionMode: a.level == .off || a.level == .suggest ? .shadow : .observing, context: context,
            parameters: parameters, evidence: evidenceSummaries, judgements: judgements, event: capturedEvent,
            invalidFields: measurements.invalidFields, droppedRecordsBefore: .init(0), scorerInputs: scorerInputs)
        return log.append(record, provenance: provenance)
    }

    static func action(_ action: R.OperatorAction, id: UUID = UUID(), outcome: R.ActionOutcome? = nil,
                       programAfter: String? = nil, previewAfter: String? = nil) -> R.Event {
        .init(kind: .operatorAction, decisionID: nil, target: nil, shot: nil, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: nil, reasons: nil,
            actionID: .init(id), action: action, phase: outcome == nil ? .attempt : .result, targetScope: .session,
            outcome: outcome, programAfter: programAfter, previewAfter: previewAfter)
    }
    static var judgeComparison: R.Event {
        .init(kind: .abstention, decisionID: .init(UUID()), target: nil, shot: nil, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: .judge,
            reasons: [.init(domain: .observation, code: .unclassified)], actionID: nil, action: nil,
            phase: nil, targetScope: nil, outcome: nil, programAfter: nil, previewAfter: nil)
    }
    static var noCutPolicy: R.Event {
        .init(kind: .abstention, decisionID: .init(UUID()), target: nil, shot: nil, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: .cut,
            reasons: [.init(domain: .observation, code: .cutPolicyUnavailable)], actionID: nil, action: nil,
            phase: nil, targetScope: nil, outcome: nil, programAfter: nil, previewAfter: nil)
    }
    static func preparation(_ request: DirectorPreparation.Request) -> R.Event {
        .init(kind: .wouldPrepare, decisionID: .init(UUID()), target: alias(request.intent.target),
            shot: .init(request.intent.shot), reason: .init(domain: .selection, code: .subjectEvidence),
            proposalID: .init(request.intent.id), requestID: .init(request.id), proposalCreatedAt: request.intent.createdAt,
            judgementIndex: nil, stage: nil, reasons: nil, actionID: nil, action: nil, phase: nil,
            targetScope: nil, outcome: nil, programAfter: nil, previewAfter: nil)
    }
    static func cut(_ decision: CutPolicy.Decision) -> R.Event {
        if case .cut(let plan) = decision {
            // Schema 1/2 has no exact vocabulary for preferredLength,
            // programUncertain or wideDue. Preserve the decision without relabelling its reason.
            return .init(kind: .wouldCut, decisionID: .init(UUID()), target: alias(plan.preview),
                shot: .init(plan.candidate.shot), reason: .init(domain: .observation, code: .unclassified),
                proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: nil,
                reasons: nil, actionID: nil, action: nil, phase: nil, targetScope: nil, outcome: nil,
                programAfter: nil, previewAfter: nil)
        }
        let reason: R.Reason
        switch decision {
        case .abstain(.invalidInput): reason = .init(domain: .policy, code: .invalidInput)
        case .abstain(.minimumDwell): reason = .init(domain: .policy, code: .minimumDuration)
        default: reason = .init(domain: .observation, code: .unclassified)
        }
        return .init(kind: .abstention, decisionID: .init(UUID()), target: nil, shot: nil, reason: nil,
            proposalID: nil, requestID: nil, proposalCreatedAt: nil, judgementIndex: nil, stage: .cut,
            reasons: [reason], actionID: nil, action: nil, phase: nil, targetScope: nil, outcome: nil,
            programAfter: nil, previewAfter: nil)
    }
    private static func alias(_ id: ChannelID) -> String {
        "input-\((ChannelID.allCases.firstIndex(of: id) ?? 0) + 1)"
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
