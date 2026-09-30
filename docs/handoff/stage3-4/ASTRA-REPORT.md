# Decisions for Stephan

Use the single [decision register](DECISIONS.md): all 37 decisions remain OPEN; its first ten are ordered for one sitting. This report adds no new product approvals. The highest-leverage recommendations are sermon Auto Prepare with per-camera nomination, global pause on intervention/fault, separate Auto Direct qualification, a feedback-actuator safety bench, and SpeechAnalyzer-first comparison with grammar before reviewed local-LLM intent.

| Decision group | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| A1 / S1 / A3 | Global or channel authority; Suggest/Prepare/Direct | Global pause + sermon Auto Prepare; separate cuts gate | Director wiring | Yes, requalify |
| H1 / V1 / V2 | Actuator/protocol; recognizer; grammar/LLM | Bounded actuator bench; SpeechAnalyzer comparison; staged language interpretation | Stage 4 next round | Software yes; hardware cost sunk |

Status: tasks **1–10 completed as document discovery**, 2026-09-30. No app code, existing specs, historical briefs, entitlements, project settings or Trello were changed. No PR, merge, purchase, microphone capture, hardware motion or new agent was initiated. Worktree `/Users/stephanmorris/Documents/alfie-astra`, branch `s34/astra`, based on `33a3faf`.

## Deliverables and commits

| Task | Files | Commit |
|---|---|---|
| 1 Authority | [authority-and-override.md](../../auto-director/authority-and-override.md) | `4f905bd` |
| 2 Scope | [product-contract.md](../../auto-director/product-contract.md) | `c152622` |
| 3 Readiness | [prepare-and-readiness.md](../../auto-director/prepare-and-readiness.md) | `496828c` |
| 4 Subject evidence | [subject-evidence.md](../../auto-director/subject-evidence.md) | `18df888` |
| 5 Roles/style | [roles-and-fallback.md](../../auto-director/roles-and-fallback.md), [shot-style.md](../../auto-director/shot-style.md) | `323a0fa` |
| 6 Preferences/UI/compute | [preferences.md](../../auto-director/preferences.md), [ui-notes.md](../../auto-director/ui-notes.md), [workload-plan.md](../../../reports/auto-director/workload-plan.md) | `e715b50` |
| 7 Qualification | [qualification-protocol.md](../../../reports/auto-director/qualification-protocol.md) | `36e5baf` |
| 8 Hardware | [control-target-decision.md](../../hardware/control-target-decision.md) | `9c5f5ff` |
| 9 Voice | [speech-stack-decision.md](../../voice/speech-stack-decision.md) | `a0c3652` |
| 10 Register/cross-check | [DECISIONS.md](DECISIONS.md), this report; Markdown paragraph spacing correction in UI notes | Commit titled `Consolidate Stage 3–4 decisions and cross-check Sol foundations` (the commit containing this report) |

Every task was committed and pushed individually to `origin/s34/astra`, with GPT-6 Astra co-author trailer. Task 10's self-containing commit is identified by subject rather than an impossible self-referential hash. `git log --oneline s34/astra` resolves it.

## Evidence snapshots

- R2 code read at base `33a3faf`: ShowCoordinator, ProgramRouter, ProgramTake, ChannelFrame, CameraChannel, OperatorCommand, MultiInputAdmission, TakeAvailability, NextShotStatus, ConsoleSnapshot, perception/composer/face code and diagnostics. Existing multi-camera spec implementation table is more current than several older prose sections.
- Required Sol R2 evidence read from `origin/r2/sol` at `8b4b284dbd014c3614c36e6e7aed41b05c3e0997`: readiness report/harness, DegradePolicy, multi-QA, privacy audit and platform baseline. Readiness and multi-QA have no real-run pass evidence in those reports.
- Final cross-check: fetched `origin`, reviewed **all 11 Swift files** under `Director/`, `Hardware/`, `Speech/` on `origin/s34/sol` at **`ec03713b482851169b299cb97a337313f4fb39a0`**. Paths below are relative to `CinematicCoreMacOS/CinematicCoreMacOS/`. Replay was first reviewed at `d9184ba`; its contents at the final snapshot remain the same. Findings are static source review, not test execution. Sol may advance after this snapshot.

