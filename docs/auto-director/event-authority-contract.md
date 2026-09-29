# Decisions for Stephan

**Proposed approval package, 30 September 2026. Not an approval record.** Based on `origin/s34/astra` at `b4b447f`, `docs/auto-director/decision-review.md`. All 37 register decisions remain **OPEN**; this branch does not edit the register. The following choices can be approved together or individually by ID.

| IDs / question | Options | Recommendation and why | Blocks | Reversible? |
|---|---|---|---|---|
| S1/S2/A3: first authority? | Sermon Suggest; sermon Auto Prepare; Auto Direct | Sermon Auto Prepare, operator-nominated person per camera; every Take manual. Hardware and microphone remain separate later gates. | Initial integration scope | Yes, requalify changes |
| A1/F2/F3: what revokes? | Global pause; channel pause; temporary suppression | Global latched pause on camera/editorial intervention, **including refused Take attempts**; exclude read-only navigation/cosmetics. Revoke before dispatch. | Authority/event adapter | Yes, requalify |
| E1/P2/R2: evidence loss? | Always pause; graduated evidence states; automatic fallback | Temporary evidence gap withdraws readiness; declared identity loss or source/output fault latches Pause. Never nominate another person or Take automatically. | Loss classifier; lifecycle adapter | Yes; loss thresholds remain study inputs |
| P1/P3/T1/T2: lifetimes? | One expiring proposal; separate composition/readiness/permit | Separate preparation permission, persistent composition, live readiness and short-lived execution permits. Preparation may move Preview immediately; settlement gates readiness. | Proposal/readiness/policy API | Yes |
| A2/A4/U1/U2: first UI? | All controls; Pause/Resume now | Next-shot panel shows level, state, proposed Preview and reason, Pause/Resume. Defer Pin/countdown; explain unavailable Auto Direct in setup. | State projection/UI | Yes |

Proposed approval wording: “Approve the recommendations above for the first sermon Auto Prepare rehearsal, with all Takes manual and Auto Direct unavailable.” Recording that choice still requires Stephan's explicit response; this document grants no authority or release qualification.

## Proposed event contract

A runtime grant records level, authority epoch and active/paused/inhibited state. Off grants nothing; Suggest can propose only; Auto Prepare can also prepare **current Preview**; Auto Direct requests are explicitly refused while unqualified. Persist preferences, never active grants. A pause retires queued proposals, preparations and future Take permits. It does not retroactively undo a committed Take or freeze existing R2 tracking.

| Event / owner | Immediate effect before other work | Recovery / cancellation rule |
|---|---|---|
| Operator enables an available level or explicitly Resumes | Revalidate nominations, channel roles, source health and current revisions; issue a **new** grant only if admissible | Never reuse pre-pause tokens; inhibit with a reason if prerequisites fail |
| Manual camera action, nomination, cue advance, behavior-affecting policy/role edit, **Take attempt** / operator | Increment authority epoch and cancel pending director work globally **before** manual admission, even if the manual action fails | Pause remains until explicit Resume; Apply and Resume may be one clearly labelled, deliberate action |
| Enter Edit Live / operator | Same revocation and latched Pause before retargeting | Leaving Edit Live removes inhibition, does not Resume |
| Read-only inspector/navigation or cosmetic label edit / operator | No authority change | Never classify merely focusing Preview as camera intervention |
| Temporary stale/missing/ambiguous evidence / evidence adapter | Immediately withdraw director-ready status; issue no new prepare action from insufficient evidence; retain nominated identity | May become ready again under the same still-valid grant; no silent new-person assignment or mandatory retap for every missed frame |
| Declared subject/identity loss / evidence adapter | Revoke epoch, pause, cancel pending work, explain reason | Existing R2 same-person recovery follows its own grant; recovery does not clear director Pause. Retap only if original identity cannot be safely retained |
| Source rebind/loss, output fault, show admission loss / lifecycle adapter | Revoke and pause; retire affected source/route context using existing lifecycle mechanisms | Restore health first, then explicit Resume; no fallback Take |
| Successful manual Take / coordinator | Prior Take-attempt revocation already happened; observe resulting Program/Preview role and route changes | Never let old Preview work edit the new Program; a refused Take also leaves director paused |
| Stop show / operator or lifecycle termination | Off; revoke all director work and runtime grants before teardown | Restart does not restore active authority from saved settings |
| Future Pin/unpin / operator, if separately approved | Pin holds editorial intent, not pixels; health faults remain visible | Unpin leaves Pause; no auto-resume. Deferred for initial release |

