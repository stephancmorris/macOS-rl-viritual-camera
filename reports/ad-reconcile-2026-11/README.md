# AD-RECONCILE: older Auto Director cards against main (4 November 2026)

Trello: [AD-RECONCILE](https://trello.com/c/jhhQuzKv). Source: `origin/main` at `89808be`. Decisions: `docs/handoff/stage3-4/DECISIONS.md`.

Four Spec Backlog cards were written before the Stage 3 ticket plan:

- [AD-AUTHORITY-CORE](https://trello.com/c/9mvrs2KS)
- [AD-LIFECYCLE](https://trello.com/c/wMOcCw7P)
- [AD-POLICY](https://trello.com/c/wfh8ki7K)
- [AD-INTEGRATE](https://trello.com/c/UXPqPKsz)

This report checks each of their acceptance lines against the code and tests now on main.

**Result:** no software gap that could be fixed without an owner decision. Everything is met, superseded by a recorded decision, or waits on an open decision or the rig. No code changed.

Status key: **met**, **partly**, **superseded** (by a recorded decision), **needs decision**, **needs rig**.

## AD-AUTHORITY-CORE: override and fault transitions

| Line | Status | Evidence |
|---|---|---|
| Unavailable Auto Direct silently maps to Auto Prepare | **met**: refused, never substituted | `DirectorAuthority.apply(.enable)` returns `.notQualified` and leaves level and epoch unchanged (`Director/DirectorAuthority.swift`, "Refused, never substituted"). Tests: `DirectorAuthorityTests.levelsAndGate`, `DirectorModeControlTests.unqualifiedLevelIsRefusedAndTheLevelStays` |
| Camera/editorial intervention pauses before manual admission; read-only navigation does not | **met** | `.manualCommand`, `.pause`, `.identityLost`, `.policyChanged` and `.nominationChanged` retire and pause; `.navigation` and `.cosmeticEdit` do nothing. Tests: `manualWinsPendingWork`, `temporaryGapAndNonInterventions` |
| Manual Take allows new proposals without explicit recovery | **superseded by N1** | N1 (recorded): in Assist a Take is a fresh start without a pause; in Auto/Backup it's a nudge with a dwell hold. Tests: `operatorTakeWithoutTimingFailsClosedWithoutPausing`, `DirectorProgramTakeTests.operatorAttemptUsesSuppliedStyleDwellOnTheSameClock` |
| Edit Live exit allows proposals without recovery | **met** | `.editLive(true)` pauses; `.editLive(false)` only clears the flag and never clears Pause. Test: `pausePinEditLiveAndLoss` |
| Declared subject loss and source/output fault latch Pause | **met** | `.sourceLoss`, `.outputFault` and `.admissionLost` set `healthy = false` and pause; `.healthRestored` "never clears Pause". The evidence adapter treats `wideWaiting` as an immediate loss (N5). Tests: `pausePinEditLiveAndLoss`, `DirectorEvidenceAdapterTests.wideWaitingIsALossImmediatelyAndOnce` |
| No implicit resume; refuse unqualified escalation | **met** | Resume / Hand to Alfie needs current prerequisites and a current qualification. Tests: `handToAlfieResumesWithCurrentPrerequisitesOnly`, `resumeRefusedWhenQualificationLapsed` |
| Defer Pin/countdown in the first UI | **needs decision A2 (pin), A4 (notice)** | Pin exists in the model (`.pin` pauses); A2 is still open. The next-cut notice (C-06) is implemented against A4's recommendation; A4 is still open |
| Event table and ordering tests: manual vs pending prepare/Take, Stop, fault/restoration, duplicate callbacks; routing unchanged | **met** | `DirectorAuthorityTests` (12 tests), `DirectorCutExecutionTests.interventionInTakeObserverRevokesTheJustIssuedPermitBeforeEffect`, `staleCallbackCannotRetireOrConsumeAReplacement`, `DirectorTakePermitTests`, `DirectorStopActionProvenanceTests` |

**Can close:** yes, once A2 and A4 are recorded or explicitly deferred. Software is complete.

## AD-LIFECYCLE: separate preparation, readiness and execution permits

| Line | Status | Evidence |
|---|---|---|
| Intent, prepared composition, recomputed readiness and a one-use permit are separate | **met** | Preparation is per Preview tenure (`DirectorAssistPolicy.PreparationHistory`); there are two readiness bars (P1, `DirectorReadiness`); `TakePermit` is one-shot (A-11). Tests: `DirectorTakePermitTests.consumptionIsOneShotAndStaleCallbackCannotCancelReplacement`, `DirectorAssistPolicyTests.n4FlagOnlySuppressesACommittedPreparationInTheCurrentTenure` |
| Bind nomination, lock, channel, source, shot, route, control target, cue and policy revisions | **met** | `DirectorEffectSink` receipts, `DirectorCaptureBinding`. Tests: `DirectorEffectSinkTests.staleCallbackCannotDiscardReplacementRequest`, `DirectorAssistPreparationTests.actualDispatchMatchesReceiptAndChangesOnlyPreviewWhileKeepingTheLock`, `DirectorProgramTakeTests.finalReadinessNeverBorrowsConfirmationOrSettlementFromAnotherSubject` |
| Preparation may move Preview before it is settled | **needs decision T2** | Assist abstains with `.movement` while the subject moves, unless the style allows cutting on motion (`DirectorAssistPolicy.swift`, the `cutOnMotionAllowed` guard on the prepare path). SU-03 leaves the prepare bar unchanged. Whether *preparation* (not the cut) may follow a moving subject is T2/AD-POLICY |
| Stale effects reject; prepared crop persists without command churn | **met** | `DirectorEffectSinkTests.commitsOneOffAirPresetAndRejectsReuse`, `DirectorAssistPreparationTests.tenureFlagCountsOnlyCommittedPreparations` |
| Readiness withdraws and may recover under an unchanged grant; no permit revives; Program unchanged | **met** | `DirectorEvidenceAdapterTests.freshRecoveryMustConfirmAgainAndStartANewSettlement`, `DirectorProgramTakeTests.stalePermitCannotConsumeReplacement`, `technicalRefusalConsumesThePermitAndNeverArmsALaterCut` |
| Proposal lifetime | **needs decision P3** | The code is revision-bound; P3 (revisions plus a 5 s intent lease) is still open |

**Can close:** after T2 and P3 are decided; any remaining work becomes its own card at that point.

## AD-POLICY: prepare early; time cut suggestions separately

| Line | Status | Evidence |
|---|---|---|
| Don't wait for minimum Program dwell before preparing | **met** | "Preview-only preparation can precede minimum Program dwell; cutting cannot" (`DirectorAssistPolicy.assistPreparation`). `CutPolicy.timingReason` is shared by the live cut and the rhythm preview (SU-06) |
| Allow Preview framing movement while Preparing | **needs decision T2** | Same gate as above |
| Require a settled entry for director-ready | **met** | SU-03 `tightened(by:)`. Tests: `DirectorSettleTimeTests` (7) |
| Minimum / preferred / soft maximum and Wide reminder as study parameters, never forced cuts | **met; values need T1/T3** | Feel table v1 (SU-02); "the soft maximum is advisory dwell only" (`DirectorShotPolicy`). T1 and T3 values aren't frozen |
| Semantic repetition, stable candidate IDs, no oscillation | **met** | `DirectorShotPolicyTests.minimumAndRepetition`, `tiesResolveIndependentOfCandidateOrder` |
| No timer-created Take; no unsupported preset or wrong-person promotion | **met / superseded by A3** | Auto cuts only through a qualified permit (A3). Tests: `DirectorAssistPolicyTests.candidatesComeFromEachInputsActualPresetLadder`, `protectedWideAndMissingPreviewAlwaysAbstain`, `DirectorProgramTakeTests.directorRequiresPermitAndFallbackCannotBorrowANormalPermit` |

**Can close:** after T1–T3 are decided.

## AD-INTEGRATE: one authority boundary for Suggest and Auto Prepare

| Line | Status | Evidence |
|---|---|---|
| One serialized ShowCoordinator path for manual commands, Take, Edit Live, Stop, faults and Director preparation | **met** | B-03 `DirectorController` on the show; B-05 off-air preparation sink; B-07 permit-checked Take inside `ShowCoordinator.take` |
| Revalidate at the final effect; route and Director status published atomically | **met** | `DirectorProgramTakeTests.finalCutInputsUseFreshMotionAndCropInsteadOfCachedTickValues`, `DirectorLiveControlsTests.staleRenderedNoticeReadsTheActualCurrentControllerAtTheActionBoundary` |
| Truthful Suggest / Auto Prepare controls in the next-shot panel | **met** | C-02/C-03 mode control and next-shot line (U2). Tests: `DirectorModeControlTests` (9) |
| Keep Auto Direct disabled; no automatic Take path | **superseded by A3** | A3 allows a cut in Auto/Backup after qualification through a one-shot permit. Without a qualification record (B-06) the level is refused (`aQualifiedRigStillLaunchesInManual`, `syntheticScenariosResetToManualAndKeepHigherLevelsUnqualified`). No record exists, so on a real rig Auto stays unavailable |
| Fake-backed races: preparation never changes Program; manual Wide/Take/Stop win; stale work never lands | **met** | `DirectorAssistPreparationTests` (9), `DirectorCutExecutionTests` (11), `DirectorAuthorityTests.manualWinsPendingWork` |
| Requires passed R2 MULTI-QA | **needs rig** | [MULTI-QA](https://trello.com/c/uO1HAlYm) has not run on two real cameras |

**Can close:** yes as a software card; the remaining gate is MULTI-QA and the per-level qualifications (G-03, G-05, G-07).

## Questions for the owner

1. **T2:** may Assist *prepare* Preview while the subject is moving, when the style says "Wait until they settle"? Today it waits. The cut-ready bar is not affected either way.
2. **P3:** is a proposal bound only to revisions, as today, or also to a short intent lease (the recommendation is 5 s)?
3. **A2 / A4:** record or explicitly defer pin semantics and the Auto next-cut notice. Both are implemented against the recommendations.
4. **T1 / T3:** freeze the pace and wide-frequency values in feel table v1, or keep them as study parameters until shadow data exists.
