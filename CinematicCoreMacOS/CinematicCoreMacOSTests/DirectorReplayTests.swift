import Foundation
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
        #expect(reports[0].staleProposalsRejected[.shotChangedByOperator] == nil)
        #expect(reports[0].proposalCount == 2)
        #expect(reports[1].labelledSubjectProposals == 1)
        #expect(reports[2].wrongSubjectProposals == 1)
        #expect(reports[2].labelledSubjectProposals == 2)
        #expect(reports[3].staleProposalsRejected[.sourceRestarted] == 1)
        #expect(reports[4].manualOverridesHonoured == 2)
        #expect(reports[4].manualOverrideLatencies.count == 2)
        #expect(reports[4].manualOverrideLatencies.allSatisfy { $0 == nil })
        #expect(reports[4].operatorTakeAttempts == 1)
        #expect(reports[4].operatorCuts == 1)
        #expect(reports[4].cutsPerMinute == 1)
        #expect(reports[4].minimumDurationViolations == 0)
        #expect(reports[4].oscillations == 0)
        #expect(reports.allSatisfy { $0.evidence == .synthetic && $0.directorCuts == 0 })
    }

    private func ready(_ at: Double) -> [DirectorReplay.Event] {
        [.init(at: at, action: .render(channel: .b)),
         .init(at: at, action: .subject(channel: .b, present: true, confidence: 0.95,
            intended: true, framingReady: true, movement: 0))]
    }

    @Test func stableEqualTimeSequenceAndOrdinaryRender() {
        let ordered = DirectorReplay.Fixture(name: "ordered", duration: 20,
            events: ready(9) + [.init(at: 9, action: .pause)])
        let pausedFirst = DirectorReplay.Fixture(name: "paused first", duration: 20,
            events: [.init(at: 9, action: .pause)] + ready(9))
        let a = DirectorReplay.run(ordered, parameters: .proposed, maximumProposalAge: 5)
        let b = DirectorReplay.run(pausedFirst, parameters: .proposed, maximumProposalAge: 5)
        #expect(a.proposalCount == 1)
        #expect(b.proposalCount == 0)
        #expect(a.proposalsMadeWhilePaused == 0)
        let render = DirectorReplay.Fixture(name: "render", duration: 20,
            events: ready(9) + [.init(at: 10, action: .render(channel: .b))])
        let result = DirectorReplay.run(render, parameters: .proposed, maximumProposalAge: 5)
        #expect(result.proposalCount == 1)
        #expect(result.staleProposalsRejected[.shotChangedByOperator] == nil)
    }

    @Test func delayedEffectManualOverrideAndDuplicateCallback() {
        let fixture = DirectorReplay.Fixture(name: "stale shadow", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "a", delay: 3, succeeds: true)),
                .init(at: 11, action: .manualCommand), .init(at: 14, action: .effect(id: "a"))])
        let report = DirectorReplay.run(fixture, parameters: .proposed, maximumProposalAge: 5)
        #expect(report.directorAttemptCount == 1)
        #expect(report.labelledSubjectAttempts == 1)
        #expect(report.wrongSubjectAttempts == 0)
        #expect(report.staleProposalsRejected[.authorityRevoked] == 1)
        #expect(report.rejectedAttempts == 1)
        #expect(report.duplicateCallbacks == 1)
        #expect(report.directorCuts == 0)
        #expect(report.programChangesWithoutAuthority == 0)
        #expect(report.manualOverridesHonoured == 1)
        #expect(report.manualOverrideLatencies == [nil])
    }

    @Test func stopFaultFailedEffectAndClockAnomalies() {
        let failed = DirectorReplay.Fixture(name: "failed effect", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "failed", delay: 1, succeeds: false)),
                .init(at: 12, action: .effect(id: "failed"))])
        let failure = DirectorReplay.run(failed, parameters: .proposed, maximumProposalAge: 5)
        #expect(failure.failedEffects == 1)
        #expect(failure.duplicateCallbacks == 1)
        #expect(failure.directorCuts == 0)
        let stopped = DirectorReplay.Fixture(name: "stopped", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "stopped", delay: 3, succeeds: true)),
                .init(at: 11, action: .stop), .init(at: 12, action: .fault(.b)),
                .init(at: 13, action: .render(channel: .b))])
        let stop = DirectorReplay.run(stopped, parameters: .proposed, maximumProposalAge: 5)
        #expect(stop.staleProposalsRejected[.authorityRevoked] == 1)
        #expect(stop.rejectedAttempts == 1)
        #expect(stop.directorCuts == 0)
        let faulted = DirectorReplay.Fixture(name: "faulted", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "faulted", delay: 3, succeeds: true)),
                .init(at: 11, action: .fault(.b))])
        let fault = DirectorReplay.run(faulted, parameters: .proposed, maximumProposalAge: 5)
        #expect(fault.staleProposalsRejected[.sourceRestarted] == 1)
        #expect(fault.rejectedAttempts == 1)
        let bad = DirectorReplay.Fixture(name: "clock anomalies", duration: 20,
            events: ready(9) + [.init(at: .nan, action: .manualCommand),
                .init(at: 10, action: .directorAttempt(id: "bad", delay: .nan, succeeds: true))])
        let anomalies = DirectorReplay.run(bad, parameters: .proposed, maximumProposalAge: 5)
        #expect(anomalies.clockAnomalies == 2)
        #expect(anomalies.rejectedAttempts == 1)
        let invalidExpiry = DirectorReplay.run(failed, parameters: .proposed,
            maximumProposalAge: .infinity)
        #expect(invalidExpiry.clockAnomalies == 1)
        #expect(invalidExpiry.proposalCount == 0)
    }
}
