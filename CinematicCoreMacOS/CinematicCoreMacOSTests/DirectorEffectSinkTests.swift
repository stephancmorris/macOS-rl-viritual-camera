import Foundation
import Testing
@testable import Alfie

nonisolated struct DirectorEffectSinkTests {
    private func context() throws -> (DirectorPreparation, DirectorPreparation.Request, DirectorLiveState) {
        var authority = DirectorAuthority(reviewPolicy: .conservative)
        authority.apply(.enable(.assist), prerequisites: .init(nominationsCurrent: true,
            previewAvailable: true, sourcesHealthy: true, outputHealthy: true,
            admissionCurrent: true, qualifiedLevels: [.assist]))
        let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3)
        let proposal = try #require(DirectorProposal(target: .b, preview: .b,
            shot: .init(preset: .stage(.waistUp)), reason: "synthetic",
            authorityEpoch: authority.epoch, revisions: revisions, routeGeneration: 4, createdAt: 10))
        var preparation = DirectorPreparation()
        let proposed = preparation.propose(proposal, maximumAge: 5, now: 10)
        let request = try #require(proposed)
        let live = DirectorLiveState(authority: authority, program: .a, preview: .b,
            revisions: revisions, routeGeneration: 4, sourceMissing: false, evidenceAvailable: true)
        return (preparation, request, live)
    }

    @Test func commitsOneOffAirPresetAndRejectsReuse() throws {
        var (preparation, request, live) = try context()
        var sink = SimulatedDirectorEffectSink(succeeds: true)
        guard case .committed(let receipt) = sink.prepare(request, preparation: &preparation, live: live, now: 11) else {
            Issue.record("Expected one synthetic off-air effect")
            return
        }
        #expect(receipt.postRevisions == .init(sourceGeneration: 1, controlEpoch: 3, shotRevision: 4))
        #expect(preparation.request == nil && preparation.receipt == receipt)
        #expect(sink.appliedReceipts == [receipt])
        guard case .rejected(let reasons) = sink.prepare(request, preparation: &preparation, live: live, now: 11) else {
            Issue.record("A consumed request must not act twice")
            return
        }
        #expect(reasons.contains(.requestReplaced))
        #expect(sink.appliedReceipts.count == 1)
    }

    @Test(arguments: [DirectorAuthority.Event.manualCommand, .editLive(true), .pause,
        .operatorTake, .sourceRebound(.b), .stopShow, .policyChanged, .nominationChanged])
    func interventionRetiresQueuedSinkEffect(event: DirectorAuthority.Event) throws {
        var (preparation, request, before) = try context()
        var authority = before.authority
        authority.apply(event)
        let live = DirectorLiveState(authority: authority, program: before.program, preview: before.preview,
            revisions: before.revisions, routeGeneration: before.routeGeneration,
            sourceMissing: false, evidenceAvailable: true)
        var sink = SimulatedDirectorEffectSink(succeeds: true)
        guard case .rejected(let reasons) = sink.prepare(request, preparation: &preparation, live: live, now: 11) else {
            Issue.record("Retired authority acted through the sink")
            return
        }
        #expect(reasons.contains(.authorityRevoked))
        #expect(sink.appliedReceipts.isEmpty)
    }

    @Test func staleCallbackCannotDiscardReplacementRequest() throws {
        var (preparation, old, live) = try context()
        let replacement = preparation.propose(old.intent, maximumAge: 5, now: 11)
        let newer = try #require(replacement)
        var sink = SimulatedDirectorEffectSink(succeeds: true)
        #expect(sink.prepare(old, preparation: &preparation, live: live, now: 11) == .rejected([.requestReplaced]))
        #expect(preparation.request == newer)
        guard case .committed = sink.prepare(newer, preparation: &preparation, live: live, now: 11) else {
            Issue.record("Stale callback cancelled replacement work")
            return
        }
        #expect(sink.appliedReceipts.count == 1)
    }

    @Test func failedEffectIsTerminalAndDoesNotBecomeALaterSuccess() throws {
        var (preparation, request, live) = try context()
        var refusing = SimulatedDirectorEffectSink(succeeds: false)
        #expect(refusing.prepare(request, preparation: &preparation, live: live, now: 11) == .failed)
        #expect(preparation.request == nil && refusing.appliedReceipts.isEmpty)
        var succeeding = SimulatedDirectorEffectSink(succeeds: true)
        #expect(succeeding.prepare(request, preparation: &preparation, live: live, now: 11) == .rejected([.requestReplaced]))
        #expect(succeeding.appliedReceipts.isEmpty)
    }

    @Test(arguments: [Double.nan, .infinity, -1, 9, 16])
    func invalidBackwardAndExpiredEffectClocksFailClosed(now: Double) throws {
        var (preparation, request, live) = try context()
        var sink = SimulatedDirectorEffectSink(succeeds: true)
        guard case .rejected(let reasons) = sink.prepare(request, preparation: &preparation, live: live, now: now) else {
            Issue.record("An invalid clock acted through the sink")
            return
        }
        #expect(reasons.contains(.expired) && sink.appliedReceipts.isEmpty)
    }

    @Test func everySyntheticFixtureUsesTheInjectedSink() {
        for fixture in DirectorReplayFixtures.all {
            var calls = 0
            let report = DirectorReplay.run(fixture, parameters: .policyStudy, maximumProposalAge: 5,
                maximumEvidenceAge: 5, readinessParameters: .replayStudy, sinkFactory: { succeeds in
                    calls += 1
                    return SimulatedDirectorEffectSink(succeeds: succeeds)
                })
            #expect(calls == 1)
            #expect(report.preparationsCommitted == 1)
            #expect(report.staleEffectsCommitted == 0 && report.directorCuts == 0)
            #expect(report.evidence == .synthetic)
        }
    }

    @Test(arguments: [false, true])
    func assistTakeStartsFreshWithoutPausingAndRetiresOldEffect(refused: Bool) {
        let action: DirectorReplay.Event.Action = refused ? .refusedOperatorTake : .operatorTake
        let next: ChannelID = refused ? .b : .a
        let fixture = DirectorReplay.Fixture(name: "Assist N1 synthetic", duration: 10, events: [
            .init(at: 1, action: .render(channel: .b)),
            .init(at: 1, action: .subject(channel: .b, present: true, identity: .confirmed,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 2, action: .directorAttempt(id: "old", delay: 3, succeeds: true)),
            .init(at: 3, action: action),
            .init(at: 4, action: .render(channel: next)),
            .init(at: 4, action: .subject(channel: next, present: true, identity: .confirmed,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 4.5, action: .directorAttempt(id: "fresh", delay: 0, succeeds: true))])
        // The fixture isolates N1 from repetition policy: the new Preview
        // was just on Program, so it explicitly supplies a zero repeat window.
        let policy = DirectorShotPolicy.Parameters(minimumShotDuration: 0, maximumShotDuration: 30,
            wideCadence: 60, repetitionWindow: 0, maximumMovement: 0.1, cutOnMotionAllowed: false)
        let report = DirectorReplay.run(fixture, parameters: policy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy)
        #expect(!report.finalPaused && report.finalLevel == .assist)
        #expect(report.operatorCuts == (refused ? 0 : 1))
        #expect(report.preparationsCommitted == 1 && report.rejectedAttempts == 1)
        #expect(report.staleEffectsCommitted == 0 && report.directorCuts == 0)
    }
    private struct DeliberatelyFaultySink: DirectorEffectSink {
        mutating func prepare(_ request: DirectorPreparation.Request,
                              preparation: inout DirectorPreparation,
                              live: DirectorLiveState, now: TimeInterval) -> DirectorPreparationEffect {
            // Fault injection deliberately bypasses every lease/context check.
            let before = request.intent.revisions
            return .committed(.init(requestID: request.id, intent: request.intent,
                postRevisions: .init(sourceGeneration: before.sourceGeneration,
                    controlEpoch: before.controlEpoch + 1, shotRevision: before.shotRevision + 1)))
        }
    }

    @Test func independentAuditDetectsASinkThatLiesAboutAStaleCommit() {
        let fixture = DirectorReplay.Fixture(name: "deliberate synthetic validator fault", duration: 10, events: [
            .init(at: 1, action: .render(channel: .b)),
            .init(at: 1, action: .subject(channel: .b, present: true, identity: .confirmed,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 2, action: .directorAttempt(id: "stale", delay: 3, succeeds: true)),
            .init(at: 3, action: .manualCommand)])
        let report = DirectorReplay.run(fixture, parameters: .policyStudy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy,
            sinkFactory: { _ in DeliberatelyFaultySink() })
        #expect(report.preparationsCommitted == 1 && report.staleEffectsCommitted == 1)
        #expect(report.directorCuts == 0 && report.evidence == .synthetic)
    }

    @Test func negativeOriginClockCannotActEvenWhenOrdered() throws {
        var (preparation, original, live) = try context()
        let proposal = try #require(DirectorProposal(target: .b, preview: .b,
            shot: original.intent.shot, reason: "negative synthetic clock",
            authorityEpoch: original.intent.authorityEpoch, revisions: original.intent.revisions,
            routeGeneration: original.intent.routeGeneration, createdAt: -3))
        let proposed = preparation.propose(proposal, maximumAge: 5, now: -2)
        let request = try #require(proposed)
        var sink = SimulatedDirectorEffectSink(succeeds: true)
        #expect(sink.prepare(request, preparation: &preparation, live: live, now: -1) == .rejected([.expired]))
        #expect(sink.appliedReceipts.isEmpty)
    }

    private enum ReceiptFault: CaseIterable { case wrongRequest, programTarget, unchangedRevisions }
    private struct WrongReceiptSink: DirectorEffectSink {
        let fault: ReceiptFault
        mutating func prepare(_ request: DirectorPreparation.Request,
                              preparation: inout DirectorPreparation,
                              live: DirectorLiveState, now: TimeInterval) -> DirectorPreparationEffect {
            var intent = request.intent
            if fault == .programTarget {
                guard let wrong = DirectorProposal(target: live.program, preview: live.program,
                    shot: intent.shot, reason: intent.reason, authorityEpoch: intent.authorityEpoch,
                    revisions: intent.revisions, routeGeneration: intent.routeGeneration,
                    createdAt: intent.createdAt) else { return .failed }
                intent = wrong
            }
            let before = request.intent.revisions
            return .committed(.init(requestID: fault == .wrongRequest ? UUID() : request.id,
                intent: intent, postRevisions: fault == .unchangedRevisions ? before :
                    .init(sourceGeneration: before.sourceGeneration, controlEpoch: before.controlEpoch + 1,
                          shotRevision: before.shotRevision + 1)))
        }
    }

    @Test(arguments: ReceiptFault.allCases)
    private func independentAuditDetectsUnrelatedAndMalformedReceipts(fault: ReceiptFault) {
        let fixture = DirectorReplay.Fixture(name: "synthetic receipt fault", duration: 3, events: [
            .init(at: 1, action: .render(channel: .b)),
            .init(at: 1, action: .subject(channel: .b, present: true, identity: .confirmed,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 2, action: .directorAttempt(id: "valid", delay: 0, succeeds: true))])
        let report = DirectorReplay.run(fixture, parameters: .policyStudy, maximumProposalAge: 5,
            maximumEvidenceAge: 5, readinessParameters: .replayStudy,
            sinkFactory: { _ in WrongReceiptSink(fault: fault) })
        #expect(report.preparationsCommitted == 1 && report.staleEffectsCommitted == 1)
        #expect(report.directorCuts == 0 && report.evidence == .synthetic)
    }

}
