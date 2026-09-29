import Testing
@testable import Alfie

@MainActor struct DirectorProposalTests {
    @Test func staleDimensions() {
        var authority = DirectorAuthority()
        authority.apply(.enable(.autoPrepare))
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3)
        let shot = DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1)
        let p = DirectorProposal(target: .b, preview: .b, shot: shot, reason: "subject",
                                 authorityEpoch: authority.epoch, revisions: revisions,
                                 routeGeneration: 4, createdAt: 10)
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
}
