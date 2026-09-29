import Foundation

/// Synthetic, labelled replay. No camera, router, timer, or UI dependency.
nonisolated struct DirectorReplay {
    struct Event: Sendable {
        enum Action: Sendable {
            case subject(channel: ChannelID, present: Bool, confidence: Double,
                         intended: Bool, framingReady: Bool, movement: Double)
            case source(channel: ChannelID, missing: Bool)
            case render(channel: ChannelID)
            case shotChange(channel: ChannelID)
            case manualCommand, operatorTake, pause, resume, editLive(Bool), stop, fault(ChannelID)
            case directorAttempt(id: String, delay: TimeInterval, succeeds: Bool)
            case effect(id: String)
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
        var confidence = 0.0
        var intended = false
        var framingReady = false
        var movement = 0.0
        var missing = false
        var lastRenderAt: TimeInterval?
        var revisions = ChannelRevisions(sourceGeneration: 0, controlEpoch: 0, shotRevision: 0)
    }

    static func run(_ fixture: Fixture, parameters: DirectorShotPolicy.Parameters,
                    maximumProposalAge: TimeInterval) -> Report {
        // Invalid clocks are counted and skipped rather than crashing a replay.
        var authority = DirectorAuthority()
        _ = authority.apply(.enable(.autoPrepare))
        var channels: [ChannelID: Channel] = [.a: Channel(), .b: Channel()]
        var program: ChannelID = .a
        var route: UInt64 = 0
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
                       intended: Bool, succeeds: Bool, sequence: Int)] = []
        var attempts = 0, takeAttempts = 0, operatorCuts = 0
        var duplicateCallbacks = 0, failedEffects = 0, rejectedAttempts = 0, clockAnomalies = 0
        var wrongAttempts = 0, labelledAttempts = 0
        let validClockConfiguration = fixture.duration.isFinite && fixture.duration > 0 &&
            maximumProposalAge.isFinite && maximumProposalAge >= 0
        if !validClockConfiguration { clockAnomalies += 1 }
        let shotA = DirectorShot(preset: .wide, mode: .manualCrop, zoomRung: 0)
        let shotB = DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1)
        var history: [DirectorShotPolicy.History] = []
        func recordStale(_ id: Int, _ reasons: [DirectorProposalValidator.StaleReason]) {
            guard rejectedProposalIDs.insert(id).inserted else { return }
            for reason in reasons { stale[reason, default: 0] += 1 }
        }
        func completeEffect(_ effect: (id: String, due: TimeInterval, proposal: DirectorProposal,
                                      proposalID: Int, intended: Bool, succeeds: Bool, sequence: Int), at now: TimeInterval) {
            guard completedAttemptIDs.insert(effect.id).inserted else { duplicateCallbacks += 1; return }
            let target = effect.proposal.target
            let live = DirectorLiveState(authority: authority, program: program,
                preview: program == .a ? .b : .a, revisions: channels[target]?.revisions,
                routeGeneration: route, sourceMissing: channels[target]?.missing ?? true)
            let validation = DirectorProposalValidator.validate(effect.proposal, against: live,
                now: now, maximumAge: maximumProposalAge)
            if case .stale(let reasons) = validation {
                recordStale(effect.proposalID, reasons); rejectedAttempts += 1
            } else if !effect.succeeds { failedEffects += 1 }
            else { rejectedAttempts += 1 } // Auto Direct is deliberately unqualified.
        }
        func flushEffects(before time: TimeInterval, inclusive: Bool = false) {
            let due = effects.filter { inclusive ? $0.due <= time : $0.due < time }
                .sorted { $0.due == $1.due ? $0.sequence < $1.sequence : $0.due < $1.due }
            effects.removeAll { inclusive ? $0.due <= time : $0.due < time }
            for effect in due { completeEffect(effect, at: effect.due) }
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
            let priorProgram = program
            var operatorAuthorizedChange = false
            func live(for target: ChannelID) -> DirectorLiveState {
                DirectorLiveState(authority: authority, program: program,
                    preview: program == .a ? .b : .a, revisions: channels[target]?.revisions,
                    routeGeneration: route, sourceMissing: channels[target]?.missing ?? true)
            }
            switch event.action {
            case .manualCommand:
                if pending != nil || !effects.isEmpty { overrides += 1 }
                _ = authority.apply(.manualCommand)
            case .operatorTake:
                takeAttempts += 1
                if pending != nil || !effects.isEmpty { overrides += 1 }
                _ = authority.apply(.operatorTake)
                let target: ChannelID = program == .a ? .b : .a
                if channels[target]?.missing == false && channels[target]?.framingReady == true {
                    if now - programStartedAt < parameters.minimumShotDuration { violations += 1 }
                    if previousProgram == target && now - programStartedAt < parameters.repetitionWindow { oscillations += 1 }
                    history.append(.init(shot: program == .a ? shotA : shotB, endedAt: now))
                    previousProgram = program; program = target; route &+= 1
                    operatorAuthorizedChange = true
                    programStartedAt = now; cuts += 1; operatorCuts += 1
                    if program == .a { lastWideAt = now }
                }
            case .pause: _ = authority.apply(.pause)
            case .resume: _ = authority.apply(.resume)
            case .editLive(let enabled): _ = authority.apply(.editLive(enabled))
            case .stop: _ = authority.apply(.stopShow)
            case .fault(let id):
                channels[id, default: Channel()].missing = true
                channels[id, default: Channel()].revisions.sourceGeneration &+= 1
                _ = authority.apply(.sourceLoss(id))
            case .source(let id, let missing):
                channels[id, default: Channel()].missing = missing
                channels[id, default: Channel()].revisions.sourceGeneration &+= 1
                if missing { _ = authority.apply(.sourceLoss(id)) }
            case .render(let id):
                channels[id, default: Channel()].lastRenderAt = now
            case .shotChange(let id):
                channels[id, default: Channel()].revisions.shotRevision &+= 1
            case .directorAttempt(let id, let delay, let succeeds):
                guard seenAttemptIDs.insert(id).inserted else { rejectedAttempts += 1; break }
                attempts += 1
                guard delay.isFinite, delay >= 0, (now + delay).isFinite,
                      now + delay <= fixture.duration, let proposal = pending,
                      let idOfProposal = pendingID else {
                    if !delay.isFinite || delay < 0 { clockAnomalies += 1 }
                    rejectedAttempts += 1; break
                }
                let result = DirectorProposalValidator.validate(proposal, against: live(for: proposal.target),
                    now: now, maximumAge: maximumProposalAge)
                if case .stale(let reasons) = result {
                    recordStale(idOfProposal, reasons); pending = nil; pendingID = nil
                    rejectedAttempts += 1; break
                }
                labelledAttempts += 1
                let intended = channels[proposal.target]?.intended ?? false
                if !intended { wrongAttempts += 1 }
                effects.append((id, now + delay, proposal, idOfProposal, intended, succeeds, indexed.offset))
            case .effect(let id):
                if let effect = effects.first(where: { $0.id == id }) {
                    effects.removeAll { $0.id == id }
                    if now >= effect.due { completeEffect(effect, at: now) }
                    else { clockAnomalies += 1; rejectedAttempts += 1 }
                } else { duplicateCallbacks += 1 }
            case .subject(let id, let present, let confidence, let intended, let ready, let movement):
                channels[id, default: Channel()].present = present
                channels[id, default: Channel()].confidence = confidence
                channels[id, default: Channel()].intended = intended
                channels[id, default: Channel()].framingReady = ready
                channels[id, default: Channel()].movement = movement
            }
            if let proposal = pending {
                let result = DirectorProposalValidator.validate(proposal, against: live(for: proposal.target),
                    now: now, maximumAge: maximumProposalAge)
                if case .stale(let reasons) = result {
                    if let pendingID { recordStale(pendingID, reasons) }
                    pending = nil; pendingID = nil
                }
            }
            let preview: ChannelID = program == .a ? .b : .a
            if validClockConfiguration, authority.mayPropose, pending == nil, let channel = channels[preview],
               channel.present && channel.framingReady && !channel.missing,
               let renderAt = channel.lastRenderAt, now - renderAt <= maximumProposalAge {
                let candidate = DirectorShotPolicy.Candidate(channel: preview,
                    shot: preview == .b ? shotB : shotA, subjectConfidence: channel.confidence,
                    movement: channel.movement, isWide: preview == .a)
                let timeline = DirectorShotPolicy.Timeline(programShot: program == .a ? shotA : shotB,
                    programStartedAt: programStartedAt, lastWideAt: lastWideAt,
                    history: history, candidates: [candidate], now: now)
                if case .chosen(let choice, let reason) = DirectorShotPolicy.choose(timeline,
                    preview: preview, parameters: parameters) {
                    pending = DirectorProposal(target: preview, preview: preview, shot: choice.shot,
                        reason: reason, authorityEpoch: authority.epoch,
                        revisions: channel.revisions, routeGeneration: route, createdAt: now)
                    proposalID += 1; pendingID = proposalID
                    labelled += 1
                    if !channel.intended { wrong += 1 }
                }
            }
            if authority.paused && pending != nil { pausedProposals += 1 }
            // There is deliberately no director route mutation: qualification is false.
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
            rejectedAttempts: rejectedAttempts, clockAnomalies: clockAnomalies,
            wrongSubjectAttempts: wrongAttempts, labelledSubjectAttempts: labelledAttempts,
            proposalsMadeWhilePaused: pausedProposals,
            programChangesWithoutAuthority: unauthorized,
            wrongSubjectProposals: wrong, labelledSubjectProposals: labelled)
    }
}
