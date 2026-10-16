# D-03 — Bounded discovery workload protocol

**AWAITING OWNER — proposed protocol, not run.** Prepared 2026-10-10 against `origin/main` `42191c71ec303e3f7d388c7cdafb5d5ef93d89db`. No scan rate, performance budget, qualification or runtime change is approved by this memo. The [named-rig worksheet](discovery-rig-budget.md) contains the budget table and missing evidence. This replaces the earlier guessed timing, memory, coverage and cadence starting values.

[Recorded decisions](../../docs/handoff/stage3-4/DECISIONS.md) override stale proposed headers elsewhere. UC-1/UC-2 require an operator and one shot per input; E2 excludes audio; E1 preserves operator nomination and visible selection; A1/N1 preserve takeover and the recorded operator-Take distinction; P1/P2 preserve readiness and wider fallback. AI-2 prohibits show-time network; C3/AI-4 require bounded metadata, 30-day retention and explicit export. C1/C2 and E3 remain owner questions. The [product contract](../../docs/auto-director/product-contract.md) and [B-10/D-03 tickets](../../docs/handoff/stage3-4/STAGE3-TICKETS.md) define scope.

## Options and recommendation

| Owner question | Options | Recommendation, tradeoff and evidence |
|---|---|---|
| C1: additional discovery work | Reuse observations only; bounded off-air scans; additional model | Calibrate the B-10 bounded scan separately from reuse-only baseline. It can find an unlocked presenter but adds full-frame Vision work; do not enable it before measurement. F-H says operator gating was part of the lag fix. No audio option is available under E2. |
| C2: admission scope | R2 result alone; discovery workload record tied to R2 fingerprint; generic Mac list | Use a separately versioned workload record tied to the exact R2 fingerprint and build. More records, but an R2 pass without discovery cannot demonstrate its additional cost. |
| Pressure response | Continue scanning; suspend optional discovery; silently reduce Program quality | Propose suspending discovery first, retaining operator control and qualified base-pipeline behavior. This reduces discovery coverage; never reduce Program standard, expand queues or bypass readiness to pass. The runtime integration remains unimplemented by this memo. |

## Preserve the operator gate (F-H)

The current [detector](../../CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift) modes `off` and `awaitingTap` do not run Vision. In [CameraManager](../../CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift), inactive `detectionDiscoveryActive` selects `awaitingTap`: its name does **not** mean periodic discovery exists. Pending taps acquire an ROI; locked tracking uses an ROI with occasional gallery refresh; lost-lock `reacquiring` can use full-frame faces. Existing recovery and the proposed unlocked-person scan must be separately identified in measurements. This memo does not claim the current app has no full-frame work.

B-10 proposes a new low-rate full-frame person scan only on **off-air inputs without a lock**. A visible candidate goes through selection and the normal acquire → lock path; discovery is neither prepare-ready nor cut-ready and grants no control or Take permit. Respect nomination, manual takeover, gestures, Edit Live and source/route changes. Do not replace an operator lock, infer a name, target children or create multiple virtual inputs/shots from a camera. Preserve the existing manual controls and tap path. An operator Take must retire old-tenure discovery work; subsequent work must obey the recorded N1 behavior and current eligibility.

Proposed acceptance requires checking Program/off-air status, authority, source generation, tenure, lock and gesture eligibility before scheduling, immediately before Vision and before publishing/adopting a result. Queued work becoming ineligible is cancelled. A non-preemptible call already running at a Take must be reported as such; reject its result and start no further discovery on Program. Do not describe generation rejection as cancellation of Vision execution. Whether B-10 must additionally prevent any in-flight full-frame work overlapping a Take is an **owner/integration question**, not permission to delay or block manual Take. Measure and disclose that overlap separately; it cannot silently satisfy a literal “Program never scanned” gate.

## Existing scheduler boundaries and integration requests

