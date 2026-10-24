# Auto Director rehearsal runbooks

D-05 · 18 October 2026 · **Prepared, not run. No level qualified.**

These checklists implement the [three product walkthroughs](../../docs/auto-director/product-contract.md) and [D-04 scoring protocol](qualification-protocol.md). Use the [blank scorecard](rehearsal-scorecard-template.csv) for every scenario/route/configuration. Record decisions in the [owner register](../../docs/handoff/stage3-4/DECISIONS.md); this runbook does not approve them.

Source check: `origin/main` `434e26aba298e4fb1fc7f32e028bad2f03fffae8`. The current DirectorController is shadow-only: `cancelNextCut` and `advanceSegment` are empty, and the real preparation/cut/fallback sinks are separate B-05/B-07/B-08/B-12 work. Open PRs and gallery states are not evidence of a working live path. **On that main revision the live scripts below are NOT RUN: stop at the capability check.** Repeat the source/build check on the actual candidate before a rehearsal.

## 1. Prepare one scored run

Assign a present operator, a downstream observer and an evidence recorder. One person may cover observation/recording only if the planned observations remain complete. Record opaque role references; keep personal contact information outside ordinary logs.

1. Create a run ID and copy the blank scorecard. Set its initial result to `not_run`. Keep earlier failed/incomplete attempts; assign reruns new IDs and link the prior run.
2. Record exact app commit/build, harness, parameter snapshot/digest, model (or rules-only), level, segment scope, UTC start/end, and each session's monotonic clock domain. Do not compare host times across sessions.
3. Attach the complete current admission fingerprint, setup attestation and R2 MULTI-QA evidence for the actual cameras, capture formats, Mac/OS, show standard and route. Check the [record mapping](../../docs/auto-director/qualification-record-format.md). A stored fingerprint alone cannot verify the physical rig.
4. Select one destination: **Direct output (HDMI / USB-C)** or **Virtual Camera**. Name the actual downstream endpoint in the controlled setup record. Put a human observer at that endpoint. The app preview, handoff counter and `Rehearsal · no output` sink cannot substitute for this observation.
5. Establish A as the verified safe-wide input and B as the shot input; label their actual roles on the worksheet. Verify the safe-wide coverage independently. If these roles are unavailable, stop; do not silently swap them during scoring.
6. Confirm every capability needed by this script is implemented in the candidate. Freeze the owner-approved decisions and parameters before measuring: dwell, notice, expiry, movement, N4, observation age, matching tolerance, workload budget, exposure and quality bars. A blank parameter is a blocker, not a default.
7. Attach the explicit authorization for the supervised trial and the qualification/enablement mechanism approved for that stage. An unqualified level must stay unavailable in ordinary operation. Do not forge a qualification file, bypass the gate or use test-only grants to run a rig.
8. Check data permission separately: E2 prohibits audio; no media recording or screenshots containing people without approved E3 scope. AI-3 separately controls off-machine disclosure. Use observation notes and permitted metadata when media permission is absent. Do not enable Training Data recording as a substitute for fixture consent.
9. Establish the operator's immediate takeover and Stop actions. The mode component defines **Manual / Hand to Alfie** and **Command Shift H**; verify the control is visible and bound once in this candidate. Use Manual explicitly during a fault so the toggle's current direction is unambiguous. Verify downstream output continues under manual R2 operation first.
10. Observe a manual baseline on comparable planned opportunities. Record its useful preparations/cuts, exposure, operator actions and workload separately. Freeze comparison rules before the Director run.

If any item is unavailable, enter the item ID and `not_run` or `incomplete` with the reason. Preparation is not a passing rehearsal. Owner approval of a trial is not per-level release qualification.

## 2. Assist: keynote with attended preparation

Prerequisites: B-05 preparation sink, actual evidence adapter, truthful console and current Assist qualification/trial authorization; N4 resolved for the scope. Run-sheet actions require separately approved F3 plus B-11/C-07. Without that capability use one Live event profile and mark run-sheet rows not run.

