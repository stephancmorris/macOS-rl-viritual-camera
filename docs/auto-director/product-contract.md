# Auto Director product contract: live-event backup producer

Status: **proposed contract, revised 2026-10-10.** It replaces the 30 Sep sermon-only Auto Prepare contract, which remains in git history. Design: [STAGE3-DESIGN-PLAN.md](../handoff/stage3-4/STAGE3-DESIGN-PLAN.md). Use case: [STAGE3-USE-CASE.md](../handoff/stage3-4/STAGE3-USE-CASE.md). Authority rules: [authority-and-override](authority-and-override.md).

**Recorded decisions** (`DECISIONS.md`, 2026-10-10, Stephan):
- **UC-1:** an operator is always present; unattended operation is out of scope.
- **E2:** audio is paused; no microphone or audio evidence.
- **UC-2:** each camera is one input with one shot that Alfie may change; Alfie sends the input that fits best; no virtual inputs.

Every other point below is **proposed, AWAITING OWNER**.

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| S1 First directing scope? | Sermon Auto Prepare only; live-event Assist only; **live-event backup producer in qualified steps** | Live-event backup producer with static cameras: shadow → Assist → supervised Auto → Backup, each behind its own gate. This matches the product goal and still earns trust step by step | AD-SCOPE, all Director wiring | Yes; a level can be withdrawn by revoking its qualification |
| S2 What remains manual? | All cuts; show-level control only; nothing | Show start/stop, output routing, the run sheet and taking control. Nomination optional. Every cut stays manual in Assist | AD-SUBJECT/TAKE | Yes, requalify |

## The product

Alfie is a **backup technical producer** for live events: conferences, services, presentations, ceremonies and similar shows that use static cameras. Each camera is one input with one shot. Alfie can change that shot and choose which input goes to Program. A run sheet helps when there is one, and Alfie still works without one. **The operator is always present and always outranks Alfie.**

## Existing foundation

- `ShowCoordinator.swift` owns the input roles and routes `TakeRequest` through a synchronous `take`.
- `ProgramRouter.swift` owns the one downstream Program output, including the soft-failure hold (0.5 s, then a 2 s labelled hold, then standby).
- `OperatorCommand.swift` / `CommandDispatcher` provide channel-scoped commands.
- `ShotComposer.swift` provides framing, lock and recovery.

The Director is orchestration above these. It is not a new crop mode, output or media graph. R2 two-camera real-rig qualification (MULTI-QA) is still required; code and unit tests are not release evidence.

## Levels

| Level | Alfie may | Alfie may not | Operator |
|---|---|---|---|
| **Manual** (every launch starts here) | Nothing | Anything | Runs the show |
| **Shadow** (internal) | Log what it would prepare and cut | Touch any camera or output | Runs the show |
| **Assist** | Change the off-air (Preview) input's shot, at most once per Preview tenure | Cut; touch Program | Makes every cut |
| **Auto** (supervised) | Assist, plus **cut to Preview** after a visible, cancellable notice; slow on-air shot moves when no better input is ready | Cut without a permit; cut to anything but Preview; snap an on-air shot | Watches, cancels, nudges, takes over |
| **Backup** | Auto without a countdown (the next cut is always shown); **cut to the verified safe wide when the Program camera is lost**, inside the router hold window | Act after a takeover; bypass R2 hold or standby; send a raw source | Present but busy; takes over with one action |

A level can only be selected on a rig with a current sign-off record for that level. Otherwise it appears greyed out as "not qualified".

## Contract

**Inputs and roles**
- Two admitted inputs first; three and four come after the INPUTS-N/CUE work.
- One input is a **verified safe wide** (R1); the others are shot inputs.

**Subjects**
- The operator may nominate a person on any input, and that always wins.
- Without a nomination, Alfie picks from what it sees: a run-sheet position hint, otherwise the central and stable presenter. The pick is shown and one tap overrides it.
- With several plausible people (panel, crossing), Alfie uses a wide or group shot. It never guesses a close-up.
- Cross-camera identity is not inferred. A name is operator metadata, not recognition.

**Shots**
- Alfie uses the app's own presets: Stage Wide / Full Body / Waist Up, Webcam Wide / Tight.
- Off-air changes are preset changes.
- On-air changes are slow, one-step moves only.
- Alfie never uses Return to Wide or mode changes, so it can't drop the subject lock.

**Cuts** (Auto and Backup only)
- Each cut needs a one-shot permit checked in the same turn as R2's existing Take checks.
- A refused cut never turns into a later cut.
- Cancel always wins.
- Director readiness never blocks an operator Take.

**Run sheet** (optional)
- Typed segments: Presenter, Panel, Performance, Video/Break, each with an optional name or position.
- The operator advances segments, and Alfie may suggest "segment changed?".
- A segment selects a style profile (pace, shot sizes, how often to go wide). It never grants authority.

**Manual priority**
- Any operator camera action or Edit Live is a **takeover**: Alfie stops preparing and cutting. One **Hand to Alfie** action gives control back.
- In Auto and Backup, an operator *cut* is a **nudge**: Alfie keeps that shot for at least the minimum shot length, then continues.
- Return to Wide is always one action.

