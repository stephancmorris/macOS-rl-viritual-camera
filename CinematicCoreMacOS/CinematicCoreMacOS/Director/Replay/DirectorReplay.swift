import Foundation

/// Synthetic, labelled replay. No camera, router, timer, or UI dependency.
nonisolated struct DirectorReplay {
    struct Event: Sendable {
        enum Action: Sendable {
            case subject(channel: ChannelID, present: Bool, confidence: Double,
                         intended: Bool, framingReady: Bool, movement: Double)
            case source(channel: ChannelID, missing: Bool)
            case render(channel: ChannelID)
            case manualCommand, operatorTake, pause, resume, editLive(Bool)
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
        let cutsPerMinute: Double
        let minimumDurationViolations: Int
        let oscillations: Int
        let staleProposalsRejected: [DirectorProposalValidator.StaleReason: Int]
        let manualOverridesHonoured: Int
        let manualOverrideLatencies: [TimeInterval]
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
        var revisions = ChannelRevisions(sourceGeneration: 0, controlEpoch: 0, shotRevision: 0)
    }

    static func run(_ fixture: Fixture, parameters: DirectorShotPolicy.Parameters,
                    maximumProposalAge: TimeInterval) -> Report {
        precondition(fixture.duration > 0)
        var authority = DirectorAuthority()
        authority.apply(.enable(.autoPrepare))
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
        let shotA = DirectorShot(preset: .wide, mode: .manualCrop, zoomRung: 0)
        let shotB = DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1)
        var history: [DirectorShotPolicy.History] = []
        for event in fixture.events.sorted(by: { $0.at < $1.at }) {
            let now = event.at
            let priorProgram = program
            var operatorAuthorizedChange = false
            func live(for target: ChannelID) -> DirectorLiveState {
                DirectorLiveState(authority: authority, program: program,
                    preview: program == .a ? .b : .a, revisions: channels[target]?.revisions,
                    routeGeneration: route, sourceMissing: channels[target]?.missing ?? true)
            }
            switch event.action {
            case .manualCommand:
                authority.apply(.manualCommand); overrides += 1
            case .operatorTake:
                authority.apply(.operatorTake); overrides += 1
                let target: ChannelID = program == .a ? .b : .a
                if channels[target]?.missing == false && channels[target]?.framingReady == true {
                    if now - programStartedAt < parameters.minimumShotDuration { violations += 1 }
                    if previousProgram == target && now - programStartedAt < parameters.repetitionWindow { oscillations += 1 }
                    history.append(.init(shot: program == .a ? shotA : shotB, endedAt: now))
                    previousProgram = program; program = target; route &+= 1
                    operatorAuthorizedChange = true
                    programStartedAt = now; cuts += 1
                    if program == .a { lastWideAt = now }
                }
            case .pause: authority.apply(.pause)
            case .resume: authority.apply(.resume)
            case .editLive(let enabled): authority.apply(.editLive(enabled))
            case .source(let id, let missing):
                channels[id, default: Channel()].missing = missing
                channels[id, default: Channel()].revisions.sourceGeneration &+= 1
                if missing { authority.apply(.sourceLoss(id)) }
            case .render(let id):
                channels[id, default: Channel()].revisions.shotRevision &+= 1
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
                    for reason in reasons { stale[reason, default: 0] += 1 }
                    pending = nil
                }
            }
            let preview: ChannelID = program == .a ? .b : .a
            if authority.mayPropose, pending == nil, let channel = channels[preview],
               channel.present && channel.framingReady && !channel.missing {
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
                    labelled += 1
                    if !channel.intended { wrong += 1 }
                }
            }
            if authority.paused && pending != nil { pausedProposals += 1 }
            // There is deliberately no director route mutation: qualification is false.
            if program != priorProgram && !operatorAuthorizedChange { unauthorized += 1 }
        }
        return Report(cutsPerMinute: Double(cuts) * 60 / fixture.duration,
            minimumDurationViolations: violations, oscillations: oscillations,
            staleProposalsRejected: stale, manualOverridesHonoured: overrides,
            manualOverrideLatencies: Array(repeating: 0, count: overrides),
            proposalsMadeWhilePaused: pausedProposals,
            programChangesWithoutAuthority: unauthorized,
            wrongSubjectProposals: wrong, labelledSubjectProposals: labelled)
    }
}
