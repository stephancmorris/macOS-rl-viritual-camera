# Claude Opus 5.5: Alfie review handoff (4 November 2026)

You are **Claude Opus 5.5**, taking over from **Sol 6.1** on **Alfie**, a macOS camera app for live events. The owner has requested you as the next agent in place of the Gemini Argon session described in `ARGON.md`. Take the pending review card below; Grok's runbook work remains next. Do the work, verify it, merge the finished card, and write the next handoff. Do not stop at a plan.

## Product and repository

Alfie auto-frames stage cameras and sends **one Program feed** through a CMIO virtual-camera extension or direct HDMI/USB-C output.

- **Single Cam:** one camera, traditional view, all Stage shots.
- **Multi Cam:** Preview/Program Multiview, deliberate Take and Edit Live; four reserved slots, exactly two running inputs ship now.
- **Webcam:** close-range single camera.

The Debug Auto Director has qualification-gated effects. Release disables Director execution paths. Preserve the existing authority and qualification boundaries; this review grants no new automation.

- Repository: `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`
- GitHub: `stephancmorris/macOS-rl-viritual-camera`; use the **gh CLI**.
- Project: `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`
- Scheme: `CinematicCoreMacOS`; app/test import: `Alfie`; unit target: `CinematicCoreMacOSTests`, using Swift Testing.
- Trello: **Alfie Coding Board**, 🤖 Agent Queue → 👀 Human Review. Never move a card to ✅ Done.

Read `docs/handoff/2026-11-04/PLAN.md` and `docs/ALFIE_MULTICAMERA_SPEC.md`, especially Operator modes and lifecycle, before touching show or console code. Read applicable `AGENTS.md` instructions. `ARGON.md` remains historical context; this prompt supplies the current agent assignment. The old October whole-codebase review brief does not expand this task into a repository-wide audit.

## Get the latest safely

Fetch current `origin/main` before starting. Work in your own fresh worktree; do not edit the owner's checkout, another agent's worktree, `.claude/`, `research_notes/`, or other untracked owner files.

```sh
cd /Users/stephanmorris/Documents/macOS-rl-viritual-camera
git fetch origin
git worktree add -b codex/opus-5-5-pr-review-1104 /private/tmp/alfie-opus-5-5-pr-review-1104 origin/main
cd /private/tmp/alfie-opus-5-5-pr-review-1104
git log -5 --oneline
gh pr list --state open
gh run list --branch main --limit 5
```

If the branch or path already exists, choose a unique suffix; never reset or remove a checkout you did not create. Re-check Trello and open PRs so you do not duplicate work another agent has since started.

## Verified starting state

At preparation of this prompt, remote main was **`8c9f43833b171faa00b3ceadb672e97370e28479`**, with no open PRs. This prompt is a subsequent documentation-only commit; fetch it from main and verify the actual HEAD rather than assuming the older SHA is still latest.

The final [main CI run](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/41750126842) passed at `8c9f438`:

- **1,179 Swift tests: 1,175 passed, 0 failed, 4 opt-in skips.** These are xcresult declaration counts; parameter invocations are reported separately.
- **127 Python diagnostics/Director report tests passed.**
- **16 Director dataset/training tests passed.**
- Unsigned Debug build-for-testing, xcresult/summary upload, unsigned Release build and consistency checks all passed.

Hosted CI pins **Xcode 26.2 (17C52)** on `macos-26`. The local machine was **Xcode 27.1 (27A9275)** when Sol worked; the same full suite passed locally. Check `xcodebuild -version` yourself. The older handoff's local-Xcode-26.x assumption was stale.

Sol completed both cards, merged them and moved them to Human Review:

