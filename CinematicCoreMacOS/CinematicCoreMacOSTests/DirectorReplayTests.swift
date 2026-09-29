import Testing
@testable import Alfie

@MainActor struct DirectorReplayTests {
    @Test func fiveSyntheticTimelines() {
        let reports = DirectorReplayFixtures.all.map {
            DirectorReplay.run($0, parameters: .proposed, maximumProposalAge: 5)
        }
        #expect(reports.count == 5)
        for report in reports {
            #expect(report.programChangesWithoutAuthority == 0)
            #expect(report.proposalsMadeWhilePaused == 0)
            #expect(report.cutsPerMinute >= 0)
        }
        #expect(reports[0].labelledSubjectProposals == 2)
        #expect(reports[0].staleProposalsRejected[.shotChangedByOperator] == 1)
        #expect(reports[1].labelledSubjectProposals == 1)
        #expect(reports[2].wrongSubjectProposals == 1)
        #expect(reports[2].labelledSubjectProposals == 2)
        #expect(reports[3].staleProposalsRejected[.sourceRestarted] == 1)
        #expect(reports[4].manualOverridesHonoured == 2)
        #expect(reports[4].manualOverrideLatencies == [0, 0])
        #expect(reports[4].cutsPerMinute == 1)
        #expect(reports[4].minimumDurationViolations == 0)
        #expect(reports[4].oscillations == 0)
    }
}
