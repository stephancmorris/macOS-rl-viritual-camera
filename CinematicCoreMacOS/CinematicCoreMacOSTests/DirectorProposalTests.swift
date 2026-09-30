import Testing
@testable import Alfie

@MainActor struct DirectorProposalTests {
    @Test func staleDimensions() throws {
        var authority = DirectorAuthority(reviewPolicy: .conservative)
        authority.apply(.enable(.autoPrepare), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true))
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3)
        let shot = DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1)
        let p = try #require(DirectorProposal(target: .b, preview: .b, shot: shot, reason: "subject",
                                 authorityEpoch: authority.epoch, revisions: revisions,
                                 routeGeneration: 4, createdAt: 10))
        let good = DirectorLiveState(authority: authority, program: .a, preview: .b,
                                     revisions: revisions, routeGeneration: 4, sourceMissing: false)
        #expect(DirectorProposalValidator.validate(p, against: good, now: 11, maximumAge: 2, action: .propose) == .valid)
        var changed = good
        changed = .init(authority: authority, program: .b, preview: .a,
                        revisions: .init(sourceGeneration: 2, controlEpoch: 3, shotRevision: 4),
                        routeGeneration: 5, sourceMissing: true)
        authority.apply(.manualCommand)
        changed = .init(authority: authority, program: changed.program, preview: changed.preview,
                        revisions: changed.revisions, routeGeneration: changed.routeGeneration, sourceMissing: true)
        let result = DirectorProposalValidator.validate(p, against: changed, now: 13, maximumAge: 2, action: .propose)
        guard case .stale(let reasons) = result else { Issue.record("Expected stale"); return }
        #expect(Set(reasons) == Set([.authorityRevoked, .routeChanged, .sourceRestarted,
                                      .shotChangedByOperator, .targetBecameProgram, .sourceMissing, .expired]))
    }

    @Test func proposalForANonPreviewChannelIsRefusedNotACrash() {
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 1, shotRevision: 1)
        let shot = DirectorShot(preset: .wide, mode: .manualCrop, zoomRung: 0)
        #expect(DirectorProposal(target: .a, preview: .b, shot: shot, reason: "program", authorityEpoch: 0,
                                 revisions: revisions, routeGeneration: 0, createdAt: 0) == nil)
    }

    @Test func malformedProposalTimeAndExpiryFailClosed() throws {
        var authority = DirectorAuthority(reviewPolicy: .conservative)
        authority.apply(.enable(.autoPrepare), prerequisites: .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true, outputHealthy: true, admissionCurrent: true))
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 1, shotRevision: 1)
        let live = DirectorLiveState(authority: authority, program: .a, preview: .b,
            revisions: revisions, routeGeneration: 1, sourceMissing: false)
        let shot = DirectorShot(preset: .wide, mode: .manualCrop, zoomRung: 0)
        for createdAt in [Double.nan, Double.infinity, -Double.infinity] {
            let proposal = try #require(DirectorProposal(target: .b, preview: .b, shot: shot, reason: "test",
                authorityEpoch: authority.epoch, revisions: revisions, routeGeneration: 1, createdAt: createdAt))
            #expect(DirectorProposalValidator.validate(proposal, against: live, now: 5, maximumAge: 2, action: .propose) == .stale([.expired]))
        }
        let proposal = try #require(DirectorProposal(target: .b, preview: .b, shot: shot, reason: "test",
            authorityEpoch: authority.epoch, revisions: revisions, routeGeneration: 1, createdAt: 4))
        for maximumAge in [Double.nan, Double.infinity, -Double.infinity, -1] {
            #expect(DirectorProposalValidator.validate(proposal, against: live, now: 5, maximumAge: maximumAge, action: .propose) == .stale([.expired]))
        }
        for now in [Double.nan, Double.infinity, -Double.infinity, 3] {
            #expect(DirectorProposalValidator.validate(proposal, against: live, now: now, maximumAge: 2, action: .propose) == .stale([.expired]))
        }
    }

    @Test func readinessRejectsMalformedEvidenceAndThresholds() {
        let take = TakeAvailability(program: .a, preview: .b, standard: .p50,
            reason: nil, takePending: false, editLive: false)
        let good = DirectorReadiness.Parameters(minimumIdentityConfidence: 0.7,
            minimumSettledTime: 0.2, maximumMotion: 0.5, cutOnMotionAllowed: true)
        for bad in [Double.nan, Double.infinity, -0.1, 1.1] {
            let evidence = DirectorReadiness.Inputs(take: take, identityConfidence: bad,
                framingSettledFor: 1, motion: 0)
            #expect(DirectorReadiness.evaluate(evidence, parameters: good).reasons.contains(.invalidEvidence))
        }
        let negativeMotion = DirectorReadiness.Inputs(take: take, identityConfidence: 1,
            framingSettledFor: 1, motion: -1)
        #expect(DirectorReadiness.evaluate(negativeMotion, parameters: good).reasons.contains(.invalidEvidence))
        let badTime = DirectorReadiness.Inputs(take: take, identityConfidence: 1,
            framingSettledFor: .nan, motion: 0)
        #expect(DirectorReadiness.evaluate(badTime, parameters: good).reasons.contains(.invalidEvidence))
        let invalid = DirectorReadiness.Parameters(minimumIdentityConfidence: .nan,
            minimumSettledTime: 0, maximumMotion: 0, cutOnMotionAllowed: true)
        #expect(DirectorReadiness.evaluate(negativeMotion, parameters: invalid).reasons.contains(.invalidParameters))
    }
}

