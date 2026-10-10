# Stage 3 use case: Alfie as a backup technical producer

Prepared 10 Oct 2026 from the owner's direction in chat. This **reframes** the Stage 3 product contract (`docs/auto-director/product-contract.md`, 30 Sep). All recommendations remain **AWAITING OWNER** until recorded in `DECISIONS.md`. The rewritten contract is now in `docs/auto-director/product-contract.md` (10 Oct).

## 1. The use case

> Alfie is used primarily at **live events**. Some events have a **run sheet** and some don't. Alfie's strength is making **several good shots from static cameras** (initially). In auto mode Alfie **sets the shots based on what it sees and puts the best input to Program**. The goal is a **backup technical producer**.

### What "backup technical producer" means here (confirmed 10 Oct: UC-1)

A human operator is **always present** and always outranks Alfie. Unattended events are out of scope. Alfie can do three jobs, each needing more trust than the last:

| Mode | Who frames | Who cuts | Typical moment |
|---|---|---|---|
| **Assist** | Alfie prepares Preview | Operator | The operator is busy with slides or audio but still cutting |
| **Auto (supervised)** | Alfie | **Alfie**, with a short visible "next cut" notice the operator can cancel | The operator watches and corrects |
| **Backup** | Alfie | Alfie | The operator is present but busy or overloaded (another task, a fault elsewhere); Alfie keeps a clean, safe show going |

Taking back control is always **one action**, and any manual action takes over immediately.

### How this differs from the 30 Sep contract

| 30 Sep contract | Live-event producer |
|---|---|
| Sermon only, one nominated speaker | Any live event: presenters, panels, performances, breaks |
| Automatic Take unavailable; Auto Prepare is the end state | **Automatic Take is the product goal.** Auto Prepare becomes a qualification step towards it |
| Operator nominates every subject | Operator *may* nominate; otherwise Alfie chooses from what it sees and the run sheet |
| Panels, active speaker and unattended operation unsupported | Panels (wide/group shots, no audio) and Backup are in scope, each behind its own gate. Unattended stays out |
| On loss: ask and pause | On loss: a producer **cuts to the safe wide**. That needs its own qualified rule |
| Two inputs only | Two first; **one shot per input** that Alfie may change, and Alfie sends the input that fits best (UC-2) |

### What stays non-negotiable (from the locked product rules)

1. **The preview is truthful**: what Alfie sends is what the operator sees.
2. **Manual control outranks Alfie instantly**, and Return to Wide is always one action.
3. **No automatic cut without its own qualification gate.** The gate is now on the roadmap, not removed.
4. **Soft failure**: hold the last good frame; never send a raw or broken source.
5. **No audio is recorded or kept** without an approved privacy decision.

---

## 2. Revised recommendations (AWAITING OWNER)

Rows marked **Changed** differ from the register's current recommendation. ✔ = same as before.

### Scope and authority

| ID | Question | Revised recommendation | vs register |
|---|---|---|---|
| **S1** | First directing scope | **Live-event backup producer with static cameras.** Build up in qualified steps: shadow → Assist → supervised Auto (single-presenter segments first) → Backup. Each step ships only after its gate passes | **Changed** (was sermon Auto Prepare only) |
| **S2** | What stays manual | Show start/stop, output routing, the run sheet, and taking control. Subject nomination is **optional**, not required | **Changed** (was all cuts and nominations manual) |
| **A3** | Who may cut automatically | **Alfie, in Auto and Backup, after qualification.** One-shot permit checked in the same turn as the existing Take checks (`ShowCoordinator.take`) | **Changed** (was "unavailable initially") |
| **A1** | Manual override scope | Any manual action → **immediate takeover**: Alfie stops cutting and preparing. One **"Hand to Alfie"** button to give control back | Changed in wording; same intent |
| **N1** | What an operator Take does | **Assist:** start fresh on the new Preview, no pause. **Auto:** treat it as a *nudge*: Alfie holds the operator's choice for at least the minimum shot length, then continues. **Manual** button = full takeover | **Changed** (was a fresh epoch without pausing, for Auto Prepare only) |
| **A4** | Notice before an automatic cut | **Auto (supervised):** short visible "Next: Cam B" with one-key cancel (start at 2–3 s and tune with data). **Backup:** no countdown, but the next cut is always shown | Refined |
| **N2** | Framing changes on Program with one camera | **Yes, as part of Auto:** slow, on-air-safe pushes and pulls only (no snaps), because with one static camera, reframing *is* the edit | **Changed** (was "not in Stage 3") |
| **UC-2** | Shots per camera | **DECIDED 10 Oct:** one shot per input (camera); Alfie may change that shot and sends the input that fits best. No virtual inputs | Decided |

### Subjects, evidence and run sheet

