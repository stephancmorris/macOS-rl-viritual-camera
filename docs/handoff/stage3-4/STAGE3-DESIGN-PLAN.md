# Stage 3 Auto Director: design and implementation plan (full path)

Prepared 10 Oct 2026 against `main` / `r2/engine` at `a89644b`. Read-only exploration; nothing was built, run or committed. Revised the same day for the live-event backup-producer use case ([STAGE3-USE-CASE.md](STAGE3-USE-CASE.md)). Hybrid AI options are in [STAGE3-AI-OPTIONS.md](STAGE3-AI-OPTIONS.md).

**Recorded decisions** (`DECISIONS.md`, 10 Oct 2026):
- **UC-1:** an operator is always present.
- **E2:** audio paused.
- **UC-2:** one shot per input, Alfie sends the best input.

Everything else here is a recommendation **AWAITING OWNER**.

---

## 1. Summary

**Goal:** Alfie as a **backup technical producer** for live events with static cameras. Each camera is one input with one shot that Alfie may change, and Alfie puts the input that fits best on Program. A run sheet is optional. An operator is always present and outranks Alfie instantly.

**The path:** four qualified steps. Each later step reuses everything before it, and none ships until its own gate passes.

| Stage | Level | Alfie does | Operator does | Gate |
|---|---|---|---|---|
| — | **Shadow** | Runs on live evidence; logs the shot it *would* set and the cut it *would* make. No camera effects | Runs the show normally | None. This is how data is collected |
| **3a** | **Assist** | Prepares the off-air (Preview) input's shot | Every cut | Q-Assist |
| **3b** | **Auto** (supervised) | Prepares Preview **and cuts**, after a visible, cancellable "Next: Cam B" notice. Slow on-air shot changes when needed | Watches, cancels, nudges, takes over | Q-Auto |
| **3c** | **Backup** | As Auto, without a countdown; falls back to the safe wide on source loss; handles panels and breaks on wide or group shots | Busy elsewhere but present; takes over with one action | Q-Backup |

**What exists:** pure, well-tested Director logic (authority, proposals, staleness, readiness, preparation leases, synthetic replay), with nothing wired into the app.

**Findings that shape the design** (details in §3):
1. The Director's shot types don't match the app's presets (N3).
2. Return to Wide would wipe the lock on the subject.
3. A single preset command is an atomic, predictable preparation.
4. No single identity-confidence score exists; evidence comes as discrete lock states.
5. Today every Take pauses the Director (N1).
6. **New for the full path:**
   - **Alfie can't find people on its own today.** Detection is off until the operator presses Detect and taps someone.
   - **Preset changes deliberately snap quickly** (0.5 s fast framing). That is fine off air but wrong on air.
   - **Take has no notion of who asked for it.**
   - **The authority model always pauses on source loss**, which conflicts with the Backup fallback.

---

## 2. Handover claims, checked against code

| Claim | Result |
|---|---|
| Authority levels; `autoTakeQualified = false`; `mayTake` always false | **Confirmed** (`DirectorAuthority.swift:33,48`) |
| Epoch revocation; Pause is a global latch; Pin and Edit Live are modelled | **Confirmed.** Unpin, Edit Live exit and `healthRestored` never clear Pause |
| `choosePreparation`, `recommendationDue`, six abstention reasons | **Confirmed** (`DirectorShotPolicy.swift`) |
| Proposal target must be Preview; 13 stale reasons; readiness; lease lifecycle; `ShowDirectorWorld` | **Partly.** `StaleReason` has **11** cases, not 13. `ShowDirectorWorld.directorState()` never sets evidence, policy or nomination revisions |
| `DirectorPreferences` is versioned and not persisted | **Confirmed.** `safeDefaults` (8/35/90/20 s) conflict with the register's T1/T3 values |
| Five synthetic 60 s replay fixtures | **Confirmed** (`DirectorReplayFixtures.swift:9–29`) |
| `DirectorSection` is always nil and never rendered | **Confirmed** (`NextShotStatus.swift:51`; `NextShotPanel.swift:7`). It already has a `countdown` field, which Auto's notice will use |
| No ShowCoordinator Director field; `section()` has no outside caller | **Confirmed** |
| `LiveConsole.cue(_:)` is empty | **Confirmed** (`LiveConsole.swift:202`). Not needed with two inputs; **needed for Auto with 3–4 inputs** |
| No microphone entitlement or usage string | **Confirmed**, and it stays that way (E2 decided: audio paused) |
| R2 two-camera qualification | `origin/r2/sol:reports/release-2/multi-qa.md`: **"Status: Not run."** |
| (Docs) Multiview "off by default" | **Stale:** `DeveloperFlags.useMultiviewConsole = true` (`DeveloperFlags.swift:91`) |

