# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| Q1 Release gates? | One director sign-off; per-autonomy gates; direct live trial | Replay → supervised live → explicit sign-off per level and rig | AD-QA/TAKE | Yes, revoke anytime |
| Q2 Acceptable error budget? | Average quality only; zero critical events + bounded quality; statistical guarantee | Zero observed critical events plus exposure and uncertainty; never claim zero risk | AD-QA | Threshold changes require new frozen run |
| Q3 Who approves? | Developer alone; product owner + operator + technical reviewer; operator alone | Stephan + named volunteer lead + independent technical reviewer | AD-QA | Yes |

Status: protocol proposed, **no qualification run**, 2026-09-30. Freeze signed values, hashes and exclusions before any scored run. These thresholds are proposed starting values with rationale, not settled acceptance. A changed policy or budget invalidates the comparison; preserve failed runs.

## Frozen metrics

| Metric | Numerator / denominator and instrumentation | Proposed pass threshold / rationale |
|---|---|---|
| Wrong-subject cut | Reviewed unintended physical-person cuts / all person-specific committed director cuts; also per live hour; log intended/actual IDs | 0 observed; critical editorial error. Minimum proposed exposure 300 cut opportunities across replay and live, separately reported |
| Wrong-person ready proposal | Wrong-person ready proposals / all person-specific ready proposals | 0 observed; protects Auto Prepare even before automatic cuts |
| Excessive switching | Director cuts below applicable minimum / all director cuts; A→B→A equivalent-shot return within proposed 20 s / all eligible cut triplets; cuts per eligible minute | 0 below-minimum or oscillation violations; proposed ≤3 cuts/min in any rolling 5 min. Manual cuts reported separately |
| Bad movement | Reviewer-labelled jerks/reversals/edge clipping/unintended zoom episodes / rendered Program minutes; motion-on-entry / director cuts | 0 motion-on-entry for settled-only policy; proposed ≤1 minor episode/10 min and 0 severe lost-subject/illegal crop episodes; compare manual baseline |
| Stale Take attempts | Attempts with old authority/channel/source/shot/policy/route or expired evidence / all director attempts; rejected and committed counts separately | 0 stale commits, 100% injected stale attempts rejected. Natural stale attempts proposed ≤1% (race load reported separately), to catch waste without punishing correct rejection |
| Override latency | Monotonic manual-ingress→revocation/effect rejection; visible acknowledgement separately; all manual override trials including rejected manual commands | 0 post-revocation director effects; proposed p95 ≤50 ms internal, max ≤100 ms; visible acknowledgement ≤150 ms. Budget tests immediate perceived control, not next periodic poll |
| Useful preparation coverage | Correct ready proposals / annotated acceptable preparation opportunities; latency for successes and failures | Proposed ≥80% coverage, p95 ≤5 s; prevents passing by abstaining everywhere |
| Program safety/compute | Frozen R2 cadence/freshness/memory/thermal metrics plus workload-plan budgets | All R2 and director workload gates pass, no raw output fallback or unauthorized route change |

Define an opportunity as an annotated interval with one eligible desired shot; repeated callbacks within it do not inflate exposure. Blind two-reviewer labels; adjudicate disagreements. N/A for absent denominators, never “100% pass.” For zero errors in 300 independent events the familiar approximate 95% upper bound is about 1%; correlated shots reduce effective evidence. Report per-session clustering and do not advertise that bound as a service guarantee. Proposed 300 is a starting exposure target; enlarge for missing strata, never count synthetic repetitions as independent real-world evidence.

## Stages and sign-off

