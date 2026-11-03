# Agent relay, 4 November 2026

Order: **Claude (done) → Sol 6.1 → Gemini Argon → Grok 4.7 → Claude** (after the 12:20 reset).
Each agent finishes its group, merges to `main`, then writes the next agent's prompt from this plan.

## State of main at handoff (`4782291`)

Claude landed:

- **PR #85** integrates #55 (B10), #82 (Director wave 2), #84 (run sheet in a real show), #83 (cut settle evidence), #81 (show lifecycle and Director evidence tooling), #54 (B12 CameraManager split) and #43 (hygiene audit report). They were tested together: 1,147 tests, 1,143 passed, 0 failed, 4 opt-in skips. #84 and #83 were closed with a pointer to #85.
- **PR #86** PAIR-FIRST-FRAME: Cam B starts only after the output accepts Cam A's first new frame. 1,154 tests, 1,150 passed, 0 failed, 4 opt-in skips.

Still open on GitHub: #29 (CI, draft; Grok's group) and nothing else that should land.

## Groups (all cards are in 🤖 Agent Queue)

| Group | Agent | Card | Kind |
|---|---|---|---|
| S | Sol 6.1 | [B13 split ShotComposer](https://trello.com/c/JkIvhOM8) | move-only refactor |
| S | Sol 6.1 | [RUNSHEET-FOLLOWUPS](https://trello.com/c/K3yljzlQ) | small fixes |
| S | Sol 6.1 | [AD-RECONCILE](https://trello.com/c/jhhQuzKv) | report + undecided-free fixes |
| G | Gemini Argon | [DEGRADE-MODEL](https://trello.com/c/mn5yLeQe) | pure model behind a flag |
| G | Gemini Argon | [PAN-EASE-MODEL](https://trello.com/c/2eNaDU59) | pure model behind a flag |
| G | Gemini Argon | [HR-DIGEST](https://trello.com/c/IwgrhJkg) | board report |
| K | Grok 4.7 | [CI-GATES](https://trello.com/c/D2VGtAGU) | finish PR #29 |
| K | Grok 4.7 | [GUIDE-RENDERS](https://trello.com/c/lZEFdClW) | docs |

Each card holds its full scope and "done when". If an agent finishes early, it may take the next group's first card. It should say so on the card, and the next agent skips it.

## Not for agents (owner or rig)

- MODE-QA, DISPLAY-QA, ZOOM-QA, PAN-HITCH, SOAK, INSTALL: the attended rig run, in that order.
- Owner decision sittings G-02…G-08 and the qualification sign-offs.
- Whether the Auto Director gets a home in Single Cam (MODES-SPEC open question).
- Rhythm preview v2: Often and Rarely wides look the same with one camera (PR #82 note).
- READINESS, SETUP, DEGRADE thresholds, LAG-DIAG: these need calibrated or rig evidence.
- INPUTS-N / CUE / ADMISSION-N: gated on two-input MULTI-QA and owner G-08.

## Rules every agent follows

1. **Repo** `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`, Xcode project `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`, scheme `CinematicCoreMacOS`, test module `Alfie`. Read `docs/ALFIE_MULTICAMERA_SPEC.md` (Operator modes, lifecycle) before touching show or console code.
2. **Branch per card** from fresh `origin/main` (for example `sol/b13-shotcomposer-split`). Use a separate worktree, because other agents' worktrees exist under `~/Documents/alfie-*` and `~/.codex/worktrees`; never edit those. Don't commit `.claude/`, `research_notes/` or other untracked owner files.
3. **Build and test (unsigned)**, with your own DerivedData path:
   ```
   xcodebuild build-for-testing -project CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS -destination 'platform=macOS' -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO
   xcodebuild test-without-building ... -only-testing:CinematicCoreMacOSTests -resultBundlePath <x>.xcresult CODE_SIGNING_ALLOWED=NO
   ```
   Wrap the test run in a time limit (`perl -e 'alarm 3000; exec @ARGV' xcodebuild …`): an awaited Task that never resumes hangs the whole run. Read the totals with `xcrun xcresulttool get test-results summary --path <x>.xcresult`. The baseline is 1,154 tests, 0 failed, 4 opt-in skips. Python: `python3 -m unittest` in `CinematicCoreMacOS/scripts`.
4. **Swift 6 project flags:** `default-isolation=MainActor`, `NonisolatedNonsendingByDefault`, `MemberImportVisibility`.
   - Pure value types used off the main actor are `nonisolated`.
   - A default argument that constructs a MainActor type fails in tests; use an optional and `??` instead.
   - Add explicit `import Combine` / `CoreGraphics` where needed.
   - `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, `ProgramOutputDiagnostics.swift` and `ShowStandard.swift` also compile into the CMIO extension; a new type they reference must be added there too.
5. **Frame path:** no per-frame `@Published` writes. UI reads at ≤15 Hz or on transitions.
6. **Dev-only behaviour** goes behind a `DeveloperFlags` constant that is `#if DEBUG`-gated and off in Release.
7. **PR** per card with what changed, why, tests and verification totals. End the PR body with your agent's attribution line. Merge with a merge commit once the full suite is green. Don't force-push `main` or rewrite others' branches.
8. **Trello** (Alfie Coding Board): comment on the card with the PR link, the merge commit and the test totals, then move it to 👀 Human Review. Never move a card to ✅ Done, and never mark a rig, release, privacy or qualification gate as passed from software tests.
9. **Handoff:** when your group is done, write `docs/handoff/2026-11-04/<NEXT-AGENT>.md`. Base it on this plan and on `SOL-6.1.md` as the template: update the "state of main", add your results, and note anything the next agent must know. Commit it to main. Then tell the owner the prompt to paste (one line pointing at that file).
