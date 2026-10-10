# Director qualification protocol: Assist, Auto and Backup

Status: **D-04 proposal, AWAITING OWNER (Q1–Q3), 2026-10-10. No run or level is qualified by this memo.** This replaces the September sermon/Auto Prepare protocol. Recorded S1/A1/A3/E1/P1/P2/N1/N3/N5/U2 and privacy decisions remain binding; numerical study settings and remaining choices are not approved here.

Sources inspected: main `42191c71ec303e3f7d388c7cdafb5d5ef93d89db`, [recorded decisions](../../docs/handoff/stage3-4/DECISIONS.md), [D-04/B-06 and integration tickets](../../docs/handoff/stage3-4/STAGE3-TICKETS.md), [design/evaluation plan](../../docs/handoff/stage3-4/STAGE3-DESIGN-PLAN.md), [product walkthroughs](../../docs/auto-director/product-contract.md), and the actual admission types/producers cited in the [proposed B-06 record format](../../docs/auto-director/qualification-record-format.md). Recorded decisions override stale proposed headers. The A-08 review at `ba0601e` supplies synthetic sink-audit evidence only; no live trial or R2 MULTI-QA result was produced by this task.

## Choices for owner sitting 3 — AWAITING OWNER

| ID | Options | Recommendation and tradeoff | Evidence needed before approval |
|---|---|---|---|
| Q1 gates | One global sign-off; separate level/rig gates; direct live trial | Separate Assist, Auto and Backup gates, each tied to an exact rig/route and frozen scope. Reusing unchanged evidence reduces repeated work, but never inherits a later level's permission | A completed per-level matrix below, exact admission binding and a complete evidence index |
| Q2 pass bars | Average quality; zero observed critical events plus exposure/quality bars; claimed statistical guarantee | Zero observed critical events, complete mandatory fault coverage, and owner-frozen exposure/quality bars. This is stricter than an average but cannot prove zero future risk | Pilot distributions, manual baseline, failure opportunities and separately counted live exposure; agree all numerical budgets before scoring |
| Q3 signatories | Developer alone; owner/operator/independent reviewer; operator alone | Owner + an event operator + independent technical reviewer, each attesting the same frozen record. Adds review work but separates product acceptance, booth usability and technical evidence | Recorded approvals with roles, identity references, scope, content digest and dates; no pre-filled signatures |

Recommendations elsewhere in this memo and the linked record format are also **AWAITING OWNER**. No sample duration, count, latency, probability, cadence or coverage percentage is silently inherited from the superseded draft.

## 1. Evidence and authorization boundary

Use three source classes, never a combined denominator: **synthetic** (authored fixtures/fault injection), **recorded** (previously captured source evidence with its original provenance), and **live** (observed rig/event). Shadow is an execution mode, not a source class: live shadow is live evidence with no Director effects; replaying recorded input remains recorded. Mixed-source sessions must report their components separately and cannot be encoded as homogeneous schema-1 shadow records. Missing provenance makes the affected result unverified.

E-0 deterministic tests establish exercised software invariants, not an operating permission. E-1 shadow compares would-prepare/would-cut with actual operator actions without effects. E-2 recorded footage is blocked until E3 and the necessary consent/fixture register are approved; do not substitute synthetic repetitions for it. E-3 is supervised live rehearsal on the real rig, with the operator present and able to stop. E-4 is the explicit per-level sign-off. If a required step is unavailable, the package remains incomplete. Any proposed alternative to recorded evidence requires owner approval of a revised protocol before scoring, not an evaluator's waiver.

Trial permission is separate from qualification. Before any live Assist preparation or automatic cut, require current R2 two-input technical evidence, implementation prerequisites and explicit owner-approved supervised-trial scope. Debug-injected qualification records may exercise the UI and lookup in controlled tests; they cannot become Release records or establish live qualification. Production availability remains false until real per-level sign-off. Every launch stays Manual, including after a successful lookup.

## 2. Freeze before collecting scored evidence

Create an immutable run-plan ID and digest. Record these inputs; a blank required entry means **not ready to score**, not a permissive default:

