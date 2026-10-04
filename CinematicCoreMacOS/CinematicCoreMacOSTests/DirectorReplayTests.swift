import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorReplayTests {
    @Test func fiveSyntheticTimelines() {
        let reports = DirectorReplayFixtures.all.map {
            DirectorReplay.run($0, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        }
        #expect(reports.count == 5)
        for report in reports {
            #expect(report.programChangesWithoutAuthority == 0)
            #expect(report.proposalsMadeWhilePaused == 0)
            #expect(report.cutsPerMinute >= 0)
        }
        #expect(reports[0].labelledSubjectProposals == 1)
        #expect(reports[0].staleProposalsRejected[.shotChangedByOperator] == nil)
        #expect(reports[0].proposalCount == 1)
        #expect(reports[1].labelledSubjectProposals == 1)
        #expect(reports[2].wrongSubjectProposals == 1)
        #expect(reports[2].labelledSubjectProposals == 1)
        #expect(reports[3].staleProposalsRejected[.sourceRestarted] == 1)
        #expect(reports[4].manualOverridesHonoured == 1)
        #expect(reports[4].manualOverrideLatencies.count == 1)
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
        let a = DirectorReplay.run(ordered, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        let b = DirectorReplay.run(pausedFirst, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(a.proposalCount == 1)
        #expect(b.proposalCount == 0)
        #expect(a.proposalsMadeWhilePaused == 0)
        let render = DirectorReplay.Fixture(name: "render", duration: 20,
            events: ready(9) + [.init(at: 10, action: .render(channel: .b))])
        let result = DirectorReplay.run(render, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(result.proposalCount == 1)
        #expect(result.staleProposalsRejected[.shotChangedByOperator] == nil)
    }

    @Test func delayedEffectManualOverrideAndDuplicateCallback() {
        let fixture = DirectorReplay.Fixture(name: "stale shadow", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "a", delay: 3, succeeds: true)),
                .init(at: 11, action: .manualCommand), .init(at: 14, action: .effect(id: "a"))])
        let report = DirectorReplay.run(fixture, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
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
        let failure = DirectorReplay.run(failed, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(failure.failedEffects == 1)
        #expect(failure.duplicateCallbacks == 1)
        #expect(failure.directorCuts == 0)
        let stopped = DirectorReplay.Fixture(name: "stopped", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "stopped", delay: 3, succeeds: true)),
                .init(at: 11, action: .stop), .init(at: 12, action: .fault(.b)),
                .init(at: 13, action: .render(channel: .b))])
        let stop = DirectorReplay.run(stopped, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(stop.staleProposalsRejected[.authorityRevoked] == 1)
        #expect(stop.rejectedAttempts == 1)
        #expect(stop.directorCuts == 0)
        let faulted = DirectorReplay.Fixture(name: "faulted", duration: 20,
            events: ready(9) + [.init(at: 10, action: .directorAttempt(id: "faulted", delay: 3, succeeds: true)),
                .init(at: 11, action: .fault(.b))])
        let fault = DirectorReplay.run(faulted, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(fault.staleProposalsRejected[.sourceRestarted] == 1)
        #expect(fault.rejectedAttempts == 1)
        let bad = DirectorReplay.Fixture(name: "clock anomalies", duration: 20,
            events: ready(9) + [.init(at: .nan, action: .manualCommand),
                .init(at: 10, action: .directorAttempt(id: "bad", delay: .nan, succeeds: true))])
        let anomalies = DirectorReplay.run(bad, parameters: .proposed, maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(anomalies.clockAnomalies == 2)
        #expect(anomalies.rejectedAttempts == 1)
        let invalidExpiry = DirectorReplay.run(failed, parameters: .proposed,
            maximumProposalAge: .infinity, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
        #expect(invalidExpiry.clockAnomalies == 1)
        #expect(invalidExpiry.proposalCount == 0)
    }
}


extension DirectorReplayTests {
    private func replay(_ events: [DirectorReplay.Event], duration: Double = 120) -> DirectorReplay.Report {
        DirectorReplay.run(.init(name: "lifecycle review", duration: duration, events: events),
            parameters: .init(minimumShotDuration: 20, maximumShotDuration: 90,
                wideCadence: 120, repetitionWindow: 20, maximumMovement: 0.1, cutOnMotionAllowed: false),
            maximumProposalAge: 5, maximumEvidenceAge: 5, readinessParameters: .init(minimumIdentityConfidence: 0.7,
                minimumSettledTime: 0.2, maximumMotion: 0.1, cutOnMotionAllowed: false))
    }

    @Test(arguments: [DirectorReplay.Event.Action.manualCommand, .refusedOperatorTake,
        .operatorTake, .editLive(true), .identityLoss(.b), .sourceRebind(.b), .outputFault,
        .admissionLoss, .policyChange, .nominationChange, .stop])
    func delayedPreparationCannotSurviveIntervention(action: DirectorReplay.Event.Action) {
        let report = replay(ready(1) + [
            .init(at: 2, action: .directorAttempt(id: "queued", delay: 3, succeeds: true)),
            .init(at: 3, action: action), .init(at: 4, action: .editLive(false)),
            .init(at: 4, action: .healthRestored), .init(at: 6, action: .effect(id: "queued"))])
        #expect(report.preparationsCommitted == 0 && report.staleEffectsCommitted == 0)
        #expect(report.rejectedAttempts == 1 && report.directorCuts == 0)
        #expect(report.programChangesWithoutAuthority == 0)
        #expect(report.finalPaused || report.finalLevel == .off)
        if case .operatorTake = action { #expect(report.operatorCuts == 1) }
        if case .refusedOperatorTake = action { #expect(report.operatorCuts == 0 && report.operatorTakeAttempts == 1) }
    }

    @Test func delayedAcknowledgementAfterReplacementAndDuplicate() {
        let report = replay(ready(1) + [
            .init(at: 2, action: .directorAttempt(id: "old", delay: 0, succeeds: true, acknowledgementDelay: 4)),
            .init(at: 3, action: .manualCommand), .init(at: 4, action: .resume),
            .init(at: 4, action: .render(channel: .b)),
            .init(at: 5, action: .directorAttempt(id: "new", delay: 0, succeeds: true)),
            .init(at: 7, action: .acknowledgement(id: "old")),
            .init(at: 8, action: .acknowledgement(id: "new"))])
        #expect(report.preparationsCommitted == 2)
        #expect(report.acknowledgementsAccepted == 1 && report.acknowledgementsRejected == 3)
        #expect(report.staleEffectsCommitted == 0 && report.directorCuts == 0)
    }

    @Test func compositionPersistsWithoutReapplyingAndGapWithdrawsReadiness() {
        let report = replay(ready(1) + [
            .init(at: 2, action: .directorAttempt(id: "once", delay: 0, succeeds: true)),
            .init(at: 3, action: .navigation), .init(at: 4, action: .cosmeticEdit),
            .init(at: 10, action: .evidenceGap(true)), .init(at: 20, action: .render(channel: .b)),
            .init(at: 21, action: .evidenceGap(false)),
            .init(at: 21, action: .subject(channel: .b, present: true, confidence: 0.95,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 50, action: .render(channel: .b)),
            .init(at: 50, action: .subject(channel: .b, present: true, confidence: 0.95,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 51, action: .directorAttempt(id: "reapply", delay: 0, succeeds: true))])
        #expect(report.proposalCount == 1 && report.preparationsCommitted == 1)
        #expect(report.acknowledgementsAccepted == 1 && report.readyEvaluations > 0)
        #expect(!report.finalPaused && report.staleEffectsCommitted == 0)
    }

    @Test func earlyMovingPreparationAndLegalManualMovingTake() {
        let events: [DirectorReplay.Event] = [.init(at: 1, action: .render(channel: .b)),
            .init(at: 1, action: .subject(channel: .b, present: true, confidence: 0.95,
                intended: true, framingReady: false, movement: 0.5)),
            .init(at: 2, action: .directorAttempt(id: "moving", delay: 0, succeeds: true)),
            .init(at: 3, action: .navigation)]
        let preparing = replay(events)
        #expect(preparing.preparationsCommitted == 1 && preparing.readyEvaluations == 0)
        let manual = replay(events + [.init(at: 4, action: .operatorTake)])
        #expect(manual.operatorCuts == 1 && manual.directorCuts == 0)
        // Below minimum Director dwell remains a legal manual R2 cut.
        #expect(manual.minimumDurationViolations == 1)
    }

    @Test func stopRestartResumeAndUnavailableLevels() {
        let off = replay(ready(1) + [.init(at: 2, action: .stop), .init(at: 3, action: .restart),
            .init(at: 4, action: .resume), .init(at: 5, action: .enable(.autoDirect))])
        #expect(off.finalLevel == .off && off.autoDirectRefusals == 1)
        let suggest = replay([.init(at: 0, action: .enable(.suggest))] + ready(1) + [
            .init(at: 2, action: .directorAttempt(id: "suggest", delay: 0, succeeds: true)),
            .init(at: 3, action: .enable(.autoDirect))])
        #expect(suggest.preparationsCommitted == 0 && suggest.rejectedAttempts == 1)
        #expect(suggest.finalLevel == .suggest && suggest.autoDirectRefusals == 1)
        let unhealthy = replay(ready(1) + [.init(at: 2, action: .source(channel: .b, missing: true)),
            .init(at: 3, action: .healthRestored), .init(at: 4, action: .resume)])
        #expect(unhealthy.finalPaused && unhealthy.preparationsCommitted == 0)
        let resume = replay(ready(1) + [.init(at: 2, action: .identityLoss(.b)),
            .init(at: 3, action: .healthRestored), .init(at: 3, action: .render(channel: .b)),
            .init(at: 4, action: .resume),
            .init(at: 5, action: .directorAttempt(id: "fresh", delay: 0, succeeds: true))])
        #expect(resume.preparationsCommitted == 1 && !resume.finalPaused)
    }

    @Test func expiredRequestsAndEvidenceGapsRejectQueuedEffects() {
        let expired = replay(ready(1) + [.init(at: 2, action: .directorAttempt(id: "expired", delay: 6, succeeds: true)),
            .init(at: 10, action: .render(channel: .b)),
            .init(at: 11, action: .directorAttempt(id: "retry", delay: 0, succeeds: true))])
        #expect(expired.preparationsCommitted == 0 && expired.proposalCount == 1)
        #expect(expired.rejectedAttempts == 2 && expired.staleProposalsRejected[.expired] == 1)
        let gap = replay(ready(1) + [.init(at: 2, action: .directorAttempt(id: "gap", delay: 2, succeeds: true)),
            .init(at: 3, action: .evidenceGap(true)), .init(at: 5, action: .evidenceGap(false))])
        #expect(gap.preparationsCommitted == 0 && gap.rejectedAttempts == 1 && !gap.finalPaused)
        let noEvidence = replay([.init(at: 0, action: .evidenceGap(true))] + ready(1))
        #expect(noEvidence.proposalCount == 0)
    }
}

/// The committed-effect audit judges raw facts at the sink, independently of
/// DirectorPreparation.validate, so it can catch a stale effect a faulty
/// validator lets through.
struct DirectorEffectAuditTests {
    private let revisions = ChannelRevisions(sourceGeneration: 1, controlEpoch: 2, shotRevision: 3)
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let replacementID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func evidence(authority: Bool = true, present: Bool = true, observedAt: Double? = 10,
                          confidence: Double = 0.95, movement: Double = 0,
                          maximumAge: Double = 2, floor: Double = 0.7) -> DirectorReplay.EffectEvidence {
        .init(authorityAvailable: authority, subjectPresent: present, observedAt: observedAt,
              identityConfidence: confidence, movement: movement, maximumAge: maximumAge,
              minimumIdentityConfidence: floor)
    }

    private func effect(epoch: UInt64 = 7, mayPrepare: Bool = true, program: ChannelID = .a, preview: ChannelID = .b,
                        route: UInt64 = 4, before: ChannelRevisions? = nil, missing: Bool = false,
                        policy: UInt64 = 0, nomination: UInt64 = 0, age: TimeInterval = 0.1,
                        currentRequest: Bool = true, matchingRequest: Bool = true,
                        evidence rawEvidence: DirectorReplay.EffectEvidence? = nil) throws -> DirectorReplay.CommittedEffect {
        let proposal = try #require(DirectorProposal(target: .b, preview: .b,
            shot: DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1), reason: "test",
            authorityEpoch: 7, revisions: revisions, routeGeneration: 4, createdAt: 10))
        return .init(proposal: proposal, requestID: requestID,
                     currentRequestID: currentRequest ? (matchingRequest ? requestID : replacementID) : nil,
                     requestIssuedAt: 10, requestMaximumAge: 0.5, appliedAt: 10 + age,
                     program: program, preview: preview, routeGeneration: route,
                     revisionsBefore: before ?? revisions, sourceMissing: missing,
                     authorityEpoch: epoch, authorityMayPrepare: mayPrepare,
                     policyRevision: policy, nominationRevision: nomination,
                     evidence: rawEvidence ?? evidence())
    }

    @Test func validEffectPassesTheAudit() throws {
        #expect(DirectorReplay.audit(try effect()).isEmpty)
    }

    @Test func everyStaleFactIsCaughtIndependently() throws {
        #expect(DirectorReplay.audit(try effect(epoch: 8)) == [.authorityRevoked])
        #expect(DirectorReplay.audit(try effect(mayPrepare: false)) == [.authorityRevoked])
        #expect(DirectorReplay.audit(try effect(route: 5)) == [.routeChanged])
        #expect(DirectorReplay.audit(try effect(program: .b, preview: .a)) == [.targetBecameProgram])
        #expect(DirectorReplay.audit(try effect(missing: true)) == [.sourceMissing])
        #expect(DirectorReplay.audit(try effect(before: .init(sourceGeneration: 2, controlEpoch: 2, shotRevision: 3))) == [.sourceRestarted])
        #expect(DirectorReplay.audit(try effect(before: .init(sourceGeneration: 1, controlEpoch: 3, shotRevision: 3))) == [.shotChangedByOperator])
        #expect(DirectorReplay.audit(try effect(policy: 1)) == [.policyChanged])
        #expect(DirectorReplay.audit(try effect(nomination: 1)) == [.nominationChanged])
        #expect(DirectorReplay.audit(try effect(age: 0.6)) == [.expired])
        #expect(DirectorReplay.audit(try effect(age: -1, evidence: evidence(observedAt: 9))) == [.expired])
        #expect(Set(DirectorReplay.audit(try effect(age: -1))) == Set([.expired, .evidenceUnavailable]))
        #expect(DirectorReplay.audit(try effect(currentRequest: false)) == [.requestReplaced])
        #expect(DirectorReplay.audit(try effect(matchingRequest: false)) == [.requestReplaced])
    }

    @Test(arguments: ["authority", "presence", "missingTime", "nanTime", "infiniteTime", "futureTime", "staleTime",
        "nanConfidence", "infiniteConfidence", "negativeConfidence", "overConfidence", "belowFloor",
        "nanMovement", "infiniteMovement", "negativeMovement", "nanFloor", "negativeFloor", "overFloor",
        "nanMaximumAge", "infiniteMaximumAge", "negativeMaximumAge"])
    func rawEvidenceFaultsAreIndependentOfTheValidator(fault: String) throws {
        let raw: DirectorReplay.EffectEvidence
        switch fault {
        case "authority": raw = evidence(authority: false)
        case "presence": raw = evidence(present: false)
        case "missingTime": raw = evidence(observedAt: nil)
        case "nanTime": raw = evidence(observedAt: .nan)
        case "infiniteTime": raw = evidence(observedAt: .infinity)
        case "futureTime": raw = evidence(observedAt: 11)
        case "staleTime": raw = evidence(observedAt: 7)
        case "nanConfidence": raw = evidence(confidence: .nan)
        case "infiniteConfidence": raw = evidence(confidence: .infinity)
        case "negativeConfidence": raw = evidence(confidence: -0.1)
        case "overConfidence": raw = evidence(confidence: 1.1)
        case "belowFloor": raw = evidence(confidence: 0.6)
        case "nanMovement": raw = evidence(movement: .nan)
        case "infiniteMovement": raw = evidence(movement: .infinity)
        case "negativeMovement": raw = evidence(movement: -0.1)
        case "nanFloor": raw = evidence(floor: .nan)
        case "negativeFloor": raw = evidence(floor: -0.1)
        case "overFloor": raw = evidence(floor: 1.1)
        case "nanMaximumAge": raw = evidence(maximumAge: .nan)
        case "infiniteMaximumAge": raw = evidence(maximumAge: .infinity)
        default: raw = evidence(maximumAge: -0.1)
        }
        #expect(DirectorReplay.audit(try effect(evidence: raw)) == [.evidenceUnavailable])
    }

    @Test func evidenceConfidenceAndFreshnessBoundariesAreInclusive() throws {
        #expect(DirectorReplay.audit(try effect(age: 0, evidence: evidence(observedAt: 8))).isEmpty)
        #expect(DirectorReplay.audit(try effect(evidence: evidence(confidence: 0, floor: 0))).isEmpty)
        #expect(DirectorReplay.audit(try effect(evidence: evidence(confidence: 1, floor: 1))).isEmpty)
        // Preparation can move; editorial readiness is a separate gate.
        #expect(DirectorReplay.audit(try effect(evidence: evidence(movement: 0.5))).isEmpty)
    }
}

@MainActor
struct DirectorEffectFaultInjectionTests {
    private func replay(_ interventions: [DirectorReplay.Event],
                        executor: DirectorReplay.SimulatedExecutor = .guarded,
                        maximumEvidenceAge: Double = 10, succeeds: Bool = true) -> DirectorReplay.Report {
        let events: [DirectorReplay.Event] = [
            .init(at: 1, action: .render(channel: .b)),
            .init(at: 1, action: .subject(channel: .b, present: true, confidence: 0.95,
                intended: true, framingReady: true, movement: 0)),
            .init(at: 2, action: .directorAttempt(id: "queued", delay: 3, succeeds: succeeds))]
            + interventions + [.init(at: 6, action: .effect(id: "queued"))]
        return DirectorReplay.run(.init(name: "explicit simulated executor fault", duration: 7, events: events),
            parameters: .proposed, maximumProposalAge: 20, maximumEvidenceAge: maximumEvidenceAge,
            readinessParameters: .init(minimumIdentityConfidence: 0.7, minimumSettledTime: 0.2,
                maximumMotion: 0.1, cutOnMotionAllowed: false), simulatedExecutor: executor)
    }

    @Test func validGuardedCommitCapturesRequestBeforeItIsCleared() {
        let normal = replay([])
        let simulated = replay([], executor: .faultyPreviewMutation)
        for report in [normal, simulated] {
            #expect(report.preparationsCommitted == 1 && report.staleEffectsCommitted == 0)
            #expect(report.staleCommittedEffectReasons.isEmpty)
            #expect(report.duplicateCallbacks == 1 && report.directorCuts == 0)
            #expect(report.programChangesWithoutAuthority == 0 && report.evidence == .synthetic)
        }
        #expect(normal.acknowledgementsAccepted == 1)
        #expect(simulated.acknowledgementsAccepted == 0) // Fault path forges no receipt.
    }

    @Test(arguments: ["missing", "confidence", "movement", "stale", "authority"])
    func faultyPreviewMutationExposesLostEvidence(fault: String) {
        let interventions: [DirectorReplay.Event]
        let maximumEvidenceAge: Double
        switch fault {
        case "stale": interventions = []; maximumEvidenceAge = 2
        case "authority": interventions = [.init(at: 3, action: .evidenceGap(true))]; maximumEvidenceAge = 10
        default:
            interventions = [.init(at: 3, action: .subject(channel: .b, present: fault != "missing",
                confidence: fault == "confidence" ? .nan : 0.95, intended: true, framingReady: true,
                movement: fault == "movement" ? .infinity : 0))]
            maximumEvidenceAge = 10
        }
        let normal = replay(interventions, maximumEvidenceAge: maximumEvidenceAge)
        let faulty = replay(interventions, executor: .faultyPreviewMutation, maximumEvidenceAge: maximumEvidenceAge)
        #expect(normal.preparationsCommitted == 0 && normal.staleEffectsCommitted == 0)
        #expect(normal.rejectedAttempts == 1)
        #expect(faulty.preparationsCommitted == 1 && faulty.staleEffectsCommitted == 1)
        #expect(faulty.staleCommittedEffectReasons[.evidenceUnavailable] == 1)
        #expect(faulty.duplicateCallbacks == 1 && faulty.directorCuts == 0)
        #expect(faulty.programChangesWithoutAuthority == 0)
    }

    @Test(arguments: [DirectorReplay.Event.Action.syntheticRequestRetirement, .syntheticRequestReplacement])
    func authoritativeRequestIdentityExposesRetiredAndReplacedCallbacks(action: DirectorReplay.Event.Action) {
        let interventions = [DirectorReplay.Event(at: 3, action: action)]
        let normal = replay(interventions)
        let faulty = replay(interventions, executor: .faultyPreviewMutation)
        #expect(normal.preparationsCommitted == 0 && normal.rejectedAttempts == 1)
        #expect(normal.staleEffectsCommitted == 0)
        #expect(faulty.preparationsCommitted == 1 && faulty.staleEffectsCommitted == 1)
        #expect(faulty.staleCommittedEffectReasons == [.requestReplaced: 1])
        #expect(faulty.directorCuts == 0 && faulty.programChangesWithoutAuthority == 0)
    }

    @Test func combinedReasonsCountOneCommittedEffectAndDuplicateDoesNotInflateIt() {
        let interventions: [DirectorReplay.Event] = [
            .init(at: 3, action: .syntheticRequestRetirement),
            .init(at: 3, action: .subject(channel: .b, present: false, confidence: .nan,
                intended: true, framingReady: true, movement: .infinity))]
        let faulty = replay(interventions, executor: .faultyPreviewMutation)
        #expect(faulty.preparationsCommitted == 1 && faulty.staleEffectsCommitted == 1)
        #expect(faulty.staleCommittedEffectReasons == [.requestReplaced: 1, .evidenceUnavailable: 1])
        #expect(faulty.duplicateCallbacks == 1 && faulty.directorCuts == 0)
        #expect(faulty.programChangesWithoutAuthority == 0)
    }

    @Test func failedEffectsDoNotReachTheAuditInEitherExecutor() {
        for executor in [DirectorReplay.SimulatedExecutor.guarded, .faultyPreviewMutation] {
            let report = replay([], executor: executor, succeeds: false)
            #expect(report.failedEffects == 1 && report.duplicateCallbacks == 1)
            #expect(report.preparationsCommitted == 0 && report.staleEffectsCommitted == 0)
            #expect(report.staleCommittedEffectReasons.isEmpty && report.directorCuts == 0)
        }
    }

    @Test func evenTheFaultyExecutorCannotMutateATargetThatBecameProgram() {
        let report = replay([.init(at: 3, action: .operatorTake)], executor: .faultyPreviewMutation)
        #expect(report.operatorCuts == 1 && report.directorCuts == 0)
        #expect(report.preparationsCommitted == 0 && report.staleEffectsCommitted == 0)
        #expect(report.rejectedAttempts == 1 && report.programChangesWithoutAuthority == 0)
    }
}