Declared-loss thresholds require labelled evidence and a separate frozen study configuration; this contract deliberately supplies no new timeout. A temporary gap cannot authorize a new command, but does not itself terminate existing R2 tracking. If tracking cannot retain identity safely, classify declared loss rather than silently replacing the subject.

## Existing mechanisms and final-effect requirements

| Existing code at Sol `605df3f` | Required proposed integration |
|---|---|
| `ShowCoordinator.swift` / `controlTargetRevision`, `makeCommand`, `dispatch` | Target revision changes on retargeting, **not every manual action**. Add a separate authority event at manual admission; bind immutable channel/role/source context, never late-bind to current selection. |
| `OperatorCommand.swift` / `CommandDispatcher` channel epochs | Cancel pending director command effects on revocation; check action-specific permission (`prepare` versus `propose`) at final effect, not just initial enqueue. |
| `ChannelFrame.swift` / `ChannelRevisions` | Bind source generation, command epoch and shot revision. Ordinary rendering/tracking interpolation does not increment shot revision. A preparation acknowledgement binds the **resulting** shot revision, avoiding immediate self-invalidation. |
| `ProgramRouter.swift` / `routeGeneration`; `ProgramTake.swift` / `TakeRequest`; `ShowCoordinator.take` | R2 Take is synchronous admission/commit, not a queued future cut. Any future director permit must be rechecked immediately before Take in the same serialized coordinator turn, without an intervening await; R2 frame/output checks still apply. No such automatic path in first release. |
| `Console/NextShotStatus.swift` / `DirectorSection` | Future seam needs distinct Auto Prepare/Auto Direct modes and explicit active/paused/inhibited status. R2's existing Take readiness remains authoritative for manual Take; director readiness must not disable otherwise legal manual operation. |

Prepared composition may persist while useful. Live identity, evidence age and settlement are recomputed. Dispatch permits have bounded expiry and context; expiry discards the permit, never renews it invisibly or repeatedly reapplies the preset. Dwell/cut-reminder timing must not delay preparing Preview. A countdown would describe an already revocable proposed cut, never grant one.

## Inconsistencies for Sol's next authority/lifecycle round

Baseline inspected is `origin/s34/sol` **605df3f**, not a claim about Sol's concurrent repair branch:

- `DirectorAuthority.apply` silently substitutes Auto Prepare for unavailable Auto Direct; manual/Take/source-loss events cancel an epoch without latching Pause. Edit Live exit and unpin can restore eligibility. The recommendation requires explicit refusal and deliberate Resume.
- `DirectorAuthority.admits(forTake: false)` tests proposal permission, which is insufficient to admit preparation in Suggest. Require an action-specific permission check at final effect.
- `DirectorShotPolicy.choose` minimum-duration filtering conflates preparation with cut timing. `DirectorProposal` expiry must distinguish a dispatch permit from retained composition and refreshed readiness.
- The old authority memo's first-release Pin and fixed countdown, short “proposal expiry,” and the original roles memo's broad loss wording are superseded **as recommendations** by decision-review, not by recorded approvals. The original register/memos still need reconciliation after Stephan chooses.
- Add explicit temporary-evidence, declared-identity-loss, output/admission-fault and Stop lifecycle events; do not force them through generic source loss. Threshold selection remains open.

Acceptance for the next round: delayed preparation after manual action is rejected; Take then role-swap cannot retarget old work; evidence recovery cannot clear a latched pause; Suggest cannot prepare; refused Auto Direct never changes level; ordinary renders do not invalidate composition; no director command predating intervention takes effect afterward. Replay must test delayed effects and report unavailable latency as N/A, not synthetic zero. Stage 2 real-camera/output qualification and a measured director-workload gate remain prerequisites to app integration/rehearsal.
