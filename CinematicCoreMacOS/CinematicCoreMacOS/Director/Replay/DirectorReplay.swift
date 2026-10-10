import Foundation

/// Synthetic, labelled replay. No camera, router, timer, or UI dependency.
nonisolated struct DirectorReplay {
    struct Event: Sendable {
        enum Action: Sendable {
            case subject(channel: ChannelID, present: Bool, identity: IdentityEvidence,
                         intended: Bool, framingReady: Bool, movement: Double)
            case source(channel: ChannelID, missing: Bool)
            case render(channel: ChannelID)
            case shotChange(channel: ChannelID)
            case manualCommand, operatorTake, refusedOperatorTake, pause, resume, editLive(Bool), stop, fault(ChannelID)
            case directorAttempt(id: String, delay: TimeInterval, succeeds: Bool, acknowledgementDelay: TimeInterval = 0)
            case effect(id: String)
            case acknowledgement(id: String)
            case enable(DirectorAuthority.Level), restart, navigation, cosmeticEdit
            case evidenceGap(Bool), identityLoss(ChannelID), sourceRebind(ChannelID)
            case outputFault, admissionLoss, healthRestored, policyChange, nominationChange
        }
        let at: TimeInterval
        let action: Action
    }
    struct Fixture: Sendable {
        let name: String
        let duration: TimeInterval
        let events: [Event]
    }
    struct Report: Equatable, Sendable {
        enum Evidence: Sendable { case synthetic }
        let evidence: Evidence
        let cutsPerMinute: Double
        let minimumDurationViolations: Int
        let oscillations: Int
        let staleProposalsRejected: [DirectorProposalValidator.StaleReason: Int]
        let manualOverridesHonoured: Int
        /// nil is N/A: headless replay cannot measure UI override latency.
        let manualOverrideLatencies: [TimeInterval?]
        let proposalCount: Int
        let directorAttemptCount: Int
        let directorCuts: Int
        let operatorTakeAttempts: Int
        let operatorCuts: Int
        let duplicateCallbacks: Int
        let failedEffects: Int
        let rejectedAttempts: Int
        let preparationsCommitted: Int
        let acknowledgementsAccepted: Int
        let acknowledgementsRejected: Int
        let readyEvaluations: Int
        let staleEffectsCommitted: Int
        let unqualifiedRefusals: Int
        let finalLevel: DirectorAuthority.Level
        let finalPaused: Bool
        let clockAnomalies: Int
        let wrongSubjectAttempts: Int
        let labelledSubjectAttempts: Int
        let proposalsMadeWhilePaused: Int
        let programChangesWithoutAuthority: Int
        let wrongSubjectProposals: Int
        let labelledSubjectProposals: Int
    }
    struct Channel: Sendable {
        var present = false
        var identity = IdentityEvidence.unavailable
        var intended = false
        var framingReady = false
        var movement = 0.0
        var missing = false
        var lastRenderAt: TimeInterval?
        var lastEvidenceAt: TimeInterval?
        var revisions = ChannelRevisions(sourceGeneration: 0, controlEpoch: 0, shotRevision: 0)
    }

    static func run(_ fixture: Fixture, parameters: DirectorShotPolicy.Parameters,
                    maximumProposalAge: TimeInterval, maximumEvidenceAge: TimeInterval, readinessParameters: DirectorReadiness.Parameters) -> Report {
        run(fixture, parameters: parameters, maximumProposalAge: maximumProposalAge,
            maximumEvidenceAge: maximumEvidenceAge, readinessParameters: readinessParameters,
            sinkFactory: { SimulatedDirectorEffectSink(succeeds: $0) })
    }

    /// Injectable synthetic boundary for contract tests. The factory is called
    /// at effect time, after the current world has been sampled, never at enqueue.
    static func run(_ fixture: Fixture, parameters: DirectorShotPolicy.Parameters,
                    maximumProposalAge: TimeInterval, maximumEvidenceAge: TimeInterval,
                    readinessParameters: DirectorReadiness.Parameters,
                    sinkFactory: (Bool) -> any DirectorEffectSink) -> Report {
        // Invalid clocks are counted and skipped rather than crashing a replay.
        var authority = DirectorAuthority(reviewPolicy: .conservative)
        _ = authority.apply(.enable(.assist), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist]))
        var channels: [ChannelID: Channel] = [.a: Channel(), .b: Channel()]
        var program: ChannelID = .a
        var route: UInt64 = 0
        var policyRevision: UInt64 = 0, nominationRevision: UInt64 = 0
        var preparation = DirectorPreparation()
        var activeRequest: DirectorPreparation.Request?
        var acknowledgements: [(id: String, due: TimeInterval, receipt: DirectorPreparation.Receipt)] = []
        var preparationsCommitted = 0, acknowledgementsAccepted = 0, acknowledgementsRejected = 0
        var readyEvaluations = 0, unqualifiedRefusals = 0, staleEffectsCommitted = 0
        var programStartedAt = 0.0
        var lastWideAt = 0.0
        var previousProgram: ChannelID?
        var cuts = 0, violations = 0, oscillations = 0
        var stale: [DirectorProposalValidator.StaleReason: Int] = [:]
        var overrides = 0, pausedProposals = 0, unauthorized = 0
        var wrong = 0, labelled = 0
        var pending: DirectorProposal?
        var proposalID = 0
        var pendingID: Int?
        var rejectedProposalIDs: Set<Int> = []
        var seenAttemptIDs: Set<String> = []
        var completedAttemptIDs: Set<String> = []
        var effects: [(id: String, due: TimeInterval, proposal: DirectorProposal, proposalID: Int,
                       intended: Bool, succeeds: Bool, sequence: Int, request: DirectorPreparation.Request, acknowledgementDelay: TimeInterval)] = []
        var attempts = 0, takeAttempts = 0, operatorCuts = 0
        var duplicateCallbacks = 0, failedEffects = 0, rejectedAttempts = 0, clockAnomalies = 0
        var wrongAttempts = 0, labelledAttempts = 0
        let validClockConfiguration = fixture.duration.isFinite && fixture.duration > 0 &&
            maximumProposalAge.isFinite && maximumProposalAge >= 0 && maximumEvidenceAge.isFinite && maximumEvidenceAge >= 0
        if !validClockConfiguration { clockAnomalies += 1 }
        let shotA = DirectorShot(preset: .stage(.wide))
        let shotB = DirectorShot(preset: .stage(.waistUp))
        var history: [DirectorShotPolicy.History] = []
        func currentPrerequisites() -> DirectorAuthority.Prerequisites {
            .init(nominationsCurrent: true, previewAvailable: channels[program == .a ? .b : .a] != nil,
                  sourcesHealthy: channels.values.allSatisfy { !$0.missing },
                  outputHealthy: authority.healthy, admissionCurrent: authority.healthy,
                  qualifiedLevels: [.assist])
        }
        func recordStale(_ id: Int, _ reasons: [DirectorProposalValidator.StaleReason]) {
            guard rejectedProposalIDs.insert(id).inserted else { return }
            for reason in reasons { stale[reason, default: 0] += 1 }
        }
        func completeEffect(_ effect: (id: String, due: TimeInterval, proposal: DirectorProposal,
                                      proposalID: Int, intended: Bool, succeeds: Bool, sequence: Int, request: DirectorPreparation.Request, acknowledgementDelay: TimeInterval), at now: TimeInterval) {
            guard completedAttemptIDs.insert(effect.id).inserted else { duplicateCallbacks += 1; return }
            let target = effect.proposal.target
            let live = DirectorLiveState(authority: authority, program: program,
                preview: program == .a ? .b : .a, revisions: channels[target]?.revisions,
                routeGeneration: route, sourceMissing: channels[target]?.missing ?? true,
                policyRevision: policyRevision, nominationRevision: nominationRevision,
                evidenceAvailable: channels[target]?.present == true && authority.evidenceAvailable &&
                    channels[target]?.lastEvidenceAt.map { now >= $0 && now - $0 <= maximumEvidenceAge } == true &&
                    channels[target]?.movement.isFinite == true && (channels[target]?.movement ?? -1) >= 0 &&
                    channels[target]?.identity == .confirmed && readinessParameters.isValid)
            var sink = sinkFactory(effect.succeeds)
            switch sink.prepare(effect.request, preparation: &preparation, live: live, now: now) {
            case .rejected(let reasons):
                recordStale(effect.proposalID, reasons)
                rejectedAttempts += 1
            case .failed:
                failedEffects += 1
            case .committed(let receipt):
                // Audit raw pre-effect facts independently of the sink's
                // validator. A deliberately faulty sink cannot hide a stale
                // mutation behind its reported success.
                let audit = Self.audit(CommittedEffect(
                    proposal: effect.request.intent, requestIssuedAt: effect.request.issuedAt,
                    requestMaximumAge: effect.request.maximumAge, appliedAt: now,
                    program: program, preview: program == .a ? .b : .a, routeGeneration: route,
                    revisionsBefore: channels[target]?.revisions,
                    sourceMissing: channels[target]?.missing ?? true,
                    authorityEpoch: authority.epoch, authorityMayPrepare: authority.mayPrepare,
                    policyRevision: policyRevision, nominationRevision: nominationRevision))
                channels[target]?.revisions = receipt.postRevisions
                preparationsCommitted += 1
                if !audit.isEmpty { staleEffectsCommitted += 1 }
                acknowledgements.append((effect.id, now + effect.acknowledgementDelay, receipt))
            }
        }
        func completeAcknowledgement(_ ack: (id: String, due: TimeInterval, receipt: DirectorPreparation.Receipt)) {
            let target = ack.receipt.intent.target
            let live = DirectorLiveState(authority: authority, program: program,
                preview: program == .a ? .b : .a, revisions: channels[target]?.revisions,
                routeGeneration: route, sourceMissing: channels[target]?.missing ?? true,
                policyRevision: policyRevision, nominationRevision: nominationRevision,
                evidenceAvailable: channels[target]?.present == true)
            if preparation.acknowledge(ack.receipt, live: live) { acknowledgementsAccepted += 1 }
            else { acknowledgementsRejected += 1 }
        }
        func flushEffects(before time: TimeInterval, inclusive: Bool = false) {
            // Process effects and ACKs in clock order; an ACK cannot skip a later effect.
            while true {
                let effect = effects.filter { inclusive ? $0.due <= time : $0.due < time }
                    .sorted { $0.due == $1.due ? $0.sequence < $1.sequence : $0.due < $1.due }.first
                let ack = acknowledgements.filter { inclusive ? $0.due <= time : $0.due < time }
                    .sorted { $0.due < $1.due }.first
                if let ack, effect == nil || ack.due < effect!.due {
                    acknowledgements.removeAll { $0.id == ack.id }; completeAcknowledgement(ack)
                } else if let effect {
                    effects.removeAll { $0.id == effect.id }; completeEffect(effect, at: effect.due)
                } else { break }
            }
        }
        let valid = fixture.events.enumerated().filter { _, event in
            fixture.duration.isFinite && fixture.duration > 0 && event.at.isFinite &&
                event.at >= 0 && event.at <= fixture.duration
        }
        clockAnomalies += fixture.events.count - valid.count
        let ordered = valid.sorted {
            $0.element.at == $1.element.at ? $0.offset < $1.offset : $0.element.at < $1.element.at
        }
        for (position, indexed) in ordered.enumerated() {
            let event = indexed.element
            let now = event.at
            flushEffects(before: now)
            preparation.discardExpiredRequest(now: now)
            let priorEpoch = authority.epoch
            let priorProgram = program
            var operatorAuthorizedChange = false
            func live(for target: ChannelID) -> DirectorLiveState {
                DirectorLiveState(authority: authority, program: program,
                    preview: program == .a ? .b : .a, revisions: channels[target]?.revisions,
                    routeGeneration: route, sourceMissing: channels[target]?.missing ?? true,
                policyRevision: policyRevision, nominationRevision: nominationRevision,
                evidenceAvailable: channels[target]?.present == true && authority.evidenceAvailable &&
                    channels[target]?.lastEvidenceAt.map { now >= $0 && now - $0 <= maximumEvidenceAge } == true &&
                    channels[target]?.movement.isFinite == true && (channels[target]?.movement ?? -1) >= 0 &&
                    channels[target]?.identity == .confirmed && readinessParameters.isValid)
            }
            switch event.action {
            case .manualCommand:
                if pending != nil || !effects.isEmpty { overrides += 1 }
                _ = authority.apply(.manualCommand)
            case .operatorTake, .refusedOperatorTake:
                takeAttempts += 1
                if pending != nil || !effects.isEmpty { overrides += 1 }
                _ = authority.apply(.operatorTake)
                let target: ChannelID = program == .a ? .b : .a
                let refused: Bool
                if case .refusedOperatorTake = event.action { refused = true } else { refused = false }
                // Synthetic R2 technical gate, independent of Director settlement/motion.
                if !refused, channels[target]?.missing == false,
                   let renderAt = channels[target]?.lastRenderAt, now - renderAt <= maximumProposalAge {
                    if now - programStartedAt < parameters.minimumShotDuration { violations += 1 }
                    if previousProgram == target && now - programStartedAt < parameters.repetitionWindow { oscillations += 1 }
                    history.append(.init(shot: program == .a ? shotA : shotB, endedAt: now))
                    previousProgram = program; program = target; route &+= 1
                    operatorAuthorizedChange = true
                    programStartedAt = now; cuts += 1; operatorCuts += 1
                    if program == .a { lastWideAt = now }
                }
            case .pause: _ = authority.apply(.pause)
            case .resume: _ = authority.apply(.resume, prerequisites: currentPrerequisites())
            case .editLive(let enabled): _ = authority.apply(.editLive(enabled))
            case .stop: _ = authority.apply(.stopShow)
            case .fault(let id):
                channels[id, default: Channel()].missing = true
                channels[id, default: Channel()].revisions.sourceGeneration &+= 1
                _ = authority.apply(.sourceLoss(id))
            case .source(let id, let missing):
                channels[id, default: Channel()].missing = missing
                channels[id, default: Channel()].revisions.sourceGeneration &+= 1
                _ = authority.apply(missing ? .sourceLoss(id) : .sourceRebound(id))
            case .render(let id):
                channels[id, default: Channel()].lastRenderAt = now
            case .shotChange(let id):
                channels[id, default: Channel()].revisions.shotRevision &+= 1
            case .directorAttempt(let id, let delay, let succeeds, let acknowledgementDelay):
                guard seenAttemptIDs.insert(id).inserted else { rejectedAttempts += 1; break }
                attempts += 1
                guard delay.isFinite, delay >= 0, (now + delay).isFinite,
                      now + delay <= fixture.duration, let proposal = pending,
                      let idOfProposal = pendingID, let request = activeRequest,
                      acknowledgementDelay.isFinite, acknowledgementDelay >= 0,
                      (now + delay + acknowledgementDelay).isFinite else {
                    if !delay.isFinite || delay < 0 { clockAnomalies += 1 }
                    rejectedAttempts += 1; break
                }
                let result = preparation.validate(request, live: live(for: proposal.target), now: now)
                if case .stale(let reasons) = result {
                    recordStale(idOfProposal, reasons)
                    rejectedAttempts += 1; break
                }
                labelledAttempts += 1
                let intended = channels[proposal.target]?.intended ?? false
                if !intended { wrongAttempts += 1 }
                effects.append((id, now + delay, proposal, idOfProposal, intended, succeeds, indexed.offset, request, acknowledgementDelay))
            case .effect(let id):
                if let effect = effects.first(where: { $0.id == id }) {
                    effects.removeAll { $0.id == id }
                    if now >= effect.due { completeEffect(effect, at: now) }
                    else { clockAnomalies += 1; rejectedAttempts += 1 }
                } else { duplicateCallbacks += 1 }
            case .acknowledgement(let id):
                if let ack = acknowledgements.first(where: { $0.id == id }), now >= ack.due {
                    acknowledgements.removeAll { $0.id == id }; completeAcknowledgement(ack)
                } else { acknowledgementsRejected += 1 }
            case .enable(let level):
                let transition = authority.apply(.enable(level), prerequisites: currentPrerequisites())
                if transition.refusal == .notQualified { unqualifiedRefusals += 1 }
            case .restart: authority.apply(.restart)
            case .navigation: authority.apply(.navigation)
            case .cosmeticEdit: authority.apply(.cosmeticEdit)
            case .evidenceGap(let gap): authority.apply(.evidenceAvailable(!gap))
            case .identityLoss(let id): authority.apply(.identityLost(id))
            case .sourceRebind(let id):
                channels[id]?.revisions.sourceGeneration += 1; authority.apply(.sourceRebound(id))
            case .outputFault: authority.apply(.outputFault)
            case .admissionLoss: authority.apply(.admissionLost)
            case .healthRestored: authority.apply(.healthRestored)
            case .policyChange: policyRevision += 1; authority.apply(.policyChanged)
            case .nominationChange: nominationRevision += 1; authority.apply(.nominationChanged)
            case .subject(let id, let present, let identity, let intended, let ready, let movement):
                channels[id, default: Channel()].lastEvidenceAt = now
                channels[id, default: Channel()].present = present
                channels[id, default: Channel()].identity = identity
                channels[id, default: Channel()].intended = intended
                channels[id, default: Channel()].framingReady = ready
                channels[id, default: Channel()].movement = movement
            }
            if authority.epoch != priorEpoch {
                if let pendingID, let pending,
                   case .stale(let reasons) = DirectorProposalValidator.validate(pending,
                       against: live(for: pending.target), now: pending.createdAt, maximumAge: 0, action: .propose) {
                    recordStale(pendingID, reasons)
                }
                pending = nil; pendingID = nil; activeRequest = nil; preparation.retire()
            }
            if let proposal = pending, preparation.composition == nil, preparation.receipt == nil {
                let result = DirectorProposalValidator.validate(proposal, against: live(for: proposal.target),
                    now: proposal.createdAt, maximumAge: 0, action: .propose)
                if case .stale(let reasons) = result {
                    if let pendingID { recordStale(pendingID, reasons) }
                    pending = nil; pendingID = nil; activeRequest = nil; preparation.retire()
                }
            }
            if !authority.mayPropose { pending = nil; pendingID = nil; activeRequest = nil; preparation.retire() }
            let preview: ChannelID = program == .a ? .b : .a
            if validClockConfiguration, authority.mayPropose, pending == nil, let channel = channels[preview],
               live(for: preview).evidenceAvailable,
               let renderAt = channel.lastRenderAt, now - renderAt <= maximumProposalAge {
                let candidate = DirectorShotPolicy.Candidate(channel: preview,
                    shot: preview == .b ? shotB : shotA, subjectConfidence: channel.identity == .confirmed ? 1 : 0,
                    movement: channel.movement, isWide: preview == .a)
                let timeline = DirectorShotPolicy.Timeline(programShot: program == .a ? shotA : shotB,
                    programStartedAt: programStartedAt, lastWideAt: lastWideAt,
                    history: history, candidates: [candidate], now: now)
                if case .chosen(let choice, let reason) = DirectorShotPolicy.choosePreparation(timeline,
                    preview: preview, parameters: parameters) {
                    if let proposal = DirectorProposal(target: preview, preview: preview, shot: choice.shot,
                        reason: reason, authorityEpoch: authority.epoch,
                        revisions: channel.revisions, routeGeneration: route, createdAt: now, policyRevision: policyRevision, nominationRevision: nominationRevision) {
                        pending = proposal
                        activeRequest = preparation.propose(proposal, maximumAge: maximumProposalAge, now: now)
                        proposalID += 1; pendingID = proposalID
                        labelled += 1
                        if !channel.intended { wrong += 1 }
                    }
                }
            }
            let channel = channels[preview] ?? Channel()
            let evidence = DirectorReadiness.Inputs(take: TakeAvailability(program: program, preview: preview,
                standard: .p50, reason: channel.missing ? .sourceMissing : nil, takePending: false, editLive: authority.editLive),
                identity: channel.identity,
                framingSettledFor: channel.framingReady ? readinessParameters.minimumSettledTime : 0,
                motion: channel.movement, cropConverged: channel.framingReady)
            if preparation.refresh(live: live(for: preview), evidence: evidence, parameters: readinessParameters).isReady {
                readyEvaluations += 1
            }
            if authority.paused && pending != nil { pausedProposals += 1 }
            // The A-08 sink has no Take entry point; only an operator can change Program.
            if program != priorProgram && !operatorAuthorizedChange { unauthorized += 1 }
            let nextTime = position + 1 < ordered.count ? ordered[position + 1].element.at : fixture.duration
            if nextTime > now { flushEffects(before: nextTime) }
        }
        if fixture.duration.isFinite && fixture.duration > 0 {
            flushEffects(before: fixture.duration, inclusive: true)
        }
        return Report(evidence: .synthetic,
            cutsPerMinute: fixture.duration.isFinite && fixture.duration > 0 ? Double(cuts) * 60 / fixture.duration : 0,
            minimumDurationViolations: violations, oscillations: oscillations,
            staleProposalsRejected: stale, manualOverridesHonoured: overrides,
            manualOverrideLatencies: Array(repeating: nil, count: overrides),
            proposalCount: labelled, directorAttemptCount: attempts, directorCuts: 0,
            operatorTakeAttempts: takeAttempts, operatorCuts: operatorCuts,
            duplicateCallbacks: duplicateCallbacks, failedEffects: failedEffects,
            rejectedAttempts: rejectedAttempts, preparationsCommitted: preparationsCommitted,
            acknowledgementsAccepted: acknowledgementsAccepted, acknowledgementsRejected: acknowledgementsRejected,
            readyEvaluations: readyEvaluations, staleEffectsCommitted: staleEffectsCommitted, unqualifiedRefusals: unqualifiedRefusals,
            finalLevel: authority.level, finalPaused: authority.paused, clockAnomalies: clockAnomalies,
            wrongSubjectAttempts: wrongAttempts, labelledSubjectAttempts: labelledAttempts,
            proposalsMadeWhilePaused: pausedProposals,
            programChangesWithoutAuthority: unauthorized,
            wrongSubjectProposals: wrong, labelledSubjectProposals: labelled)
    }

    // MARK: Independent committed-effect audit

    /// The raw world at the moment a Director preparation mutates a channel,
    /// captured before the mutation. Judged by `audit`, which shares no code
    /// with `DirectorPreparation.validate`, so `staleEffectsCommitted` can
    /// catch a stale effect that a faulty validator let through.
    struct CommittedEffect: Equatable, Sendable {
        let proposal: DirectorProposal
        let requestIssuedAt: TimeInterval
        let requestMaximumAge: TimeInterval
        let appliedAt: TimeInterval
        let program: ChannelID
        let preview: ChannelID
        let routeGeneration: UInt64
        let revisionsBefore: ChannelRevisions?
        let sourceMissing: Bool
        let authorityEpoch: UInt64
        let authorityMayPrepare: Bool
        let policyRevision: UInt64
        let nominationRevision: UInt64
    }

    /// Every way the committed effect was stale; empty means it was valid.
    static func audit(_ effect: CommittedEffect) -> [DirectorProposalValidator.StaleReason] {
        let p = effect.proposal
        var reasons: [DirectorProposalValidator.StaleReason] = []
        if effect.authorityEpoch != p.authorityEpoch || !effect.authorityMayPrepare { reasons.append(.authorityRevoked) }
        if effect.routeGeneration != p.routeGeneration { reasons.append(.routeChanged) }
        if p.target == effect.program || p.target != effect.preview { reasons.append(.targetBecameProgram) }
        if effect.sourceMissing || effect.revisionsBefore == nil { reasons.append(.sourceMissing) }
        if let before = effect.revisionsBefore {
            if before.sourceGeneration != p.revisions.sourceGeneration { reasons.append(.sourceRestarted) }
            if before.controlEpoch != p.revisions.controlEpoch || before.shotRevision != p.revisions.shotRevision {
                reasons.append(.shotChangedByOperator)
            }
        }
        if effect.policyRevision != p.policyRevision { reasons.append(.policyChanged) }
        if effect.nominationRevision != p.nominationRevision { reasons.append(.nominationChanged) }
        let age = effect.appliedAt - effect.requestIssuedAt
        if !age.isFinite || age < 0 || !effect.requestMaximumAge.isFinite || age > effect.requestMaximumAge {
            reasons.append(.expired)
        }
        return reasons
    }
}