[FrameWorkScheduler](../../CinematicCoreMacOS/CinematicCoreMacOS/FrameWorkScheduler.swift) has separate render/perception lanes, one running permit per lane and at most one latest waiting request per channel per lane. Program priority is bounded by its existing `maxProgramStreak`; this is not a discovery rate. Running work is not preempted and there is no elapsed-time service guarantee. Current channels are A/B; three/four-input fairness is unproven and INPUTS-N remains gated.

The normal asynchronous detection path has one in-flight detection per input, obtains a perception permit and checks generation before work and publication. The operator-tap path separately awaits detection and does not use this scheduler path. New periodic scans must not reuse that bypass; preserve operator priority and measure interference with taps. `detectionFrameInterval` is a frame interval, not Hz or a measurement of completed scans.

Existing scheduler stats are per-channel granted/superseded/cancelled totals across work classes. They do not identify discovery, permit wait or occupied time. **Requested B-10/instrumentation integration:** a distinct discovery mode/work kind; rate-limiter configuration and revision; eligibility/rejection reasons; bounded counters for requests, starts, completions, supersessions and stale-result rejection; host timestamps for permit wait and service; channel/source/tenure identity. These are requested fields, not existing APIs. Rate limiting must not accumulate a catch-up burst after ineligibility or stalls; any burst allowance must be explicit, frozen and tested.

## Budget definition and calibration

For each named rig × real output route × show standard × exact input configuration, freeze the following study parameters before a scored run:

| Symbol | Meaning / units | Status |
|---|---|---|
| `N`, eligible input set | Admitted input count; off-air unlocked subset | Initially two admitted inputs, so at most one off-air candidate; one-input Program has no eligible discovery input. Three/four inputs blocked by INPUTS-N. |
| `r_i`, `R = sum(r_i)` | Requested maximum scan starts per second for each eligible input and aggregate | Candidate values derived from pilot; finite, nonnegative, supplied explicitly. Missing/invalid budget means discovery disabled, evidence incomplete. |
| `s_i` | Measured discovery service seconds per completed scan, with distribution/tail support stated | Missing pilot data; report content, resolution, scan type and sample counts. |
| `D = sum(r_i × s_i)` | Estimated perception service seconds per wall second | Planning estimate only: not CPU utilization, queue prediction or proof of headroom. Shared work and bursts need measurement. |
| Exposure and limits | Warm-up, paired-window duration, soak duration, repeats, rate/burst rule, maximum age, pressure/stop bounds | AWAITING OWNER; no replacement production defaults. Preserve any separately frozen R2 exposure requirement. |

1. Confirm rig ownership, exact inputs/cables/hubs, power state, real consumer/display and route, show standard, app/source build and R2 admission evidence. Inventory is not certification. Freeze telemetry schema and missing-data rules before collection.
2. Collect matched discovery-disabled baselines for normal unlocked wide, tracking, reacquisition, manual framing and operator taps. Preserve the same Program/Preview roles and actual input format/rate. The disabled baseline is not a proposed production rate.
3. In an explicitly authorized lab pilot, sweep owner-supplied candidate rates on eligible off-air unlocked inputs. Start values, exposure and stop limits must be supplied before the pilot; this memo invents none. Include low/high scene complexity, empty frame, occlusion, entry/exit, motion and loss/recovery without creating identity-labelled datasets.
4. Alternate and reverse baseline/enabled order, exchange A/B roles, repeat after thermal stabilization, and include sustained soak and repeated manual takeover/Take/rebind/output-loss drills. Match windows; split at route, generation or role changes. Do not average a failure away across routes or roles.
5. Estimate feasible rate and uncertainty from measured headroom, useful selection latency and tails. Choose candidate limits from pilot data with owner-approved margin, freeze a versioned table, then evaluate separate held-out runs. A threshold tuned on the scored run requires a new freeze and rerun.
6. Report every cell as pass/fail/incomplete with exposure and missing fields. Rehearsal output is useful synthetic plumbing evidence, never a substitute for either real route. No live trial begins without its prerequisites and explicit per-level authorization.