extension DirectorProposalTests {
    private var prerequisites: DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true)
    }
    private var thresholds: DirectorReadiness.Parameters {
        .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2,
              maximumMotion: 0.1, cutOnMotionAllowed: false)
    }
    private func world() -> DirectorLiveState {
        var authority = DirectorAuthority(reviewPolicy: .conservative)
        authority.apply(.enable(.autoPrepare), prerequisites: prerequisites)
        return .init(authority: authority, program: .a, preview: .b,
            revisions: .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3),
            routeGeneration: 4, sourceMissing: false, policyRevision: 5,
            nominationRevision: 6, evidenceAvailable: true)
    }
    private func intent(_ live: DirectorLiveState, at: Double = 0) throws -> DirectorProposal {
        let revisions = try #require(live.revisions)
        return try #require(DirectorProposal(target: .b, preview: .b,
            shot: .init(preset: .waistUp, mode: .autoTracking, zoomRung: 1), reason: "study",
            authorityEpoch: live.authority.epoch, revisions: revisions,
            routeGeneration: live.routeGeneration, createdAt: at,
            policyRevision: live.policyRevision, nominationRevision: live.nominationRevision))
    }
    private func evidence(_ live: DirectorLiveState, settled: Double = 1, motion: Double = 0) -> DirectorReadiness.Inputs {
        .init(take: .init(program: live.program, preview: live.preview, standard: .p50,
            reason: nil, takePending: false, editLive: false), identityConfidence: 0.95,
            framingSettledFor: settled, motion: motion)
    }

    @Test func acknowledgedCompositionOutlivesRequestAndRefreshesReadiness() throws {
        var live = world()
        let proposal = try intent(live)
        var lifecycle = DirectorPreparation()
        let operation1 = lifecycle.propose(proposal, maximumAge: 2, now: 0)
        let request = try #require(operation1)
        let post = ChannelRevisions(sourceGeneration: 1, controlEpoch: 3, shotRevision: 4)
        let operation2 = lifecycle.commit(request, live: live, now: 1, postRevisions: post)
        let receipt = try #require(operation2)
        live = .init(authority: live.authority, program: .a, preview: .b, revisions: post,
            routeGeneration: 4, sourceMissing: false, policyRevision: 5, nominationRevision: 6, evidenceAvailable: true)
        let operation3 = lifecycle.acknowledge(receipt, live: live)
        #expect(operation3)
        let operation4 = lifecycle.acknowledge(receipt, live: live)
        #expect(!operation4)
        let operation5 = lifecycle.commit(request, live: live, now: 1, postRevisions: post)
        #expect(operation5 == nil)
        let operation6 = lifecycle.refresh(live: live, evidence: evidence(live, settled: 0, motion: 0.5), parameters: thresholds)
        #expect(!operation6.isReady)
        for _ in 0..<100 {
            let operation7 = lifecycle.refresh(live: live, evidence: evidence(live), parameters: thresholds)
            #expect(operation7.isReady)
            #expect(lifecycle.request == nil && lifecycle.composition?.revisions == post)
        }
        live.evidenceAvailable = false
        let operation8 = lifecycle.refresh(live: live, evidence: evidence(live), parameters: thresholds)
        #expect(operation8.reasons == [.evidenceUnavailable])
        #expect(lifecycle.composition != nil)
        live.evidenceAvailable = true
        let operation9 = lifecycle.refresh(live: live, evidence: evidence(live), parameters: thresholds)
        #expect(operation9.isReady)
    }

    @Test func replacedRequestsAndReceiptsCannotAttachToNewWork() throws {
        let live = world(), post = ChannelRevisions(sourceGeneration: 1, controlEpoch: 3, shotRevision: 4)
        var lifecycle = DirectorPreparation()
        let operation10 = lifecycle.propose(try intent(live), maximumAge: 2, now: 0)
        let first = try #require(operation10)
        let operation11 = lifecycle.commit(first, live: live, now: 1, postRevisions: post)
        let oldReceipt = try #require(operation11)
        let operation12 = lifecycle.propose(try intent(live), maximumAge: 2, now: 0)
        let replacement = try #require(operation12)
        #expect(first.id != replacement.id && first.intent.id != replacement.intent.id)
        let operation13 = lifecycle.commit(first, live: live, now: 1, postRevisions: post)
        #expect(operation13 == nil)
        let operation14 = lifecycle.acknowledge(oldReceipt, live: live)
        #expect(!operation14)
        #expect(lifecycle.request == replacement)
        let operation15 = lifecycle.commit(replacement, live: live, now: 1, postRevisions: post)
        #expect(operation15 != nil)
    }

    @Test func leaseIsSeparateFromIntentAndNeverRenewed() throws {
        let live = world(), post = ChannelRevisions(sourceGeneration: 1, controlEpoch: 3, shotRevision: 4)
        var lifecycle = DirectorPreparation()
        // A retained intent can explicitly produce a new dispatch request later.
        let operation16 = lifecycle.propose(try intent(live), maximumAge: 2, now: 100)
        let request = try #require(operation16)
        let operation17 = lifecycle.commit(request, live: live, now: 103, postRevisions: post)
        #expect(operation17 == nil)
        #expect(lifecycle.request == nil && lifecycle.composition == nil)
        let operation18 = lifecycle.commit(request, live: live, now: 101, postRevisions: post)
        #expect(operation18 == nil)
        let expiring = lifecycle.propose(try intent(live), maximumAge: 2, now: 100)
        #expect(expiring != nil)
        lifecycle.discardExpiredRequest(now: 104)
        #expect(lifecycle.request == nil)
        let operation19 = lifecycle.propose(try intent(live), maximumAge: 2, now: 100)
        let next = try #require(operation19)
        let operation20 = lifecycle.commit(next, live: live, now: 101, postRevisions: post)
        #expect(operation20 != nil)
    }

    @Test(arguments: ["manual", "take", "edit", "identity", "source", "output", "admission", "policy", "nomination", "stop", "gap", "suggest", "role", "revisions"])
    func finalEffectAndAcknowledgementRecheckEveryContext(change: String) throws {
        let original = world(), post = ChannelRevisions(sourceGeneration: 1, controlEpoch: 3, shotRevision: 4)
        var changed = original
        var authority = original.authority
        switch change {
        case "manual": authority.apply(.manualCommand)
        case "take": authority.apply(.operatorTake)
        case "edit": authority.apply(.editLive(true))
        case "identity": authority.apply(.identityLost(.b))
        case "source": authority.apply(.sourceRebound(.b))
        case "output": authority.apply(.outputFault)
        case "admission": authority.apply(.admissionLost)
        case "stop": authority.apply(.stopShow); authority.apply(.restart)
        case "suggest": authority.apply(.enable(.suggest), prerequisites: prerequisites)
        default: break
        }
        changed = .init(authority: authority, program: change == "role" ? .b : .a,
            preview: change == "role" ? .a : .b,
            revisions: change == "revisions" ? .init(sourceGeneration: 2, controlEpoch: 4, shotRevision: 5) : original.revisions,
            routeGeneration: change == "role" ? 5 : 4, sourceMissing: false,
            policyRevision: change == "policy" ? 7 : 5,
            nominationRevision: change == "nomination" ? 7 : 6, evidenceAvailable: change != "gap")
        var lifecycle = DirectorPreparation()
        let operation21 = lifecycle.propose(try intent(original), maximumAge: 2, now: 0)
        let request = try #require(operation21)
        let operation22 = lifecycle.commit(request, live: changed, now: 1, postRevisions: post)
        #expect(operation22 == nil)
        #expect(lifecycle.composition == nil)
        // ACK checks post-context too, rather than trusting an accepted enqueue.
        let operation23 = lifecycle.propose(try intent(original), maximumAge: 2, now: 0)
        let second = try #require(operation23)
        let operation24 = lifecycle.commit(second, live: original, now: 1, postRevisions: post)
        let receipt = try #require(operation24)
        if change != "gap" {
            let operation25 = lifecycle.acknowledge(receipt, live: changed)
            #expect(!operation25)
        }
    }

    @Test func acknowledgementMustMatchExpectedPostRevision() throws {
        let live = world()
        var lifecycle = DirectorPreparation()
        let operation26 = lifecycle.propose(try intent(live), maximumAge: 2, now: 0)
        let request = try #require(operation26)
        let operation27 = lifecycle.commit(request, live: live, now: 1,
            postRevisions: .init(sourceGeneration: 1, controlEpoch: 3, shotRevision: 4))
        let receipt = try #require(operation27)
        let operation28 = lifecycle.acknowledge(receipt, live: live)
        #expect(!operation28)
        #expect(lifecycle.composition == nil)
    }
}
