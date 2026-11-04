# Sol 6.1: Group S handoff (4 November 2026, rev 2)

You are Sol 6.1, a coding agent working on **Alfie**, a macOS camera app. It auto-frames a stage camera and sends one Program feed out over a virtual camera or HDMI, with Single Cam, Multi Cam and Webcam operator modes and an Auto Director in shadow. Claude handed this to you. After you, Gemini Argon and then Grok 4.7 take the next groups.

## Read first (in order)

1. `docs/handoff/2026-11-04/PLAN.md`: the relay, the groups, and **the rules you must follow** (branching, build/test commands, Swift isolation gotchas, PR and Trello conventions, handoff).
2. Your two Trello cards (Alfie Coding Board, 🤖 Agent Queue). Each holds the full scope and "done when":
   - https://trello.com/c/D2VGtAGU: **CI-GATES**, finish draft PR #29 so unsigned build, unit tests and Python checks run on GitHub Actions with a job timeout
   - https://trello.com/c/CWN4G0nA: **WORKLOAD-INSPECTOR**, a read-only Inspector row for the workload level, only when the policy is enabled

## State of main when you start

Claude merged PRs #85–#95 today; the table is in PLAN.md. Rev 1's Sol cards (B13, RUNSHEET-FOLLOWUPS, AD-RECONCILE) are done. The baseline is about 1,172 tests, 0 failed, 4 opt-in skips.

## Do the work in this order

1. **CI-GATES first.** It takes the longest because runner round-trips are slow.
   - Bring `ci/research-and-pipeline` up to date with main.
   - Make the macOS workflow run `build-for-testing`, then `test-without-building -only-testing:CinematicCoreMacOSTests`, then the Python checks. Upload the xcresult.
   - Set `timeout-minutes`.
   - Keep the signing and notarize workflows manual, with no secrets.
   - Iterate until green, then merge. Don't make the check required in branch protection.
2. **WORKLOAD-INSPECTOR.** Fresh branch from the new main.
   - The data is `show.workloadLevel` and the last `DegradePolicy.Transition`, from PR #92.
   - Hide the row when `show.workloadPolicy == nil`.
   - Test the copy at the value level.
   - PR, merge.

For each card: comment the PR link, merge commit and test totals on the card, then move it to 👀 Human Review.

## Hard limits

- Don't change Director authority levels, qualification records or `DeveloperFlags` release behaviour.
- Never create an automatic Take path.
- Never mark rig, release, privacy or qualification gates as passed.
- If something needs an owner decision, stop that item and write the exact question on the card and in your report.
- Don't edit other agents' worktrees or branches. Don't force-push.

## When you finish (or near the end of your budget)

1. Make sure everything you finished is merged to `main` and the full suite is green on main.
2. Write `docs/handoff/2026-11-04/ARGON.md` for **Gemini Argon**. Use this file as the template: same structure, with Argon's card from PLAN.md (PR-REVIEW-1104, which must also cover your PRs), an updated "state of main" (commit and test totals), and anything you learned that Argon needs. Add a short "Sol results" section to `PLAN.md`. Commit both to main.
3. Any card you couldn't finish: comment where you stopped, leave it in 🤖 Agent Queue, and list it at the top of ARGON.md as carry-over.
4. Reply to the owner with a 3–5 line summary and the one-line prompt for Argon:
   `Read docs/handoff/2026-11-04/ARGON.md in /Users/stephanmorris/Documents/macOS-rl-viritual-camera and do it.`
