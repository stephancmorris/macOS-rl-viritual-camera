import Testing
@testable import Alfie

@MainActor struct DirectorAuthorityTests {
    let good = DirectorAuthority.Prerequisites(nominationsCurrent: true, previewAvailable: true,
        sourcesHealthy: true, outputHealthy: true, admissionCurrent: true)
    @Test func levelsAndGate() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        #expect(!state.mayPropose)
        #expect(state.apply(.enable(.suggest), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true)).state.mayPropose)
        #expect(!state.mayPrepare)
        #expect(state.apply(.enable(.autoPrepare), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true)).state.mayPrepare)
        #expect(state.apply(.enable(.autoDirect), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true)).state.level == .autoPrepare)
        #expect(!state.mayTake)
        #expect(state.apply(.enable(.autoDirect), prerequisites: good).refusal == .autoDirectUnqualified)
        #expect(state.apply(.disable).state.level == .off)
    }

    @Test func manualWinsPendingWork() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.autoPrepare), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true))
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
        state.apply(.enable(.autoPrepare), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true))
        #expect(!state.apply(.pause).state.mayPrepare)
        #expect(state.apply(.resume, prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true)).state.mayPrepare)
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
        state.apply(.enable(.autoPrepare), prerequisites: good)
        #expect(state.mayPropose && state.mayPrepare)
        state.apply(.pause)
        #expect(!state.mayPropose && !state.mayPrepare && !state.mayTake)
    }
}


extension DirectorAuthorityTests {
    @Test func actionSpecificAndSupersedingGrants() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        #expect(state.apply(.enable(.autoPrepare)).refusal == .prerequisites)
        state.apply(.enable(.suggest), prerequisites: good)
        let suggest = state.epoch
        #expect(state.authorizes(suggest, action: .propose))
        #expect(!state.authorizes(suggest, action: .prepare))
        #expect(!state.authorizes(suggest, action: .take))
        #expect(state.apply(.enable(.autoDirect), prerequisites: good).refusal == .autoDirectUnqualified)
        #expect(state.level == .suggest && state.epoch == suggest)
        state.apply(.enable(.autoPrepare), prerequisites: good)
        let first = state.epoch
        state.apply(.enable(.autoPrepare), prerequisites: good)
        #expect(!state.authorizes(first, action: .prepare))
        let second = state.epoch
        state.apply(.disable); state.apply(.enable(.autoPrepare), prerequisites: good)
        #expect(!state.authorizes(second, action: .prepare))
        let third = state.epoch
        state.apply(.pause)
        for index in 0..<5 {
            let incomplete = DirectorAuthority.Prerequisites(nominationsCurrent: index != 0,
                previewAvailable: index != 1, sourcesHealthy: index != 2,
                outputHealthy: index != 3, admissionCurrent: index != 4)
            #expect(state.apply(.resume, prerequisites: incomplete).refusal == .prerequisites)
            #expect(state.paused && !state.mayPrepare)
        }
        state.apply(.stopShow); state.apply(.restart)
        #expect(state.level == .off && !state.mayPrepare)
        #expect(state.apply(.resume, prerequisites: good).refusal == .prerequisites)
        state.apply(.enable(.autoPrepare), prerequisites: good)
        #expect(!state.authorizes(third, action: .prepare))
    }

    @Test(arguments: [DirectorAuthority.Event.manualCommand, .operatorTake, .editLive(true),
        .identityLost(.b), .sourceLoss(.b), .sourceRebound(.b), .outputFault, .admissionLost,
        .policyChanged, .nominationChanged, .pin(.a)])
    func interventionsLatchPause(event: DirectorAuthority.Event) {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.autoPrepare), prerequisites: good)
        let old = state.epoch
        #expect(state.apply(event).cancellations == [.proposal, .prepare, .take])
        state.apply(.healthRestored); state.apply(.evidenceAvailable(true))
        state.apply(.editLive(false)); state.apply(.unpin)
        #expect(state.paused && !state.mayPrepare)
        #expect(!state.authorizes(old, action: .prepare))
        #expect(state.apply(.enable(.autoPrepare), prerequisites: good).refusal == .paused)
        #expect(state.apply(.resume).refusal == .prerequisites)
        state.apply(.resume, prerequisites: good)
        #expect(state.mayPrepare && state.epoch != old)
    }

    @Test func temporaryGapAndNonInterventions() {
        var state = DirectorAuthority(reviewPolicy: .conservative)
        state.apply(.enable(.autoPrepare), prerequisites: good)
        let old = state.epoch
        state.apply(.navigation); state.apply(.cosmeticEdit)
        state.apply(.evidenceAvailable(false))
        #expect(!state.mayPrepare && !state.paused && state.epoch == old)
        state.apply(.evidenceAvailable(true))
        #expect(state.authorizes(old, action: .prepare))
    }

    @Test func generationExhaustionIsTerminal() {
        var state = DirectorAuthority(reviewPolicy: .conservative, initialEpoch: UInt64.max - 1)
        state.apply(.enable(.autoPrepare), prerequisites: good)
        let old = state.epoch
        #expect(state.mayPrepare)
        state.apply(.manualCommand)
        #expect(state.exhausted && state.epoch == UInt64.max)
        for event in [DirectorAuthority.Event.disable, .restart, .enable(.autoPrepare), .resume] {
            state.apply(event, prerequisites: good)
            #expect(!state.authorizes(old, action: .prepare) && !state.mayPropose)
            #expect(state.epoch == UInt64.max)
        }
    }
}