| ID | Operator action | Observe and score |
|---|---|---|
| AS-01 | Launch stopped; inspect the mode control. Attempt an unavailable level on an unqualified test setup. | Manual at launch; unavailable mode refuses with no camera/output effect. Record actual UI and state, not an assumed refusal. |
| AS-02 | Start the admitted show manually with A Wide on Program and B on Preview. Select the authorized Assist scope. | A stays Program at the frozen show standard. The actual downstream output matches Program. |
| AS-03 | Nominate the intended presenter on B, or use approved visual discovery if implemented. Let acquisition settle. | Learning/hold is not ready. A truthful Alfie-set badge appears only after Alfie actually prepares B; record request/commit/receipt separately. No Program change. |
| AS-04 | Observe the next eligible presenter opportunity, then press Take. | Only the operator cuts. Completed Take swaps roles; old work retires and Assist begins fresh on the new Preview without pausing. A refused Take is not a completed cut. |
| AS-05 | Take back to A; allow B preparation during its new Preview tenure. | N4 behavior matches the frozen policy; repeated observations do not silently re-prepare within a restricted tenure. |
| AS-06 | Adjust B, including a deliberately refused camera-command attempt in the test harness, then exercise Edit Live. | Both admitted and refused manual command ingress cause takeover. Edit Live also pauses preparation. No stale preparation occurs afterward. |
| AS-07 | Press Hand to Alfie after restoring prerequisites. | Only fresh work resumes; no old callback changes either shot. |
| AS-08 | Under the authorized subject script, show acquisition, brief hold, ambiguous crossing and declared loss. Exercise a gesture. | No guessed tight subject. Confirm prepare and stricter cut bars separately; `confirmed` is not independent face-visibility proof. A gesture inhibits new effects. |
| AS-09 | If the run-sheet path is in scope, explicitly advance to Panel, then Video/Break. | The chosen style changes only after the operator action; no authority is granted. Multiple people stay on wide/group coverage. A suggestion never advances the sheet. |
| AS-10 | Stop and relaunch. | Capture stops; old grants/work cannot survive; new launch is Manual. |

Record eligible preparation opportunities, useful ready preparations, misses, abstentions, unwanted Preview changes and every Program effect. Assist has **zero Director cuts and zero Director Program reframing**. Count operator Take attempts and completed cuts separately. Compare usefulness and latency with the manual baseline under the frozen bars; an always-abstaining Director cannot pass usefulness.

## 3. Auto: supervised presenter segment

Prerequisites: applicable Assist rows, A-11/A-12 plus B-07/B-08, approved A4 and style parameters, current Auto qualification/trial authorization. N2 slow moves, discovery, run sheet and learned judge are separate optional scope cells; do not imply they exist because Auto is selected.

| ID | Operator action | Observe and score |
|---|---|---|
| AU-01 | Set A Program / B Preview and start authorized Auto with an eligible prepared B shot. | Next cut names actual Preview. No cut before minimum dwell or before the stricter cut-ready bar. Nothing better ready may abstain indefinitely. |
| AU-02 | Let one eligible notice complete. | Visible configured notice, fresh decision and one-shot permit, then existing technical Take checks. Record attempt/admission/commit/acknowledgement separately; the sink result alone is not downstream presentation. |
| AU-03 | Cancel a notice early, just before deadline and at deadline using the deterministic harness. Verify the real Esc/control path in a separate rehearsal. | Cancellation is processed before firing and wins; no cut from that notice; full minimum-shot hold follows. Record opportunities and exact event order. A timing attempt without observed ordering is incomplete. |
| AU-04 | Use the harness to change Preview role, source generation, revisions, policy, nomination or readiness during a notice; replay a stale callback and reused permit. | Refusal is terminal, with no later cut and no effect on replacement work. A non-Preview target is never cut. |
| AU-05 | Press Take during Auto, including a refused attempt in the harness. | N1 nudge retires old work and blocks Director cuts for the frozen minimum duration. Take attempts and actual role swaps remain distinct. |
| AU-06 | Adjust a camera or choose Manual; later use Hand to Alfie. | Full takeover stops preparing/cutting immediately; handback starts fresh work only after current prerequisites. |
| AU-07 | If approved N2 is in scope, arrange one input or no better cut-ready input; request a one-step slow move, then interrupt with gesture/Edit Live/nudge. | Rate matches approved parameters; no snap or cross-format step, no move during inhibition, and at most one per minimum dwell. Measure actual downstream motion. Single-input qualification/enablement must be explicitly implemented. |
| AU-08 | Stop/relaunch; run applicable fault rows below. | Manual launch, all prior notices and permits retired. |

Score cuts to wrong input, missing/invalid/reused permits, post-takeover effects, cancellation failures and readiness/minimum-hold violations as critical events. Record motion/pace distributions separately; apparent agreement with the operator cannot excuse a critical failure.

## 4. Backup: operator present but busy

Prerequisites: applicable Auto rows; A-17/B-12/B-13; resolved R1/R2/A4; exact fallback capability sign-off/trial authorization. The open register's Auto/Backup recommendation and the narrower Backup-only product proposal must be reconciled before a fallback trial.

