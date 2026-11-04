# Gemini Argon: independent review handoff (4 November 2026)

**Carry-over from Sol: none.** Both cards are merged and in 👀 Human Review.

You are Gemini Argon, a coding agent working on **Alfie**, a macOS camera app for live events. Alfie auto-frames stage cameras and sends one Program feed over a CMIO virtual camera or direct HDMI/USB-C output. Its operator modes are Single Cam, Multi Cam (Preview/Program with deliberate Take, two running inputs and four reserved slots), and Webcam. The Debug Auto Director requires qualification for any effect; Release disables its execution paths. This relay is **Claude → Sol 6.1 (done) → Gemini Argon (you) → Grok 4.7 → Claude**.

## Read first (in order)

1. `docs/handoff/2026-11-04/PLAN.md`: the full relay and the mandatory branching, test, Swift isolation, PR, Trello and handoff rules.
2. `docs/ALFIE_MULTICAMERA_SPEC.md`, especially Operator modes and lifecycle, before touching show or console code.
3. Your card, **PR-REVIEW-1104**: https://trello.com/c/0U0ZMxZl (Alfie Coding Board, 🤖 Agent Queue). Review **PRs #85–#96 and Sol's PRs #29 and #97**. The older card wording may end at #95; this handoff includes #96 as requested by the owner.

## State of main when you start

Source main is `3f92f72e76cd428ba7e32e73fe5335c26ce7fa6e` (PR #97 merge), immediately before this documentation-only handoff commit. Claude's starting main was `068cf29`. Sol merged:

| PR | What | Merge commit | Verification |
|---|---|---|---|
| [#29](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/29) | Finish CI-GATES: bounded unsigned Debug build-for-testing, full Swift suite, Python reports/Director training, xcresult artifact, unsigned Release and consistency checks; fix gallery test-host sizing | `2ecd621d7f7bb25bf89bce0196b114195b745e48` | 1,172 Swift tests, 0 failed, 4 opt-in skips; Python 127 + 16 passed; [hosted green run](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/41747416904) |
| [#97](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/97) | WORKLOAD-INSPECTOR: optional read-only level and last-transition reasons, 2 Hz, VoiceOver text, value tests and 1280 pt renders | `3f92f72e76cd428ba7e32e73fe5335c26ce7fa6e` | **1,179 Swift tests: 1,175 passed, 0 failed, 4 opt-in skips**; Python **127 + 16 passed**; [hosted green run](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/41748905461) |

The same 1,179-test suite passed unsigned locally with Xcode **27.1 (27A9275)**. The handoff's claim that local Xcode was 26.x was stale. CI deliberately pins **26.2 (17C52)** on `macos-26`; both toolchains are documented in `docs/ci/README.md`. The Swift totals are xcresult's declaration counts; parameter invocations are reported separately.

Main's CI status is available from `gh run list --branch main` / `gh run view`; the final main run after this handoff is also required to be green before Sol reports completion. The final run URL is discoverable by this documentation commit's SHA. Signing/notarization/App Store workflows remain **manual, unconfigured, fail-closed placeholders**, including when secrets are supplied. No credentials or branch-protection settings were changed. There is no claim of a signed release or hardware qualification.

## Do the work

1. Independently review PRs **#85–#96, #29 and #97** against their scopes and the product contract. Use `gh`; inspect code and tests, not only summaries. Focus closely on #86, #88, #89, #91 and #92 for lifecycle/races, MainActor isolation, per-frame publishing, default-off flags and the move-only claim. Check #85 integration, including user-guide conflict resolution and the B12 split against #81. Confirm suspected findings before changing code.
2. Use a fresh branch/worktree from current `origin/main` for the review card. Fix confirmed findings with meaningful regression tests in small commits, and include `reports/pr-review-2026-11-04/README.md` with each finding's severity, file:line and reproduction. Follow the current one-PR-per-card rule; the report and confirmed fixes must be merged. Do not edit the owner's checkout or another agent's worktree. The repo is `/Users/stephanmorris/Documents/macOS-rl-viritual-camera`, GitHub `stephancmorris/macOS-rl-viritual-camera`.
3. Run the unsigned full suite with your own DerivedData and the mandatory time limit from PLAN.md, plus Python checks. CI now runs automatically on the PR; wait for green and merge with a merge commit. End every PR body with your agent attribution. Never force-push main or rewrite another agent's branch.
4. Record findings, fixes/PR links, merge commits and exact test totals in the review report and on the card. If a suspected issue needs an owner decision, record the exact question rather than inventing a decision. When complete, move PR-REVIEW-1104 to **👀 Human Review**, never ✅ Done.

## Sol-specific review notes

- #29's old red gate was real: all twelve gallery invocations produced a **989 pt image instead of the requested 1000 pt canvas** under Xcode 26.2. The final fix sets the SwiftUI root frame, disables `NSHostingView.sizingOptions`, uses an unconstrained offscreen window and checks bounds before/after layout. No gallery assertions or Swift tests were removed/skipped. Summary JSON is printed in the job log as well as uploaded; this avoids downloading a roughly 100 MB xcresult just to inspect failures.
- CI's job limit is 60 minutes; the test step limit is 50 minutes and the test process alarm is 45 minutes. It uses fresh runner-local DerivedData and has no pip/credential dependency for the standard-library Director tests. Older RL/BC/CoreML smoke scripts remain outside this Director gate; see `docs/ci/README.md`.
- #97 samples `DegradePolicy.level` and `transitions.last` together in the existing Inspector timeline. It adds no stored/published state or frame work. A nil policy hides the row; enabled single-input shows only workload detail. Higher policy levels use advice wording since #92 only applies the optional UI hint today. Do not extend degradation behavior as part of a wording review.
- The committed [render report](../../../reports/workload-inspector-2026-11/README.md) contains disabled/enabled 1280×800 pt views of the actual drawer. The policy flag remains off by default. VoiceOver copy is provided and value-tested; an attended accessibility acceptance run remains owner work.
- Local Xcode 27.1 emits pre-existing test-isolation warnings (for example `ProgramTakeTests` / `FramingCapability.Reason`) plus the existing CMIO extension placement and AppIntents warnings. These are not a claim of a warning-free build. #95's release fixes were verified with its own toolchain; check any new finding independently.

## Hard limits and owner-only work

Do not change Director authority levels, qualification records or DeveloperFlags release behavior. Never add an automatic Take path. Do not mark any rig, release, privacy or qualification gate as passed from software tests. Human Review triage, T2/P3/A2/A4/T1/T3 decisions, eased-pan approval, threshold calibration and the MODE-QA/DISPLAY-QA/ZOOM-QA/PAN-HITCH/SOAK/INSTALL rig runs remain owner work, as listed in PLAN.md.

## When you finish (or near the end of your budget)

1. Merge completed fixes to main and verify the full suite on main.
2. Write `docs/handoff/2026-11-04/GROK-4.7.md` for Grok 4.7 using this structure and PLAN.md. Grok's card is **RIG-RUNBOOK-UPDATE** (https://trello.com/c/SS7mZhnQ), plus independent review of your fixes. Update main's commit, test totals and relevant findings; add an Argon results section to PLAN.md and commit both to main.
3. Comment any unfinished work on PR-REVIEW-1104, leave unfinished work in 🤖 Agent Queue, and put carry-over at the top of Grok's handoff.
4. Give the owner a 3–5 line result and the one-line prompt pointing Grok at that handoff file.
