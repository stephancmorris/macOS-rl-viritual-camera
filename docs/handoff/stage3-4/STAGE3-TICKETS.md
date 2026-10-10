# Stage 3 tickets: plan, groups and agent hand-off

Prepared 10 Oct 2026 from [STAGE3-DESIGN-PLAN.md](STAGE3-DESIGN-PLAN.md), the [product contract](../../auto-director/product-contract.md) and `DECISIONS.md`. Sitting 1 and UC-1, E2 and UC-2 are recorded. Paste-ready prompts for each agent are in [STAGE3-AGENT-BRIEFS.md](STAGE3-AGENT-BRIEFS.md).

There are **59 tickets**: 51 for agents in four groups, plus 8 owner gates. Base branch: `main` (== `r2/engine`).

---

## 1. Groups and who owns what

Tickets are grouped by **the files they change**, so four agents can work in parallel without merge conflicts. The engine files every stage touches (`ShowCoordinator`, `CameraManager`) have a **single owner**.

| Group | Agent | Why this agent | Owns (only this group edits these) |
|---|---|---|---|
| **A: Director core** (pure Swift logic and tests) | **Sol 6.1** | Sol wrote the existing Director foundations and their tests, so this continues that work | `Director/**` except `DirectorController.swift`; `Director/Replay/**`; `Console/NextShotStatus.swift`; new `Director/DirectorConsoleAPI.swift`; `CinematicCoreMacOSTests/Director*` and other new pure-logic tests |
| **B: Engine integration** (MainActor wiring, camera, Take, router) | **Opus 5.5** | Concurrency-sensitive changes to the hottest files; wrote this plan and verified its line-level findings | `ShowCoordinator.swift`, `CameraManager.swift`, `ShotComposer.swift`, `PersonDetector.swift`, `ProgramRouter.swift`, `ProgramTake.swift`, `OperatorCommand.swift`, `ChannelFrame.swift`, `DeveloperFlags.swift`, `DiagnosticsLog.swift`, `Console/LiveConsole.swift`, new `Director/DirectorController.swift`; integration tests |
| **C: Operator UI and tooling** (SwiftUI views, gallery, Python tools) | **Grok 4.7** | Self-contained stream: views against a fixed API, plus Python tooling. Little coupling to engine internals | `Console/*` views (`NextShotPanel`, `MultiviewConsoleView`, `TakeBarView`, `ProgramPreviewPane`, `ConsolePresentation`), `InputTileView.swift`, `Console/Gallery/**`, `Console/FakeConsoleModel.swift`, Settings views, new `Director/UI/**`; `CinematicCoreMacOS/scripts/director_*.py`; `training/*director*` |
| **D: Discovery, specs and evaluation** | **Astra** | Astra wrote the decision memos and qualification protocol; reviews against the contract | `docs/**` (except this hand-off folder's ticket/brief files), `reports/**`; reviews every PR |
| **G: Owner gates** | **Stephan** | Decisions, hardware runs and sign-offs can't be delegated | `DECISIONS.md` recordings, rig runs, qualification records |

These assignments are recommendations based on the type of work and each agent's history in this repo, not on measured model strengths. Swap groups freely, but keep **one owner per group** so file ownership stays clean.

**Nobody** edits `project.pbxproj`, entitlements or `Info.plist`. The project uses synchronized folders, so new files are added automatically. **Gotcha:** `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, `ShowStandard.swift` and `CropRenderer.metal` also compile into the camera extension. They must not reference app-only types such as Director types, or the extension build fails.

### Interface contracts (defined first so the groups can work in parallel)

| Contract | Defined by | Used by | Ticket |
|---|---|---|---|
| `DirectorShot.Preset` = `OperatorCommand.Preset` (nonisolated, Hashable, Sendable) | B | A, C | B-00 |
| `ChannelEvidenceSample` (per-input evidence value) | A | B produces, A consumes | A-02 |
| `DirectorConsoleAPI`: status struct + `DirectorConsoleControlling` protocol (setLevel, handToAlfie, takeOver, cancelNextCut, advanceSegment, overrideSubject) | A | C builds views against a fake; B implements | A-04 |
| `DirectorShadowRecord` (Codable, metadata only) | D specifies, A codes | B writes, C analyses | D-02 → A-09 |
| `TakePermit` | A | B | A-11 |
| `RunSheet` / `StyleProfile` | A | B, C | A-05, A-13 |

---

## 2. Waves (what can run at the same time)

| Wave | Stage | Sol (A) | Opus (B) | Grok (C) | Astra (D) | Owner (G) |
|---|---|---|---|---|---|---|
| **1** | 3a | A-01, A-02, A-04, A-05, A-06 | **B-00 first**, then B-01, B-02 | C-01 | D-01, D-02, D-03 | G-01 MULTI-QA |
| **2** | 3a | A-03, A-07, A-08, A-09 | B-03, B-04 | C-02, C-03 | D-04 | — |
| **3** | 3a | A-10 | B-05, B-06 | C-04, C-05 | D-05 | G-02 sitting 2 |
| **4** | 3a gate | (fixes) | (fixes) | (fixes) | D-06, D-07 (Assist runs) | **G-03 Q-Assist sign-off** |
| **5** | 3b | A-11, A-12, A-13, A-14, A-15 | B-07, B-08 | C-06, C-07 | D-08 (sitting 3 memos) | G-04 sitting 3 |
| **6** | 3b | A-16 | B-09, B-10, B-11 | C-08, C-10 | D-06 (Auto runs) | **G-05 Q-Auto sign-off** |
| **7** | 3c | A-17 | B-12, B-13 | C-09 | D-06 (Backup runs) | G-06 sitting 4, **G-07 Q-Backup** |
| **8** | 3c+ | A-18 | B-14 | — | — | G-08 INPUTS-N |

The **critical path** is: B-00 → A-01 → A-03/A-07 → B-03 → B-05 → G-01 + G-03 → B-07 → B-08 → G-05 → B-12 → G-07.

---

## 3. Shared rules (every agent)

1. **One ticket = one branch = one PR.** Branch `s3/<group>/<ticket-id>-<slug>` off the latest `main`; rebase only your own branch. Never merge; the owner merges.
2. **Edit only files your group owns** (§1). If you need a hook in someone else's file, add a request to `docs/handoff/stage3-4/integration-requests.md` and reference the ticket.
3. **Decisions are binding.** Recorded rows in `DECISIONS.md` are requirements, and open rows are not yours to decide. Numeric values (durations, thresholds, speeds) are **parameters with no invented defaults**: tests supply them explicitly.
4. **Locked product rules:**
   - truthful preview;
   - manual control wins instantly;
   - no automatic cut without a permit and a qualification record;
   - soft failure (hold, never send a raw source);
   - no audio;
   - no network;
   - an operator is always present.
5. **No Release enablement.** New behaviour sits behind Debug-only `DeveloperFlags` (on in Debug, `false` in Release, like `allowRehearsalOutput`). Levels also need a qualification record.
6. **Frame path:** no new `@Published` writes per frame; use 15 Hz UI mirrors (see the progressive-lag notes). No `await` between validation and effect in any sink.
7. **Tests:** Swift Testing (`import Testing`, `@testable import Alfie`). Every ticket adds tests and keeps the full suite green:

   ```sh
   xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS \
     -destination 'platform=macOS' -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO
   ```

8. **PR description:**
   - ticket ID;
   - "done when" checklist with evidence;
   - test counts from the result bundle;
   - evidence class (synthetic / recorded / live);
   - anything left undone.

   Never call synthetic evidence qualification.

---

## 4. Tickets

Format: **Stage · Wave · Depends** / Do / Done when / Decisions.

### Group A: Director core (Sol 6.1)

**A-01 · Reconcile shot vocabulary (N3)**
- 3a · W1 · Depends: B-00
- Do: replace `DirectorShot.Preset/Mode/zoomRung` with `OperatorCommand.Preset`. Update `DirectorShotPolicy` ordering (preset ladder order), `DirectorProposal`, the four Director test files and the replay fixtures.
- Done when:
  - no `zoomRung` or `medium/closeUp/custom` remains;
  - ordering is deterministic across Stage and Webcam presets;
  - the Director suite is green.
- Decisions: N3 ✔

**A-02 · Identity evidence and two readiness bars (P1, P2, N5)**
- 3a · W1 · Depends: —
- Do:
  - add `IdentityEvidence` (`confirmed / acquiring / holding / lost / ambiguous`) and `ChannelEvidenceSample` (lock phase, tracking owns control, gallery ready, observation age, subject speed, crop converged, gesture in progress, person count, sample time);
  - replace `identityConfidence: Double` in `DirectorReadiness` with `identity`;
  - add `prepareReady` and a stricter `cutReady` (face visible, not mid-stride, framing landed).
- Done when: table tests cover every row of plan §5.2, and invalid or NaN inputs fail closed.
- Decisions: P1, P2, N5 ✔

**A-03 · Authority levels v2 and Assist semantics (U2, A1, N1)**
- 3a · W2 · Depends: A-01
- Do:
  - `Level` becomes `off / suggest / assist / auto / backup`;
  - a `QualificationLookup` is injected (defaults to not qualified), and `.enable` of an unqualified level is refused without substitution;
  - `.manualCommand` and Edit Live → takeover (pause) at every level;
  - Assist `.operatorTake` retires work and starts a new epoch **without pausing** (N1);
  - add a `.handToAlfie` event, which is `.resume` with prerequisites;
  - keep `autoTakeQualified` semantics via the lookup.
- Done when:
  - every existing authority invariant test still holds or is deliberately migrated, with the reason stated in the PR;
  - new tests cover N1 Assist and unqualified refusal.
- Decisions: U2, A1, N1 ✔

**A-04 · Console status model and control API (U2, U1)**
- 3a · W1 · Depends: —
- Do:
  - `NextShotStatus.DirectorSection` v2: `level`, `state` (active / paused / inhibited / abstaining, each with a reason), `prepared`, `nextCut` (input, countdown, cancellable), `qualified` per level;
  - new `DirectorConsoleAPI.swift` with the `DirectorConsoleControlling` protocol;
  - retire `DirectorAuthority.section()`.
- Done when: the model has plain-words reason text for every state (used by C), and `NextShotStatus.make` compiles with `director: nil` by default.
- Decisions: U2 ✔, U1 (open; the API is layout-neutral)

**A-05 · One parameter source and style profiles**
- 3a · W1 · Depends: —
- Do:
  - `DirectorPreferences` v2 keyed by `SegmentType` (`presenter / panel / performance / videoBreak / liveEvent`), holding minimum, preferred and soft-maximum shot length, wide cadence, maximum speed, settle time and on-air move rate;
  - `DirectorShotPolicy` reads it, and `Parameters.proposed` is deleted;
  - versioned Codable, conservative merge.
- Done when: there are no numeric defaults outside test fixtures, and migration tests pass.
- Decisions: T1–T3 open (values are parameters only)

**A-06 · DirectorJudge seam (AI-1)**
- 3a · W1 · Depends: —
- Do: `protocol DirectorJudge` returning a ranked list with probabilities or `.abstain(reason)`; `RuleJudge` wraps today's sort; `RecordedJudge` replays logged judgements; judgements bind to an evidence revision and timestamp.
- Done when: `RuleJudge` output is identical to the current `choosePreparation` on all fixtures, and a stale judgement is refused.
- Decisions: AI-1 ✔

**A-07 · Evidence adapter (pure)**
- 3a · W2 · Depends: A-02
- Do: `[ChannelEvidenceSample]` over time → per-input `IdentityEvidence`, settled-since, prepare-ready and cut-ready, plus authority events (`evidenceAvailable`, `identityLost`, `nominationChanged`), with a debounce parameter (F-D).
- Done when: sequence tests cover tracking → hold flicker, `wideWaiting` → `identityLost`, a gesture → inhibit only, and a stale observation → gap.
- Decisions: P1, N5 ✔

**A-08 · Replay through the sink protocol**
- 3a · W2 · Depends: A-01, A-03
- Do: define a `DirectorEffectSink` protocol (prepare off-air; later take and on-air move), drive the replay harness through a simulated sink, and update the five fixtures for the new levels.
- Done when: 0 stale commits and 0 Director cuts across all fixtures and the new Assist N1 cases.

**A-09 · Shadow record type**
- 3a · W2 · Depends: D-02
- Do: `DirectorShadowRecord` (Codable, metadata only) per the D-02 spec: would-prepare, would-cut, abstentions, operator actions, evidence summary, parameters version.
- Done when: round-trip tests pass, there are no frame or pixel fields, and there is a schema version.
- Decisions: AI-4, C3 ✔

**A-10 · Shot policy v2 for Assist (N4 hooks)**
- 3a · W3 · Depends: A-05, A-06, A-07
- Do:
  - candidates per input from its preset ladder;
  - safe-wide abstention `previewIsSafeWide`;
  - ambiguity → wide preset (P2);
  - one-preparation-per-tenure as a policy parameter (N4 is open, so it's a flag);
  - policy goes through `DirectorJudge`.
- Done when: fixture tests show prepare decisions and abstention reasons for each §5.2 row.

**A-11 · TakePermit and level-aware Take events (A3, N1)**
- 3b · W5 · Depends: A-03
- Do:
  - `TakePermit` (one-shot; bound to epoch, roles, route generation, Preview revisions and expiry);
  - authority issues it only at the Auto or Backup level when qualified;
  - Auto/Backup `.operatorTake` → nudge hold (minimum shot length, no pause).
- Done when: tests show reuse refused, any binding mismatch refused, an unqualified level never issues, and the nudge blocks Director cuts for the hold.
- Decisions: A3, N1 ✔

**A-12 · CutPolicy and CutNotice**
- 3b · W5 · Depends: A-10, A-11
- Do:
  - pure cut decision per plan §5.5: minimum dwell plus cut-ready, plus one of: past preferred length, Program subject lost or uncertain, or the profile wants wide;
  - abstention allowed;
  - `CutNotice` with a deadline token; cancel → hold.
- Done when: replay shows 0 cuts to a non-Preview input, cancel always wins, and no cut fires while the operator nudge hold is active.
- Decisions: A4 open (notice length is a parameter)

**A-13 · RunSheet and StyleProfile model (F3)**
- 3b · W5 · Depends: A-05
- Do: `RunSheet` (typed segments, optional name and position hint), advance and back, and a "segment changed?" suggestion from evidence such as a person-count change. Never advances by itself.
- Done when: Codable round-trip; no authority effect; suggestion tests.
- Decisions: F3 open (the model supports the recommendation)

**A-14 · SubjectSelector (E1, P2)**
- 3b · W5 · Depends: A-02
- Do: pick a subject from discovery observations: operator nomination > run-sheet position hint > central and stable person in the lectern zone; two or more plausible people → `ambiguous`.
- Done when: rule-order tests pass; it never picks when ambiguous; an override always wins.
- Decisions: E1, P2 ✔

**A-15 · On-air move policy (N2)**
- 3b · W5 · Depends: A-10
- Do: decide when Program's shot may change through a slow move: no better input is cut-ready, or there is a single input; at most one per minimum shot length. The rate is a parameter.
- Done when: replay tests pass with zero moves during gestures, Edit Live or the nudge hold.
- Decisions: N2 open

**A-16 · LearnedJudge adapter**
- 3b · W6 · Depends: A-06, C-10
- Do: a CoreML-backed `DirectorJudge` (model optional; missing → `RuleJudge`); probability threshold → abstain.
- Done when: it falls back cleanly; is deterministic with a fixed model; and A/B comparison is logged in shadow records.
- Decisions: AI-1 ✔

**A-17 · Backup fallback rule (R2, R1)**
- 3c · W7 · Depends: A-11
- Do: at the Backup level, `.sourceLoss(program)` → one fallback permit for a fresh, verified safe-wide Preview, valid only inside the router hold window, then pause; all other levels unchanged.
- Done when: permutation tests cover a stale safe wide, both lost, a rebind and a pre-fault permit reuse; the fallback is never outside the window.
- Decisions: R1, R2 open

**A-18 · Preview selection among 3–4 inputs**
- 3c+ · W8 · Depends: A-12; owner INPUTS-N
- Do: choose which input to cue next.
- Done when: pure tests pass; gated by INPUTS-N.

### Group B: Engine integration (Opus 5.5)

**B-00 · Make `OperatorCommand.Preset` shareable** *(merge first)*
- 3a · W1 · Depends: —
- Do: make `OperatorCommand.Preset` (and the nested preset enums if needed) usable from `nonisolated` code: `Hashable`, `Sendable`. No behaviour change.
- Done when: a nonisolated test uses it in a `Set`, and the full suite is green.

**B-01 · Read-only evidence accessors**
- 3a · W1 · Depends: —
- Do: expose `subjectSpeed`, `cropConverged`, `lastObservationAge`, `operatorGestureInProgress`, lock phase and gallery readiness, and build a `ChannelEvidenceSample` from them (type from A-02; stub locally until merged).
- Done when: zero behaviour change; the values are read with no frame-path `@Published`; there's a unit test per accessor.

**B-02 · Director origin and the manual-action hook (F-A, F-B)**
- 3a · W1 · Depends: B-00
- Do:
  - `OperatorCommand.Origin.director`;
  - an observer at the top of `CameraManager.dispatch` (admitted **and** refused, non-Director origin);
  - a `ShotComposer.$config` change hook;
  - `take(origin:)` parameter, defaulting to the operator.
- Done when: tests prove the ContentView, OperatorPill and LiveConsole paths all reach the observer, and that Director-origin commands don't.

**B-03 · DirectorController in shadow (C1, C4)**
- 3a · W2 · Depends: A-03, A-04, A-07, B-01, B-02
- Do:
  - `Director/DirectorController.swift`, owned by `ShowCoordinator`;
  - all ingress hooks in plan §5.3;
  - 4 Hz injectable tick;
  - Suggest/shadow only, with **no camera effects**;
  - implements `DirectorConsoleControlling` (status only);
  - `[DIRECTOR]` log lines.
- Done when:
  - hook tests cover every §5.3 row, including refused Take;
  - Stop → restart stays Manual;
  - `[SOAK]` is unchanged within noise on a Debug run.

**B-04 · Shadow logging to disk (AI-4, C3)**
- 3a · W2 · Depends: A-09, B-03
- Do: write `DirectorShadowRecord`s as JSONL beside the diagnostics files, with 30-day pruning and an explicit export. **Do not reference Director types from `DiagnosticsLog.swift`**, because it compiles into the extension; use a separate writer.
- Done when: the extension builds; files are pruned; there are no pixel fields.

**B-05 · Assist off-air sink (C5, F-C, N4)**
- 3a · W3 · Depends: A-08, A-10, B-03
- Do:
  - atomic `.selectPreset` preparation per plan §5.4;
  - gesture inhibit;
  - tenure rule flag;
  - `DeveloperFlags.allowDirectorAssist` (Debug only).
- Done when:
  - expected revisions == actual;
  - a mismatch → takeover with a log line;
  - never Program or Edit Live;
  - never supersedes a gesture;
  - replay through the real sink adapter shows 0 stale commits.

**B-06 · Qualification records (C16)**
- 3a · W3 · Depends: A-03
- Do: store per-level sign-off records bound to the admission fingerprint, and implement `QualificationLookup`. Debug builds may inject records for testing; Release reads only real records.
- Done when: a level becomes unavailable when the fingerprint changes, and records survive relaunch.
- Decisions: Q1–Q3 open (the format follows D-04)

**B-07 · Permit-checked Take (A3)**
- 3b · W5 · Depends: A-11, B-02
- Do: `take(_:origin:permit:)` consumes and verifies the permit **before** the existing checks, in the same turn. The operator path is unchanged; the nudge event is emitted for operator origin.
- Done when: the existing Take tests are unchanged and green; permit tests show reuse, stale and non-Preview refused; a refused Director Take never retries.

**B-08 · Cut execution and notice (A3, A4)**
- 3b · W5 · Depends: A-12, B-07
- Do: the controller runs `CutPolicy`, then `CutNotice`; at the deadline, permit + take in the same turn; Esc or Cancel → hold. Behind `DeveloperFlags.allowDirectorAuto` (Debug).
- Done when: the replay sink and a live Debug rehearsal show cancel always wins and no cut without a permit.

**B-09 · On-air slow move sink (N2, F-G)**
- 3b · W6 · Depends: A-15
- Do: a Director-origin slow variant of the shot move (`beginZoom` path) on Program. Never through `selectPreset`, which has the 0.5 s fast framing.
- Done when: the measured move duration respects the profile rate, and the move is refused during gestures or Edit Live.

**B-10 · Bounded discovery mode (E1, F-H)**
- 3b · W6 · Depends: A-14, D-03
- Do:
  - a new detector mode: a low-rate full-frame person scan on off-air inputs with no lock;
  - the `SubjectSelector` pick then goes through the normal acquire → lock path;
  - the rate is a parameter.
- Done when: `[SOAK]` with discovery on stays within the D-03 budget on the named rig, and Program inputs are never scanned at full frame.

**B-11 · Run sheet wiring (F3)**
- 3b · W6 · Depends: A-13, B-03
- Do: the controller holds the current `RunSheet` and segment; advancing emits a style-scoped `.policyChanged` (no takeover); `LiveConsole` actions.
- Done when: a segment change switches the profile in the next decision, and there's no authority effect.

**B-12 · Backup fallback execution (R2, F-K)**
- 3c · W7 · Depends: A-17, B-07
- Do: on Program source loss at the Backup level, cut once to the verified safe wide inside `ProgramRouter`'s hold window (0.5 s + 2 s); otherwise R2 hold → standby, unchanged.
- Done when: fault permutation tests and a live unplug drill pass; there is never a raw source and never a cut after standby.

**B-13 · Backup level wiring**
- 3c · W7 · Depends: B-08, B-12
- Do: zero-countdown cuts with the next cut always shown, and panel/break profiles on wide or group shots.
- Done when: the Backup walkthrough (contract script 3) passes in a Debug rehearsal.

**B-14 · Cue for 3–4 inputs**
- 3c+ · W8 · Depends: A-18; owner INPUTS-N
- Do: implement `LiveConsole.cue(_:)` and Director Preview selection.
- Done when: separate qualification.

### Group C: Operator UI and tooling (Grok 4.7)

**C-01 · Director gallery states**
- 3a · W1 · Depends: A-04 (mirror its struct locally until merged)
- Do: gallery demo (`Console/Gallery/DirectorDemo.swift`) showing every `DirectorSection` v2 state through `FakeConsoleModel`; screenshots into `docs/gallery-screenshots/`.
- Done when: every state from plan §5.9 is rendered, with plain-words copy.

**C-02 · Mode control and Hand to Alfie (U2, A1)**
- 3a · W2 · Depends: A-04
- Do:
  - Manual · Assist · Auto · Backup control, with unqualified levels greyed out ("not qualified");
  - an always-visible **Manual / Hand to Alfie** toggle with a keyboard shortcut;
  - built against `DirectorConsoleControlling` (fake in the gallery, real via B-03).
- Done when: every launch shows Manual; VoiceOver labels are present; the shortcut is documented.

**C-03 · Next-shot director line and tile badge**
- 3a · W2 · Depends: A-04
- Do: a third line or strip on `NextShotPanel` (prepared shot plus plain status), and an "AUTO" badge in `InputTileView.directorBadgeReserve` when Alfie set that input's shot.
- Done when: the panel stays within the console layout budget, and gallery screenshots exist.

**C-04 · Style settings and preferences store (F1)**
- 3a · W3 · Depends: A-05
- Do: a settings screen for the per-segment style profiles, plus `DirectorPreferencesStore` (versioned JSON in Application Support; **never stores the level**); saving emits a policy change through the API.
- Done when: a corrupt or unknown version falls back to fail-closed, with a visible message.
- Decisions: F1, F2 open

**C-05 · Shadow report script**
- 3a · W3 · Depends: A-09, B-04
- Do: `CinematicCoreMacOS/scripts/director_shadow_report.py`: would-prepare and would-cut versus the operator, agreement by segment type, abstention reasons, dwell distributions. Used by D-08 to propose T1–T3 values.
- Done when: it runs on synthetic JSONL fixtures and outputs a markdown report.

**C-06 · Next-cut notice UI (A4)**
- 3b · W5 · Depends: A-04, B-08
- Do: "Next: Cam B · 2 s · Esc to cancel" with Esc bound; a Backup variant without a countdown that still shows the next cut.
- Done when: gallery states exist, and Esc reaches `cancelNextCut` in a Debug rehearsal.

**C-07 · Run sheet editor and strip (F3)**
- 3b · W5 · Depends: A-13
- Do: an editor (add, reorder, typed segments, optional name and position) and a console strip (current and next, Advance button and key).
- Done when: it saves per show and the strip is in the gallery.

**C-08 · Subject pick display and override (E1)**
- 3b · W6 · Depends: A-14, B-10
- Do: show Alfie's pick on the input tile or pane; one tap or click overrides it (operator nomination).
- Done when: the pick is visible within 1 refresh, and an override emits a nomination change.

**C-09 · Backup alerts**
- 3c · W7 · Depends: B-12
- Do: alerts for "Program lost → switched to Cam A", "Both inputs stale" and "Paused after fallback: Hand to Alfie when ready".
- Done when: gallery states exist, and alerts appear in the live drill.

**C-10 · Learned scorer training (after shadow data)**
- 3b · W6 · Depends: C-05, shadow data from G-03 runs
- Do:
  - `training/train_director_scorer.py`: features from shadow records → small model (gradient-boosted trees or MLP) → CoreML via `export_coreml.py` patterns;
  - held-out agreement and calibration report.
- Done when: a report compares the model with `RuleJudge` on held-out events; the model is bundled only if it wins.
- Decisions: AI-1, AI-4 ✔

### Group D: Discovery, specs and evaluation (Astra)

**D-01 · Reconcile the specs with recorded decisions**
- 3a · W1
- Do:
  - update `docs/auto-director/` (authority-and-override, prepare-and-readiness, subject-evidence, roles-and-fallback, shot-style, preferences, ui-notes, event-authority-contract) to the live-event producer and sitting 1;
  - fix the stale Multiview line in `ALFIE_MULTICAMERA_SPEC.md`;
  - add a Director section to `ALFIE_ENGINEERING_SPEC.md`.
- Done when: no doc contradicts `DECISIONS.md` or the product contract.

**D-02 · Shadow record schema and privacy note (C3, AI-4)**
- 3a · W1
- Do: specify the `DirectorShadowRecord` fields, units, schema version, retention, export and what is never logged (no frames, no names beyond operator-entered labels).
- Done when: A-09 can implement it without questions.

**D-03 · Discovery workload protocol (C1, C2)**
- 3a · W1
- Do: a measurement plan and budget for B-10 (scan rate × inputs × rig), the `[SOAK]` fields to compare and pass/fail limits, tied to the admission fingerprint.
- Done when: a budget table exists for the named rig.

**D-04 · Qualification protocol and record format (Q1–Q3)**
- 3a · W2
- Do: per-level gates (Assist, Auto, Backup), pass bars (zero critical events plus exposure), signatories (owner, event operator, independent reviewer) and the record fields B-06 stores.
- Done when: memos are ready for owner sitting 3, and Assist can be evaluated with them.

**D-05 · Rehearsal runbooks**
- 3a · W3
- Do: turn the three contract walkthroughs into step-by-step rehearsal checklists with scoring sheets, plus fault drills (unplug, rebind, both stale, output fault).
- Done when: the owner can run them without the agent.

**D-06 · Run and report evaluations (per level)**
- W4, W6, W7
- Do: analyse rehearsal and shadow results (with C-05) per D-04, and write `reports/auto-director/q-<level>-<date>.md`.
- Done when: every report states its evidence class and counts; nothing is called qualified without a sign-off.

**D-07 · Consent and fixture register (E3, AI-3)**
- 3a · W4
- Do: the procedure and register for consented recorded footage (validation clips) and offline labelling; a decision memo for E3/AI-3.
- Done when: the owner can record E3 and AI-3.

**D-08 · Data-driven parameter memos (sittings 2–4)**
- W3, W5, W7
- Do: from the shadow reports, propose T1–T3 per segment type, N4, P3, the A4 notice length and the N2 move rate, with evidence.
- Done when: each memo gives options, recommendation and data, and is marked AWAITING OWNER.

**Ongoing · Contract review**
- Review every PR against the product contract, `DECISIONS.md` and locked rules; comment, don't merge.

### Group G: Owner gates (Stephan)

| ID | Gate | When | Blocks |
|---|---|---|---|
| G-01 | **Run R2 two-camera MULTI-QA** on the named rig (currently *Not run*) | Start now | B-05 live use; every automatic cut |
| G-02 | Decision sitting 2: S2, N4, P3, R1, F1, F2, U1, interim T1–T3 | Wave 3 | B-05, C-04 |
| G-03 | **Q-Assist sign-off** | After D-06 Assist | Stage 3b live trials; real shadow data for C-10 |
| G-04 | Decision sitting 3: A4, N2, F3, C1/C2 budget, Q1–Q3 | Wave 5 | B-08, B-09, B-10 |
| G-05 | **Q-Auto sign-off** | After D-06 Auto | Stage 3c |
| G-06 | Decision sitting 4: R2 fallback, Backup profiles | Wave 7 | B-12 |
| G-07 | **Q-Backup sign-off** | After D-06 Backup | Backup in the field |
| G-08 | INPUTS-N / CUE go-ahead (three and four inputs) | After G-05 | A-18, B-14 |

---

## 5. Merge and review flow

1. An agent opens a PR for one ticket and the full suite is green.
2. **Astra** reviews against the contract and decisions.
3. **Opus** reviews any PR touching MainActor, engine or concurrency code (including Sol's authority changes).
4. The owner merges in wave order. After each merge, agents rebase their open branches on `main`.
5. A ticket that needs an open decision stops at the decision and writes it up for D-08; it doesn't pick a value.

---

## 6. Trello cards (Alfie Coding Board)

Created 10 Oct 2026 on [Alfie Coding Board](https://trello.com/b/FkxA6E36/alfie-coding-board). Overview card: [S3-PLAN](https://trello.com/c/jaGqyyNe).

The cards are placed by wave:
- **🤖 Agent Queue** (labelled `agent:ready`): wave 1.
- **📐 Spec Ready**: waves 2–3.
- **🧭 Spec Backlog**: wave 4 onwards, plus the owner gates.

Labels: `priority:P0` marks the critical path, and `needs:privacy-review` and `needs:device-test` are added where they apply. G-01 is the existing [MULTI-QA](https://trello.com/c/uO1HAlYm) card.

| Ticket | Card | Ticket | Card | Ticket | Card |
|---|---|---|---|---|---|
| A-01 | [KEP9a0e6](https://trello.com/c/KEP9a0e6) | B-00 | [Udx29X9T](https://trello.com/c/Udx29X9T) | C-01 | [8UiB9wGU](https://trello.com/c/8UiB9wGU) |
| A-02 | [Pp4Qx61z](https://trello.com/c/Pp4Qx61z) | B-01 | [xppmScjj](https://trello.com/c/xppmScjj) | C-02 | [4FVemMN9](https://trello.com/c/4FVemMN9) |
| A-03 | [lTm0DOzF](https://trello.com/c/lTm0DOzF) | B-02 | [DxeOCC66](https://trello.com/c/DxeOCC66) | C-03 | [PA87fkd9](https://trello.com/c/PA87fkd9) |
| A-04 | [mvNmZuap](https://trello.com/c/mvNmZuap) | B-03 | [pj2ZbM6j](https://trello.com/c/pj2ZbM6j) | C-04 | [tE0tzjNz](https://trello.com/c/tE0tzjNz) |
| A-05 | [8PTAcfTW](https://trello.com/c/8PTAcfTW) | B-04 | [3tyDYrWL](https://trello.com/c/3tyDYrWL) | C-05 | [6RaMJbfT](https://trello.com/c/6RaMJbfT) |
| A-06 | [Vaxqejhv](https://trello.com/c/Vaxqejhv) | B-05 | [UDJjhR6j](https://trello.com/c/UDJjhR6j) | C-06 | [auY6HYtj](https://trello.com/c/auY6HYtj) |
| A-07 | [DHZ8Yyc4](https://trello.com/c/DHZ8Yyc4) | B-06 | [KfmsFyHQ](https://trello.com/c/KfmsFyHQ) | C-07 | [JAU8oFd7](https://trello.com/c/JAU8oFd7) |
| A-08 | [2tGH9vfr](https://trello.com/c/2tGH9vfr) | B-07 | [DCd6gN5I](https://trello.com/c/DCd6gN5I) | C-08 | [7BJdvATP](https://trello.com/c/7BJdvATP) |
| A-09 | [RADJVXDn](https://trello.com/c/RADJVXDn) | B-08 | [aDEyv84C](https://trello.com/c/aDEyv84C) | C-09 | [DRRk4TJu](https://trello.com/c/DRRk4TJu) |
| A-10 | [bZJ8YmgQ](https://trello.com/c/bZJ8YmgQ) | B-09 | [q4H7i3Bt](https://trello.com/c/q4H7i3Bt) | C-10 | [7HOi1AOx](https://trello.com/c/7HOi1AOx) |
| A-11 | [ubKJgTwM](https://trello.com/c/ubKJgTwM) | B-10 | [9ifoF0DZ](https://trello.com/c/9ifoF0DZ) | D-01 | [551GFUVp](https://trello.com/c/551GFUVp) |
| A-12 | [khjdjadA](https://trello.com/c/khjdjadA) | B-11 | [aKjuMfoo](https://trello.com/c/aKjuMfoo) | D-02 | [HBSY3JF2](https://trello.com/c/HBSY3JF2) |
| A-13 | [s0beu1Pm](https://trello.com/c/s0beu1Pm) | B-12 | [axfQoBKj](https://trello.com/c/axfQoBKj) | D-03 | [pO1kLChg](https://trello.com/c/pO1kLChg) |
| A-14 | [UL42Le8H](https://trello.com/c/UL42Le8H) | B-13 | [LTxj751i](https://trello.com/c/LTxj751i) | D-04 | [9qoW56pQ](https://trello.com/c/9qoW56pQ) |
| A-15 | [UH9qLSdJ](https://trello.com/c/UH9qLSdJ) | B-14 | [v2FCFGN2](https://trello.com/c/v2FCFGN2) | D-05 | [Csi7ssyT](https://trello.com/c/Csi7ssyT) |
| A-16 | [E4adcm5o](https://trello.com/c/E4adcm5o) | G-02 | [4O2fQSQY](https://trello.com/c/4O2fQSQY) | D-06 | [865rDWWm](https://trello.com/c/865rDWWm) |
| A-17 | [uNbaquTL](https://trello.com/c/uNbaquTL) | G-03 | [78H6IZGF](https://trello.com/c/78H6IZGF) | D-07 | [rvrRqGbH](https://trello.com/c/rvrRqGbH) |
| A-18 | [wpvkzlUu](https://trello.com/c/wpvkzlUu) | G-04 | [M60haHIz](https://trello.com/c/M60haHIz) | D-08 | [jIwznl6v](https://trello.com/c/jIwznl6v) |
| | | G-05 | [oTRGY1jT](https://trello.com/c/oTRGY1jT) | | |
| | | G-06 | [gQ5pcSht](https://trello.com/c/gQ5pcSht) | | |
| | | G-07 | [t2aR3QJu](https://trello.com/c/t2aR3QJu) | | |
| | | G-08 | [Rsw999yI](https://trello.com/c/Rsw999yI) | | |

**Card workflow for agents:**
- When you start a card, move it to 🚧 In Progress.
- When your PR is open, comment the PR link on the card and move it to 👀 Human Review.
- Only touch your own group's cards.
- Never move a card to ✅ Done. The owner does that after merging and checking the evidence.