## Cross-check: mismatches and integration gaps

“Now” means foundation behavior or tests should change before treating them as the accepted contract; “wiring” means the isolated scaffold can remain, but must not be connected with that assumption. Both are conditional on Stephan choosing the recommended policy. Missing integrations are called gaps, not claims that Sol has changed the running app.

| # | Sol code / observed assumption | Recommendation / consequence | When |
|---|---|---|---|
| 1 | `DirectorAuthority.swift` / `apply(.manualCommand/.operatorTake)` increments epoch but does not set paused | Global pause until explicit Resume; otherwise a fresh next-event proposal immediately reverses manual ownership | **Now**, A1 |
| 2 | `apply(.sourceLoss)` only cancels; no health-fault latch | Fault pause, clear pin, explicit health-gated resume; restored source cannot implicitly restore authority | **Now**, R2/A1 |
| 3 | `.editLive(false)` restores `mayPropose` if not separately paused | Both entering/exiting live edit must leave director paused | **Now**, A1 |
| 4 | `.unpin` removes channel pin without pausing; pin stores only ChannelID | Pin current Program shot intent + tracking explanation; unpin → paused; reject arbitrary non-Program pins | **Now**, A2 |
| 5 | `.enable(.autoDirect)` silently maps to AutoPrepare; mode changes reset pause | Refuse unqualified escalation with explicit reason, never silently substitute authority; faults cannot be bypassed by changing mode | **Now**, A3/U2 |
| 6 | `section()` maps both automatic levels to `.auto`; no inhibition or proposal identity | Proposed seam needs explicit levels, fault/pin/pause reason, proposal lifecycle and snapshot revision | Wiring, AD-UI |
| 7 | `admits(token)` means mayPropose; validator has no action-specific prepare permission | Suggest-valid proposal must not become an executable prepare grant. Check mayPrepare or manual acceptance and permit at effect | Wiring, AD-PREPARE |
| 8 | `DirectorShot` presets medium/closeUp/custom, lacks fullBody; modes lack full-view wide | Map only real `ShotComposer.Config.ShotPreset` ladder; safe full view must differ from Wide crop. Extra enum cases are not supported modes | **Now** model alignment, AD-STYLE/ROLES |
| 9 | `DirectorProposal` lacks ID, nomination/lock generation, cue/policy revision and target-revision context | Add or externally bind all invalidations and at-most-once consumption; channel/revisions alone miss policy/identity changes | Wiring, AD-PREPARE |
| 10 | Proposal captures pre-command ChannelRevisions; validator rejects any epoch/shot change as operator change | Explicitly acknowledge resulting revisions of its own successful prepare, without rebinding to arbitrary external changes | Wiring, AD-PREPARE |
| 11 | Validator checks now finite but not createdAt or maximumAge finite/nonnegative | NaN creation/age can evade expiry comparisons; malformed inputs must reject | **Now**, validation invariant |
| 12 | `DirectorReadiness` assumes scalar confidence/motion and externally supplied settled duration | Expose categorical nomination/lock/veto state, evidence age, distinct observations, planned-move state, source-normalized center/log-scale speeds; no calibrated confidence exists today | **Now** interface choice, P1/E1 |
| 13 | `DirectorReadiness.evaluate` uses comparisons without nonfinite validation | NaN confidence/settle/motion can fail all refusal predicates; reject invalid parameters and evidence | **Now**, validation invariant |
| 14 | `DirectorPreferences.safeDefaults` and `DirectorShotPolicy.Parameters.proposed`: 8/35/90 s, repetition 20 s, movement 0.1 | Proposed 20/45/90 s pace, 120 s Wide reminder, semantic two-shot history and explicit 0.02/s motion units; only study starting values, no silent default authority | Before study freeze, T1–T3 |
| 15 | `DirectorPreferences.resolve` widens maximum to meet conflicting minimum | Reject empty bound intersection with explanation; do not invent a new maximum. Soft Wide cadence isn't a safety ordering | **Now**, F1 |
| 16 | Preferences only include six style fields | Add versioned scope, roles, cues, privacy, qualification reference and policy identity; never persist live grant | Wiring, F1–F3 |
| 17 | `DirectorShotPolicy.choose` accepts confidence 0 as eligible; compares shots without physical-person/viewpoint key | Subject eligibility must be separate from ranking; semantic repetition needs nomination/viewpoint, safe-wide exception. Candidate scalar ranking cannot choose a new person | Wiring, E1/T1 |
| 18 | Motion scalar lacks units/nonnegative check; timing Parameters permit some infinities; sorting only preset breaks complete tie ordering | Finite ranges/timestamps, distinct motion units and explicit stable candidate ID tie-break; deterministic replay should not rely on unspecified sort stability | **Now**, policy invariants |
| 19 | Maximum duration only changes reason text; selection may happen immediately after minimum, no preferred duration | Preserve soft maximum, but approved pacing considers preferred/event opportunity; no forced timer cuts. Wide has no separate dwell parameter | Before style wiring, T1/T3 |
| 20 | `DirectorReplay` performs only operatorTake; zero unauthorized changes is structural | Add shadow/qualified director attempts separately; never use operator cuts as evidence for autonomous cut policy | Before qualification, Q1/Q2 |
| 21 | Replay fills override latencies with zeros and increments honoured count on input | Add delayed effects and timestamped rejection; no live latency claim from these arrays | **Now** report interpretation, Q2 |
| 22 | Replay reports wrong-subject proposals only, stale counts per reason, no cut denominator or bad-movement metric | Unique event/attempt IDs, actor-specific denominators, reviewed person labels and movement episodes; preserve counts, N/A when unmeasured | Before qualification, Q2 |
| 23 | Replay `.render` increments shotRevision; equal-time event sort has no explicit sequence | Ordinary render does not alter shot intent in R2; separate intent/render/source/evidence events and order ties explicitly | **Now** fixture fidelity |
| 24 | Replay fixtures are synthetic and small; defaults auto-enable AutoPrepare; wide candidate still depends on `present` | Separate synthetic unit fixtures from consented physical-person replay and product startup Off; safe full view does not require face nomination | Before qualification, S1/E1 |
| 25 | `HardwareWireRecord` supports generic string payload only, every record requires seq; no boot/caps/device-clock/ack_seq model | Typed negotiated records, device boot/session lease context, ack semantics and actual telemetry; keep codec scaffold, don't call it S5 wire compatible yet | **Now** contract design, H4 |
| 26 | `HardwareWireCodec` expects one complete line, unknown types pass, JSONDecoder used without duplicate-key rejection | Transport framing must bound partial/coalesced lines before allocation; type/range/duplicate-key validation before any effect | Before transport wiring, S5 |
| 27 | `SimulatedHardwareDevice.connect` session uses sequence; reboot resets sequence to 0 | Fresh boot/session identity on every negotiation; replaying old session-0 after reboot must reject | **Now**, S5 safety foundation |
| 28 | Simulator `arm` enters armed with motion=false; resetEmergencyStop may enter connectedDisarmed without new negotiation | Prefer communications-only visibly disarmed S5. Reset cannot bypass hello/boot/version health; explicit clear never grants arm | **Now** state semantics, H4 |
| 29 | Simulator receiveWire decodes only; does not apply ping/estop/negotiation. `checkLink` is invoked externally | Test decode→device effect and an independent device clock/watchdog model. Current fake is not a working firmware deadline or physical stop proof | Before claiming S5 integration |
| 30 | Hardware telemetry omits boot/position validity/limits/current; timing uses 40 Hz telemetry | Null position/velocity is honest. Add proposed telemetry capability fields; 20 vs 40 Hz is a tunable workload difference, not a safety defect | Wiring/bench, H1/H4 |
| 31 | Hardware timing/lease input finite checks absent; wireRejections grows unbounded; negotiated version and codec version can diverge after changeProtocolVersion | Validate configuration/clock/lease; bound diagnostics; rebuild codec on successful new protocol negotiation. Motion remains disabled today | **Now** robustness; before real device |
| 32 | `SpeechCommandGrammar` accepts unqualified text and camera three/four, rejects A/B or numeric aliases | Require explicit A/B or one/two in dual-input initial scope; C/D parser syntax must not imply support. Align exact allowed aliases | Before wiring, V4 |
| 33 | `VoiceCommandAdapter.accept` captures target/manualEpoch at final transcript, no utterance-start token | Manual action during recognition can be missed; capture epoch/mic/target/source context at start and reject late finals | **Now**, V4 race contract |
| 34 | Adapter constructs fresh `ShowCommand` and epoch at dispatch; named Program may execute in Edit Live | Recheck original target/source/control revision, expiry and Preview-only scope; fresh factory must not launder a stale utterance into valid command | **Now**, V4 |
| 35 | No mute/session/utterance timestamps; seen/dispatched ID sets unbounded; confidence upper range/floor validity not checked | Bounded expiry-aware dedupe and input validation; mute/Stop retire work. Per-recognizer confidence is not interchangeable | Before recognizer wiring, V1/V5 |
| 36 | Grammar `subjectLocked` is one caller bool before explicit target resolution | Lock precondition must be checked for the named/captured target at final admission; dispatcher remains final authority | Before wiring, V4 |
| 37 | Voice factories still make operatorUI commands; no director revocation, voice provenance or start-token guard | Proposed voice origin and serialized lower priority than physical UI; accepted voice pauses director; no direct channel bypass | Wiring, V2/V4 |
| 38 | No recognizer, microphone, LLM, local firmware/serial adapter, role fallback, cue UI, workload admission or automatic Take integration exists in reviewed files | Deliberate foundation boundary, not evidence of failure. Keep disabled/unwired until decisions and qualification; SpeechAnalyzer recommendation requires a future adapter | Later approved round |

