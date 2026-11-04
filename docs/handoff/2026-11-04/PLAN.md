# Agent relay, 4 November 2026

Order (rev 2, after Claude's second pass): **Claude (done) → Sol 6.1 → Gemini Argon → Grok 4.7 → Claude** (after the 12:20 reset).
Each agent finishes its group, merges to `main`, then writes the next agent's prompt from this plan.

## State of main at handoff (rev 2)

Claude merged 11 PRs on 4 November:

| PR | What | Full suite |
|---|---|---|
| #85 | Integration of #55, #82, #84, #83, #81, #54, #43 (tested together) | 1,147 tests, 0 failed |
| #86 | PAIR-FIRST-FRAME: Cam B starts only after Cam A's first frame is accepted | 1,154, 0 failed |
| #87 | This plan (rev 1) | docs |
| #88 | B13: split ShotComposer.swift, move only | 1,154, 0 failed |
| #89 | RUNSHEET-FOLLOWUPS: Current marker follows Advance; opaque Dark panel | 1,157, 0 failed |
| #90 | AD-RECONCILE report: no owner-free gaps; questions T2, P3, A2/A4, T1/T3 | report |
| #91 | PAN-EASE-MODEL: eased pan behind `DeveloperFlags.easedAutoPan` (off) | 1,163, 0 failed |
| #92 | DEGRADE-MODEL: DegradePolicy runs behind `DeveloperFlags.runtimeWorkloadPolicy` (off) | 1,170, 0 failed |
| #93 | HR-DIGEST: 92 Human Review cards: 54 recommend Done, 23 rig/privacy, 15 owner, 0 missing | report |
| #94 | GUIDE-RENDERS: 7 labelled synthetic figures in the user guide | 1,172, 0 failed |
| #95 | RELEASE-CHECK: Release build succeeds; 3 isolation warnings fixed; fingerprint note | 1,170, 0 failed |

Every number is an unsigned local run: 4 opt-in skips each time, and none of it is GitHub Actions. Still open on GitHub: #29 (CI draft, Sol's group).

## Groups (rev 2; all cards are in 🤖 Agent Queue)

| Group | Agent | Card | Kind |
|---|---|---|---|
| S | Sol 6.1 | [CI-GATES](https://trello.com/c/D2VGtAGU) | finish PR #29 (GitHub Actions) |
| S | Sol 6.1 | [WORKLOAD-INSPECTOR](https://trello.com/c/CWN4G0nA) | small read-only UI |
| G | Gemini Argon | [PR-REVIEW-1104](https://trello.com/c/0U0ZMxZl) | independent review of #85–#95 and Sol's PRs; fix confirmed findings |
| K | Grok 4.7 | [RIG-RUNBOOK-UPDATE](https://trello.com/c/SS7mZhnQ) | docs |
| K | Grok 4.7 | Review Argon's fixes | the same rules as PR-REVIEW, applied to Argon's PRs |

Rev 1's cards (B13, RUNSHEET-FOLLOWUPS, AD-RECONCILE, DEGRADE-MODEL, PAN-EASE-MODEL, HR-DIGEST, GUIDE-RENDERS, RELEASE-CHECK) are done and in 👀 Human Review.

Each card holds its full scope and "done when". An agent that finishes early may take the next group's first card. It should say so on the card, and the next agent skips it.

## Not for agents (owner or rig)

- Triage of Human Review using `reports/human-review-digest-2026-11/README.md`: 54 cards there are recommended for Done.
- Decisions T2 (may Assist prepare while the subject moves?), P3, A2/A4 and T1/T3, from `reports/ad-reconcile-2026-11/README.md`.
- Approving the eased pan from a rig replay (`reports/pan-ease-2026-11/`), and calibrating DegradePolicy thresholds (MULTI-QA).
- Replacing the guide's synthetic figures with approved live captures (`docs/user-guide/screenshot-checklist.md`).
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
   Wrap the test run in a time limit (`perl -e 'alarm 3000; exec @ARGV' xcodebuild …`): an awaited Task that never resumes hangs the whole run. Read the totals with `xcrun xcresulttool get test-results summary --path <x>.xcresult`. The baseline is about 1,172 tests, 0 failed, 4 opt-in skips (check the last PR in the table). Python: `python3 -m unittest` in `CinematicCoreMacOS/scripts`.
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
