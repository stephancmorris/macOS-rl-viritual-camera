# Sol 6.1: Group S handoff (4 November 2026)

You are Sol 6.1, a coding agent working on **Alfie**, a macOS camera app. It auto-frames a stage camera and sends one Program feed out over a virtual camera or HDMI, with Single Cam, Multi Cam and Webcam operator modes and an Auto Director in shadow. Claude handed this to you. After you, Gemini Argon and then Grok 4.7 take the next groups.

## Read first (in order)

1. `docs/handoff/2026-11-04/PLAN.md`: the relay, the groups, and **the rules you must follow** (branching, build/test commands, Swift isolation gotchas, PR and Trello conventions, handoff).
2. Your three Trello cards (Alfie Coding Board, 🤖 Agent Queue). Each holds the full scope and "done when":
   - https://trello.com/c/JkIvhOM8: **B13** split `ShotComposer.swift`, move only
   - https://trello.com/c/K3yljzlQ: **RUNSHEET-FOLLOWUPS**, the editor's Current marker follows Advance; Dark sheet background
   - https://trello.com/c/jhhQuzKv: **AD-RECONCILE**, reconcile four older AD cards with the shipped S3 work; fix only what needs no owner decision
3. Background for AD-RECONCILE: `docs/handoff/stage3-4/DECISIONS.md`, `docs/handoff/stage3-4/STAGE3-TICKETS.md`, and the code under `CinematicCoreMacOS/CinematicCoreMacOS/Director/`.

## State of main when you start

`origin/main` = `4782291`. Everything that was open has been merged (see PLAN.md). The baseline is 1,154 tests, 0 failed, 4 opt-in skips.

## Do the work in this order

1. **B13 first.** It is mechanical and touches the most lines, so landing it first avoids conflicts with the other two.
   - Move only, as B12 did for CameraManager (see the merged PR #54 for the pattern).
   - Verify with `FramingRegressionTests`, then the full suite.
   - PR, merge.
2. **RUNSHEET-FOLLOWUPS.** Fresh branch from the new main.
   - Write a test for the marker.
   - Check Light and Dark renders with `ALFIE_GALLERY_SNAPSHOTS=1`; they're written under `$TMPDIR/AlfieMultiviewGallery/`.
   - PR, merge.
3. **AD-RECONCILE.**
   - Write the report first (`reports/ad-reconcile-2026-11/README.md`).
   - Then fix the undecided-free gaps, each with a test.
   - PR, merge.
   - Comment on the four AD cards with the report link.

For each card: comment the PR link, merge commit and test totals on the card, then move it to 👀 Human Review.

## Hard limits

- Don't change Director authority levels, qualification records or `DeveloperFlags` release behaviour.
- Never create an automatic Take path.
- Never mark rig, release, privacy or qualification gates as passed.
- If something needs an owner decision, stop that item and write the exact question on the card and in your report.
- Don't edit other agents' worktrees or branches. Don't force-push.

## When you finish (or near the end of your budget)

1. Make sure everything you finished is merged to `main` and the full suite is green on main.
2. Write `docs/handoff/2026-11-04/ARGON.md` for **Gemini Argon**. Use this file as the template: same structure, with Argon's three cards from PLAN.md (DEGRADE-MODEL, PAN-EASE-MODEL, HR-DIGEST), an updated "state of main" (commit and test totals), and anything you learned that Argon needs. Add a short "Sol results" section to `PLAN.md`. Commit both to main.
3. Any card you couldn't finish: comment where you stopped, leave it in 🤖 Agent Queue, and list it at the top of ARGON.md as carry-over.
4. Reply to the owner with a 3–5 line summary and the one-line prompt for Argon:
   `Read docs/handoff/2026-11-04/ARGON.md in /Users/stephanmorris/Documents/macOS-rl-viritual-camera and do it.`