Existing alignment worth retaining: four authority levels, static Auto Take qualification false, Preview-target precondition, channel/source/shot/route staleness checks, versioned preferences, motion disabled, null unsupported telemetry, strict full-utterance grammar, eight intents/no spoken Stop, and use of existing show dispatch. All mismatch recommendations are documents only; no Sol or R2 code was edited.

## External verification and remaining unknowns

Sources and access dates are embedded beside claims in hardware, voice and style memos. Confirmed narrowly: Sony publicly lists PXW-Z200 and macOS support; Apple documents local SpeechAnalyzer assets and availability checks; Blackmagic documents a specific SDI→VISCA bridge; ONVIF documents ContinuousMove timeout; Actuonix distinguishes feedback and limit-switch variants. These are documentation findings, not device compatibility certificates.

| UNVERIFIED item | Required next evidence |
|---|---|
| Real subject accuracy/readiness, cross-camera identity, active-speaker mapping | Consented labelled held-out study and full composer/rig replay; no dataset was supplied or collected |
| Style/timing/qualification budgets and volunteer UI fit | Freeze proposed parameters with Stephan, render prototype and run operator rehearsal; no universal broadcast duration was verified |
| Director overhead/live latency/downstream cadence | Paired rig runs, per-channel instrumentation, external presentation evidence; synthetic zeros excluded |
| Z200 exact transport/zoom/readback/local-loss behavior | Obtain model/firmware API matrix and signed macOS SDK test; vendor support page is not function proof |
| VISCA model-specific inquiries and watchdog | Obtain current command manual/firmware and bench loss tests. Sony manual index search was available; direct linked command PDF returned 404 during browsing |
| Actuator force/duty/geometry, physical stop and calibration | Named tripod/payload measurements, hardware reviewer, independent limit/e-stop circuit and stop matrix; exact AU price/stock/landed BOM unverified |
| Blackmagic exact camera/head/ATEM compatibility and feedback | Match real model/connectors/firmware/lens; legacy Micro Studio bridge cannot be assumed on every model |
| Network/USB/serial sandbox and local-network privacy behavior | Signed target app entitlement/permission tests on exact OS and transport; none run |
| Speech recognition latency/false actions/offline assets/permissions | Three-stack corpus comparison on 26.2 rig; denial/revocation, asset absence, offline and thermal tests |
| Privacy cleanup and exported contents | Runtime Stop/Wide/mute/rebind, filesystem/network/crash inspection; existing CSV pruning does not cover all files |
| July master-plan wording | File absent at supplied Downloads path; no exact July document claims made beyond user-provided direction |