Synthetic tests establish boundedness and fault behavior; recorded replay establishes only behavior for its supplied traces; live metadata measurements establish workload on the actual rig. Label each artifact and every source explicitly. Keep classes separate; do not relabel mixed sources as live. No new recorded media may be collected without E3. These runs cannot qualify Assist, Auto or Backup; separate owner, event-operator and independent-reviewer signatures per level are required under the [D-04 proposal](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/24).

## What `[SOAK]` and current diagnostics actually measure

[DiagnosticsLog](../../CinematicCoreMacOS/CinematicCoreMacOS/DiagnosticsLog.swift) defines CSV `MetricColumn` units, windows and provenance. Console `[SOAK]` fields below have mixed window/cumulative semantics. Compare actual elapsed windows and configuration; never compare raw cumulative counts between different-duration runs.

| Existing `[SOAK]` field | Meaning | Comparison |
|---|---|---|
| `footprint` | Current physical footprint, MB | Baseline/enabled level, high water and post-warm-up slope; not RSS or a GPU allocation count. |
| `hopLag` | Mean/max callback-enqueue → MainActor lag, ms | Same-window paired delta plus absolute frozen bound. |
| `queueWait` | Mean/max detection dispatch queue wait, ms | Not scheduler-permit wait; do not claim scheduler fairness from it. |
| `visionWall` | Mean/max Vision wall time, ms | Existing detection modes combined; discovery attribution needs requested mode tag. |
| `delivered`, `admitted` | Window frame counts | Delivered = admitted + gate-skipped; preserve capture-drop evidence separately. |
| `handoff`, `refused` | Cumulative accepted/refused handoffs | Use validated deltas or CSV window counters; resets/discontinuities invalidate naive subtraction. Accepted is not presented. |
| `repeated`, `renderFailed`, `captureDropped` | Window counts | Compare rates and totals with exposure. Repeats are not new camera frames. |
| `gateDrops` | Window / cumulative gate-skipped counts | Separate one-frame processing-gate skips from capture drops and output failures. |

Existing CSV adds `window_s`, `window_kind`, `cpu_cores`, `cpu_pct`, `thermal`, `low_power`, `frame_wall_mean_ms/max_ms`, `main_active_mean_ms/max_ms`, `observation_age_mean_ms/max_ms`, `detections`, `detector_fps`, `processed_input_fps`, `handoff_fps`, routing counters and `diag_emit_ms`. These abbreviated mean/max pairs denote the separate columns with the shared prefix. `detector_fps` counts all completed Vision runs divided by `window_s`, not discovery alone. `processed_input_fps` is an existing rolling source-PTS measure; `handoff_fps` includes repeats. `presented_fps` is **unknown**: no consumer/display presentation acknowledgement exists. Observation age is captured detection frame → composer consumption, not sensor-exposure latency.

`cpu_cores` is CPU seconds per second; `cpu_pct` is that value × 100 and can exceed 100. Do not feed `cpu_pct / 100` into a normalized-capacity `[0,1]` policy without an explicitly defined denominator. Memory CSV distinguishes physical/internal/compressed/external/heap measurements; `external_mb` is not a distinct IOSurface/GPU buffer count. Process CPU/memory are not attributed exclusively to discovery. Existing means/maxima do not yield p95/p99; request bounded histograms if those pass bars are selected, with memory limits and no frame retention.

[RouterChannelPort in ProgramRouter](../../CinematicCoreMacOS/CinematicCoreMacOS/ProgramRouter.swift) forwards detailed diagnostics only for Program. Consequently these CSVs cannot establish off-air scan rate/age/wait by themselves, and a window crossing Take may combine channels. Existing `PreviewAdmissionSample` exposes only rendered frames and window seconds. **Requested integration:** per-input discovery counters/timings, role/generation boundaries, scheduler occupancy/wait, cancellation-to-last-effect timing and independently observed real output cadence. Deadline-miss fraction needs a defined deadline and instrumented denominator; handoff refusal, capture drops and frame-wall means are not substitutes. The `[SOAK]` line alone is insufficient to pass D-03.

