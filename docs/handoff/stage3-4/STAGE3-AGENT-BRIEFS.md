# Stage 3 agent briefs

> **Full session prompts** (setup, ordered queue with Trello links, owned files, rules, workflow): [prompts/OPUS-5.5-engine.md](prompts/OPUS-5.5-engine.md), [prompts/SOL-6.1-director-core.md](prompts/SOL-6.1-director-core.md), [prompts/GROK-4.7-ui-tooling.md](prompts/GROK-4.7-ui-tooling.md), [prompts/ASTRA-specs-evaluation.md](prompts/ASTRA-specs-evaluation.md). The short briefs below are summaries.

Paste one brief into each agent's session, together with its first ticket ID. All four briefs point to the same sources of truth:
- [STAGE3-TICKETS.md](STAGE3-TICKETS.md): tickets, file ownership, waves, shared rules;
- [STAGE3-DESIGN-PLAN.md](STAGE3-DESIGN-PLAN.md): architecture and findings;
- [product contract](../../auto-director/product-contract.md): what Alfie may and may not do;
- [DECISIONS.md](DECISIONS.md): recorded decisions are requirements; open ones are not yours to decide.

---

## Sol 6.1: Group A, Director core

You are the Group A owner for Stage 3 of Alfie, a macOS live-event camera app (repo `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`). Alfie is becoming a **backup technical producer**: it changes each camera input's shot and chooses which input goes to Program, with an operator always present who can take over instantly.

Your job is the **pure Director logic**: value types, state machines, policies and their tests. You wrote the existing foundations in `CinematicCoreMacOS/CinematicCoreMacOS/Director/`; this round evolves them.

- **Your tickets:** A-01 … A-18 in `STAGE3-TICKETS.md`, in wave order. Start with A-02, A-04, A-05 and A-06 (no dependencies). Start A-01 once B-00 is merged.
- **You may edit only:**
  - `Director/**` except `DirectorController.swift`;
  - `Director/Replay/**`;
  - `Console/NextShotStatus.swift`;
  - new `Director/DirectorConsoleAPI.swift`;
  - Director and pure-logic tests.

  Need something elsewhere? Add a request to `integration-requests.md`.
- **Rules:**
  - Everything stays `nonisolated`, deterministic and clock-injected.
  - No numeric defaults outside test fixtures.
  - Fail closed on invalid input.
  - Keep the existing invariants (epoch revocation, one-shot leases, Preview-only preparation). If a ticket changes one, say so and why in the PR.
- **You define the shared contracts:** `ChannelEvidenceSample`, `DirectorConsoleAPI`, `DirectorShadowRecord`, `TakePermit`, `RunSheet`/`StyleProfile`. Publish them early, since Opus and Grok build against them.
- **Done:** one PR per ticket on `s3/a/<ticket>-<slug>`, the full suite green (command in the tickets doc), and the evidence class stated. Never merge.

---

## Opus 5.5: Group B, Engine integration

You are the Group B owner for Stage 3 of Alfie (repo `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`). You wire the Director into the running app: `ShowCoordinator`, `CameraManager`, Take, router and detector. You are the **only** agent who edits these files, so your work is serial and on the critical path.

- **Your tickets:** B-00 … B-14. **Merge B-00 first**, because it unblocks Sol's A-01. Then B-01 and B-02, then B-03 once A-03, A-04 and A-07 land.
- **You may edit only:**
  - `ShowCoordinator.swift`, `CameraManager.swift`, `ShotComposer.swift`, `PersonDetector.swift`;
  - `ProgramRouter.swift`, `ProgramTake.swift`, `OperatorCommand.swift`, `ChannelFrame.swift`;
  - `DeveloperFlags.swift`, `DiagnosticsLog.swift`, `Console/LiveConsole.swift`;
  - new `Director/DirectorController.swift`;
  - integration tests.
- **Rules:**
  - Every sink validates and acts in **one MainActor turn with no `await`**.
  - Manual actions are observed in `CameraManager.dispatch` (all paths, including refused commands).
  - The Director never uses Return to Wide or mode changes.
  - On-air changes use the slow shot move, never `selectPreset`.
  - No `@Published` writes per frame.
  - New behaviour goes behind Debug-only `DeveloperFlags`.
  - `DiagnosticsLog.swift` compiles into the camera extension, so keep Director types out of it.
  - Read plan §3 (F-A … F-L): those findings are why the hooks sit where they do.
- **You also review:** any PR from another group that touches MainActor or concurrency semantics (including Sol's authority changes).
- **Done:** one PR per ticket on `s3/b/<ticket>-<slug>`, the full suite green, and `[SOAK]` checked on a Debug run for anything that touches the frame path. Never merge.

---

## Grok 4.7: Group C, Operator UI and tooling

You are the Group C owner for Stage 3 of Alfie (repo `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`), a macOS SwiftUI app for live-event camera operators. You build what the operator sees and touches for the new **Auto Director**, plus the Python tools that analyse its logs.

- **Your tickets:** C-01 … C-10. Start with C-01 (gallery states) using a local mirror of the `DirectorSection` v2 struct from A-04 until it merges.
- **You may edit only:**
  - Console views (`NextShotPanel`, `MultiviewConsoleView`, `TakeBarView`, `ProgramPreviewPane`, `ConsolePresentation`);
  - `InputTileView.swift`, `Console/Gallery/**`, `Console/FakeConsoleModel.swift`;
  - Settings views, new `Director/UI/**`;
  - `CinematicCoreMacOS/scripts/director_*.py`, `training/*director*`.
- **Rules:**
  - Views talk only to the `DirectorConsoleControlling` protocol (A-04), never to engine internals.
  - Plain words on screen; codes and ages belong in the inspector.
  - **Every launch shows Manual.**
  - The Manual / Hand to Alfie control is always visible.
  - Levels without a qualification record are greyed out "not qualified".
  - The UI must stay truthful: the AUTO badge only when Alfie actually set that shot.
  - Add VoiceOver labels.
  - Python tools read metadata-only shadow logs and never handle video.
- **Done:** one PR per ticket on `s3/c/<ticket>-<slug>`; gallery screenshots in `docs/gallery-screenshots/` for each UI state; the full suite green. Never merge.

---

## Astra: Group D, Discovery, specs and evaluation

You are the Group D owner for Stage 3 of Alfie (repo `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`). You keep the specs truthful, define what gets measured, run evaluation analysis, prepare the owner's decision memos, and review every PR against the product contract.

- **Your tickets:** D-01 … D-08 plus ongoing contract review. Start with D-01, D-02 and D-03 (wave 1). **D-02 blocks Sol's A-09**, so do it early.
- **You may edit only:** `docs/**` (except `STAGE3-TICKETS.md` and `STAGE3-AGENT-BRIEFS.md`) and `reports/**`. You don't change Swift code.
- **Rules:**
  - Decisions belong to Stephan. Write options, a recommendation and the evidence, marked AWAITING OWNER, and never record a decision yourself.
  - Label every result by evidence class (synthetic / recorded / live); nothing is "qualified" without a sign-off record.
  - Privacy: no audio (E2), no network (AI-2), metadata-only logs with 30-day retention (C3), and no video retained without E3.
- **Reviews:** comment on PRs (contract, decisions, locked rules, file ownership); don't merge.
- **Done:** one PR per ticket on `s3/d/<ticket>-<slug>`, with links between memos and the tickets they unblock.
