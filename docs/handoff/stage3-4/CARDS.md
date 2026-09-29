# Stage 3 / Stage 4 Trello cards — snapshot 30 Sep 2026

Copied from the "Alfie Coding Board" (https://trello.com/b/FkxA6E36/alfie-coding-board) so agents without Trello access have the exact card text. Trello stays the source of truth; this copy is read-only context. Card text is a proposal: every R3/R4 card says decisions are open and no implementation is authorised by the draft itself.

######## [ROADMAP] Single camera → Multi-camera → Auto Director → Physical control
URL: https://trello.com/c/hvK9YzKN/25-roadmap-single-camera-%E2%86%92-multi-camera-%E2%86%92-auto-director-%E2%86%92-physical-control
## Four product stages
R1 — Dependable single camera: core beta released; lag, readiness and sustained-output validation remain. [R1 gate](https://trello.com/c/IDAjbyA9); [LAG-DIAG](https://trello.com/c/D6KPsTw4).
R2 — Multi-camera: one output, two live inputs first; four UI slots, with inputs 3–4 gated on two-input QA. Gallery UI exists; channel/router/Take remain unbuilt. [Channels](https://trello.com/c/4sFQx8lb); [technical/store gates](https://trello.com/c/fALbW5sX).
R3 — Auto Director: prepare/select shots under approved rules; a coordinator above existing camera modes. Proposed, not implementation-ready.
R4 — Physical control and expanded automation: protocol or actuator, calibration, telemetry, emergency stop, coordinated framing and optional offline voice. Deferred until R3 qualification.

## Auto Director work
[AD-SCOPE](https://trello.com/c/RzNRzLzV)
[AD-PREFS](https://trello.com/c/Re5j7Bt4)
[AD-SUBJECT](https://trello.com/c/Vs5JzYzF)
[AD-ROLES](https://trello.com/c/NIgYGG4C)
[AD-STYLE](https://trello.com/c/ORiADKgA)
[AD-PREPARE](https://trello.com/c/BbkpFx8K)
[AD-OVERRIDE](https://trello.com/c/lMdFMboz)
[AD-TAKE](https://trello.com/c/3eZzPx9M)
[AD-UI](https://trello.com/c/zQ4d3i3H)
[AD-COMPUTE](https://trello.com/c/roId5VyH)
[AD-QA](https://trello.com/c/KSRnlMWe)

## Boundaries
Sermon-focused Auto Prepare is a recommendation awaiting approval. No automatic cuts authorised by these drafts. Cards carry questions, logic, files, outcomes, confidence, effort and dependencies. Lists track workflow; R1–R4 are product stages; old S1–S7 are engineering work IDs.
Licensing, guide and beta delivery support the roadmap. Store launch has separate gates. No iOS port or extra output planned. Inputs 3–4 need INPUTS-N/CUE/ADMISSION-N/MULTI-QA-N. Stage 4 hardware choice: [HW-CHOICE](https://trello.com/c/nTylkwW1).

######## [R3][AD-SCOPE][DECISION] Choose first directing use case and autonomy level
URL: https://trello.com/c/RzNRzLzV/54-r3ad-scopedecision-choose-first-directing-use-case-and-autonomy-level
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Bound the first release before implementation.

**Open questions** Sermon, worship, panel or whole service? Suggest only, Auto Prepare or Auto Direct first? Can levels change live? What must remain manual?

**Proposed logic** Record approved use cases, autonomy transitions and exclusions. Sermon-focused Auto Prepare with operator-selected subject is a proposal, not an accepted decision.

**Files** New docs/auto-director/product-contract.md. New names are proposals.

**Expected result / acceptance** Approved examples and explicit unsupported scenarios; no automatic Take before its separate acceptance gate.

**Dependencies** [R2 technical gate](https://trello.com/c/fALbW5sX)

**Confidence** Medium.

**Implementation size** S (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-PREFS][DESIGN] Define directing presets, preferences and service cues
URL: https://trello.com/c/Re5j7Bt4/55-r3ad-prefsdesign-define-directing-presets-preferences-and-service-cues
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Give volunteers predictable instruction controls.

**Open questions** Which built-in styles/settings? Structured controls or natural language? Service cues/rundown? Can rules change mid-show?

**Proposed logic** Version a structured preference model with validation and safe defaults. Natural-language interpretation remains optional future scope until approved; resolve conflicting preferences deterministically.

**Files** Proposed DirectorPreferences.swift, DirectorPreferencesTests.swift; SettingsWindow.swift. New names are proposals.

**Expected result / acceptance** Invalid/conflicting settings handled; preferences round-trip; approved cue changes do not trigger an unintended cut.

**Dependencies** [AD-SCOPE](https://trello.com/c/RzNRzLzV)

**Confidence** Medium.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-SUBJECT][SPIKE] Decide evidence for subject and active-speaker selection
URL: https://trello.com/c/Vs5JzYzF/56-r3ad-subjectspike-decide-evidence-for-subject-and-active-speaker-selection
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Person detection alone does not establish who should be live.

**Open questions** Operator-nominated subject or autonomous selection? What visual/audio/operator/rundown evidence permits switching person? Is audio allowed, local-only and recorded?

**Proposed logic** Compare evidence on representative recordings; retain identity vetoes and abstain when uncertain. No active-speaker claim from visual detection alone. Resolve privacy/retention before adding audio.

**Files** Proposed docs/auto-director/subject-evidence.md, replay fixtures; PersonDetector.swift, ShotComposer.swift integration only after decision. New names are proposals.

**Expected result / acceptance** Report wrong-person events and denominators, ambiguity/occlusion cases and approved evidence thresholds; no unapproved audio collection.

**Dependencies** [AD-SCOPE](https://trello.com/c/RzNRzLzV)

**Confidence** Low until evaluation.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-ROLES][DESIGN] Assign camera roles and safe fallback policies
URL: https://trello.com/c/NIgYGG4C/57-r3ad-rolesdesign-assign-camera-roles-and-safe-fallback-policies
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Auto direction must have an explicit response to unavailable shots.

**Open questions** Speaker close-up versus safe wide roles? Must one camera preserve fallback? On subject/camera loss: hold, widen, safe Take or ask operator?

**Proposed logic** Define role eligibility and a state/response table. Separate director-authorized fallback from R2 manual operation, which never silently switches sources. Never cut to stale or invalid fallback.

**Files** Proposed DirectorCameraPolicy.swift, DirectorFailurePolicyTests.swift; ShowCoordinator.swift. New names are proposals.

**Expected result / acceptance** Loss/no-safe-shot scenarios are deterministic; operator override dominates; no implicit R2 failover added.

**Dependencies** [AD-SCOPE](https://trello.com/c/RzNRzLzV), [AD-SUBJECT](https://trello.com/c/Vs5JzYzF)

**Confidence** Medium.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-STYLE][DESIGN] Specify shot duration, movement and transition rules
URL: https://trello.com/c/ORiADKgA/58-r3ad-styledesign-specify-shot-duration-movement-and-transition-rules
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Avoid distracting cuts and unnecessary camera movement.

**Open questions** Minimum/maximum shot duration? Frequency of Wide? Repetition avoidance? Allowed zoom/pan speeds? Move live or prepare off-air? May a cut land on a moving shot?

**Proposed logic** Define bounded rules over existing presets/modes; Auto Director is a coordinator, not a fifth crop mode. Preserve cinematic shot moves and hard quality limits; numerical timing is approved before implementation.

**Files** Proposed DirectorShotPolicy.swift, DirectorShotPolicyTests.swift. New names are proposals.

**Expected result / acceptance** Recorded sequences demonstrate approved pace, no cut oscillation and movement within limits; rules remain explainable.

**Dependencies** [AD-PREFS](https://trello.com/c/Re5j7Bt4), [AD-ROLES](https://trello.com/c/NIgYGG4C)

**Confidence** Medium.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-PREPARE][FEATURE] Prepare eligible next shots in Preview
URL: https://trello.com/c/BbkpFx8K/59-r3ad-preparefeature-prepare-eligible-next-shots-in-preview
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Build automatic preparation on the proven two-input pipeline.

**Open questions** What constitutes readiness: identity, framing, source age, settling or allowed motion? What happens when preparation becomes stale?

**Proposed logic** Generate bounded shot proposals and dispatch commands to Preview only. Track target/generation/shot revision; invalidate on intervention or input change. Use R2 frame readiness and subject evidence, not a second framing/output path.

**Files** Proposed AutoDirector.swift, DirectorProposal.swift, AutoPrepareTests.swift; ShowCoordinator.swift. New names are proposals.

**Expected result / acceptance** Program stays unchanged during preparation; stale proposals reject; stationary and moving shot preparation obeys approved readiness.

**Dependencies** [AD-SUBJECT](https://trello.com/c/Vs5JzYzF), [AD-STYLE](https://trello.com/c/ORiADKgA)

**Confidence** Medium after R2.

**Implementation size** L (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-OVERRIDE][FEATURE] Define manual priority, pause, shot pin and resume
URL: https://trello.com/c/lMdFMboz/60-r3ad-overridefeature-define-manual-priority-pause-shot-pin-and-resume
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** A volunteer must be able to regain control immediately.

**Open questions** Any control pauses all direction or one channel? How is it resumed? Can a shot be pinned? What happens to pending Take/preparation?

**Proposed logic** Explicit authority state machine with cancellation tokens/epochs. Manual commands revoke conflicting director authority before taking effect; resumption is explicit. Stop/Wide remain accessible.

**Files** Proposed DirectorAuthority.swift, DirectorAuthorityTests.swift; OperatorCommand.swift, OperatorPill.swift. New names are proposals.

**Expected result / acceptance** Race tests for manual input vs queued prepare/Take; no later automatic command reverses operator action; pin/pause/resume behavior agreed.

**Dependencies** [AD-SCOPE](https://trello.com/c/RzNRzLzV)

**Confidence** High on principle; transitions open.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-TAKE][FEATURE] Enable automatic Take only within approved authority
URL: https://trello.com/c/3eZzPx9M/61-r3ad-takefeature-enable-automatic-take-only-within-approved-authority
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Automatic live cuts need a separate safety and quality gate.

**Open questions** When may Auto Direct be enabled? Which shot-readiness and editorial conditions permit a cut? Does loss permit an approved fallback?

**Proposed logic** Reuse the R2 atomic Take path; no bypass of freshness, source generation or format checks. Require current director authority and approved policy. Suggest/Auto Prepare modes never cut automatically. Keep deterministic decision reasons.

**Files** Proposed AutoTakePolicy.swift, AutoTakeTests.swift; AutoDirector.swift, OperatorCommand.swift. New names are proposals.

**Expected result / acceptance** Rejected/stale/racing/duplicate Takes preserve Program; manual intervention wins; unattended Take remains disabled until qualification.

**Dependencies** [AD-PREPARE](https://trello.com/c/BbkpFx8K), [AD-OVERRIDE](https://trello.com/c/lMdFMboz)

**Confidence** Medium-low until replay/live trials.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-UI][DESIGN] Show autonomy state, next-shot reasons and operator controls
URL: https://trello.com/c/zQ4d3i3H/62-r3ad-uidesign-show-autonomy-state-next-shot-reasons-and-operator-controls
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Make automatic decisions understandable without crowding the pill.

**Open questions** Show proposed shot/reason? Countdown before Take? Where do enable, pause, pin and resume live? How do users distinguish suggested versus armed actions?

**Proposed logic** Prototype concise visible authority and next-shot status with accessible controls; inspector holds detail. No hidden emergency manual override. Countdown, if approved, is cancellable and cannot bypass revalidation.

**Files** ContentView.swift, OperatorPill.swift, SettingsWindow.swift; new UI design notes. New names are proposals.

**Expected result / acceptance** One-handed 1280-point rehearsal; operator can identify live/Preview, autonomy and next action; no unannounced authority change.

**Dependencies** [AD-PREFS](https://trello.com/c/Re5j7Bt4), [AD-OVERRIDE](https://trello.com/c/lMdFMboz), [AD-TAKE](https://trello.com/c/3eZzPx9M)

**Confidence** Medium; prototype review needed.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-COMPUTE][SPIKE] Measure director workload and local processing limits
URL: https://trello.com/c/roId5VyH/63-r3ad-computespike-measure-director-workload-and-local-processing-limits
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Additional analysis must not degrade Program delivery.

**Open questions** Video only or audio too? Must all inference remain offline? What hardware/workload limits apply? What is retained or exported?

**Proposed logic** Measure directing overhead on qualified R2 rigs. Extend admission with bounded analysis cadence and memory; preserve output/identity safeguards. Unknown machines remain unverified; no model/LLM requirement without evidence.

**Files** SetupCheck.swift, CapabilityReport.swift, DiagnosticsLog.swift; new reports/auto-director/workload.md. New names are proposals.

**Expected result / acceptance** Baseline versus enabled timing/memory/thermal evidence; bounded queues; approved privacy/data inventory; honest supported matrix.

**Dependencies** [AD-SUBJECT](https://trello.com/c/Vs5JzYzF), [AD-PREPARE](https://trello.com/c/BbkpFx8K)

**Confidence** Low until measurements.

**Implementation size** M (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R3][AD-QA][VALIDATE] Qualify Suggest, Auto Prepare and Auto Direct separately
URL: https://trello.com/c/KSRnlMWe/64-r3ad-qavalidate-qualify-suggest-auto-prepare-and-auto-direct-separately
Stage 3 · Design backlog — decisions open; not implementation-ready. Depends on Stage 2 technical validation, not App Store launch.

**Why** Good framing is not sufficient evidence of good directing.

**Open questions** What counts as wrong-subject cut, excessive switching or bad movement? Which fixtures/live services and pass budgets? Who signs off each autonomy level?

**Proposed logic** Freeze metrics and acceptance thresholds before runs. Evaluate replay first, supervised live trial next, then explicit Auto Direct sign-off. Record candidate, policy/version, rig and operator interventions. R2 technical gate is prerequisite; hardware/robotics remain Stage 4.

**Files** New reports/auto-director/qualification.md; director regression fixtures. New names are proposals.

**Expected result / acceptance** Approved scope, decision register, manual override, failure cases, measured compute and editorial outcomes signed off separately for each autonomy level.

**Dependencies** [AD-UI](https://trello.com/c/zQ4d3i3H), [AD-COMPUTE](https://trello.com/c/roId5VyH), [AD-TAKE](https://trello.com/c/3eZzPx9M)

**Confidence** High method confidence; outcome unproven.

**Implementation size** L (S 1–2, M 3–5, L 6–10 engineering days; rough estimate, excludes research/rig waits; re-estimate after decisions).

**Out of scope** Physical movement, new crop mode, third input, extra output. No implementation authorised by this draft.

######## [R4][DEFERRED] [S7][FEATURE] Hybrid physical yaw + digital zoom / fine pan
URL: https://trello.com/c/e3unhEFF/19-r4deferred-s7feature-hybrid-physical-yaw-digital-zoom-fine-pan
Stage 4 · Deferred until [Auto Director qualification](https://trello.com/c/KSRnlMWe). Old S4–S7 are work IDs. Historical proposal; redesign before implementation.

Session 7 of the 19 Sep 2026 memo. After Step A and Step B bench.

**Hybrid model**
Slow physical yaw + digital zoom and fine pan. One channel controller. Physical deadband larger/slower than digital follow. Do not run two independent centering loops.

**Do**
- Visual error from the **wide source image** vs a desired sensor anchor — not post-crop error alone
- Low-gain bounded proportional yaw-velocity, no integral in v1
- On stale/lost vision: stop physical promptly (observation age + motion lease), do **not** keep moving for the 10s digital HOLD
- Link loss: hardware halts locally; show “Arm stopped · digital only”; digital tracking may continue in remaining FOV; no auto-home
- Return to Wide: stop/disarm physical **and** digital wide recovery in one action. Reveals current full camera view, not the original whole-stage shot
- Persistent “Arm STOP” on the pill when hardware is connected (keeps digital shot)
- Then physical auto-pan on a separately calibrated yaw range — never send digital crop phase as actuator stroke

**Done when**
Rehearsed: target loss, camera freeze, crop limit, slack/jam, link dropout. Digital and physical do not fight.

**Out of scope**
IK, multi-axis head, autonomous home search, optical-zoom protocol, tripod replacement, speech-driven physical motion.

**Files (proposed)** HardwareLink.swift, adapter/firmware, tests.
**Confidence** Low; hardware untested.
**Size** L (6–10 days initial estimate; re-estimate after design; excludes rig waits).

######## [R4][DEFERRED] [S6][FEATURE] Linear actuator jog/goto — physical yaw bench
URL: https://trello.com/c/wFzqHXgD/20-r4deferred-s6feature-linear-actuator-jog-goto-physical-yaw-bench
Stage 4 · Deferred until [Auto Director qualification](https://trello.com/c/KSRnlMWe). Old S4–S7 are work IDs. Historical proposal; redesign before implementation.

Session 6 of the 19 Sep 2026 memo. After Hardware Step A. One linear actuator parallel to the tripod pan arm.

**Sign convention**
Extend → tripod left. Retract → tripod right. Verify polarity at low speed; persist per device/channel.

**Do**
- Commands: Extend, Retract, Stop, Go to normalized **actuator stroke** (not image position)
- Measure stroke-to-yaw over a restricted monotonic range; do not assume uniform actuator speed = uniform yaw
- Calibrate min/max stroke, neutral yaw, permitted range, braking distance, current/force thresholds, position validity **before** enabling motion
- Home slowly only during setup, or use verified absolute sensing — never blind-home during a service
- Hard end switches + firmware soft limits; MCU owns motor deadlines
- First motion slice: low-speed bounded manual jog/goto, watchdog/limits, measured stop distance

**Depends on**
[DECIDE] Q7 (USB at Mac vs long run) and Q8 (rigid bidirectional actuator vs pull-only + return/tension). Pull-only cannot push a slack cable.

**Done when**
Safe jog/goto on the real mechanism; stop distance measured; limits/current enforced; no image servo yet.

**Out of scope**
Closed-loop visual recentering (S7). Digital crop phase as actuator position. Multi-axis robotics.

**Files (proposed)** HardwareLink.swift, adapter/firmware, tests.
**Confidence** Low; hardware untested.
**Size** L (6–10 days initial estimate; re-estimate after design; excludes rig waits).

######## [R4][DEFERRED] [S5][INFRA] HardwareLink — USB/simulator, telemetry, e-stop
URL: https://trello.com/c/zY3O7OLb/21-r4deferred-s5infra-hardwarelink-usb-simulator-telemetry-e-stop
Stage 4 · Deferred until [Auto Director qualification](https://trello.com/c/KSRnlMWe). Old S4–S7 are work IDs. Historical proposal; redesign before implementation.

Session 5 of the 19 Sep 2026 memo. First hardware win: connection, not motion. After S1 zoom and S2 channel ownership. Speech is not a prerequisite.

**Transport**
USB CDC serial on the bench first. `HardwareLink` abstraction: discover, negotiate, connect, arm/disarm, priority stop, command, ack, telemetry. Simulator + USB share the contract. Firmware owns motor deadlines — a Mac timer is not enough if the app crashes.

**Lifecycle**
disconnected → discovered → negotiating → connected/disarmed → explicitly armed → stopped/faulted.
Discover by stable identity; confirm Alfie protocol after open; never drive arbitrary serial gear. Reconnect / reboot / version mismatch / heartbeat loss always returns **disarmed**. No last-velocity replay. No auto-home.

**Wire (v1)**
Bounded newline-delimited JSON. Every record: `v`, session, seq, type. Motion later adds device-clock expiry. Starting test numbers: 10 Hz heartbeat, 20–50 Hz telemetry, ≤200 ms motion lease, ≤300 ms link-loss. Heartbeat must not perpetuate stale motion.

**Do this slice**
App discovers one device, pings, negotiates, enables comms with **motion disabled**, receives truthful telemetry, latches emergency stop. Tests: unplug, app quit, sleep, malformed/duplicate/late records, MCU reset, reconnect. Prove CDC inside the signed sandbox (`com.apple.security.device.serial`).

**Done when**
E-stop latches. Telemetry is real (nulls allowed). Motion commands are rejected or ignored. No actuator geometry.

**Out of scope**
Velocity/goto, image servo, BLE/Wi-Fi, Ethernet long-run (same abstraction later), GPIO-from-Mac.

**Files (proposed)** HardwareLink.swift, adapter/firmware, tests.
**Confidence** Low; hardware untested.
**Size** L (6–10 days initial estimate; re-estimate after design; excludes rig waits).

######## [R4][DEFERRED] [S4][FEATURE] Offline speech-to-action — eight wake-prefix commands
URL: https://trello.com/c/h5D0Mj0x/22-r4deferred-s4feature-offline-speech-to-action-eight-wake-prefix-commands
Stage 4 · Deferred until [Auto Director qualification](https://trello.com/c/KSRnlMWe). Old S4–S7 are work IDs. Historical proposal; redesign before implementation.

Session 4 of the 19 Sep 2026 memo. Depends on the S1 command dispatcher.

**Vocabulary (wake prefix required)**
Finite grammar, complete utterance, not substring match.
- “Alfie, detect” — arm Detect
- “Alfie, track” — Crop/Track only if locked, else “Pick a subject.”
- “Alfie, manual” / “Alfie, pan”
- “Alfie, back to wide” — safety Return to Wide (do not map bare “wide”)
- “Alfie, waist up” — select/reset preset
- “Alfie, push in” / “Alfie, pull out” — one rung on the current shot ladder
After multi-input: “Alfie, camera two, pan.”

**Stack**
Default for macOS 14+ product: bundled whisper.cpp (`base.en` first). SFSpeechRecognizer on-device is a comparison — never silent cloud fallback. SpeechAnalyzer only if we formally require 26.2+.

**Trust**
Close-talk/headset mic. Final/stable results only. Show “B · Push in” or reject reason above the pill. No spoken booth reply. Mic mute on the pill. Manual input cancels pending voice. Voice cannot undo Return to Wide after the fact. Stop session is **not** in the first eight.

**Do**
Off-frame-path recognizer; utterance IDs; eight mappings into Command. Bounded in-memory audio, discard after recognize. `NSMicrophoneUsageDescription` + audio-input entitlement.

**Done when**
Airplane/offline after setup; zero actions on sermon/music/silence corpus; one action per utterance; model failure leaves video running. Aim ~1s ack after phrase end, then measure on the rig.

**Out of scope**
LLM crop policy. “Alfie has the pastor” as an executable. Spoken Stop. Hold-to-talk as the first required path (useful later).

**Files (proposed)** SpeechCommandAdapter.swift, OperatorCommand.swift, tests.
**Confidence** Medium; unmeasured recognition.
**Size** L (6–10 days initial estimate; re-estimate after design; excludes rig waits).

######## [R4][HW-CHOICE][DECISION] Select actuator or supported camera-control protocol
URL: https://trello.com/c/nTylkwW1/66-r4hw-choicedecision-select-actuator-or-supported-camera-control-protocol
Stage 4 · Deferred until Auto Director qualification: https://trello.com/c/KSRnlMWe.

**Why** Existing hardware cards describe a custom yaw actuator; supported camera protocols may offer a different physical-control route.

**Questions / logic** Which cameras/mechanism, transport, pan/tilt/optical zoom, feedback and stop guarantees are required? Compare existing actuator proposal against supported protocols using actual vendor documentation and bench hardware. Select one bounded first target; do not implement both by default. Keep physical safety deadlines and emergency stop local to hardware where applicable. Define safe loss/disarm behavior before motion.

**Files** New docs/hardware/control-target-decision.md; future HardwareLink/adapter and firmware files only after target selection.

**Expected result / acceptance** Supported-device/transport decision, permission requirements, simulator contract, calibration/stop-test plan and cost/availability recorded. Update conditional actuator cards if a protocol route is chosen.

**Dependencies** Stage 3 qualification and named physical hardware. Legacy S5/S6/S7 remain engineering IDs, not product-stage numbers.

**Confidence** Low until hardware chosen.

**Implementation size** S (1–2 engineering days decision work excluding procurement/bench waits; implementation re-estimated).

