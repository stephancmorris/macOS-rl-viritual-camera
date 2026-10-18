import Foundation
import Testing
@testable import Alfie

/// Synthetic fault permutations only. R1/R2 and live qualification stay open.
nonisolated struct DirectorBackupFallbackPolicyTests {
    private var prerequisites: DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist, .auto, .backup])
    }
    private func authority(_ level: DirectorAuthority.Level = .backup) -> DirectorAuthority {
        var a = DirectorAuthority(reviewPolicy: .conservative)
        a.apply(.enable(level), prerequisites: prerequisites)
        return a
    }
    private func snapshot(_ a: DirectorAuthority, now: Double = 10, deadline: Double = 12,
                          frame: Double? = 10, program: ChannelID = .a, preview: ChannelID? = .b,
                          generation: UInt64 = 1, shot: UInt64 = 3, route: UInt64 = 1,
                          policy: UInt64 = 1, nomination: UInt64 = 1, missing: Bool = false,
                          qualified: Bool = true, verified: Bool = true, wide: Bool = true,
                          eligible: Bool = true, gesture: Bool = false, holding: Bool = true,
                          programMissing: Bool = true, outputHealthy: Bool = true) -> BackupFallbackPolicy.Snapshot {
        var p = prerequisites
        if !outputHealthy {
            p = .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: false,
                      outputHealthy: false, admissionCurrent: true, qualifiedLevels: [.backup])
        }
        return .init(live: .init(authority: a, program: program, preview: preview,
            revisions: .init(sourceGeneration: generation, controlEpoch: 2, shotRevision: shot),
            routeGeneration: route, sourceMissing: missing, policyRevision: policy, nominationRevision: nomination,
            evidenceAvailable: true),
            prerequisites: p, fallbackQualified: qualified, verifiedSafeWide: verified,
            previewShot: .init(preset: .stage(wide ? .wide : .waistUp)), previewFrameAt: frame,
            technicalTakeEligible: eligible, operatorGestureInProgress: gesture,
            programStillMissing: programMissing, routerHolding: holding, holdDeadline: deadline)
    }
    private func begin(_ p: inout BackupFallbackPolicy, _ a: inout DirectorAuthority) throws -> BackupFallbackPolicy.Permit {
        let before = snapshot(a)
        let permit = p.sourceLoss(.a, authority: &a, snapshot: before, now: 10, maximumFrameAge: 0.5)
        return try #require(permit)
    }
    @Test func oneFallbackIsPreviewOnlyInsideTheOriginalHoldAndAuthorityStaysPaused() throws {
        var a = authority(), p = BackupFallbackPolicy()
        let permit = try begin(&p, &a)
        #expect(a.paused && !a.healthy && permit.epoch == a.epoch && permit.preview == .b)
        #expect(!a.mayIssueTake(at: 10))
        #expect(p.consume(permit, snapshot: snapshot(a, frame: 11.5), now: 11.999, maximumFrameAge: 0.5) == permit)
        #expect(p.consume(permit, snapshot: snapshot(a), now: 11.999, maximumFrameAge: 0.5) == nil)
        #expect(a.paused && p.pending == nil)
        let after = snapshot(a, frame: 11.999)
        #expect(p.sourceLoss(.a, authority: &a, snapshot: after, now: 11.999, maximumFrameAge: 0.5) == nil)
    }
    @Test(arguments: [DirectorAuthority.Level.off, .suggest, .assist, .auto])
    func everyOtherLevelKeepsItsOrdinaryFaultTransition(level: DirectorAuthority.Level) {
        var a = authority(level), expected = a, p = BackupFallbackPolicy()
        let before = snapshot(a)
        expected.apply(.sourceLoss(.a))
        #expect(p.sourceLoss(.a, authority: &a, snapshot: before, now: 10, maximumFrameAge: 0.5) == nil)
        #expect(a == expected && p.pending == nil)
    }
    @Test(arguments: ["stale", "bothLost", "unverified", "tight", "unqualified", "notEligible", "gesture", "standby", "output", "wrongInput"])
    func unsafeFaultsNeverIssue(reason: String) {
        var a = authority(), p = BackupFallbackPolicy()
        let s = snapshot(a, frame: reason == "stale" ? 9 : 10, missing: reason == "bothLost",
            qualified: reason != "unqualified", verified: reason != "unverified", wide: reason != "tight",
            eligible: reason != "notEligible", gesture: reason == "gesture", holding: reason != "standby",
            outputHealthy: reason != "output")
        #expect(p.sourceLoss(reason == "wrongInput" ? .b : .a, authority: &a, snapshot: s, now: 10, maximumFrameAge: 0.5) == nil)
        #expect(a.paused)
    }
    @Test(arguments: 0..<12)
    func everyFinalBindingAndFaultConditionIsRechecked(index: Int) throws {
        var a = authority(), p = BackupFallbackPolicy()
        let permit = try begin(&p, &a)
        let s: BackupFallbackPolicy.Snapshot
        switch index {
        case 0: s = snapshot(a, program: .b, preview: .a)
        case 1: s = snapshot(a, generation: 2)
        case 2: s = snapshot(a, shot: 4)
        case 3: s = snapshot(a, route: 2)
        case 4: s = snapshot(a, policy: 2)
        case 5: s = snapshot(a, nomination: 2)
        case 6: s = snapshot(a, missing: true)
        case 7: s = snapshot(a, qualified: false)
        case 8: s = snapshot(a, verified: false)
        case 9: s = snapshot(a, programMissing: false)
        case 10: s = snapshot(a, outputHealthy: false)
        default: s = snapshot(a, deadline: 13)
        }
        #expect(p.consume(permit, snapshot: s, now: 10, maximumFrameAge: 0.5) == nil)
        #expect(p.pending == nil)
        #expect(p.consume(permit, snapshot: snapshot(a), now: 10, maximumFrameAge: 0.5) == nil)
    }
    @Test(arguments: [DirectorAuthority.Event.manualCommand, .operatorTake, .sourceRebound(.b), .sourceLoss(.b), .outputFault, .admissionLost, .healthRestored, .stopShow])
    func faultPermutationsNeverReviveAuthorityOrReuseThePermit(event: DirectorAuthority.Event) throws {
        var a = authority(), p = BackupFallbackPolicy()
        let permit = try begin(&p, &a)
        a.apply(event)
        #expect(p.consume(permit, snapshot: snapshot(a), now: 10, maximumFrameAge: 0.5) == nil)
        #expect(p.pending == nil)
    }
    @Test func preFaultNormalTakePermitIsRevoked() throws {
        var a = authority(), issuer = TakePermitIssuer(), fallback = BackupFallbackPolicy()
        let before = snapshot(a)
        let preState = DirectorTakeState(world: before.live, prerequisites: prerequisites,
            cutReadiness: .init(reasons: []), operatorGestureInProgress: false)
        let issued = issuer.issue(live: preState, now: 10, validity: 10)
        let ordinary = try #require(issued)
        _ = try begin(&fallback, &a)
        let after = DirectorTakeState(world: snapshot(a).live, prerequisites: prerequisites,
            cutReadiness: .init(reasons: []), operatorGestureInProgress: false)
        if case .admitted = issuer.consume(ordinary, live: after, now: 10) { Issue.record("Pre-fault permit survived") }
    }
    @Test(arguments: [Double.nan, .infinity, -1, 9, 12, 12.001])
    func neverFiresAtOrAfterStandbyOrWithAnInvalidClock(now: Double) throws {
        var a = authority(), p = BackupFallbackPolicy()
        let permit = try begin(&p, &a)
        #expect(p.consume(permit, snapshot: snapshot(a, frame: now), now: now, maximumFrameAge: 0.5) == nil)
        #expect(p.pending == nil && a.paused)
    }
    @Test func replacementFaultIsProtectedFromAStaleCallback() throws {
        var a = authority(), p = BackupFallbackPolicy()
        let old = try begin(&p, &a)
        a.apply(.healthRestored)
        a.apply(.handToAlfie, prerequisites: prerequisites)
        let replacement = try begin(&p, &a)
        #expect(p.consume(old, snapshot: snapshot(a), now: 10, maximumFrameAge: 0.5) == nil)
        #expect(p.pending == replacement)
        #expect(p.consume(replacement, snapshot: snapshot(a), now: 10, maximumFrameAge: 0.5) == replacement)
    }
    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidFreshnessConfigurationCannotIssue(value: Double) {
        var a = authority(), p = BackupFallbackPolicy()
        let before = snapshot(a)
        #expect(p.sourceLoss(.a, authority: &a, snapshot: before, now: 10, maximumFrameAge: value) == nil)
        #expect(a.paused && p.pending == nil)
    }
    @Test func missingFutureAndAgedPreviewFramesCannotExecuteAndFreshnessCannotBeLoosened() throws {
        for frame in [nil, 9.0, 10.1] as [Double?] {
            var a = authority(), p = BackupFallbackPolicy()
            let permit = try begin(&p, &a)
            #expect(p.consume(permit, snapshot: snapshot(a, frame: frame), now: 10, maximumFrameAge: 0.5) == nil)
        }
        var a = authority(), p = BackupFallbackPolicy()
        let permit = try begin(&p, &a)
        #expect(p.consume(permit, snapshot: snapshot(a), now: 11, maximumFrameAge: 2) == nil)
    }
}
