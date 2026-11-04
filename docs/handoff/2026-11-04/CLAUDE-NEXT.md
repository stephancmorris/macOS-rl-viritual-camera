# Claude: Alfie handoff (4 November 2026)

You are **Claude**, taking over from **Grok 4.7** on **Alfie**, a macOS camera app for live events. Alfie auto-frames stage cameras and sends **one Program feed** through a CMIO virtual-camera extension or direct HDMI/USB-C output. It has three operator modes: **Single Cam**, **Multi Cam** (Preview/Program Multiview with Take; two running inputs ship now) and **Webcam**. The Debug-only Auto Director's effects are gated by qualification records, and Release disables Director execution.

The relay so far: Claude → Sol 6.1 → Claude Opus 5.5 → Grok 4.7 → **you**.

There is no unfinished agent card. Grok's review and the optional gallery card are both merged. Do not invent a card, do not take owner or rig work, and do not move anything to ✅ Done.

## Repository and tools

- Repository: `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`. GitHub: `stephancmorris/macOS-rl-viritual-camera` (use the `gh` CLI).
- Xcode project `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`, scheme `CinematicCoreMacOS`. Test target `CinematicCoreMacOSTests` (Swift Testing, `@testable import Alfie`).
- Trello: **Alfie Coding Board**. The lists are 🤖 Agent Queue → 🚧 In Progress → 👀 Human Review. Never move a card to ✅ Done.
- Read `docs/handoff/2026-11-04/PLAN.md` (rules, owner-only work, Grok results) before doing anything else.
- Work in your own fresh worktree from `origin/main`. Never edit the owner's checkout, another agent's worktree, `.claude/`, `research_notes/` or other untracked owner files.

## State of main when you start

- Main is at **`3b71903`** (merge of PR #110, the gallery captures), on top of **`086ff74`** (merge of PR #109, the review). Fetch and check the actual HEAD and its CI: `gh run list --branch main --limit 3`.
- The gallery merge's main CI was still running when this file was written: [run 41783290384](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/41783290384). Confirm it passed. The review merge's [main CI passed](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/41781006486).
- Local Xcode 27.1, unsigned, serial full suite on the gallery branch: **1,188 tests, 1,184 passed, 0 failed, 4 opt-in skips**. Python: 127 + 16 passed. Hosted Xcode 26.2 CI passed on PR #109 and PR #110 before merge.
- A parallel local run can still hit the existing one-minute limit on `DirectorSubjectDiscoveryIntegrationTests` (`cancellingDiscoveryWaiterPreservesRenderWaiterAndRunningPermits`, `detectorExecutorSkipsRetiredPendingCallAndRejectsRunningCompletion`). Those 7 tests pass alone in a few seconds, and hosted CI's parallel run passed. Do not treat one local timeout as a new product bug.
- **No open PRs** and an empty 🤖 Agent Queue when this handoff was written. Confirm the queue before assuming that is still true.

## What Grok 4.7 merged

| PR | Card | Merge | What |
|---|---|---|---|
| [#109](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/109) | [CLAUDE-REVIEW-1104](https://trello.com/c/C9cMNLBm) | `086ff74` | Independent review of #98–#108. Report: `reports/claude-review-2026-11-04/README.md`. No code defect. Two doc corrections. |
| [#110](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/110) | [GALLERY-CAPTURES](https://trello.com/c/Hu6Jobuo) | `3b71903` | 17 synthetic input, setup and pill PNGs. README labels them synthetic. |

Review conclusions Claude should not reopen:

- **#104.** `ShotComposer`, `CropEngine` and `PersonDetector` can be released off the main actor. `isolated deinit` defers until the main actor, and the object stays fully initialized until then. The timer callback only republishes UI mirrors. In-flight render and detection hold `self` until they return. `FaceSignatureExtractor` does not touch main-actor state. The Vision prints are not mutated after capture; the `@unchecked Sendable` boxes match `FaceSignature`. Swift 6 `build-for-testing` succeeded. The project stays on Swift 5.
- **#107.** Every show go-live path sets `isRunning` or `isStartingSession`, and both call `updateShowStandardLifetime`. The span restarts on that edge, which is before `isRunning`, because the diagnostics window opens during startup. A sole-input camera change includes 500 ms of sleep before the next window. Not fixed: restarting only at `isRunning` would put the startup window back on the pre-live span. The flag is off, and one window cannot change the level.
- **#105.** The app's `LiveShowSetup` does not pass `cameras`. Only tests do, and they want the fixture to stay.
- **#98.** `timerTick` and `refresh` do not interleave. The regression test fails without the fix (exit 65) and passes with it.
- **Docs.** MODE-QA step 6 now says the Cam B note appears after A is running, not during startup. Multi Cam stays enabled when it is already the current mode.

## Your work

1. Fetch `origin/main` and confirm HEAD and the latest main CI. If the gallery main run is still going, wait for it. If it failed, fix only that failure.
2. Read the Agent Queue. If it is still empty, stop. Tell the owner that the remaining work is the owner and rig list in `PLAN.md`, and do not start it.
3. If the owner has added a card to Agent Queue since this file was written, do that card under the rules in `PLAN.md`. One PR per card. Merge with a merge commit after the full suite and hosted CI are green. Comment the PR link, merge SHA and exact totals, then move the card to 👀 Human Review. Never to ✅ Done.

## Rules that still bind

- Don't change Director authority levels, qualification records or `DeveloperFlags` release behaviour. Never add an automatic Take path. Keep the eased pan and workload policy off by default.
- Don't switch the project to Swift 6 and don't add a Swift 6 CI job.
- Never certify a rig, release, privacy review or qualification gate from software tests.
- Owner-only work stays with the owner: Human Review triage; T2, P3, A2/A4 and T1/T3; G-02…G-08; approving the eased pan; DegradePolicy calibration and the C1 and C3 notes from PR-REVIEW-1104; Single Cam Director placement; the Swift 6 switch; the MODE-QA → DISPLAY-QA → ZOOM-QA → PAN-HITCH → SOAK → INSTALL rig runs.

## Build and test

```sh
xcodebuild -version
A="$(mktemp -d /private/tmp/alfie-claude.XXXXXX)"
xcodebuild build-for-testing -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' -derivedDataPath "$A/DerivedData" CODE_SIGNING_ALLOWED=NO
perl -e 'alarm 3000; exec @ARGV' xcodebuild test-without-building -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' -derivedDataPath "$A/DerivedData" \
  -only-testing:CinematicCoreMacOSTests -resultBundlePath "$A/unit.xcresult" CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path "$A/unit.xcresult"
(cd CinematicCoreMacOS/scripts && python3 -m unittest)
(cd training && python3 -m unittest discover -p 'test_director_*.py')
```

Always use the time limit. In zsh, pass multiple `-only-testing:` flags as an array. Swift Testing filters need the trailing `()`; without it xcodebuild reports success and runs 0 tests. Docs-only changes still need hosted CI green before merging.
