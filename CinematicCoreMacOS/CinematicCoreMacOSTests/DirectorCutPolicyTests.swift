import Foundation
import Testing
@testable import Alfie

/// Synthetic timelines only: these tests do not qualify automatic cuts.
nonisolated struct DirectorCutPolicyTests {
    private typealias P = DirectorShotPolicy
    private let wide = DirectorShot(preset: .stage(.wide))
    private let tight = DirectorShot(preset: .stage(.waistUp))

    private func prerequisites(_ levels: Set<DirectorAuthority.Level> = [.auto, .backup], healthy: Bool = true) -> DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: healthy, admissionCurrent: true, qualifiedLevels: levels)
    }
    private func authority(_ level: DirectorAuthority.Level = .auto) -> DirectorAuthority {
        var a = DirectorAuthority()
        a.apply(.enable(level), prerequisites: prerequisites([.assist, .auto, .backup]))
        return a
    }
    private func state(_ a: DirectorAuthority? = nil, program: ChannelID = .a, preview: ChannelID? = .b,
                       route: UInt64 = 1, revisions: ChannelRevisions? = .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3),
                       levels: Set<DirectorAuthority.Level> = [.auto, .backup], policy: UInt64 = 1,
                       nomination: UInt64 = 1, missing: Bool = false, ready: Bool = true,
                       gesture: Bool = false, evidence: Bool = true, healthy: Bool = true) -> DirectorTakeState {
        .init(world: .init(authority: a ?? authority(), program: program, preview: preview,
                          revisions: revisions, routeGeneration: route, sourceMissing: missing,
                          policyRevision: policy, nominationRevision: nomination, evidenceAvailable: evidence),
              prerequisites: prerequisites(levels, healthy: healthy), cutReadiness: .init(reasons: ready ? [] : [.identityUncertain]),
              operatorGestureInProgress: gesture)
    }
    private func style(minimum: Double = 5, preferred: Double = 10) -> DirectorStyle {
        .init(minimumShotDuration: minimum, preferredShotDuration: preferred, softMaximumShotDuration: 30,
              wideCadence: 20, repetitionWindow: 4, maximumMovement: 0.2,
              settleTime: 1, onAirMoveRate: 0.1, cutOnMotionAllowed: false)
    }
    private func candidate(channel: ChannelID = .b, isWide: Bool = false, confidence: Double = 0.9, movement: Double = 0) -> P.Candidate {
        .init(channel: channel, shot: isWide ? wide : tight, subjectConfidence: confidence, movement: movement, isWide: isWide)
    }
    private func timeline(now: Double = 10, started: Double = 0, lastWide: Double = 0, history: [P.History] = []) -> P.Timeline {
        .init(programShot: wide, programStartedAt: started, lastWideAt: lastWide,
              history: history, candidates: [], now: now)
    }
    private func decide(_ live: DirectorTakeState? = nil, now: Double = 10,
                        prepared: P.Candidate? = nil, identity: IdentityEvidence = .confirmed,
                        timeline t: P.Timeline? = nil, style s: DirectorStyle? = nil,
                        judge: any DirectorJudge = RuleJudge(), probability: Double? = nil) -> CutPolicy.Decision {
        CutPolicy.evaluate(live: live ?? state(), timeline: t ?? timeline(now: now), prepared: prepared ?? candidate(),
            programIdentity: identity, style: s ?? style(), evidenceRevision: 7, judge: judge,
            judgeMaximumAge: 1, minimumProbability: probability)
    }
    private func begin(_ notice: inout CutNotice, live: DirectorTakeState? = nil, now: Double = 10,
                       length: Double = 2, lateness: Double = 1) throws -> CutNotice.Token {
        let live = live ?? state()
        let token = notice.begin(decide(live, now: now), live: live, now: now,
                                 autoNoticeLength: length, maximumLateness: lateness)
        return try #require(token)
    }

    @Test func allThreeCutReasonsRespectMinimumDwell() {
        for identity in [IdentityEvidence.confirmed, .lost, .ambiguous] {
            #expect(decide(now: 4.999, identity: identity) == .abstain(.minimumDwell))
        }
        #expect(decide(now: 5) == .abstain(.nothingBetter))
        guard case .cut(let length) = decide(),
              case .cut(let uncertain) = decide(now: 5, identity: .lost) else {
            Issue.record("Expected preferred-length and uncertain-subject cuts"); return
        }
        #expect(length.reason == .preferredLength && uncertain.reason == .programUncertain)
        let t = P.Timeline(programShot: tight, programStartedAt: 15, lastWideAt: 0, history: [], candidates: [], now: 20)
        guard case .cut(let reminder) = decide(prepared: candidate(isWide: true), timeline: t) else {
            Issue.record("Expected a wide reminder before preferred dwell"); return
        }
        #expect(reminder.reason == .wideDue)
    }

    @Test(arguments: [DirectorAuthority.Level.off, .suggest, .assist, .auto, .backup])
    func qualifiedCuttingLevelsOnly(level: DirectorAuthority.Level) {
        let result = decide(state(authority(level)))
        if DirectorAuthority.cuts(level) {
            guard case .cut = result else { Issue.record("Qualified cut refused"); return }
        } else { #expect(result == .abstain(.authority)) }
        #expect(decide(state(authority(level), levels: [])) == .abstain(.authority))
    }

    @Test(arguments: [ChannelID.a, .b, .c, .d])
    func targetsOnlyTheCurrentPreview(channel: ChannelID) {
        let result = decide(prepared: candidate(channel: channel))
        if channel == .b {
            guard case .cut(let plan) = result else { Issue.record("Preview refused"); return }
            #expect(plan.preview == .b && plan.candidate.channel == .b)
        } else { #expect(result == .abstain(.notReady)) }
    }

    @Test(arguments: 0..<10)
    func missingSafetyFactsAlwaysAbstain(index: Int) {
        let live: DirectorTakeState
        switch index {
        case 0: live = state(preview: nil)
        case 1: live = state(preview: .a)
        case 2: live = state(revisions: nil)
        case 3: live = state(missing: true)
        case 4: live = state(ready: false)
        case 5: live = state(gesture: true)
        case 6: live = state(evidence: false)
        case 7: live = state(healthy: false)
        case 8:
            var a = authority(); a.apply(.manualCommand); live = state(a)
        default:
            var a = authority(); a.apply(.operatorTake, takeTiming: .init(now: 9, minimumShotDuration: 5)); live = state(a)
        }
        guard case .abstain = decide(live) else { Issue.record("Unsafe state admitted"); return }
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func malformedInputsFailClosed(value: Double) {
        #expect(decide(now: value) == .abstain(.invalidInput))
        #expect(decide(timeline: timeline(started: value)) == .abstain(.invalidInput))
        #expect(decide(timeline: timeline(lastWide: value)) == .abstain(.invalidInput))
        #expect(decide(timeline: timeline(history: [.init(shot: tight, endedAt: value)])) == .abstain(.invalidInput))
        #expect(decide(prepared: candidate(confidence: value)) == .abstain(.invalidInput))
        #expect(decide(prepared: candidate(movement: value)) == .abstain(.invalidInput))
        #expect(decide(style: style(minimum: value)) == .abstain(.invalidInput))
        #expect(decide(probability: value) == .abstain(.invalidInput))
    }

    @Test func repetitionAndMovementAllowAbstentionEvenPastSoftMaximum() {
        #expect(decide(prepared: candidate(movement: 0.21)) == .abstain(.notReady))
        #expect(decide(now: 100, timeline: timeline(now: 100, history: [.init(shot: tight, endedAt: 99)])) == .abstain(.judge))
        #expect(decide(now: 100, judge: RecordedJudge(records: [:])) == .abstain(.judge))
        #expect(decide(prepared: candidate(confidence: 1.1)) == .abstain(.invalidInput))
        #expect(decide(prepared: .init(channel: .b, shot: tight, subjectConfidence: 0.9, movement: 0, isWide: true)) == .abstain(.invalidInput))
    }

    @Test func judgeCannotInventOrRetargetAShot() {
        let forbidden = DirectorJudgement.Ranked(candidate: candidate(channel: .a), probability: 1, reason: "synthetic")
        #expect(decide(judge: RecordedJudge(records: [7: .ranked([forbidden])])) == .abstain(.judge))
        let low = DirectorJudgement.Ranked(candidate: candidate(), probability: 0.2, reason: "synthetic")
        #expect(decide(judge: RecordedJudge(records: [7: .ranked([low])]), probability: 0.8) == .abstain(.judge))
    }

    @Test func noticeKeepsItsDeadlineAcrossObservationRefreshesAndFiresOnce() throws {
        var notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice)
        #expect(notice.consoleNextCut(now: 10)?.countdown == 2)
        #expect(notice.begin(decide(now: 11), live: state(), now: 11, autoNoticeLength: 2, maximumLateness: 1) == token)
        #expect(notice.fire(token, decision: decide(now: 11), live: state(), now: 11, permitValidity: 1, issuer: &issuer) == nil)
        let refreshed = decide(now: 12, prepared: candidate(confidence: 0.8, movement: 0.1))
        let issued = notice.fire(token, decision: refreshed, live: state(), now: 12, permitValidity: 1, issuer: &issuer)
        let permit = try #require(issued)
        #expect(permit.preview == .b && notice.pending == nil)
        #expect(issuer.consume(permit, live: state(), now: 12) == .admitted(permit))
        #expect(notice.fire(token, decision: refreshed, live: state(), now: 12, permitValidity: 1, issuer: &issuer) == nil)
        #expect(issuer.consume(permit, live: state(), now: 12) == .refused(.replacedOrConsumed))
    }

    @Test func backupShowsNextCutWithoutACountdown() throws {
        let live = state(authority(.backup))
        var notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice, live: live)
        let line = try #require(notice.consoleNextCut(now: 10))
        #expect(token.deadline == 10 && line.input == .b && line.countdown == nil && line.cancellable)
        #expect(notice.fire(token, decision: decide(live), live: live, now: 10, permitValidity: 0, issuer: &issuer) != nil)
    }

    @Test(arguments: [10.0, 11.999, 12.0])
    func syntheticCancelReplayAlwaysWinsDuringNotice(now: Double) throws {
        var a = authority(), notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice, live: state(a))
        let cancelled = notice.cancel(token, authority: &a, now: now, minimumShotDuration: 5)
        #expect(cancelled && !a.paused && a.mayPrepare)
        #expect(notice.fire(token, decision: decide(state(a), now: now), live: state(a), now: now,
                            permitValidity: 1, issuer: &issuer) == nil)
        #expect(!a.mayIssueTake(at: now + 4.999) && a.mayIssueTake(at: now + 5))
        #expect(decide(state(a), now: now + 4.999) == .abstain(.authority))
        #expect(issuer.pending == nil && notice.pending == nil)
    }

    @Test(arguments: [DirectorAuthority.Level.auto, .backup])
    func syntheticNudgeReplayRevokesDeadlineAndInhibitsAllCuts(level: DirectorAuthority.Level) throws {
        var a = authority(level), notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice, live: state(a))
        a.apply(.operatorTake, takeTiming: .init(now: 10, minimumShotDuration: 5))
        for now in [10.0, 12.0, 14.999] {
            let live = state(a)
            #expect(decide(live, now: now) == .abstain(.authority))
            #expect(notice.fire(token, decision: decide(live, now: now), live: live, now: now,
                                permitValidity: 1, issuer: &issuer) == nil)
        }
        #expect(issuer.pending == nil)
    }

    @Test(arguments: 0..<11)
    func deadlineRevalidatesEveryBindingAndSafetyGate(index: Int) throws {
        var notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice)
        let changed: DirectorTakeState
        switch index {
        case 0: changed = state(program: .b, preview: .a)
        case 1: changed = state(route: 2)
        case 2: changed = state(revisions: .init(sourceGeneration: 2, controlEpoch: 2, shotRevision: 3))
        case 3: changed = state(revisions: .init(sourceGeneration: 1, controlEpoch: 3, shotRevision: 3))
        case 4: changed = state(revisions: .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 4))
        case 5: changed = state(policy: 2)
        case 6: changed = state(nomination: 2)
        case 7: changed = state(levels: [])
        case 8: changed = state(ready: false)
        case 9: changed = state(gesture: true)
        default: changed = state(evidence: false)
        }
        #expect(notice.fire(token, decision: decide(changed, now: 12), live: changed, now: 12,
                            permitValidity: 1, issuer: &issuer) == nil)
        #expect(notice.pending == nil && issuer.pending == nil)
        #expect(notice.fire(token, decision: decide(now: 12), live: state(), now: 12,
                            permitValidity: 1, issuer: &issuer) == nil)
    }

    @Test func replacementIsProtectedFromStaleCancelAndDeadlineCallbacks() throws {
        var a = authority(), notice = CutNotice(), issuer = TakePermitIssuer()
        let old = try begin(&notice, live: state(a))
        a.apply(.operatorTake, takeTiming: .init(now: 10, minimumShotDuration: 0))
        let replacement = try begin(&notice, live: state(a))
        let epoch = a.epoch
        #expect(!notice.cancel(old, authority: &a, now: 11, minimumShotDuration: 5))
        #expect(a.epoch == epoch && notice.pending == replacement)
        #expect(notice.fire(old, decision: decide(state(a), now: 12), live: state(a), now: 12,
                            permitValidity: 1, issuer: &issuer) == nil)
        #expect(notice.pending == replacement)
    }

    @Test(arguments: [Double.nan, .infinity, -1, 9, 13.01])
    func invalidBackwardAndExpiredDeadlinesRetireWithoutRetry(now: Double) throws {
        var notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice)
        #expect(notice.fire(token, decision: decide(now: now), live: state(), now: now,
                            permitValidity: 1, issuer: &issuer) == nil)
        #expect(notice.pending == nil && issuer.pending == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidNoticeParametersFailClosed(value: Double) {
        var notice = CutNotice()
        #expect(notice.begin(decide(), live: state(), now: 10, autoNoticeLength: value, maximumLateness: 1) == nil)
        #expect(notice.begin(decide(), live: state(), now: 10, autoNoticeLength: 2, maximumLateness: value) == nil)
        #expect(notice.pending == nil)
    }

    @Test func cancellationNeverResumesTakeoverOrTouchesReplacementAuthority() throws {
        var a = authority(), notice = CutNotice()
        let token = try begin(&notice, live: state(a))
        a.apply(.manualCommand)
        let epoch = a.epoch
        #expect(notice.cancel(token, authority: &a, now: 11, minimumShotDuration: 5))
        #expect(a.paused && a.epoch == epoch)
        #expect(!a.mayIssueTake(at: 100))
    }
    @Test func backwardsClockAfterAnEarlyTickRevokesNoticeAndCancellationInhibits() throws {
        var notice = CutNotice(), issuer = TakePermitIssuer()
        let token = try begin(&notice)
        #expect(notice.fire(token, decision: decide(now: 11), live: state(), now: 11,
                            permitValidity: 1, issuer: &issuer) == nil)
        #expect(notice.fire(token, decision: decide(now: 10.5), live: state(), now: 10.5,
                            permitValidity: 1, issuer: &issuer) == nil)
        #expect(notice.pending == nil)
        var a = authority()
        let second = try begin(&notice, now: 12)
        #expect(notice.cancel(second, authority: &a, now: 11, minimumShotDuration: 5))
        #expect(a.nudgeHold == .unavailable && !a.mayIssueTake(at: 100))
    }

}