Useful seams:
- `InputTileView.directorBadgeReserve` already reserves a 64 pt badge slot.
- Each channel can play a validation clip (`CameraManager.validationClipURL`), so recorded footage can run through the real pipeline.

---

## 3. Findings that shape the design

### Assist (3a)

**F-A: Commands bypass the coordinator.** `ContentView.swift:184–202`, `OperatorPill.swift:25` and `LiveShowSetup.swift:155` call `CameraManager.dispatch` directly. The manual-action hook therefore belongs in `CameraManager.dispatch`, the one admission point every path reaches, as an observer the coordinator installs and filters by origin.

**F-B: Changes that go through no command.** A format change can switch the mode directly (`CameraManager.swift:1636–1646`), and Settings edits `ShotComposer.config` without a command. Both must count as manual actions on that input.

**F-C: A Director command supersedes operator work in progress.** Accepting any command increments the channel's `commands.epoch`. While the operator is mid-gesture on an input, the Director must not touch it. Mid-gesture means:
- Detect armed (`detectionDiscoveryActive`);
- a tap pending (`tapPending`);
- a zoom move in flight (`shotMove`).

**F-D: A lock phase change invalidates preparation.** The frame path increments `shotRevision` on every lock-phase change (`CameraManager.swift:2101–2105`). Prepared shots are withdrawn when the lock wobbles. That is the intended behaviour, but the evidence adapter needs a debounce.

**F-E: Never use Return to Wide or a mode change from the Director.** `returnToWide()` calls `shotComposer.reset(clearManualLock: true)` (`CameraManager.swift:1295`), which loses the subject. The Director's only camera verbs are **`.selectPreset`** for off-air inputs and the animated **shot move** for on-air inputs (F-G). The safe-wide input already shows the full view, so it never needs preparing.

### Auto (3b) and Backup (3c)

**F-G: Preset changes are built for off-air use.** `selectPreset` calls `boostFramingTransition()`, which uses fast framing smoothing for 0.5 s (`CameraManager.swift:546–556`). Off air, that is good: Preview is ready sooner. On air it reads as a snap. On-air changes (N2) should use the existing one-rung **shot move** (`beginZoom` → animated `CropEngine` zoom, `CameraManager.swift:841–877`), or a slower Director variant of it. The on-air speed is a style parameter, measured rather than guessed.

**F-H: Alfie can't discover people on its own.** Detection is deliberately gated: `DetectionMode.off` → `awaitingTap` (operator pressed Detect) → `acquiring` around a tapped point → `lockedROI` (`PersonDetector.swift:112–128`). This gating was part of the progressive-lag fix. Auto subject selection (E1 revised) therefore needs a new **bounded discovery mode**, for example a low-rate full-frame person scan on an off-air input with no lock. That adds Vision workload and must be measured against the admission fingerprint before Auto qualifies.

**F-I: Take doesn't know who asked.** `ShowCoordinator.take(_:)` (`ShowCoordinator.swift:212`) validates and commits synchronously, with a 0.5 s guard between Takes (`ProgramTake.swift:26`). That synchronous design is exactly what a **one-shot Director permit** needs: check the permit and commit in the same turn. `take` needs an origin (operator / director / fallback) so that the N1 rules and logs can tell the cases apart.

