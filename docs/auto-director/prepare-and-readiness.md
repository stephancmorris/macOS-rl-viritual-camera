# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| P1 Director-ready means? | R2 technical eligibility only; identity + settled shot; allow moving shots | Identity + settled shot first; technical freshness is not editorial readiness | AD-PREPARE/TAKE | Yes, requalify |
| P2 Ambiguous identity? | Guess strongest detection; abstain; operator confirmation | Abstain and request nomination; operator may still use manual R2 Take | AD-SUBJECT/PREPARE | Yes |
| P3 Proposal lifetime? | Unlimited; fixed expiry; version-bound plus expiry | Version-bound plus proposed 5 s intent lease; re-evaluate, never silently extend a Take | AD-PREPARE | Yes |

Status: proposed, 2026-09-30. Code baseline `33a3faf`; evidence from `origin/r2/sol:reports/readiness-evaluation.md` and `CinematicCoreMacOS/CinematicCoreMacOSTests/ReadinessEvaluationTests.swift`. The report contains **no real dataset results**. Synthetic decoder/CSV success establishes plumbing only. All new numerical values below are proposed starting values, not observed performance.

## What already exists

`ProgramTake.swift` / `TakeRules.inputs` checks source present/admitted, candidate channel, render age, processing-start age, sourceGeneration, shotRevision, legal geometry and non-repeat. Current provisional constants are 2 render periods, 4 source periods and 0.5 s between Takes; these are existing code values, not new evidence. `RenderedChannelFrame.processingStartedAt` in `ChannelFrame.swift` is a host-clock **processing proxy**, not a sensor exposure timestamp. `RenderedChannelFrame.matches` does not compare controlEpoch. `TakeAvailability.swift` permits R2 manual Take of a valid moving shot. Preserve that behavior.

`ShowCoordinator.take` validates the current latest frame and synchronously invokes `ProgramRouter.commitTake`; `TakeRequest` carries roles/route generation, not all director revisions. Director must add its permit outside this request and atomically validate it at admission. Do not build a parallel render/output path.

## Proposed conjunction

`directorReady = R2Eligible AND currentPermit AND editorialEvidence AND permittedMotion AND stableWindow`.

| Gate / proposed parameter | Starting rule / rationale | Measurement and refusal |
|---|---|---|
| identityEvidence | Operator-nominated same physical person; tracking state, ready gallery, no identity veto or pending reacquisition | Expose categorical evidence, not invented probability. Review wrong-person events against labels; uncertain → abstain |
| observationMaxAgeS | 0.15 s and current source/lock generation | Match initial R2 perception budget; test stale observation ages separately from fresh renders; measure at decision host time |
| settledWindowS | 0.75 s continuously eligible | Prevent cut during preparation transient; plot false-ready vs preparation delay on held-out clips |
| stableFreshObservations | At least 3 distinct fresh observations spanning the window | Avoid repeated sample counting; insufficient cadence is not readiness |
| centerSpeedMaxPerS | 0.02 source-width/height normalized units/s, Euclidean center speed | Finite differences of actual rendered crops with monotonic timestamps; rejects visibly moving pan until qualified |
| logScaleSpeedMaxPerS | 0.02/s absolute d(log crop height)/dt | Scale-independent settle criterion; label noticeable zoom on replay |
| plannedMoveActive | False: no in-flight rung move or Auto Pan | Tiny instantaneous speed at easing endpoints must not look settled |
| source age | Keep R2 render/source-period gates; do not relax for director | Clock-injection boundary tests and rig capture-to-processing measurements |
| proposalIntentTTLSeconds | 5 s since proposal creation | Bounds abandoned intent. Refresh creates new proposal/evidence, never extends an armed notice automatically |
| future countdownSeconds | 3 s only after separate approval | Continuous readiness throughout notice; new exact render at dispatch must match intent/revisions; expiry/staleness cancels notice |

For a safe full-view candidate with no person-specific intent, nomination/face evidence is not required; explicit camera-role verification and fresh lawful rendering are required. A Wide preset tracking a person is not equivalent to this safe full view.

## Proposed lifecycle and invalidation

`proposed → preparing → settling → ready → consumed`, with any pre-consumed state able to become `invalid(reason)`. Suggest displays proposed intent without executing it. Auto Prepare applies one bounded intent to Preview, records the acknowledged resulting epoch/shotRevision, then observes it. An operator Take consumes/invalidates the proposal whether the click commits or rejects, because authority pauses.

| Change | Result |
|---|---|
| Any manual intent, Pause/Pin/Off, Edit Live, Stop | Invalidate authority token, pending effects and countdown before action |
| Input stop/rebind/reconnect, channel removed, source missing | Invalidate sourceGeneration and nomination for that source; no substitution |
| External shot revision / control epoch change | Invalidate; only the identified preparation acknowledgement may rebind its own expected post-command revisions |
| Take/route change | Invalidate roles/routeGeneration; never reinterpret former Preview as current Preview |
| Subject/lock generation, cue, preference policy version or role assignment change | Invalidate even if R2 frame remains technically fresh |
| Observation ages out, ambiguity, movement or health failure | Revoke ready immediately; clear settling window and countdown; same intent can settle anew only inside current lease |
| Intent expiry, nonfinite/negative age or clock discontinuity | Invalidate; fail closed, record reason |

Ordinary tracking interpolation need not increment shotRevision; this is why live motion/evidence must be checked independently. Readiness never arms a delayed manual Take. Countdown is a director notice, not a reserved stale frame.

## Evaluation using the existing harness

1. Freeze consented train/held-out clips and annotations before tuning. Existing harness uses nearest target point in Vision bottom-left coordinates; require physical-person interval labels and explicit absence/ambiguity labels for director study.
2. Run existing `ReadinessEvaluationTests` with `ALFIE_READINESS_CLIPS` and `ALFIE_READINESS_OUT`; record decoding, selected/face/print/pose frames, source-pixel height distribution and processing freshness. Unannotated tallest-person selection cannot validate identity.
3. Proposed second replay layer drives actual acquisition/locked ROI/recovery and composer/render trajectories with recorded observation timestamps and injected delays. Existing full-frame `.reacquiring` harness does **not** exercise that pipeline. UUID continuity is only a proxy, never wrong-person truth.
4. Independent reviewers label each candidate as intended person, acceptable composition, settled/moving and eligible/uncertain. Count false-ready candidates / all declared-ready candidates; missed-ready time / labelled acceptable time; median/p95 preparation latency for successful attempts, with failures separately counted.
5. Freeze thresholds using training only; evaluate held-out small-subject, crossing and loss strata separately. Then test two live cameras and actual downstream cadence; offline processing age cannot establish live source freshness.

Acceptance proposal: zero identity-veto bypasses and stale-revision accepts in deterministic tests; zero wrong-person director-ready proposals in held-out evaluation, with sample size and abstention published. Numeric quality/coverage budgets require the qualification protocol and Stephan approval before runs. Risk: conservative settling may starve useful shots; report coverage rather than easing thresholds after looking at held-out errors.
