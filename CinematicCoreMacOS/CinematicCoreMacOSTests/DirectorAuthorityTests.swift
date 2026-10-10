import Testing
@testable import Alfie

@MainActor struct DirectorAuthorityTests {
    let good = DirectorAuthority.Prerequisites(nominationsCurrent: true, previewAvailable: true,
        sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])
    @Test func levelsAndGate() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        #expect(!state.mayPropose)
        #expect(state.apply(.enable(.suggest), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])).state.mayPropose)
        #expect(!state.mayPrepare)
        #expect(state.apply(.enable(.assist), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])).state.mayPrepare)
        #expect(state.apply(.enable(.auto), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])).state.level == .assist)
        #expect(!state.mayTake)
        #expect(state.apply(.enable(.auto), prerequisites: good).refusal == .notQualified)
        #expect(state.apply(.disable).state.level == .off)
    }

    @Test func manualWinsPendingWork() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist]))
        let old = state.epoch
        let result = state.apply(.manualCommand)
        #expect(result.cancellations == [.proposal, .prepare, .take])
        #expect(!state.authorizes(old, action: .propose))
        #expect(!state.authorizes(state.epoch, action: .propose))
        let second = state.epoch
        state.apply(.operatorTake)
        #expect(!state.authorizes(second, action: .propose))
        state.apply(.stopShow)
        #expect(!state.authorizes(state.epoch, action: .propose))
    }

    @Test func pausePinEditLiveAndLoss() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist]))
        #expect(!state.apply(.pause).state.mayPrepare)
        #expect(state.apply(.resume, prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist])).state.mayPrepare)
        #expect(!state.apply(.pin(.a)).state.mayPrepare)
        #expect(!state.apply(.unpin).state.mayPrepare)
        state.apply(.resume, prerequisites: good)
        #expect(!state.apply(.editLive(true)).state.mayPrepare)
        #expect(!state.apply(.editLive(false)).state.mayPrepare)
        state.apply(.resume, prerequisites: good)
        let token = state.epoch
        #expect(state.apply(.sourceLoss(.a)).cancellations.contains(.take))
        #expect(!state.authorizes(token, action: .propose))
    }

    @Test func pauseWithdrawsProposalAndPreparation() {
        // Replaces the retired section() projection (A-04): status now comes
        // from the controller; the authority only answers what is allowed.
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: good)
        #expect(state.mayPropose && state.mayPrepare)
        state.apply(.pause)
        #expect(!state.mayPropose && !state.mayPrepare && !state.mayTake)
    }
}


extension DirectorAuthorityTests {
    @Test func actionSpecificAndSupersedingGrants() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        #expect(state.apply(.enable(.assist)).refusal == .prerequisites)
        state.apply(.enable(.suggest), prerequisites: good)
        let suggest = state.epoch
        #expect(state.authorizes(suggest, action: .propose))
        #expect(!state.authorizes(suggest, action: .prepare))
        #expect(!state.authorizes(suggest, action: .take))
        #expect(state.apply(.enable(.auto), prerequisites: good).refusal == .notQualified)
        #expect(state.level == .suggest && state.epoch == suggest)
        state.apply(.enable(.assist), prerequisites: good)
        let first = state.epoch
        state.apply(.enable(.assist), prerequisites: good)
        #expect(!state.authorizes(first, action: .prepare))
        let second = state.epoch
        state.apply(.disable); state.apply(.enable(.assist), prerequisites: good)
        #expect(!state.authorizes(second, action: .prepare))
        let third = state.epoch
        state.apply(.pause)
        for index in 0..<5 {
            let incomplete = DirectorAuthority.Prerequisites(nominationsCurrent: index != 0,
                previewAvailable: index != 1, sourcesHealthy: index != 2,
                outputHealthy: index != 3, admissionCurrent: index != 4, qualifiedLevels: [.assist])
            #expect(state.apply(.resume, prerequisites: incomplete).refusal == .prerequisites)
            #expect(state.paused && !state.mayPrepare)
        }
        state.apply(.stopShow); state.apply(.restart)
        #expect(state.level == .off && !state.mayPrepare)
        #expect(state.apply(.resume, prerequisites: good).refusal == .prerequisites)
        state.apply(.enable(.assist), prerequisites: good)
        #expect(!state.authorizes(third, action: .prepare))
    }

    @Test(arguments: [DirectorAuthority.Event.manualCommand, .editLive(true),
        .identityLost(.b), .sourceLoss(.b), .sourceRebound(.b), .outputFault, .admissionLost,
        .policyChanged, .nominationChanged, .pin(.a)])
    func interventionsLatchPause(event: DirectorAuthority.Event) {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: good)
        let old = state.epoch
        #expect(state.apply(event).cancellations == [.proposal, .prepare, .take])
        state.apply(.healthRestored); state.apply(.evidenceAvailable(true))
        state.apply(.editLive(false)); state.apply(.unpin)
        #expect(state.paused && !state.mayPrepare)
        #expect(!state.authorizes(old, action: .prepare))
        #expect(state.apply(.enable(.assist), prerequisites: good).refusal == .paused)
        #expect(state.apply(.resume).refusal == .prerequisites)
        state.apply(.resume, prerequisites: good)
        #expect(state.mayPrepare && state.epoch != old)
    }

    @Test func temporaryGapAndNonInterventions() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: good)
        let old = state.epoch
        state.apply(.navigation); state.apply(.cosmeticEdit)
        state.apply(.evidenceAvailable(false))
        #expect(!state.mayPrepare && !state.paused && state.epoch == old)
        state.apply(.evidenceAvailable(true))
        #expect(state.authorizes(old, action: .prepare))
    }

    @Test func generationExhaustionIsTerminal() {
        var state = DirectorAuthority(reviewPolicy: .conservative, initialEpoch: UInt64.max - 1)
        state.apply(.enable(.assist), prerequisites: good)
        let old = state.epoch
        #expect(state.mayPrepare)
        state.apply(.manualCommand)
        #expect(state.exhausted && state.epoch == UInt64.max)
        for event in [DirectorAuthority.Event.disable, .restart, .enable(.assist), .resume] {
            state.apply(event, prerequisites: good)
            #expect(!state.authorizes(old, action: .prepare) && !state.mayPropose)
            #expect(state.epoch == UInt64.max)
        }
    }
}

