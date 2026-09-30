import Testing
@testable import Alfie

@MainActor struct DirectorProposalTests {
    @Test func staleDimensions() throws {
        var authority = DirectorAuthority()
        authority.apply(.enable(.autoPrepare))
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3)
        let shot = DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1)
        let p = try #require(DirectorProposal(target: .b, preview: .b, shot: shot, reason: "subject",
                                 authorityEpoch: authority.epoch, revisions: revisions,
                                 routeGeneration: 4, createdAt: 10))
        let good = DirectorLiveState(authority: authority, program: .a, preview: .b,
                                     revisions: revisions, routeGeneration: 4, sourceMissing: false)
        #expect(DirectorProposalValidator.validate(p, against: good, now: 11, maximumAge: 2) == .valid)
        var changed = good
        changed = .init(authority: authority, program: .b, preview: .a,
                        revisions: .init(sourceGeneration: 2, controlEpoch: 3, shotRevision: 4),
                        routeGeneration: 5, sourceMissing: true)
        authority.apply(.manualCommand)
        changed = .init(authority: authority, program: changed.program, preview: changed.preview,
                        revisions: changed.revisions, routeGeneration: changed.routeGeneration, sourceMissing: true)
        let result = DirectorProposalValidator.validate(p, against: changed, now: 13, maximumAge: 2)
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
        var authority = DirectorAuthority()
        authority.apply(.enable(.autoPrepare))
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 1, shotRevision: 1)
        let live = DirectorLiveState(authority: authority, program: .a, preview: .b,
            revisions: revisions, routeGeneration: 1, sourceMissing: false)
        let shot = DirectorShot(preset: .wide, mode: .manualCrop, zoomRung: 0)
        for createdAt in [Double.nan, Double.infinity, -Double.infinity] {
            let proposal = try #require(DirectorProposal(target: .b, preview: .b, shot: shot, reason: "test",
                authorityEpoch: authority.epoch, revisions: revisions, routeGeneration: 1, createdAt: createdAt))
            #expect(DirectorProposalValidator.validate(proposal, against: live, now: 5, maximumAge: 2) == .stale([.expired]))
        }
        let proposal = try #require(DirectorProposal(target: .b, preview: .b, shot: shot, reason: "test",
            authorityEpoch: authority.epoch, revisions: revisions, routeGeneration: 1, createdAt: 4))
        for maximumAge in [Double.nan, Double.infinity, -Double.infinity, -1] {
            #expect(DirectorProposalValidator.validate(proposal, against: live, now: 5, maximumAge: maximumAge) == .stale([.expired]))
        }
        for now in [Double.nan, Double.infinity, -Double.infinity, 3] {
            #expect(DirectorProposalValidator.validate(proposal, against: live, now: now, maximumAge: 2) == .stale([.expired]))
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