## Proposed pass/fail bars — AWAITING OWNER

| Gate | Proposed bar | Missing evidence / failure rule |
|---|---|---|
| Authority and privacy | Zero observed discovery starts on Program/ineligible inputs, unauthorized lock replacements, adopted stale results, gesture/takeover bypasses, media/audio/name logging or show-network activity | Enumerate opportunities and fault exposure. Any observed violation fails; unobserved/instrumentation gaps are incomplete, not zero. In-flight overlap is separately unresolved above. |
| Bounded work | Starts obey each frozen `r_i` and its explicit burst rule; existing one-running-per-lane / one-waiting-per-channel bounds remain intact; no new retained frame queue | Test stalls, supersession and generation changes; requested instrumentation must prove the new work participates in these bounds. |
| Base pipeline | Pass every applicable frozen R2 admission/route gate with discovery enabled, at unchanged show standard | Require exact fingerprint and actual real-route evidence. A provisional/unknown R2 status is not certification. |
| Added cost | Absolute limits and paired increases for hop, main-active/frame wall, observation age, memory slope/high water, CPU and thermal within owner-frozen pilot-derived budgets | All numeric bounds currently unset in worksheet. No pass until limits, exposure and required statistics exist. Use appropriate weights, not an unweighted mean of means. |
| Output and operator response | Real output cadence and takeover/gesture latency meet separately frozen bounds; no hidden repeats or dropped source substituted for success | Consumer presentation and cancellation timing need additional evidence. Unknown is incomplete. Never delay manual Take to make a workload measurement pass. |
| Useful discovery | Latency/coverage on labelled, eligible visible opportunities meets frozen target while all safety/resource gates pass | Define denominator, ambiguous cases and nomination precedence before scoring. A wide suggestion does not establish readiness. Missing utility pilot prevents selecting a rate. |
| Stability/revocation | Required sustained exposure passes per route; mismatch, stale record or missing required measurement disables claimed workload approval | Discovery suspension/recovery must not restore Director authority. No silent reuse across build/policy/input/route changes. |

[CapabilityReport](../../CinematicCoreMacOS/CinematicCoreMacOS/CapabilityReport.swift) and `PairAdmission` have existing **provisional** thresholds; do not relabel them approved discovery limits. Set detection expectations truthfully: a no-detection baseline and enabled discovery are different workloads. [DegradePolicy](../../CinematicCoreMacOS/CinematicCoreMacOS/DegradePolicy.swift) is a pure policy model with inputs including normalized CPU, deadlines and ages; its presence does not prove runtime shedding or those measurements exist. Any selected C1/C2 pressure policy requires implementation and test evidence before claiming it works.

## Privacy and evidence handling

Collect only bounded local numeric/categorical metadata, opaque session/channel IDs and versions needed to reproduce the workload. Apply 30-day ordinary metadata retention and explicit dataset export under C3/AI-4; export is an intentional reviewable action, not show-time network permission or silent retention renewal. Track creation/expiry/export metadata and verify cleanup across CSV, manifests and console-derived artifacts. Retention/export wiring is an integration prerequisite, not implemented by this document.

Never include frames, thumbnails, video, audio, transcripts, embeddings, person names, inferred identity, child targets, device serials, source URLs or unrestricted notes. Do not blindly export current diagnostics manifests (`deviceName` and other free text) or CSV `note`/local `clock`; project the minimal allowlist and monotonic elapsed times. Existing application capture buffers remain ephemeral pipeline work, not study recordings. E3 is required before any new study media retention; missing E3 is not fixed by labelling a run “recorded.”

Evidence reviewed: the linked source files at the stated main revision, the recorded decisions/tickets and local non-identifying machine inventory. No camera, output route, performance trial or new study collection was run for this memo. Missing pilot and owner gates remain visible in the companion worksheet.