| Frozen input | What must be supplied |
|---|---|
| Level and capability scope | Assist / Auto / Backup; two-input Stage scope, segment types, discovery/run-sheet/model/on-air-move/fallback capabilities included or excluded |
| Decision baseline | Recorded choices and the owner resolutions needed by this scope. A4/N2/N4/R1/R2 and Q1–Q3 remain open until recorded |
| Build and parameters | App/engine/harness commits, build configuration, model identity if used, exact resolved profiles and readiness/adapter/judge/cut/notice/fallback/workload parameters, versions and units |
| Rig matrix | Full actual `AdmissionFingerprint` per configuration and route; current R2 certification reference; separate attested setup manifest for facts not represented in the API |
| Exposure plan | Required live minutes, independent event sessions, eligible preparation/cut opportunities, and each mandatory fault/override stratum, **per level and output route** |
| Quality budgets | Maximum measured internal/visible override latency, minimum useful-preparation coverage, allowed minor motion/pace deviations, shadow-agreement matching rule and any agreed limit |
| Evaluation procedure | Label definitions, adjudication, clocks, instrumentation locations, missing-record handling, evaluator roles, retained/exported metadata references |
| Trial authorization | Scope, people at controls, stop conditions and authorization reference. No authority is inferred from a run-plan file |

Derive exposure and quality proposals from a named pilot/manual baseline, workload measurements and relevant opportunities, then ask the owner to freeze them. Keep the pilot outside held-out scoring. If thresholds, labels or policy change after results are seen, create a new plan/version and report the prior result; do not retroactively turn it into a pass. The applicable [workload memo](workload-plan.md) still requires its own owner-reviewed budget; its old proposed values are not defaults adopted here.

## 3. Proposed pass bars and scoring — AWAITING OWNER

Zero critical events and complete mandatory checks are proposed Q2 acceptance bars, reflecting the recorded safety invariants. Other numeric fields must be supplied in the frozen plan from data. A threshold below is not evidence that it has been met.

| Metric | Count and denominator | Proposed bar / failure rule |
|---|---|---|
| Effects without authority | Actual sink/route commits after takeover, in Manual/shadow, to prohibited Program, or with stale/reused request/permit / all observed Director commits and injected forbidden opportunities | **0 observed**. Any instance fails the run and stops trial effects; a rejected stale attempt is counted separately and is not a stale commit |
| Wrong subject or input | Wrong-subject preparations / labelled person-specific preparations; wrong-input or wrong-subject automatic cuts / labelled committed Director cuts; also report live exposure time | **0 observed critical events**. Use session-local opportunity/correctness labels, not person names, face IDs or cross-camera identity inference; unresolved labels are unverified |
| Unexpected Preview/Program change | Unexplained Preview mutations in Assist; unexplained Program mutations in Auto/Backup / all observed mutations, separated by actor | **0 observed**. Explain every change with admitted intent and observed effect; operator cuts remain separate |
| Mandatory fault/override coverage | Completed, observed scenario cells / all required cells, per route and level | **Every required cell passes**. Missing, skipped, timed-out or unobservable cells are incomplete, not pass |
| Cancellation and Take permits | Reused/stale/non-Preview/no-permit commits; commits from a cancelled notice; duplicate fallback / attempted relevant cases | **0 observed**. Refusal never retries later; observe the final sink and downstream Program, not just enum transitions |
| Readiness and ambiguous subjects | Invalid cut-bar entries; guessed close-ups under ambiguity; false ready states / labelled opportunities | **0 critical entries**. Preserve distinct prepare/cut bars and actual evidence; a legal manual Take remains available |
| Override timing | Host-clock ingress→authority revocation and last forbidden-effect rejection; UI acknowledgement measured separately | No effects after revocation; measured distributions must meet owner-frozen bounds. Null/unmeasured is not zero latency |
| Useful preparation | Correct useful ready preparations / annotated eligible opportunities; latency distribution for successes, misses and abstentions | Meet owner-frozen coverage and latency bars. Abstaining everywhere cannot pass; a zero denominator is N/A/incomplete |
| Pace / movement | Below-minimum cuts, repeated equivalent shots, motion-on-entry, jerks/reversals/edge clipping per cuts/triplets/Program minutes | No critical readiness/minimum-hold/illegal-crop violation; remaining quality rates meet the frozen profile budget and manual-baseline comparison |
| Shadow agreement | Would-prepare/cut matches / eligible comparisons under a predeclared input/time matching rule | Report all denominators, unmatched records and uncertainty; apply only the owner-frozen agreement bar. Agreement is not proof the operator or Director was correct |
| Program and workload | Delivered cadence/freshness, drops/repeats, memory/thermal and Program/Preview compute while Director workload runs | All applicable R2 and frozen Director workload gates pass; no raw-source fallback, silent destination switch or lowered show standard |
| Capture completeness | Sequence gaps, dropped records, unmatched attempts/results, missing evidence/parameter snapshots and unobserved effects | Critical scenario evidence must be complete. Other missing intervals remain unverified; repeat affected coverage under the frozen plan, retain the failed/incomplete attempt |