**F-J: The authority model can't express Backup yet.**
- `Level` has `off / suggest / autoPrepare / autoDirect`, `autoTakeQualified` is a hard-coded `false`, and `.enable(.autoDirect)` always refuses.
- `.sourceLoss` always revokes and pauses (`DirectorAuthority.swift:96–97`), so the Backup rule "cut to the safe wide on Program loss" (R2 revised) can't be expressed.
- `.operatorTake` always pauses, so the Auto "nudge" can't be expressed either (N1).

These are deliberate foundation choices, to be changed in reviewed steps rather than edited away.

**F-K: The router already provides soft failure.** On Program source loss the router holds the last good frame after 0.5 s, shows a labelled hold for 2 s, then sends black standby (`ProgramRouter.swift:43–44`). The Backup fallback must cut to the safe wide **inside that hold window** and must never bypass it.

**F-L: More than two inputs needs Cue.** With two inputs, Preview is always "the other one". With 3–4 inputs, Auto must also choose *which* input to set up next, and `cue(_:)` is empty. So Auto qualifies on two inputs first, and 3–4 inputs follow INPUTS-N and CUE.

---

## 4. Behaviour by level

| Situation | Assist | Auto | Backup |
|---|---|---|---|
| Normal running | Prepares the off-air input's shot, at most once per tenure (N4) | Prepares, then cuts when the off-air input is cut-ready and the on-air shot has run long enough; "Next: Cam B · 2 s · Esc to cancel" | Same as Auto, no countdown; the next cut is always shown |
| Operator **cuts** | Starts fresh on the new Preview | **Nudge:** hold the operator's choice for at least the minimum shot length, then continue (N1) | Same as Auto |
| Operator touches a camera (preset, zoom, tap, Wide, settings) | **Takeover:** Alfie stops; "Hand to Alfie" resumes | Takeover | Takeover |
| Edit Live | Takeover | Takeover | Takeover |
| On-air subject drifts or the shot needs tightening | — (Program is never touched) | Slow on-air shot move if no better input is ready (N2) | Same |
| Unsure who to show | Prepares a wider shot instead | Cuts to or holds the wider shot (P2) | Same |
| Subject gone (`wideWaiting`) | Drops the close-up preparation | Cuts to the safe wide when cut-ready, otherwise holds the wide (N5) | Same |
| Program source lost | Pauses; operator decides | Pauses; "Program lost: Take Cam A?" | **Cuts to the healthy, verified safe wide inside the router hold window**, then pauses (R2) |
| Output fault or admission lost | Pause | Pause | Pause. The output is R2's job, never Alfie's |
| Run-sheet segment change | Style profile changes; Alfie may suggest "segment changed?" | Same; panel → wide or group shots | Same |
| Show stop | Off; restart is always Manual | Off | Off |

---

## 5. Architecture

```
                 ┌────────────────────────────── ShowCoordinator (MainActor) ─────────────────────────────┐
 operator UI ───►│ take(origin:) / setEditLive / stopShow / add/removeChannel   (pre-admission hooks)     │
 CameraManager   │          ▼                                                                            │
 dispatch obs ──►│  DirectorController ── owns ─► DirectorAuthority (levels incl. Auto/Backup, permits)    │
 source/output/  │    • 4 Hz tick                ─► DirectorPreparation (off-air lease lifecycle)          │
 admission obs ─►│    • event router                                                                      │
                 │    • SubjectSelector  ◄── DirectorEvidenceAdapter ×input ◄── bounded discovery (F-H)    │
                 │    • RunSheet (optional) ─► StyleProfile                                               │
                 │    • ShotPolicy + DirectorJudge (rules today, learned scorer later)                    │
                 │    • CutPolicy (Auto/Backup) ─► CutNotice (countdown) ─► TakePermit ─► take(origin: .director)
                 │    • FallbackRule (Backup) ─► TakePermit ─► take(origin: .fallback)                     │
                 │    • off-air sink: dispatch(.selectPreset, origin: .director)                          │
                 │    • on-air sink:  shot move (slow), origin: .director                                 │
                 │    • status() ─► ConsoleSnapshot ─► NextShotPanel / Manual-Hand to Alfie / tile badge   │
                 └────────────────────────────────────────────────────────────────────────────────────────┘
   DirectorPreferencesStore (style only; level never restored)     DiagnosticsLog [DIRECTOR] (metadata; shadow training data)
```

