# Grok 4.7: Alfie handoff (4 November 2026, rev 3)

You are **Grok 4.7**, taking over from **Claude Opus 5.5** on **Alfie**, a macOS camera app for live events. Alfie auto-frames stage cameras and sends **one Program feed** through a CMIO virtual-camera extension or direct HDMI/USB-C output. It has three operator modes: **Single Cam**, **Multi Cam** (Preview/Program Multiview with Take; two running inputs ship now) and **Webcam**. The Debug-only Auto Director's effects are gated by qualification records, and Release disables Director execution.

The relay so far: Claude → Sol 6.1 → Claude Opus 5.5 → **you** → Claude.

**What changed since rev 1.** Claude Opus 5.5 had budget left and did your original card, RIG-RUNBOOK-UPDATE (PR #100), plus seven small owner-free cards. **Your main job is an independent review of everything Claude Opus 5.5 merged on 4 November.** One optional docs card follows it. Claude reviewed its own work only as the author; that is not an independent review.

## Repository and tools

- Repository: `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`. GitHub: `stephancmorris/macOS-rl-viritual-camera` (use the `gh` CLI).
- Xcode project `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`, scheme `CinematicCoreMacOS`. Test target `CinematicCoreMacOSTests` (Swift Testing, `@testable import Alfie`).
- Trello: **Alfie Coding Board**. The lists are 🤖 Agent Queue → 🚧 In Progress → 👀 Human Review. Never move a card to ✅ Done.
- Read `docs/handoff/2026-11-04/PLAN.md` (rules, owner-only work) and `docs/ALFIE_MULTICAMERA_SPEC.md` (Operator modes, lifecycle).
- Work in your own fresh worktree from `origin/main`. Never edit the owner's checkout, another agent's worktree (Claude's are under `/private/tmp/alfie-*`), `.claude/`, `research_notes/` or other untracked owner files.

## State of main when you start

- Main's code is at **`7d08ecd`** (merge of PR #107), plus this documentation-only handoff on top. Fetch and check the actual HEAD and its CI: `gh run list --branch main --limit 3`.
- Full `CinematicCoreMacOSTests` on main's code (#107's head, local Xcode 27.1, unsigned): **1,185 tests, 1,181 passed, 0 failed, 4 opt-in skips**. [Main CI on `3349cd0`](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/41763826300), before #106 and #107 (hosted Xcode 26.2): 1,183 tests, 1,179 passed, 0 failed, 4 skips, plus the unsigned Release build. Hosted CI passed on every PR below before merge. Python: 127 diagnostics/Director report tests and 16 Director dataset/training tests passed.
- A clean Debug build-for-testing has **0 Swift warnings** in app and test sources. The remaining CMIO placement and AppIntents tool warnings are expected.
- **No open PRs** at handoff and no unfinished Claude Opus 5.5 work.

## What Claude Opus 5.5 merged (review all of these)

| PR | Card | Merge | What |
|---|---|---|---|
| [#98](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/98) | [PR-REVIEW-1104](https://trello.com/c/0U0ZMxZl) | `3d7f471` | Review of #85–#96, #29, #97. **F1 fix:** `LiveConsoleModel.timerTick()` thins only timer refreshes under workload pressure; `refresh()` always runs. Test `LiveConsoleTests.reducedWorkloadNeverDropsAnActionsRefresh`. |
| [#99](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/99) | | `4db9295` | Handoff rev 1 (docs). |
| [#100](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/100) | [RIG-RUNBOOK-UPDATE](https://trello.com/c/SS7mZhnQ) | `1dd3dc1` | `reports/director-study-evidence-2026-10-22/next-group.md`: "What changed since 22 October", 12-step MODE-QA checklist, PAN-EASE replay step, workload notes, `build_release.sh` candidate setup. Procedure only. |
| [#101](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/101) | [ISOLATION-WARNINGS](https://trello.com/c/88MKLWt4) | `c8c3e34` | 71 → 0 Swift warnings: `nonisolated` on `FramingCapability.Reason` and `CropEngine.CropRect`; `@MainActor` on the `ProgramTakeTests.Rig` helper. |
| [#102](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/102) | [SPEC-TRUTH](https://trello.com/c/71EkTIfa) | `0e6f6fd` | `docs/ALFIE_MULTICAMERA_SPEC.md`: picker location and camera-based availability, first-frame rule implemented (#86), degraded-operation note. Docs only. |
| [#103](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/103) | [A11Y-INSPECTOR](https://trello.com/c/CfoiPs0x) | `15d012e` | `InspectorDrawer`: "Open Inspector" / "Close Inspector" accessibility labels and tooltips on the "⌥" handle and chevron close button. Test file `InspectorAccessibilityTests.swift`. |
| [#104](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/104) | [SWIFT6-READINESS](https://trello.com/c/zkEGV4H4) | `5d435c2` | Compiles under `SWIFT_VERSION=6`; project setting stays Swift 5. `nonisolated` boxes and pure types, `isolated deinit` in ShotComposer/CropEngine/PersonDetector, `nonisolated static` signature workers with `@unchecked Sendable` result boxes. Report `reports/swift6-readiness-2026-11/README.md`. |
| [#105](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/105) | [SETUP-TEST-FLAKE](https://trello.com/c/iHwZAJGm) | `3349cd0` | `LiveShowSetupModel` keeps a supplied camera provider authoritative over live rediscovery (a hot-plug overwrote test fixtures). DEBUG seam `CameraManager.setAvailableCamerasForTesting`. Tests `suppliedCamerasSurviveLiveRediscovery`, `defaultCamerasFollowLiveRediscovery`. |
| [#106](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/106) | | `59c2728` | Handoff rev 2 (docs). |
| [#107](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/107) | [CPU-SPAN](https://trello.com/c/gAIDOIR0) | `7d08ecd` | Fixes PR-REVIEW-1104 C2. `ProcessCPUClock` takes an injectable reading and gains `restart()`; `ShowCoordinator.updateShowStandardLifetime` restarts it when the show goes live, so the first window's CPU fraction no longer averages in idle time since launch. Tests `cpuClockRestartDropsTheIdleSpanBeforeIt`, `goingLiveRestartsTheCPUSpan` (fails without the restart). |

## Your work: CLAUDE-REVIEW-1104

Card: [CLAUDE-REVIEW-1104](https://trello.com/c/C9cMNLBm), in 🤖 Agent Queue. Read the live card first. Move it to 🚧 In Progress when you start and to 👀 Human Review when merged. Use the same standard as `reports/pr-review-2026-11-04/README.md`: every finding gets severity, file:line, a reproduction, and either a fix with a regression test or a reason it is not fixed. **Don't manufacture findings.** "No finding" is a valid result for a PR.

Write your report to `reports/claude-review-2026-11-04/README.md`, with a per-PR table like the existing review's.

Questions worth answering, in priority order:

1. **#104, Swift 6 readiness (highest risk).**
   - `isolated deinit` now invalidates each 15 Hz UI-mirror `Timer` on the main actor. Can any of the three objects be released off the main actor, and does `isolated deinit` then defer teardown in a way that matters (a frame callback firing on a half-torn-down object)?
   - `ShotComposer.runSignatureCapture` / `runReacquisitionScoring` are now `nonisolated static`. Check every value they read or return. Is `@unchecked Sendable` on `SignatureCaptureResult` and `ReferencePrints` justified (are the Vision prints really never mutated after capture)?
   - `FaceSignatureExtractor` is now `nonisolated`. Confirm nothing in it touches main-actor state.
   - Optional: build with `SWIFT_VERSION=6` yourself and confirm it still succeeds on main.
2. **#107, CPU span.** Does every way a show goes live pass through `updateShowStandardLifetime` (including `isStartingSession`, which also fires `sessionLivenessDidChange`)? Could a restart while starting, before the first window opens, skew the sample? Is the injected `@Sendable` reading safe?
3. **#105, setup flake.** In the app, `cameras` is never supplied, so the production path should be unchanged. Confirm that. Is there any preview or caller that supplies `cameras` and expects live discovery to replace it?
4. **#98, F1.** Can `timerTick()` and action refreshes still interleave badly? Does anything else depend on refresh parity? Does the test truly fail without the fix (revert the fix locally and run it)?
5. **#101, #103.** Quick checks: no behaviour change in #101; the #103 labels match the visible state.
6. **#100, #102 (docs).** Spot-check claims against the source: the MODE-QA checklist steps, the mode-picker location, the availability rules, and the degraded-operation note. Fix wrong copy in the same PR.

## Optional second card: GALLERY-CAPTURES

Only after CLAUDE-REVIEW-1104 is merged. Card: [GALLERY-CAPTURES](https://trello.com/c/Hu6Jobuo), in 🤖 Agent Queue.

- `docs/gallery-screenshots/README.md` links 17 Multiview captures (`input-*`, `setup-*`, `pill-*`) that were never committed, and no test writes those names.
- Extend the snapshot tests to render each named state from the existing fake models (1280 pt, dark), and commit the PNGs labelled as synthetic.
- Remove rows that have no matching state instead of inventing one.

If you run out of budget, leave the card in Agent Queue and mention it at the top of CLAUDE-NEXT.md.

## Build and test

```sh
xcodebuild -version
A="$(mktemp -d /private/tmp/alfie-grok.XXXXXX)"
xcodebuild build-for-testing -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' -derivedDataPath "$A/DerivedData" CODE_SIGNING_ALLOWED=NO
perl -e 'alarm 3000; exec @ARGV' xcodebuild test-without-building -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' -derivedDataPath "$A/DerivedData" \
  -only-testing:CinematicCoreMacOSTests -resultBundlePath "$A/unit.xcresult" CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path "$A/unit.xcresult"
(cd CinematicCoreMacOS/scripts && python3 -m unittest)
(cd training && python3 -m unittest discover -p 'test_director_*.py')
```

- For the Swift 6 check, add `SWIFT_VERSION=6` to the build-for-testing line and use a separate DerivedData path.
- Always use the time limit. In zsh, pass multiple `-only-testing:` flags as an array.
- Docs-only changes still need hosted CI green before merging.

## Rules and hard limits

- One PR per card, ending with your agent attribution line. Merge with a merge commit after the full suite and hosted CI are green. Never force-push `main` or rewrite another agent's branch. Leave branch protection unchanged.
- Comment the PR link, merge SHA and exact totals on each card, then move it to 👀 Human Review.
- Don't change Director authority levels, qualification records or `DeveloperFlags` release behaviour. Never add an automatic Take path. Keep the eased pan and workload policy off by default.
- **Don't switch the project to Swift 6** (`SWIFT_VERSION` stays 5.0) and don't add a Swift 6 CI job. Both are owner decisions; see `reports/swift6-readiness-2026-11/README.md`.
- Never certify a rig, release, privacy review or qualification gate from software tests.
- Owner-only work stays with the owner:
  - Human Review triage;
  - the T2, P3, A2/A4 and T1/T3 decisions;
  - the G-02…G-08 sign-offs;
  - approving the eased pan;
  - DegradePolicy calibration, and the C1 and C3 notes from PR-REVIEW-1104 (C2 is fixed in #107);
  - Single Cam Director placement;
  - the Swift 6 switch;
  - the MODE-QA → DISPLAY-QA → ZOOM-QA → PAN-HITCH → SOAK → INSTALL rig runs.

## When you finish

1. Make sure everything is merged and main is green.
2. Write `docs/handoff/2026-11-04/CLAUDE-NEXT.md` for Claude, after the usage reset. Use this file's structure, add a "Grok results" section to `PLAN.md`, and merge both.
3. For anything unfinished: put it at the top of that handoff, comment on the card, and leave it in 🤖 Agent Queue.
4. Give the owner a short summary and the prompt:
   `Read docs/handoff/2026-11-04/CLAUDE-NEXT.md in /Users/stephanmorris/Documents/macOS-rl-viritual-camera and do it.`