An opportunity is a pre-labelled interval with an eligible desired shot; callbacks, repeated frames and duplicate log entries do not multiply it. Count admission, effect commit and acknowledgement separately. Only an observed completed operator Take with post-Take Program is a cut label; an attempt, acceptance or would-cut is not. For technical rejection reasons, one attempt may have several reasons: reason totals are not the attempt denominator.

Report raw numerators, denominators, minutes, sessions and strata before aggregate rates. Do not pool synthetic/recorded/live, levels, routes or parameter versions to hit exposure. Repeated shots within an event are correlated; any uncertainty model must state its independence assumptions and clustering unit. A zero count with little exposure is not evidence of zero risk. This memo supplies neither a statistical guarantee nor a chosen confidence level/sample count.

## 4. Per-level scripts and route matrix

Run each required script on **Direct output (HDMI / USB-C)** and **Virtual Camera**, observing the actual selected downstream output. The `rehearsal` sink accepts frames without output and cannot fill either route cell. Each route has its own fingerprint, measurement and result; a cross-route claim requires both complete. Additional show standards/input formats/mode combinations need their own declared matrix, not extrapolation. D-05 will turn these scoring contracts into operator runbooks.

| Level | Required script and observation | Integration / decision dependencies |
|---|---|---|
| Assist | Start Manual; attempt unqualified selection; verify no effects. Under authorized trial, establish safe wide on Program and shot input on Preview, nominate/observe settled subject, prepare the app preset, verify only Preview changed with expected revisions. Exercise acquisition, hold, ambiguous crossing, declared loss, stale evidence and a gesture. Operator Take starts fresh on the new Preview without pause; every manual camera action including a refused attempt and Edit Live takes over. Hand to Alfie starts fresh work; Stop/relaunch is Manual. Count useful preparation against a manual baseline | B-01/B-02 ingress, B-03 shadow controller, B-05 real atomic sink, B-06 lookup and truthful UI. N4/parameter choices resolved for the scope. No Director cut or Program framing change |
| Auto | Re-run applicable Assist invariants; supervised single-presenter segments first. Observe actual cut policy and stricter cut bar, show the next Preview target, cancel before/at deadline, issue valid/refused/reused/stale permits, change roles/revisions/evidence during notice. Operator Take is a nudge with the frozen minimum hold; Manual fully takes over. If on-air moves are in scope, measure the approved slow path and interruption; if discovery/run sheet/model are in scope, exercise their shown picks/overrides/profile changes and workload | A-11/A-12 and B-07/B-08 permit/notice path; A4 and relevant style decisions. B-09/N2, B-10/workload, B-11/F3 only if approved and implemented. No cut to non-Preview and no unqualified capability hidden in an Auto label |
| Backup | Re-run applicable Auto invariants and approved notice policy while the present operator is busy with another booth task. Score whole eligible segments, panel/group ambiguity and breaks. Inject Program loss, stale wide, both inputs lost, rebind, output fault, expired hold window and pre-fault permit reuse. For approved fallback, observe one fresh verified-wide Preview cut inside the router hold window, then pause; otherwise observe unchanged R2 hold→standby and no raw frame. Reconnect does not resume old work | A-17/B-12/B-13 and owner-resolved R1/R2/A4. The open register mentions Auto/Backup fallback while the product proposal is Backup-only; resolve before trial. No unattended claim |

Include same-time and delayed-event permutations at the real adapter boundary: takeover before validation, between request/receipt/acknowledgement, stale replacement, duplicate callback, source generation change, fault during notice, invalid/nonnegative future clock evidence, cancellation and output refusal. Offline synthetic tests can inject events unsafe to repeat physically, but they do not replace live downstream observations or required real unplug/rebind drills. Stop safely when a critical fault is observed; do not manufacture a pass by continuing until a favorable repetition occurs.

