import Foundation
import Testing
@testable import Alfie

struct DirectorTakePermitTests {
    private func prerequisites(_ levels: Set<DirectorAuthority.Level> = [.auto, .backup]) -> DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true, qualifiedLevels: levels)
    }
    private func authority(_ level: DirectorAuthority.Level = .auto) -> DirectorAuthority {
        var a = DirectorAuthority(reviewPolicy: .conservative)
        a.apply(.enable(level), prerequisites: prerequisites([.assist, .auto, .backup]))
        return a
    }
    private func state(_ a: DirectorAuthority? = nil, program: ChannelID = .a, preview: ChannelID? = .b,
                       route: UInt64 = 1, revisions: ChannelRevisions? = .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3),
                       levels: Set<DirectorAuthority.Level> = [.auto, .backup], policy: UInt64 = 1,
                       nomination: UInt64 = 1, missing: Bool = false, ready: Bool = true,
                       gesture: Bool = false) -> DirectorTakeState {
        .init(world: .init(authority: a ?? authority(), program: program, preview: preview,
                          revisions: revisions, routeGeneration: route, sourceMissing: missing,
                          policyRevision: policy, nominationRevision: nomination, evidenceAvailable: true),
              prerequisites: prerequisites(levels), cutReadiness: .init(reasons: ready ? [] : [.identityUncertain]),
              operatorGestureInProgress: gesture)
    }
    @Test(arguments: [DirectorAuthority.Level.off, .suggest, .assist, .auto, .backup])
    func onlyQualifiedCuttingLevelsIssue(level: DirectorAuthority.Level) {
        var issuer = TakePermitIssuer()
        #expect((issuer.issue(live: state(authority(level)), now: 10, validity: 2) != nil) == DirectorAuthority.cuts(level))
        #expect(issuer.issue(live: state(authority(level), levels: []), now: 10, validity: 2) == nil)
    }
    @Test func consumptionIsOneShotAndStaleCallbackCannotCancelReplacement() throws {
        var issuer = TakePermitIssuer()
        let old = try #require({ issuer.issue(live: state(), now: 10, validity: 2) }())
        let replacement = try #require({ issuer.issue(live: state(), now: 10, validity: 2) }())
        #expect(old != replacement)
        issuer.discard(old)
        #expect(issuer.consume(old, live: state(), now: 10) == .refused(.replacedOrConsumed))
        #expect(issuer.pending == replacement)
        #expect(issuer.consume(replacement, live: state(), now: 12) == .admitted(replacement))
        #expect(issuer.consume(replacement, live: state(), now: 12) == .refused(.replacedOrConsumed))
    }
    @Test(arguments: 0..<12)
    func everyBindingAndFinalSafetyGateIsRechecked(index: Int) throws {
        var issuer = TakePermitIssuer()
        let permit = try #require({ issuer.issue(live: state(), now: 10, validity: 2) }())
        var a = authority()
        a.apply(.enable(.auto), prerequisites: prerequisites())
        let altered: DirectorTakeState
        switch index {
        case 0: altered = state(a)
        case 1: altered = state(program: .b, preview: .a)
        case 2: altered = state(route: 2)
        case 3: altered = state(revisions: .init(sourceGeneration: 2, controlEpoch: 2, shotRevision: 3))
        case 4: altered = state(revisions: .init(sourceGeneration: 1, controlEpoch: 3, shotRevision: 3))
        case 5: altered = state(revisions: .init(sourceGeneration: 1, controlEpoch: 2, shotRevision: 4))
        case 6: altered = state(levels: [])
        case 7: altered = state(policy: 2)
        case 8: altered = state(nomination: 2)
        case 9: altered = state(missing: true)
        case 10: altered = state(ready: false)
        default: altered = state(gesture: true)
        }
        if case .admitted = issuer.consume(permit, live: altered, now: 11) { Issue.record("Mismatched binding admitted") }
        #expect(issuer.consume(permit, live: state(), now: 11) == .refused(.replacedOrConsumed))
    }
    @Test(arguments: [Double.nan, .infinity, -1, 9, 12.01])
    func invalidOrExpiredEffectClocksConsumeTheLease(now: Double) throws {
        var issuer = TakePermitIssuer()
        let permit = try #require({ issuer.issue(live: state(), now: 10, validity: 2) }())
        if case .admitted = issuer.consume(permit, live: state(), now: now) { Issue.record("Invalid clock admitted") }
        #expect(issuer.pending == nil)
    }
    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidDurationsNeverIssue(duration: Double) {
        var issuer = TakePermitIssuer()
        #expect(issuer.issue(live: state(), now: 10, validity: duration) == nil)
    }
    @Test(arguments: [DirectorAuthority.Level.auto, .backup])
    func operatorNudgeRetiresWithoutPauseAndHoldsFullDuration(level: DirectorAuthority.Level) throws {
        var a = authority(level)
        var issuer = TakePermitIssuer()
        let before = try #require({ issuer.issue(live: state(a), now: 10, validity: 100) }())
        let epoch = a.epoch
        let transition = a.apply(.operatorTake, takeTiming: .init(now: 11, minimumShotDuration: 5))
        #expect(transition.cancellations == [.proposal, .prepare, .take])
        #expect(!a.paused && a.mayPrepare && a.epoch != epoch)
        #expect(!a.authorizes(a.epoch, action: .take))
        #expect(!a.mayIssueTake(at: 15.999))
        #expect(issuer.issue(live: state(a), now: 15.999, validity: 1) == nil)
        if case .admitted = issuer.consume(before, live: state(a), now: 16) { Issue.record("Pre-Take permit survived") }
        #expect(issuer.issue(live: state(a), now: 16, validity: 0) != nil)
        a.apply(.operatorTake, takeTiming: .init(now: 16, minimumShotDuration: 5))
        #expect(!a.mayIssueTake(at: 20.999) && a.mayIssueTake(at: 21))
    }
    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidNudgeParametersInhibitUntilFreshGrant(duration: Double) {
        var a = authority()
        a.apply(.operatorTake, takeTiming: .init(now: 10, minimumShotDuration: duration))
        #expect(!a.paused && a.mayPrepare && !a.mayIssueTake(at: 100))
        a.apply(.handToAlfie, prerequisites: prerequisites())
        #expect(a.mayIssueTake(at: 100))
    }
    @Test func backwardNudgeAndOverflowFailClosed() {
        var a = authority()
        a.apply(.operatorTake, takeTiming: .init(now: 10, minimumShotDuration: 5))
        a.apply(.operatorTake, takeTiming: .init(now: 9, minimumShotDuration: 0))
        #expect(!a.mayIssueTake(at: 100) && !a.paused)
        a.apply(.handToAlfie, prerequisites: prerequisites())
        a.apply(.operatorTake, takeTiming: .init(now: Double.greatestFiniteMagnitude, minimumShotDuration: Double.greatestFiniteMagnitude))
        #expect(!a.mayIssueTake(at: Double.greatestFiniteMagnitude))
    }
    @Test(arguments: [DirectorAuthority.Event.manualCommand, .editLive(true), .pause, .sourceLoss(.a), .admissionLost, .stopShow])
    func interventionPreventsPermitConsumption(event: DirectorAuthority.Event) throws {
        var a = authority()
        var issuer = TakePermitIssuer()
        let permit = try #require({ issuer.issue(live: state(a), now: 10, validity: 2) }())
        a.apply(event)
        if case .admitted = issuer.consume(permit, live: state(a), now: 11) { Issue.record("Takeover admitted a cut") }
    }
}