/// A-03: levels v2 (U2), qualification-gated enable, takeover (A1), Assist
/// Take semantics (N1) and Hand to Alfie.
extension DirectorAuthorityTests {
    private func prerequisites(qualified: Set<DirectorAuthority.Level>) -> DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true, qualifiedLevels: qualified)
    }

    @Test(arguments: [DirectorAuthority.Level.assist, .auto, .backup])
    func unqualifiedLevelsAreRefusedWithoutSubstitution(level: DirectorAuthority.Level) {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.suggest), prerequisites: prerequisites(qualified: []))
        let epoch = state.epoch
        #expect(state.apply(.enable(level), prerequisites: prerequisites(qualified: [])).refusal == .notQualified)
        #expect(state.level == .suggest && state.epoch == epoch)
        #expect(state.apply(.enable(level), prerequisites: prerequisites(qualified: [level])).refusal == nil)
        #expect(state.level == level && state.mayPrepare && !state.mayTake)
    }

    @Test func suggestNeedsNoQualificationAndNeverPrepares() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        #expect(state.apply(.enable(.suggest), prerequisites: prerequisites(qualified: [])).refusal == nil)
        #expect(state.mayPropose && !state.mayPrepare && !state.mayTake)
    }

    @Test(arguments: [DirectorAuthority.Level.suggest, .assist])
    func operatorTakeInShadowOrAssistRetiresWithoutPausing(level: DirectorAuthority.Level) {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(level), prerequisites: prerequisites(qualified: [.assist]))
        let old = state.epoch
        let transition = state.apply(.operatorTake)
        #expect(transition.cancellations == [.proposal, .prepare, .take])
        #expect(!state.paused && state.level == level)
        #expect(!state.authorizes(old, action: .propose))
        #expect(state.authorizes(state.epoch, action: .propose))
    }

    @Test func operatorTakeOutsideAssistStillPausesUntilNudgeLands() {
        // Auto/Backup nudge semantics arrive with A-11; until then a Take pauses.
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.auto), prerequisites: prerequisites(qualified: [.auto]))
        state.apply(.operatorTake)
        #expect(state.paused && !state.mayPrepare)
    }

    @Test(arguments: [DirectorAuthority.Event.manualCommand, .editLive(true)])
    func manualActionIsATakeoverAtEveryLevel(event: DirectorAuthority.Event) {
        for level in [DirectorAuthority.Level.suggest, .assist, .auto, .backup] {
            var state = DirectorAuthority(reviewPolicy: .conservative)
            state.apply(.enable(level), prerequisites: prerequisites(qualified: [.assist, .auto, .backup]))
            state.apply(event)
            #expect(state.paused && !state.mayPropose, "level \(level)")
        }
    }

    @Test func handToAlfieResumesWithCurrentPrerequisitesOnly() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: prerequisites(qualified: [.assist]))
        state.apply(.manualCommand)
        let paused = state.epoch
        #expect(state.apply(.handToAlfie).refusal == .prerequisites)
        #expect(state.apply(.handToAlfie, prerequisites: prerequisites(qualified: [])).refusal == .notQualified)
        #expect(state.paused)
        #expect(state.apply(.handToAlfie, prerequisites: prerequisites(qualified: [.assist])).refusal == nil)
        #expect(!state.paused && state.mayPrepare && state.epoch != paused)
    }

    @Test func resumeRefusedWhenQualificationLapsed() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.assist), prerequisites: prerequisites(qualified: [.assist]))
        state.apply(.pause)
        #expect(state.apply(.resume, prerequisites: prerequisites(qualified: [])).refusal == .notQualified)
        #expect(state.paused && state.level == .assist)
    }

    @Test func noLevelMayTakeYet() {
        #expect(!DirectorAuthority.autoTakeQualified)
        for level in [DirectorAuthority.Level.suggest, .assist, .auto, .backup] {
            var state = DirectorAuthority(reviewPolicy: .conservative)
            state.apply(.enable(level), prerequisites: prerequisites(qualified: [.assist, .auto, .backup]))
            #expect(!state.mayTake && !state.authorizes(state.epoch, action: .take))
        }
    }
}