## Suggested changes elsewhere (not performed)

| Document/card | Proposed edit after Stephan decides |
|---|---|
| `docs/ALFIE_MULTICAMERA_SPEC.md` | Keep R2 invariants. Resolve old “no implementation”/“existing seams cameraA only” prose against implementation table; distinguish synchronous actual Take from older next-tick reservation text. Add approved director permit integration, explicit seam modes and editorial-vs-manual readiness; no director fallback silently added to R2 |
| `docs/ALFIE_ENGINEERING_SPEC.md` | Update ownership to show/router plus per-channel managers; channel targets/revisions/atomic Take already exist. Separate subject HOLD from source hold/standby. Replace old S4 minimum-OS premise after platform decision; cite new discovery memos instead of treating historical hardware/voice drafts as authorizations |
| AD-SCOPE/OVERRIDE/TAKE cards | Record chosen scope, global pause transitions, pin/unpin semantics and separate Auto Direct gate; add final-effect race tests |
| AD-PREPARE/SUBJECT/ROLES/STYLE cards | Add categorical identity, source/observation age distinctions, true full-view role, soft duration/Wide policies and frozen parameter table |
| AD-PREFS/UI/COMPUTE/QA cards | Add cue/policy revision invalidation, explicit mode display, workload fingerprint, exposure denominators and non-synthetic latency evidence |
| HW-CHOICE/S5–S7 cards | Record chosen bench target; remove unverified low-cost claim and sensorless goto; distinguish feedback vs hard limits, fix duplicate v JSON key and expiry units, add boot/session replay and physical stop tests; no human hand-jam test |
| S4 card | Compare SpeechAnalyzer on current baseline, retain eight-command executable slice but explicitly decide July LLM direction; capture voice token at utterance start and require dual-input camera name; document no cloud fallback/retention |
| `docs/astra-sessions/00-PROGRAM.md`, S4–S7, HARDWARE-OPTIONS | Preserve history with dated supersession links. Withdraw categorical PTZ dismissal, old prices and default whisper/macOS14 premise; align named physical target and staged language path only after decisions |

## What was and was not done

Completed all requested memos, measurement plans, one consolidated register and source cross-check, in the requested order with a push after each task. Reviewed required handoff/cards/specs/historical briefs and Sol branch evidence. Validation for this document-only round: allowlist diff, whitespace check, relative Markdown link resolution, balanced code fences and register-ID coverage. App tests were not run because no application code changed; no benchmark or real-world qualification result is claimed.

Could not perform physical rig, SDK binary/sandbox, audio recognition, privacy runtime, real-person replay or volunteer tests without equipment/data/approved collection and a wired candidate. The master plan was absent. Some vendor full-text pages failed retrieval; claims relying on missing model-specific details are explicitly UNVERIFIED. No remaining discovery task was dropped for budget. Stop here; Stephan's decisions and the next approved implementation round are the next work.