| PR | Result | Merge commit |
|---|---|---|
| [#29](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/29) | CI-GATES: bounded unsigned build/tests, Python checks, xcresult artifact, Release/consistency, README CI section; hosted gallery test sizing fixed | `2ecd621d7f7bb25bf89bce0196b114195b745e48` |
| [#97](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/97) | WORKLOAD-INSPECTOR: optional read-only level and latest-transition reasons at 2 Hz, VoiceOver copy, value tests and 1280 pt renders | `3f92f72e76cd428ba7e32e73fe5335c26ce7fa6e` |

There is **no unfinished Sol card**. Signing/notarization/App Store workflows remain manual, unconfigured, fail-closed placeholders even if secrets are supplied. No credentials or branch-protection settings were changed. Software tests do not qualify a rig or release.

## Your card: PR-REVIEW-1104

Card: **https://trello.com/c/0U0ZMxZl**. It was still in 🤖 Agent Queue when this prompt was prepared. Its older title names Gemini Argon and ends at #95; the owner's current scope is **PRs #85–#96 inclusive, plus #29 and #97**.

Review these changes against the current code and product contract:

| PR | Scope |
|---|---|
| #85 | Integration of #55, #82, #84, #83, #81, #54 and #43: Director wave 2, real-show run sheet, show lifecycle and CameraManager split |
| #86 | PAIR-FIRST-FRAME: B starts only after output accepts A's first frame |
| #87 | Initial 4 November plan |
| #88 | B13 ShotComposer split, claimed move-only |
| #89 | Run-sheet Current marker follows Advance; opaque Dark panel |
| #90 | AD-RECONCILE report and owner questions |
| #91 | Eased auto-pan behind the off-by-default developer flag |
| #92 | DegradePolicy diagnostics-window integration; workload level; flag off |
| #93 | Human Review digest |
| #94 | Synthetic user-guide figures |
| #95 | Unsigned Release check and isolation fixes |
| #96 | Revised relay handoff |
| #29 | Sol's completed CI gates and hosted render test fix |
| #97 | Sol's Workload Inspector |

### Review and fix

1. Record the actual reviewed main SHA in `reports/pr-review-2026-11-04/README.md`. Use `gh pr view` and `gh pr diff`, then trace relevant current callers and tests. Earlier Claude authorship is not evidence that a change is correct; review it afresh.
2. Closely inspect #86, #88, #89, #91 and #92 for lifecycle/races, MainActor/isolation, per-frame publishing, flags off by default and move-only claims. Check #85's integration, especially user-guide conflict resolution and the B12 split against #81. Check #29 and #97 just as critically.
3. Give each finding a severity, current file:line, concrete trigger/reproduction and evidence. Separate confirmed defects from unverified concerns. Re-check serious findings against the code before reporting them. Do not manufacture findings or turn stylistic preferences into bugs.
4. Fix confirmed findings with meaningful regression tests and small focused commits. Follow the current **one PR per card** rule: include the review report and confirmed fixes in the review card's PR. Do not apply the older brief's conflicting no-fix/no-merge or multi-PR instructions.
5. Keep changes within confirmed review findings. Do not perform unrelated refactors, formatting sweeps, policy tuning or repo-hygiene deletions. If a suspected finding is disproved, record the evidence. If a finding cannot be fixed safely, record exactly why and any owner question; do not quietly drop it.
6. The report must list reviewed PRs, findings/fixes, validation, remaining concerns and anything not reviewed. If no confirmed findings remain, say so and describe coverage; still merge the review report.

### Sol-specific review notes

- **#29:** the hosted gallery test's 1000 pt canvas shrank to a 989 pt image. The final test-only fix fixes the SwiftUI root frame, disables `NSHostingView.sizingOptions`, uses an unconstrained offscreen window, and checks bounds before/after layout. No Swift tests or image-size assertions were dropped. CI prints the xcresult summary JSON in its log and uploads it with the result bundle.
- **CI limits:** 60-minute job, 50-minute test step, 45-minute test-process alarm. Fresh DerivedData lives under `runner.temp`. The standard-library Python Director gate needs no pip installation; older RL/BC/CoreML smoke scripts are outside this gate. See `docs/ci/README.md` for the exact contract.
- **#97:** reads `DegradePolicy.level` and `transitions.last` together inside the existing Inspector timeline. Nil policy hides Workload; an enabled single-input policy can show its own row. No published state or frame work was added. Higher levels use advice wording because #92 currently applies only the optional UI hint. Do not expand runtime degradation as part of a copy fix.
- **Render evidence:** `reports/workload-inspector-2026-11/README.md` and the two PNGs show the actual drawer over a 1280×800 pt synthetic console, disabled and enabled. VoiceOver text is provided/value-tested; attended accessibility acceptance is still owner work.
- **Warnings:** local Xcode 27.1 reported pre-existing test-isolation warnings, including ProgramTakeTests/FramingCapability.Reason, plus CMIO extension placement and AppIntents warnings. Independently verify relevance; do not describe the baseline as warning-free.

## Build and test

Use your own DerivedData and a fresh result path. Always time-limit tests: an awaited Task that never resumes has hung a full run before. Run from your worktree root:

```sh
xcodebuild -version
ALFIE_OPUS55_ARTIFACTS="$(mktemp -d /private/tmp/alfie-opus55-review.XXXXXX)"

xcodebuild build-for-testing \
  -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -derivedDataPath "$ALFIE_OPUS55_ARTIFACTS/DerivedData" \
  CODE_SIGNING_ALLOWED=NO

perl -e 'alarm 3000; exec @ARGV' xcodebuild test-without-building \
  -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -derivedDataPath "$ALFIE_OPUS55_ARTIFACTS/DerivedData" \
  -only-testing:CinematicCoreMacOSTests \
  -resultBundlePath "$ALFIE_OPUS55_ARTIFACTS/unit.xcresult" \
  CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool get test-results summary \
  --path "$ALFIE_OPUS55_ARTIFACTS/unit.xcresult"

(cd CinematicCoreMacOS/scripts && python3 -m unittest)
(cd training && python3 -m unittest discover -p 'test_director_*.py')
```

If passing multiple `-only-testing:` flags in zsh, pass them as an array, never one string. Run focused checks while developing a fix, then the full suite. CI also builds unsigned Release; wait for the exact PR head to be green before merging. Verify main's final CI after merge. Do not weaken/skip tests merely to obtain green checks.

Swift project rules:

- `default-isolation=MainActor`, `NonisolatedNonsendingByDefault`, `MemberImportVisibility`.
- Mark pure value types used off the main actor `nonisolated`.
- A default argument constructing a MainActor type can fail in tests; use an optional and `??`.
- Add explicit Combine/CoreGraphics imports where needed.
- `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, `ProgramOutputDiagnostics.swift` and `ShowStandard.swift` also compile into the CMIO extension. Any new referenced type must join that target too. Build the app and extension.
- No per-frame `@Published` writes. UI reads at ≤15 Hz or on transitions; Inspector workload remains at its existing 2 Hz cadence.

## PR, Trello and completion

- Commit explicit paths only. Do not commit owner files, DerivedData, local logs or credentials.
- PR body: what changed, why, findings addressed, tests and exact verification totals. End it with `Agent: Claude Opus 5.5.`
- Merge with a **merge commit** after the full suite and hosted CI are green. Never force-push main or rewrite another agent's branch. Leave branch protection unchanged.
- Comment the PR link, merge SHA, findings disposition and exact test totals on PR-REVIEW-1104; then move it to **👀 Human Review**, never Done.
- If credentials or a genuine owner/product decision are needed, stop only that affected item and write the exact question in the report, PR and card. Continue unaffected authorized work.

## Hard limits and owner-only work

Do not change Director authority levels, qualification records or DeveloperFlags release behavior. Never add an automatic Take path. Keep eased pan and runtime workload policy off by default. Do not certify a rig, release, privacy review, camera pair or qualification gate from software tests.

Leave these to the owner/attended rig work: Human Review triage; T2/P3/A2/A4/T1/T3 decisions; G-02…G-08 sign-offs; eased-pan approval; DegradePolicy threshold calibration; Single Cam Director placement; three/four-input admission; and MODE-QA → DISPLAY-QA → ZOOM-QA → PAN-HITCH → SOAK → INSTALL. Do not delete owner files or decide signing, App Store tiers, entitlements or hardware policy as a review shortcut.

## Next handoff

When finished, or before exhausting your session:

1. Ensure finished work is merged/pushed to main and the full suite is green on main.
2. Write `docs/handoff/2026-11-04/GROK-4.7.md`. Grok's next card remains **RIG-RUNBOOK-UPDATE** (https://trello.com/c/SS7mZhnQ), plus review of your confirmed-finding fixes. Read the live card and do not invent its requirements.
3. Include the updated main SHA, exact test totals, your PR/merge links, findings disposition and anything Grok must review independently. Do not describe your own review of your fixes as a separate independent review.
4. Add a short Claude Opus 5.5 results section to PLAN.md; commit/push both handoff docs to main.
5. Put any unfinished work at the top of the next handoff, comment where you stopped on the card, and leave unfinished work in 🤖 Agent Queue. Do not mark it complete merely because the session ended.
6. Give the owner a concise result summary and this prompt: `Read docs/handoff/2026-11-04/GROK-4.7.md in /Users/stephanmorris/Documents/macOS-rl-viritual-camera and do it.`