### Components

| # | Component | Stage | Responsibility |
|---|---|---|---|
| C1 | `DirectorController` | 3a | Owns authority and preparation; runs the tick; routes events; publishes status. Owned by `ShowCoordinator`; epoch history survives Stop and restart |
| C2 | `DirectorEvidenceAdapter` | 3a | Per input: lock phase, gallery readiness, tracking ownership, observation age, subject speed, crop landed, operator gesture → `IdentityEvidence`, settled-since, prepare-ready and cut-ready (§5.2) |
| C3 | Read-only accessors | 3a | `subjectSpeed`, `cropConverged`, `lastObservationAge`, `operatorGestureInProgress` on `ShotComposer` / `CameraManager`. No `@Published` on the frame path |
| C4 | Ingress hooks | 3a | §5.3. `OperatorCommand.Origin` gains `.director`; `take` gains an origin |
| C5 | Off-air sink | 3a | Atomic `.selectPreset` preparation (§5.4) |
| C6 | Candidate builder and history | 3a | Candidates from each input's preset ladder; history from Takes and preset changes |
| C7 | Status and UI | 3a→3c | §5.9 |
| C8 | `DirectorPreferencesStore` | 3a | Versioned style parameters per segment type. Never stores the level |
| C9 | `DirectorJudge` seam | 3a | `RuleJudge` (today's sort) now; learned scorer later (AI options doc) |
| C10 | `CutPolicy` + `CutNotice` | 3b | Pure: when to cut and to which input. The notice holds a deadline token that is checked again at the deadline |
| C11 | `TakePermit` | 3b | One-shot permit bound to authority epoch, roles, route generation, Preview revisions and expiry. Consumed inside `take` in the same turn |
| C12 | On-air sink | 3b | Slow one-rung shot move on Program, Director origin; refused during operator gestures and Edit Live |
| C13 | `SubjectSelector` + discovery mode | 3b | Picks a subject when none is nominated (§5.7); needs bounded discovery (F-H) |
| C14 | `RunSheet` + `StyleProfile` | 3b | Optional segments; operator advances; selects pace and shot-size profile (§5.8) |
| C15 | `FallbackRule` | 3c | Program loss → permit for the verified safe wide inside the hold window (§5.6) |
| C16 | Qualification store | 3a→3c | Per-level sign-off records bound to the rig's admission fingerprint. A level is selectable only on a rig with a current record |

### 5.1 Type changes (Phase 1)

- **`DirectorShot`** becomes the app's `OperatorCommand.Preset`; drop `Mode` and `zoomRung` (N3).
- **`DirectorReadiness`**: `identityConfidence: Double` becomes `identity: IdentityEvidence` (`confirmed / acquiring / holding / lost / ambiguous`). Add a `cutReady` bar alongside `prepareReady` (P1).
- **`DirectorAuthority.Level`** becomes `off / suggest / assist / auto / backup`. Suggest stays as the internal shadow level. `autoTakeQualified` becomes a **per-level qualification lookup** (C16) that returns false until signed off. Authority **rules** stay deterministic; only *availability* is driven by qualification records.
- **Events** become level-aware:
  - In Auto/Backup, `.operatorTake` retires work and starts a nudge hold without pausing (N1).
  - In Backup, `.sourceLoss(program)` issues one fallback request before pausing (R2).
  - `.manualCommand` stays a takeover at every level.
- **`NextShotStatus.DirectorSection`**: `level`, `state` (active / paused / inhibited / abstaining, each with a reason), `prepared`, `nextCut` (input, countdown, cancellable), and `qualified` per level (U2).
- **One parameter source:** `DirectorShotPolicy` reads `DirectorPreferences`, keyed by segment type (T1–T3).

### 5.2 Evidence mapping (P1, P2, N5)

| Input state | `IdentityEvidence` | Effect |
|---|---|---|
| `.tracking`, tracking owns control, gallery ready, observation fresh | `confirmed` | Prepare-ready when settled; cut-ready when also face visible, slow and crop landed |
| `.acquiring` | `acquiring` | Gap: no new preparation or cut to this input |
| `.hold` | `holding` | Gap; composition withdrawn (F-D) |
| `.wideWaiting` | `lost` | Drop the close-up; prefer the safe wide (N5) |
| Two or more candidates and no nomination | `ambiguous` | Prefer a wider shot that holds everyone (P2) |
| Operator gesture in progress | — | Inhibit this input only |
| No lock, no nomination | — | Shot is "wide" by definition; candidate for discovery (F-H) |

All thresholds (settle time, speed, debounce, discovery rate) are study parameters, set from shadow data.

### 5.3 Ingress hooks

| Ingress | Where | Event |
|---|---|---|
| Any non-Director camera command, admitted **or refused** | Observer at the top of `CameraManager.dispatch` (`:902`) | `.manualCommand` → takeover |
| Settings or format change (F-B) | `ShotComposer.$config` subscription (`CameraManager.swift` ~`:1636`) | `.manualCommand` |
| Take attempt, including refused ones | Top of `ShowCoordinator.take` (`:212`), by origin | Operator: `.operatorTake` (N1 by level). Director or fallback: permit consumption |
| Edit Live | `setEditLive` (`:275`) | `.editLive` → takeover |
| Stop / new show | `stopShow` (`:105`), `prepareForNewShow` (`:115`) | `.stopShow` / `.restart` |
| Add or remove input | `addChannel` (`:85`) / `removeChannel` (`:97`) | `.sourceRebound` / `.sourceLoss` |
| Source missing / reconnect | `sourceMissing = true` (`:2414`); `reconnectSource` (`:2421`) | `.sourceLoss` (Backup: fallback first) / `.sourceRebound` |
| Router hold or standby | `ProgramRouter.state` | `.outputFault`, unless it is the Program-source-loss hold that the Backup fallback is handling |
| Admission degraded | `admissionDecision` change | `.admissionLost` |
| Run-sheet segment advanced | C14 | `.policyChanged` scoped to style; no takeover (it's the operator's run sheet) |
| Preferences saved | C8 | `.policyChanged` |
| "Hand to Alfie" | UI | `.resume` with current prerequisites |

### 5.4 Off-air preparation (Assist onward): one turn, no `await`

```text
prepare(request):
  pre = directorState(now)
  guard target == previewChannel, !editLive, preview.activeMode == .autoTracking, lock present,
        !preview.operatorGestureInProgress                        else discard
  expected = (pre.sourceGeneration, pre.controlEpoch &+ 1, pre.shotRevision &+ 1)
  receipt  = preparation.commit(request, live: pre, now, postRevisions: expected)   else stale
  result   = preview.dispatch(.selectPreset(shot), origin: .director)
  guard result == .accepted, preview.revisions == expected        else retire, takeover, log fault
  preparation.acknowledge(receipt, live: directorState(now))
```

Expected revisions come from `CommandDispatcher.accept` (epoch +1) and the `.selectPreset` shot-revision bump; a unit test pins both. **N4:** at most one preparation per Preview tenure, then readiness refresh only.

### 5.5 Automatic cut (Auto onward)

```text
tick:
  decision = CutPolicy(timeline, preview cut-ready, program state, style profile, judge)
  .cut(to: preview, reason)  → CutNotice(deadline = now + notice)       // Backup: notice = 0, still shown
at deadline (same turn):
  permit = authority.issuePermit(epoch, roles, routeGen, previewRevisions, expiry)
  result = show.take(TakeRequest(...), origin: .director, permit: permit)
  // inside take: verify permit first (epoch, roles, route, revisions, expiry, unused),
  // then the EXISTING technical checks (freshness, 0.5 s guard, availability, router commit)
```

Rules:
- The permit is consumed whatever the outcome.
- A refused Take never becomes a later cut.
- Esc or Cancel during the notice cancels this cut only, and starts a minimum-shot-length hold (like a nudge).
- Cuts only ever go to the current Preview. **Director readiness never blocks an operator Take.**

**CutPolicy (pure; parameters from the style profile):**
- Cut only when Program has been on air at least the minimum shot length and Preview is cut-ready.
- One of these must also be true:
  - Program passed its preferred length;
  - Program's subject is lost or uncertain;
  - the segment profile calls for a wide.
- Abstaining is always allowed: "nothing better ready" holds the current shot.

**On-air shot changes (N2):**
- Program's shot changes only through the C12 slow shot move.
- It changes only when no better off-air input is cut-ready, or when there is only one input.
- At most one on-air move per minimum shot length.

### 5.6 Safe-wide fallback (Backup)

On `.sourceLoss(programChannel)`, in Backup level only, the fallback issues one permit for the safe-wide input if all of these hold:
- the safe-wide input is the current Preview;
- it is take-eligible and its frame is fresh;
- its role was verified at setup (R1).

It must commit **within the router's hold window** (0.5 s + 2 s, F-K), and then Alfie pauses. If any check fails, R2's hold → standby continues unchanged and the operator is alerted. The fallback never revives a pre-fault permit, never targets a stale camera and never bypasses the R2 checks. It requires its own fault-rehearsal qualification (unplug, rebind, both lost).

### 5.7 Subject selection when none is nominated (E1)

1. The operator's nomination always wins, and one tap overrides Alfie's pick.
2. Without one, **bounded discovery** runs on off-air shot inputs with no lock: a low-rate person scan using the existing rect + pose requests (F-H).
3. The pick follows visible rules:
   - a run-sheet hint, if given (position: lectern / centre / left / right);
   - otherwise the most central and stable person in the lectern zone;
   - otherwise none.
4. With **two or more plausible people** (panel or crossing), the evidence is `ambiguous`, so Alfie uses a wide or group shot (P2). There is no audio-based active speaker (E2 decided).
5. The auto-pick then goes through the normal acquire → lock path, so identity uses the existing face gallery.

### 5.8 Run sheet (F3, optional)

`RunSheet = [Segment(type: presenter | panel | performance | videoBreak, name?, positionHint?)]`.
- The operator advances segments (keyboard or click). Segments never grant authority; they only select a `StyleProfile`.
- Without a run sheet there is one **Live event** profile.
- Alfie may *suggest* "segment changed?" when evidence shifts, for example when the person count changes, but never advances on its own.
- Saved per show. Import format (CSV or JSON) is a later choice.

### 5.9 UI (U1, U2)

- **Mode control:** Manual · Assist · Auto · Backup. Levels without a qualification record on this rig are greyed out with "not qualified". **Every launch starts in Manual.**
- **Hand control:** one large, always-visible **Manual / Hand to Alfie** toggle, with a keyboard shortcut. Any manual action flips it to Manual.
- **Next-shot panel:**
  - Line 1: the prepared shot.
  - Line 2: plain-words status ("Preparing Cam B Waist Up · subject settled").
  - In Auto: "Next: Cam B · 2 s · Esc to cancel".
- **Tile badge** in the reserved slot: "AUTO" when Alfie set that input's current shot.
- **Run sheet strip** (optional): current and next segment, with an Advance button.

---

## 6. Phased implementation plan

Each phase is one reviewable branch off `r2/engine` with tests. Every exit criterion includes "full unit suite green" and "no new `@Published` on the frame path". Debug-only flags follow the `a89644b` pattern (Release builds always off).

### Stage 3a: Assist

| Phase | Contents | Needs decisions | Exit criteria |
|---|---|---|---|
| **0** | Decision sitting 1 (§8) | — | Recorded in `DECISIONS.md` |
| **1. Types** | §5.1 types, `DirectorJudge` + `RuleJudge`, one parameter source; tests and replay fixtures updated | N3, U2, AI-1 | Director tests and replay green; zero app-behaviour change |
| **2. Evidence** | C3 accessors, C2 adapter, F-D debounce | P1, P2, N5 | Table-driven tests for every row of §5.2 |
| **3. Shadow** | C1, all §5.3 hooks, 4 Hz tick, `[DIRECTOR]` logs of **would-prepare and would-cut** decisions; read-only status | A1, N1, C3, AI-4 | Hook tests for every ingress, including refused Take and the bypass paths; real rehearsal logs collected |
| **4. Assist** | C5 off-air sink, `.director` origin, F-C inhibit, N4 tenure (Debug flag) | S1, N4, T1–T2 interim | Expected == actual revisions; a mismatch → takeover; never touches Program; never supersedes a gesture; replay: 0 stale commits, 0 Director cuts |
| **5. Controls** | Mode control (Manual/Assist), Hand to Alfie, panel, badge, C8 store | U1, F1, F2 | Gallery screenshots per state; launch in Manual |
| **6. Q-Assist** | Evaluation §7 rows E-0 to E-3 for Assist | E3, Q1–Q3 | Sign-off record (C16) for Assist on the named rig |

### Stage 3b: Supervised Auto

| Phase | Contents | Needs decisions | Exit criteria |
|---|---|---|---|
| **7. Take origin + permit** | `take(origin:permit:)`, C11 permit, level-aware `.operatorTake` nudge | A3, N1 | Permit tests: single use; stale epoch, roles, route or revisions refused; permit checked before the existing checks; operator Take path unchanged |
| **8. CutPolicy + notice** | C10 pure policy and notice deadline; shadow-mode cut logging compares CutPolicy with the operator | A4, T1–T3, AI-1 | Replay: 0 cuts without a permit, 0 cuts to a non-Preview input, cancel always wins; shadow agreement report |
| **9. On-air moves** | C12 slow shot move on Program | N2, T2 | Measured move speed within the style limit; never during a gesture or Edit Live |
| **10. Subject discovery** | C13 bounded discovery + `SubjectSelector`; workload measured | E1, P2, C1/C2 | `[SOAK]` within the admission budget on the named rig; picks shown and overridable |
| **11. Run sheet** | C14 model, strip UI, style profiles | F3, T1–T3 | Profile switch changes policy only; never grants authority |
| **12. Q-Auto** | Evaluation for Auto (2 inputs, presenter segments first) | Q1–Q3 | Sign-off record for Auto |

### Stage 3c: Backup

| Phase | Contents | Needs decisions | Exit criteria |
|---|---|---|---|
| **13. Fallback** | C15 safe-wide fallback inside the hold window; level-aware `.sourceLoss` | R1, R2 | Fault permutations: Program unplug, safe wide stale, both lost, rebind. Never a raw source; never outside the hold window |
| **14. Backup level** | Zero-countdown cuts, panel/break profiles on wide or group shots | A4, P2, F3 | Backup scripts pass |
| **15. Q-Backup** | Fault rehearsals with the operator busy for whole segments | Q1–Q3 | Sign-off record for Backup |
| **16. 3–4 inputs** | Cue implementation and Preview selection among inputs; after INPUTS-N/CUE | INPUTS-N | Separate qualification |

Out of scope throughout: audio (E2 decided), unattended operation (UC-1 decided), virtual inputs (UC-2 decided), network use during a show (AI-2 recommended), physical motion (Stage 4).

### External prerequisites

1. **R2 two-camera MULTI-QA** on a named rig, currently *Not run*. Required before Phase 4 is used live and **before any automatic cut**.
2. DegradePolicy numeric repair (`CANDIDATE-REVIEW.md` §1).
3. Setup certification semantics (`CANDIDATE-REVIEW.md` §3). Qualification records (C16) bind to the admission fingerprint.
4. ~~`product-contract.md` rewrite~~: **done 10 Oct** (live-event backup producer, per-level scripts).

---

## 7. Evaluation and qualification

| Step | Method | Assist | Auto | Backup |
|---|---|---|---|---|
| E-0 | Synthetic replay through the real sinks and permit | 0 stale commits | 0 cuts without a permit; cancel always wins | Fallback permutations all safe |
| E-1 | **Shadow mode** at real events | Would-prepare vs what the operator set | **Would-cut vs actual cuts** (input and timing agreement); main evidence and training data | Would-fallback on faults |
| E-2 | Recorded consented footage as validation clips (E3) | Wrong-subject preparations = 0 | Wrong-input cuts per hour; on-air move smoothness | Panel and break handling |
| E-3 | Supervised live rehearsal, both output routes | Unexpected Preview changes = 0 | Unexpected Program changes = 0; operator cancels and nudges counted | Operator busy for whole segments; fault drills |
| E-4 | Per-level sign-off (Q1/Q3) recorded in C16 | Owner + event operator + independent reviewer | Same | Same |

Logs are metadata only, with 30-day retention (`DiagnosticsLog` already prunes at 30 days). No video is kept unless E3 approves consented fixtures.

---

## 8. Decisions

**Recorded:** UC-1 (operator present), E2 (audio paused), UC-2 (one shot per input), and **sitting 1** (10 Oct). Tickets: [STAGE3-TICKETS.md](STAGE3-TICKETS.md).

| Sitting | IDs | When |
|---|---|---|
| **1** (before Phase 1) | S1, A1, A3, E1, P1, P2, N1, N3, N5, U2, AI-1, AI-2, AI-4, C3 | **Recorded 2026-10-10** |
| **2** (before Phase 4) | S2, N4, P3, R1, F1, F2, U1, T1–T3 interim values | Before Assist goes live |
| **3** (before Stage 3b) | A4, N2, F3, C1/C2 (discovery workload), Q1–Q3 | Before Auto |
| **4** (before Stage 3c) | R2 fallback rule, Backup profiles | Before Backup |
| Later | E3 and AI-3 (before collecting footage), AI-5, A2 (Pin), V*, H* | As needed |

Current recommendations for every ID are in `DECISIONS.md` (rows marked "Revised 10 Oct").

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Alfie cuts to the wrong input or person on air | Notice and cancel in Auto; cut-ready is stricter than prepare-ready; ambiguity → wide; shadow agreement evidence before Auto; per-level sign-off |
| Alfie fights the operator | Any manual action is a takeover; gestures inhibit; one-shot permits; nudge hold after operator cuts |
| A stale decision lands late | Epoch, revision and route binding on proposals, permits and notices; same-turn checks; no `await` in sinks |
| Discovery brings back lag | Bounded rate, off-air inputs only, `[SOAK]` measured against the admission budget before Auto |
| Fallback makes a bad situation worse | Backup only; verified safe wide only; inside the hold window only; one permit, then pause; R2 standby untouched |
| On-air moves look robotic | Slow shot move only, measured speed limit, at most one per minimum shot length |
| Lock flicker churns shots | Debounce (F-D) and the N4 tenure rule |
| Synthetic or shadow evidence mistaken for qualification | Evidence class labelled in every report; levels selectable only with a C16 sign-off record |
| Stale docs mislead integrators | Fix the Multiview line in `ALFIE_MULTICAMERA_SPEC.md` (the product contract was rewritten 10 Oct) |