## 5. Assist result worksheet

For each route/configuration, fill `runID`, source class, execution mode, plan digest, exact fingerprint, app/parameter versions, authorization reference, UTC start/end and observed minutes. Then record:

| Item | Result to enter (no pre-filled pass) |
|---|---|
| Startup/qualification/UI | Manual at launch; unavailable level refused; next shot and Alfie-set badge truthful; raw observations/reference |
| Real preparation boundary | Attempts / commits / rejected stale / unexpected Preview changes / Program changes; matching request and receipt references |
| Operator priority | Camera-action attempts including refusals, gestures and Edit Live; revocation/effect/UI timing; post-takeover effects |
| N1 / handback / restart | Actual operator Take outcomes, fresh Preview work, paused state, handback prerequisites, Stop/relaunch result |
| Subject/readiness | Correct/missed/ambiguous/lost opportunities; prepare versus cut evidence kept separate; unknown labels and reasons |
| Workload/output | Program and Preview metrics, current admission evidence and downstream observation on this route |
| Coverage/quality | Planned versus completed exposure and fault cells; missing records; useful coverage and latency against frozen bars |
| Disposition | Pass / fail / incomplete / not run; reviewer evidence reference, exclusions and required follow-up |

Until all required cells and both route rows are complete, record **incomplete**, even if executed tests passed. Keep raw failed/incomplete outcomes and the reason for any rerun. This worksheet makes Assist evaluable once the owner freezes the plan; it is not an authorization to run it now.

## 6. Sign-off, staleness and record handoff

Recommend three attestations over the same immutable assessment: **owner**, **event operator**, **independent technical reviewer**. The operator must have observed the relevant booth workflow; the independent reviewer must assess evidence independently of the implementation author. The owner must approve how identities and independence are verified. An approval records role, explicit approve/refuse decision, scope, record/evidence digest and UTC time; missing/refused signatures cannot be inferred from a green CI run or merged PR.

B-06's proposed [record format](../../docs/auto-director/qualification-record-format.md) binds each level to actual admission fields and separately proposed Director scope/parameter/build/evidence references. Qualification makes a level selectable, not enabled: runtime freshness, health, takeover, one-shot permits and current readiness still apply. Assist approval does not qualify Auto; Auto approval does not qualify Backup. Prior runs may support unchanged requirements with explicit provenance but do not silently transfer approval.

Recommend immediate withdrawal on a critical defect, mismatched fingerprint/build/policy/model/scope, revoked underlying admission, missing/corrupt required evidence, expired approval or incomplete signatories. Runtime source/output/admission faults must retire current grants regardless of stored approval. Restoring health cannot revive a queued effect. Record staleness/revocation explicitly, preserve audit references under the privacy limits, and require fresh owner review for requalification rather than resetting timestamps.

## 7. Privacy and current evidence

E2: no audio, microphone entitlement or active-speaker labels. AI-2: no network during a show. C3/AI-4: bounded local metadata, 30-day expiry and explicit local export; ordinary logs cannot live longer merely because referenced by a report. Exported copies preserve original capture times and source class. No frames, video, screenshots, embeddings, keypoints, gallery contents, tap coordinates, inferred names or children as targets in evaluation logs. Media collection remains blocked by E3; off-machine media transfer remains an independent open AI-3 choice. No media is collected by this memo.

Signatory identity is explicit human approval metadata in a controlled attestation, not a recognized subject name in a shadow log. Record only an opaque signer reference and role in the machine-readable format. An explicitly exported, reviewed evidence package may support later audit, but exporting data never grants qualification or extends the lifetime of its original ordinary log. See the record format for the unresolved approval-retention choice.

Current evidence is source inspection and prior reported synthetic tests, not a scored recorded/live evaluation. The known Suggest-Take extension and confirmed-as-face-visible proxy remain owner questions; the latter cannot stand in for independent P1 face-visibility evidence in an Auto/Backup qualification claim. R2 MULTI-QA, the real integration, complete frozen budgets and per-level approvals must be demonstrated by actual records, not assumed from the plan. All three levels remain **NOT QUALIFIED BY THIS MEMO**.
