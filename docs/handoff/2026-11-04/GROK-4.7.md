# Grok 4.7: Alfie handoff (4 November 2026)

You are **Grok 4.7**, taking over from **Claude Opus 5.5** on **Alfie**, a macOS camera app for live events. Alfie auto-frames stage cameras and sends **one Program feed** through a CMIO virtual-camera extension or direct HDMI/USB-C output. It has three operator modes: **Single Cam**, **Multi Cam** (Preview/Program Multiview with Take; two running inputs ship now) and **Webcam**. The Debug-only Auto Director's effects are gated by qualification records, and Release disables Director execution.

The relay so far: Claude → Sol 6.1 → Claude Opus 5.5 → **you** → Claude.

## Repository and tools

- Repository: `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`. GitHub: `stephancmorris/macOS-rl-viritual-camera` (use the `gh` CLI).
- Xcode project `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`, scheme `CinematicCoreMacOS`. Test target `CinematicCoreMacOSTests` (Swift Testing, `@testable import Alfie`).
- Trello: **Alfie Coding Board**. The lists are 🤖 Agent Queue → 👀 Human Review. Never move a card to ✅ Done.
- Read `docs/handoff/2026-11-04/PLAN.md` (rules, owner-only work) and `docs/ALFIE_MULTICAMERA_SPEC.md` (Operator modes, lifecycle).
- Work in your own fresh worktree from `origin/main`. Never edit the owner's checkout, another agent's worktree, `.claude/`, `research_notes/` or other untracked owner files.

## State of main when you start

- Main is at **`3d7f471`** (merge of PR #98), plus this documentation-only handoff on top. Fetch and check the actual HEAD.
- Hosted CI on PR #98's head (Xcode 26.2, `macos-26`): **1,180 Swift tests, 1,176 passed, 0 failed, 4 opt-in skips** (xcresult declaration counts). The Release build and consistency checks passed.
- Locally on Xcode 27.1 (27A9275): the same 1,180 / 1,176 / 0 / 4. Python: 127 diagnostics/Director report tests and 16 Director dataset/training tests passed.
- Check main's CI run for `3d7f471` and this commit: `gh run list --branch main --limit 3`.
- **No open PRs** at handoff and no unfinished Claude Opus 5.5 work.

## What Claude Opus 5.5 did

[PR #98](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/98), merge `3d7f4712154f5c9a8683dc89b1a7cdc317875a2d`, card [PR-REVIEW-1104](https://trello.com/c/0U0ZMxZl), now in 👀 Human Review.

- Reviewed #85–#96, #29 and #97 at main `823a0c3`. The report is `reports/pr-review-2026-11-04/README.md`.
- **F1 (low, confirmed, fixed):** with `DeveloperFlags.runtimeWorkloadPolicy` on and the level at `optionalUI` or above, the Multiview console skipped every other `refresh()`. That included the immediate refreshes Take, Edit Live, pane view and Advance ask for. The skip now lives in `LiveConsoleModel.timerTick()` (`Console/LiveConsole.swift`), and `refresh()` always runs. Regression test: `LiveConsoleTests.reducedWorkloadNeverDropsAnActionsRefresh`. It failed on the old code and passes now.
- **Disproved:**
  - #86, that a route change could strand Cam B: the session route is frozen while capture runs.
  - #92, that pacing repeats count as misses: only HOLD and standby repeat.
- **Recorded, not fixed:**
  - #92's miss fraction under-reports frames that are never produced (a MULTI-QA calibration question).
  - The first CPU sample spans the time since launch.
  - #97's "Recovering after pressure" text stays shown after recovery (the owner's copy call).

## Your work

### 1. RIG-RUNBOOK-UPDATE (https://trello.com/c/SS7mZhnQ)

Read the live card first and follow it, not this summary. As of handoff it asks:

- Update the attended rig runbook from commit `30ec212` ("Prepare the next attended rig validation group"; `git show 30ec212 --stat` shows the files), and MODE-QA's checklist, so each step says what to look for now. That covers:
  - the three modes, and the mode picker on the stopped screens;
  - the refusal when leaving Multi Cam;
  - Cam B waiting for Cam A's first accepted frame, with the console note (#86);
  - the run-sheet Current marker (#89);
  - the eased pan and workload flags, both off by default (#91, #92), and how to turn them on in a Debug build.
- Add a PAN-EASE replay step: record constant and eased sweeps at each speed, compare them against `reports/pan-ease-2026-11/*.csv`, and note the owner's verdict.
- Make no claims of results; the runbook is a procedure.
- **Done when:** the runbook is merged, and [MODE-QA](https://trello.com/c/bHd5ACBW) has a comment linking it.

### 2. Independently review Claude Opus 5.5's fix (PR #98)

Claude reviewed its own fix only as its author; that is **not** an independent review. Apply the same standard as PR-REVIEW-1104 to F1's change and test:

- Can `timerTick()` and the action refreshes still interleave badly?
- Is anything else that depends on refresh parity broken?
- Does the test truly fail without the fix?

Record your result in `reports/pr-review-2026-11-04/README.md` under a new "Independent review of F1 (Grok 4.7)" section. Fix any confirmed defect with a regression test. Don't manufacture findings.

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

Always use the time limit. In zsh, pass multiple `-only-testing:` flags as an array. Docs-only changes still need hosted CI green before merging.

## Rules and hard limits

- One PR per card, ending with your agent attribution line. Merge with a merge commit after the full suite and hosted CI are green. Never force-push `main` or rewrite another agent's branch. Leave branch protection unchanged.
- Comment the PR link, merge SHA and exact totals on each card, then move it to 👀 Human Review.
- Don't change Director authority levels, qualification records or `DeveloperFlags` release behaviour. Never add an automatic Take path. Keep the eased pan and workload policy off by default.
- Never certify a rig, release, privacy review or qualification gate from software tests.
- Owner-only work stays with the owner:
  - Human Review triage
  - the T2, P3, A2/A4 and T1/T3 decisions
  - the G-02…G-08 sign-offs
  - approving the eased pan
  - DegradePolicy calibration
  - Single Cam Director placement
  - the MODE-QA → DISPLAY-QA → ZOOM-QA → PAN-HITCH → SOAK → INSTALL rig runs.

## When you finish

1. Make sure everything is merged and main is green.
2. Write `docs/handoff/2026-11-04/CLAUDE-NEXT.md` for Claude, after the usage reset. Use this file's structure, add a "Grok results" section to `PLAN.md`, and commit both to main.
3. For anything unfinished: put it at the top of that handoff, comment on the card, and leave it in 🤖 Agent Queue.
4. Give the owner a short summary and the prompt:
   `Read docs/handoff/2026-11-04/CLAUDE-NEXT.md in /Users/stephanmorris/Documents/macOS-rl-viritual-camera and do it.`
