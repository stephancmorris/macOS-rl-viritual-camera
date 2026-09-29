# Stage 3 / Stage 4 handoff — Astra (discovery) and GPT-6 Sol (coding)

Prepared 30 Sep 2026. Stage 2 (multi-camera: Program / Preview, Take, Multiview console) is still being finished by Claude on branch `r2/engine`. Stage 3 (Auto Director) and Stage 4 (physical control and voice) start now **in parallel, without touching Stage 2 code**.

| Agent | Role | Branch / worktree | Prompt |
| --- | --- | --- | --- |
| Astra | Discovery for Stage 3 and Stage 4: decision memos, research, evaluation plans, one decision register for Stephan | `s34/astra` in `../alfie-astra` | [ASTRA.md](ASTRA.md) |
| GPT-6 Sol | Code for Stage 3 and Stage 4 that does not depend on open decisions: pure, isolated, unwired modules with simulators and tests | `s34/sol` in `../alfie-sol-s34` | [SOL.md](SOL.md) |

Card text for every R3/R4 card: [CARDS.md](CARDS.md).

## Why this split

Every R3/R4 card is marked "decisions open; not implementation-ready". Stephan makes those decisions. Astra turns each open question into options plus a recommendation. Sol builds only foundations that stay valid whichever option Stephan picks: the director authority state machine, stale-proposal validation, a replay harness, the HardwareLink simulator with e-stop (motion disabled), and the speech grammar as text-only. Anything a decision changes is left as a parameter. Nothing Sol writes is called from the app, so the running app is unchanged.

## Shared rules (both agents)

1. **Work only in your own worktree and branch** (created from `origin/r2/engine`). Commit and push your branch. No PRs, no merges, no rebases of other branches, no Trello writes.
2. **Never edit existing files under `CinematicCoreMacOS/`.** Stage 2 is live on `r2/engine` and edits there collide with Claude's work. Sol adds new files only in the folders listed in SOL.md. If an existing file needs a hook, write the request in `docs/handoff/stage3-4/integration-requests.md` instead.
3. **Never edit** `project.pbxproj`, entitlements, `Info.plist`, `DeveloperFlags.swift`, build scripts, or `CinematicCoreMacOS/build_out/`.
4. **Decisions belong to Stephan.** Write options and a recommendation; never mark a decision as made. Astra keeps the one register at `docs/handoff/stage3-4/DECISIONS.md`.
5. **Locked product rules** (from the specs, apply to every design and line of code):
   - Truthful preview: the operator sees what Alfie actually sends downstream.
   - Return to Wide is one action and always available; manual control outranks anything automatic.
   - No automatic cut (Take) without its own qualification gate; R2 manual operation never silently switches sources.
   - Soft failure: hold the last good Program frame; never publish raw source on failure.
   - Physical safety deadlines and emergency stop live on the hardware, not on a Mac timer; link loss always ends disarmed.
   - No audio is recorded or kept without an approved privacy decision.
6. **Each other's work:** `git fetch origin` before each task. Sol reads Astra's memos on `origin/s34/astra` when they exist; Astra reviews Sol's code on `origin/s34/sol` in its final task.

## Required reading (in the repo)

- `docs/ALFIE_MULTICAMERA_SPEC.md` — R2 authority, including the "Implementation status" table and the console contract.
- `docs/ALFIE_ENGINEERING_SPEC.md` — current-tree engineering spec.
- `docs/astra-sessions/` — earlier design briefs: `00-PROGRAM.md`, `HARDWARE-OPTIONS.md`, `S4`–`S7` (historical; R4 redesign happens here).
- Stage 2 engine code to build against (read-only): `ShowCoordinator.swift`, `ProgramRouter.swift`, `ProgramTake.swift`, `ChannelFrame.swift`, `CameraChannel.swift`, `OperatorCommand.swift`, `MultiInputAdmission.swift`, `Console/TakeAvailability.swift`, `Console/NextShotStatus.swift` (its `DirectorSection` is the reserved R3 seam), `Console/ConsoleSnapshot.swift`.
- On `origin/r2/sol` (Sol's last round, not yet merged; read with `git show origin/r2/sol:<path>`): `reports/readiness-evaluation.md`, `CinematicCoreMacOS/CinematicCoreMacOSTests/ReadinessEvaluationTests.swift`, `CinematicCoreMacOS/CinematicCoreMacOS/DegradePolicy.swift`, `reports/release-2/multi-qa.md`, `docs/privacy/privacy-audit.md`, `docs/decisions/platform-baseline.md`.

## After this round

Stephan reads `DECISIONS.md` and decides. The next round then wires Sol's modules into the app (Claude, or Sol with Claude reviewing), after Stage 2's two-camera validation.