1. Set A verified safe wide, B shot input. Select the authorized Backup scope. Observe the always-visible next cut and approved no-countdown behavior. The operator stays present while performing another planned booth task.
2. Run whole eligible Presenter, Panel and Video/Break segments in the frozen scope. Log exposure by segment, all opportunities and abstentions. Several plausible people must not produce a guessed tight shot. Run-sheet changes remain operator actions.
3. With B on Program, perform FD-01 below. If fallback is approved and ready, observe exactly one cut to fresh verified A while the original router hold remains active, then pause. No old normal permit can authorize the fallback.
4. Reconnect B and confirm a new source generation. Restoration must leave the Director paused; only explicit Hand to Alfie after current prerequisites can resume it.
5. Perform FD-02 through FD-05. Where fallback is unsafe, observe unchanged R2 hold → generated standby and an operator-visible state. Never count a raw source, silent route switch or arbitrary input substitution as recovery.
6. Take over, Stop and relaunch. Confirm no pending fault permit remains and launch is Manual.

## 5. Fault drills

Use a disconnected test destination or authorized rehearsal rig, with the operator ready to take over. Disconnect the named **capture source**, not power or an unidentified cable. For dangerous/impractical races use a deterministic adapter/harness and label them synthetic; do not claim that replaces the required physical observation.

| ID | Controlled injection | Required observation / recovery |
|---|---|---|
| FD-01 Program unplug | Note Program/Preview and host time, then unplug only Program's capture connection. | Assist/Auto pause and retain R2 recovery. Authorized Backup alone may make one fresh verified-wide Preview fallback inside the actual router deadline, then stays paused. If ineligible, hold → standby with no raw frame. Record loss, hold entry, deadline, attempt, commit and observed destination. |
| FD-02 Stale safe wide / both stale | With a harness first, stop fresh Preview delivery; separately lose both inputs. | No fallback to stale/missing Preview. R2 hold → standby continues. Mark any absence of downstream observation incomplete. Restore sources; remain paused. |
| FD-03 Rebind | Capture a pending operation in the harness; rebind/restart that source, then release the old callback. Separately reconnect the real rig. | New source generation invalidates old work. Old permit/receipt cannot cut or prepare; no automatic resume. Record old/new generation and callback outcome. |
| FD-04 Output fault | In the harness, make the selected sink refuse/unavailable; separately disconnect the known downstream output path on the rehearsal rig. | Pause/retire grants; no automatic switch to another route or source. A receiver disconnect may not be detectable by the app: record observed behavior without inventing an acknowledgement. Restore and recheck the exact endpoint manually. |
| FD-05 Deadline / reuse | In the harness delay fallback until exactly the router standby deadline and after it, replay a pre-fault permit, duplicate a callback, and inject takeover/output/admission loss before consumption. | Zero effects outside the original hold window; zero repeated effects; replacement work stays intact. Do not restart the router window on callback arrival. |

On any critical event: choose Manual, stabilize with existing R2 controls, Stop if needed, preserve allowed evidence, and mark `fail`. Record the failure before any rerun. If permission or required evidence is missing, mark `incomplete/not_run`; do not manufacture a pass from the remaining rows.

## 6. Score, close and hand off

Complete a separate row for each scenario, route, level, source class, parameter version and setup. Blank means unknown, not zero. Use `pass`, `fail`, `incomplete` or `not_run`; `N/A` requires a scope reason and cannot remove a mandatory coverage cell.

- Record eligible opportunities, actual attempts, admitted attempts, committed effects and observed downstream effects separately. Keep duplicate callbacks, rejected attempts, dropped records and sequence gaps visible.
- Report Program minutes, sessions, valid labelled comparisons, unmatched records, abstentions by reason, useful/missed preparations, cut and move counts, dwell/override latency distributions, and workload against the frozen budgets. State how intervals/opportunities were labelled and how matching worked.
- Keep synthetic, recorded and live evidence in separate denominators. A camera input clip is recorded evidence; a rehearsal sink is an output mode; neither becomes live qualification. Unknown ground truth remains unlabelled.
- Use independent subject/face-visibility observations where required. Do not infer them from lock, gallery or the app's own readiness result. Keep participant identities out of ordinary logs.
- Require both output routes for a cross-route claim. A missing mandatory fault, observation, exposure bar or signature leaves the assessment incomplete.
- Reference the [qualification record format](../../docs/auto-director/qualification-record-format.md), evidence digest, exact scope/exclusions and owner/operator/independent-reviewer attestations. Leave signatures empty until actually supplied. No code merge, test pass or completed worksheet supplies sign-off.

Initial route matrix (replace only with observed results):

| Level | Direct output | Virtual Camera |
|---|---|---|
| Assist | NOT RUN | NOT RUN |
| Auto | NOT RUN | NOT RUN |
| Backup | NOT RUN | NOT RUN |

No run, collection, upload, qualification or approval was performed while preparing this document.