| Stage | Required evidence | Permission after sign-off |
|---|---|---|
| Prerequisite | R2 two-input technical gate, exact rig/output matrix, approved decisions/privacy; deterministic authority race tests | No director release yet |
| Replay | Frozen training/held-out split from subject study; real composer/identity trace plus synthetic fault permutations; all defined metrics report actual denominators | Suggest candidate may progress to attended rehearsal |
| Supervised Suggest | Proposed 3 consented 60-min rehearsals on named rig, reviewer/operator evidence, no executable automated action | Suggest only |
| Supervised Auto Prepare | Proposed 3 further 60-min rehearsals, all Preview edits/overrides accounted for, actual Program unchanged except operator Take | Auto Prepare only; operator cuts |
| Shadow Auto Direct | Log would-cut decisions with exact policy and candidate state, no automatic routing; freeze editorial review | No live auto-cut authority |
| Supervised Auto Direct | Only after explicit trial approval; proposed 3 60-min rehearsals, operator at controls, actual cut/fault/override evidence and minimum exposure | Stephan's explicit per-rig/policy Auto Direct sign-off; no unattended claim |

Durations/counts are proposed starting values to expose thermal behavior and multiple services; absent rare-event coverage requires targeted additional sessions. Hardware and voice require separate Stage 4 tests. Revocation triggers: critical error, changed scope/policy/model/rig fingerprint or missing required evidence. Requalification preserves earlier evidence only for unchanged scope, not as inherited Auto Direct permission.

## Alignment with Sol replay (inspected `d9184ba`, 2026-09-30)

`Director/Replay/DirectorReplay.swift` / `DirectorReplay` and `DirectorReplayFixtures.swift` provide labelled synthetic events for calm sermon, walking pastor, panel of three, camera B loss and operator fighting. These test pure logic and are useful regression fixtures; they are not recorded service replay.

| Existing report field | Valid interpretation / required extension |
|---|---|
| wrongSubjectProposals / labelledSubjectProposals | Proposal error count/denominator; does not measure wrong-subject cuts. Add actual/shadow cut records and physical-person labels |
| cutsPerMinute, minimumDurationViolations, oscillations | Current cuts occur only through operatorTake; cannot grade director pace with these as-is. Split actor and count rolling windows/eligible triplets |
| staleProposalsRejected | Counts each stale reason, so totals can exceed rejected proposals. Add unique attempt/proposal IDs and denominator |
| manualOverridesHonoured | Currently increments on manual events, not verification of queued effects. Add adversarial continuations and actual result checks |
| manualOverrideLatencies | Filled with zeros synthetically; **not latency measurement**. Record event/effect timestamps from wired integration and rig |
| programChangesWithoutAuthority | Useful invariant but no director route mutation is implemented; zero is structural, not Auto Direct evidence |
| `.render` event | Increments shotRevision, unlike ordinary R2 render. Add distinct render, discrete shot intent and source/observation timestamps |

Extend fixtures with all revision invalidations, failed sink, duplicate Take, countdown cancellation, pin/fault, Stop, nonfinite/backward times, insufficient identity and delayed callbacks. Same-time events need explicit stable sequence ordering. Until integration exists, mark unavailable metrics UNVERIFIED; never fill them with synthetic zeros.

## Record format

Run record: `runID, startedUTC, appCommit, harnessCommit, policyHash, schemaVersion, fixtureManifestHash, labelsHash, rigFingerprint, outputRoute, autonomyLevel, privacyConsentRef, frozenBudgetHash, reviewerIDs`.

Event record: `runID, eventSeq, monotonicTime, actor, eventType, proposalID, intendedPersonAlias, actualPersonAlias, channel, sourceGeneration, controlEpoch, shotRevision, authorityEpoch, controlTargetRevision, routeGeneration, policyRevision, eligibility, rejectionCodes, takeResult, overrideIngressTime, finalEffectTime`. No image vectors/audio/transcripts in routine export.

Result table: metric, numerator, denominator, distribution, stratum, threshold, pass/fail/unverified, evidence path/hash, reviewer. Sign-off table: level/scope/rig/policy, evidence runs, known exclusions, Stephan/date, operator lead/date, technical reviewer/date. Leave all signatures blank until actual review. No pass claimed in this document.