**Failure**
- Soft failure stays R2's job: hold the last good frame and never publish a raw source.
- An output fault or admission loss pauses Alfie at every level.
- Program camera loss:
  - **Assist / Auto:** Alfie pauses and asks.
  - **Backup:** Alfie cuts once to a fresh, verified safe wide within the hold window, then pauses.

**Truthful preview:** a tile badge shows when Alfie set an input's shot, and the next cut is always visible.

**Privacy and connectivity**
- No audio (E2).
- No network during a show (recommended AI-2).
- Director logs are metadata only, with 30-day retention.
- No video is kept without a separate consented-fixture decision (E3).

## Supported, gated and unsupported

| Status | Items |
|---|---|
| **Supported in qualified steps** | Presenter segments; panels and performances on wide or group shots; breaks and videos on the safe wide; automatic cuts (Auto, Backup); slow on-air reframing; operator-free subject picking for a single presenter; optional run sheet; safe-wide fallback (Backup) |
| **Gated for later** | Three and four running inputs (INPUTS-N/CUE); learned shot and cut scoring (AI options, after shadow data) |
| **Unsupported** | Unattended operation (UC-1); audio or active-speaker selection (E2); several shots from one camera (UC-2); audience or reaction close-ups; children as inferred targets; physical camera motion (Stage 4); spoken commands (Stage 4); ATEM tally/control; extra outputs; network or cloud decisions during a show |

## Minute-by-minute walkthroughs

These are proposed rehearsal scripts, not timing requirements. A good stable shot may stay indefinitely, and Alfie never forces a bad cut to meet a timer. A is the safe wide; B is the shot input.

### 1. Assist: conference keynote with a run sheet

| Minute | Operator | Alfie / Program |
|---|---|---|
| 00 | Starts the show; A wide on Program; loads the run sheet ("Keynote · Jane · lectern") | Manual; confirms the downstream Program is A |
| 01 | Selects Assist | Picks the person at the lectern on B (shown, overridable); prepares B Waist Up once settled |
| 02 | Cuts to B | Starts fresh; Preview is now A (the safe wide, nothing to prepare) |
| 04 | Cuts back to A | Prepares B again; at most one change in this Preview tenure |
| 05 | Taps a different person on B | Takeover; Alfie stops |
| 06 | Presses Hand to Alfie | Resumes with that nomination |
| 09 | Advances the run sheet to "Q&A · Panel" | Panel profile: prepares B as a group shot (Wide preset), no close-ups |

### 2. Auto: presenter segment

| Minute | Operator | Alfie / Program |
|---|---|---|
| 00 | A wide on Program; selects Auto | Prepares B Waist Up on the presenter |
| 01 | Watches | "Next: Cam B · 2 s · Esc to cancel" → cuts to B |
| 02 | Presses Esc during the next notice | That cut is cancelled; A is held for at least the minimum shot length |
| 03 | Watches | The presenter walks off-centre; no better input is ready, so a slow on-air pull-out on B |
| 04 | Cuts to A themselves | Nudge: Alfie keeps A for at least the minimum shot length, then continues |
| 06 | Adjusts B's zoom | Takeover; Alfie stops cutting and preparing |
| 07 | Hand to Alfie | Resumes; fresh decisions only, nothing carried over from before the takeover |

### 3. Backup: disturbances while the operator is busy

| Minute | Operator | Alfie / Program |
|---|---|---|
| 00 | Selects Backup; turns to the slides computer | Producing presenter shots without a countdown; next cut always shown |
| 01 | — | A second person crosses B: ambiguous, so Alfie stays on or cuts to the wider shot |
| 02 | — | Presenter leaves frame: the close-up is dropped and Alfie cuts to A when cut-ready |
| 03 | — | **B (on Program) is unplugged:** the router holds; Alfie cuts once to the fresh, verified A within the hold window, then pauses with an alert |
| 04 | Returns; reconnects B | B gets a fresh source generation; Alfie is still paused |
| 05 | Hand to Alfie | Resumes with new evidence; no countdown or decision carried over |
| 06 | — | **Both inputs stale:** Alfie does nothing; R2 holds, then standby; alert |
| 07 | Stops the show | Off; every grant retired; next launch starts in Manual |

## Acceptance evidence (per level)

- **All levels:**
  - The operator can say what Alfie will do next, tell Preview from Program, and take over or go Wide without searching.
  - Every fault is recovered without a silent source switch.
  - The scripts run on both downstream routes.
- **Assist:** 0 unexpected Preview changes; preparations saved compared with manual R2.
- **Auto:** 0 cuts without a permit; 0 wrong-input cuts in scored runs; cancels and nudges counted; shadow agreement between Alfie's would-cut log and the operator's actual cuts reported before the live trial.
- **Backup:** every fault drill passes; the fallback commits only inside the hold window; whole segments run with the operator busy.
- **Sign-off:** owner, an event operator and an independent technical reviewer, recorded per level against the rig's admission fingerprint (Q1–Q3).

**Risks:**
- Wrong-person or wrong-input cuts on air: mitigated by the notice and cancel, the stricter cut-ready bar, and wide-on-ambiguity.
- Discovery workload bringing back lag: must be measured before Auto qualifies.
- Operators over-trusting Backup: the operator must always be present (UC-1).