| ID | Question | Revised recommendation | vs register |
|---|---|---|---|
| **E1** | Who chooses the person | **Operator nomination when given.** Otherwise Alfie picks using visible rules: lectern or centre-stage presenter, a run-sheet hint, and the most stable tracked person. It is always shown and one tap overrides it | **Changed** (was operator only) |
| **E2** | Audio | **DECIDED 10 Oct: none, audio paused.** Events usually run separate audio software. Panels use wide/group shots chosen from what Alfie sees | Decided |
| **P1** | "Ready" definition | **Two bars:** *prepare-ready* (confirmed lock, settled) and a stricter *cut-ready* (also face visible, not mid-stride, framing landed) | Refined |
| **P2** | Ambiguous person | Don't guess a close-up. Fall back to the wider shot that holds everyone, and keep producing | **Changed** (was abstain and ask) |
| **N5** | `wideWaiting` (the speaker has gone) | Treat it as the subject lost: Alfie cuts or holds on the wide, and drops the close-up | ✔ (consequence adjusted) |
| **F3** | Run sheet | **Optional, and it guides style, never authority.** Segments carry a type (Presenter, Panel, Performance, Video/Break) and an optional name or position hint. The operator advances segments; Alfie may *suggest* "segment changed?" from what it sees. With no run sheet, Alfie uses a general "Live event" profile | **Changed** (was operator-advanced constraints only) |
| **T1–T3** | Pace, movement, wides | **A style profile per segment type** (Presenter calm, Panel livelier, Performance musical, Break wide). Starting values come from shadow-mode data, not guesses | **Changed** (was single sermon values) |

### Roles and failure

| ID | Question | Revised recommendation | vs register |
|---|---|---|---|
| **R1** | Camera roles | **Keep one verified safe-wide**, which matters more now that Alfie cuts. The other inputs are "shot" cameras | ✔ |
| **R2** | Automatic loss fallback | **In Auto and Backup: cut to the healthy safe wide on Program source loss**, as a separately qualified rule. In Assist: ask, as before | **Changed** (was ask and pause) |

### Interface and AI

| ID | Question | Revised recommendation | vs register |
|---|---|---|---|
| **U2** | Modes shown | **Manual · Assist · Auto · Backup**. A level appears greyed out with "not qualified" until it passes its gate | **Changed** (was four technical levels) |
| **U1** | Where the controls go | Next-shot panel, plus a large **Manual / Hand to Alfie** toggle that is always visible | Refined |
| **AI-1** | What AI may decide | **Shot choice *and* which input goes to Program**, ranked within rule-allowed options, with low-confidence abstention to the safe wide | **Changed** (was ranking prepared shots only) |
| **AI-2** | Network during a show | **Never.** Venue Wi-Fi is unreliable, and a backup producer must work offline | ✔ |
| **AI-4** | Train on shadow logs | Yes, metadata only. The cut decisions logged in shadow mode become the main training signal | ✔ |

---

## 3. What this changes in the plan

| Plan area | Change |
|---|---|
| **Roadmap** | Stage 3 becomes **3a Assist** (the current plan's Phases 1–5), **3b Supervised Auto** (automatic Take with notice and cancel, single-presenter segments), **3c Backup** (hand-off while the operator is busy, safe-wide fallback, panels on wide/group shots) |
| **Shadow mode** | Now logs **cut decisions** as well as shot choices: which input Alfie would put to Program and when, against what the operator actually did. This becomes the main evidence for qualifying Auto |
| **New engine work** | Take permit (one-shot, synchronous, inside `ShowCoordinator.take`); run-sheet model and segment advance; auto subject selection; safe-wide fallback rule; on-air shot-change rules (N2); Cue for 3–4 inputs |
| **AI** | The learned scorer from `STAGE3-AI-OPTIONS.md` grows from "rank shots" to "rank shot + input + timing". It stays local, with the rules as fallback |
| **Qualification (Q1–Q3)** | Separate gates for Assist, Auto and Backup. Backup needs fault rehearsals: camera unplug, output fault, operator busy with another task for a whole segment |
| **Docs** | Done 10 Oct: `product-contract.md` rewritten. Panels and automatic cuts are supported in qualified steps; audio/active speaker and unattended operation stay unsupported; new Assist, Auto and Backup scripts |

### Prerequisites that become more important

- **R2 two-camera MULTI-QA (still Not run).** Automatic cutting depends on Take being proven on real hardware.
- **Admission and workload evidence.** Alfie deciding cuts adds work alongside the camera pipelines.
- **Cue for 3–4 inputs (INPUTS-N).** A producer with more than two inputs has to choose which input to set up next.

---

## 4. Owner answers (10 Oct 2026)

1. **Operator present.** Alfie is a safety net, never unattended (UC-1).
2. **Audio paused.** Most events run separate audio software; no audio evidence in Stage 3 (E2).
3. **One shot per input.** Each camera is one input with one shot that Alfie may change; Alfie sends the best input. No virtual inputs (UC-2).

All are recorded in `DECISIONS.md` under "Recorded decisions". All other recommendations above are mirrored into the register as "Revised 10 Oct" and stay OPEN.
