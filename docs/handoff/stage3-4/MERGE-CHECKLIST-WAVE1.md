# Stage 3 wave 1: merge checklist (10 Oct 2026)

Prepared by Opus 5.5 for the owner. **Only the owner merges.** Every PR head below was checked out and run against the full unit suite (`CinematicCoreMacOSTests`, `CODE_SIGNING_ALLOWED=NO`, Xcode 26.2). The extension target builds as part of each run.

## How to merge

- **Use "Create a merge commit"** (or "Rebase and merge") for the stack. **Don't squash** #3–#12. A squash gives each PR a new commit identity, so every PR stacked above it then shows its parents' changes again and conflicts.
- **Leave "delete branch on merge" off** (it is off now). Deleting a base branch closes the PRs stacked on it.
- After each merge, GitHub retargets the next PR's base to `main` by itself. Wait for that before clicking the next one.

## Click order

| # | PR | Base now | Tests (passed / total) | Failures | New warnings in its files | Conflicts | Safe to merge |
|---|---|---|---|---|---|---|---|
| 1 | [#3 B-00 Preset shareable](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/3) | `main` | 446 / 449 | 0 | none (only the known `ShotComposer` warning) | none | **Yes.** Critical path, merge first |
| 2 | [#4 B-01 Evidence readings](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/4) | `main` | 448 / 451 | 0 | none | none with the stack (checked by merging into A-07) | **Yes** |
| 3 | [#5 B-02 Manual-action hook](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/5) | B-00 → `main` after #3 | 455 / 458 | 0 | none | none with the stack | **Yes** |
| 4 | [#6 A-01 Shot vocabulary](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/6) | B-00 → `main` after #3 | 449 / 452 | 0 | none | none | **Yes** |
| 5 | [#7 A-02 Identity and readiness](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/7) | A-01 | 457 / 460 | 0 | none | none | **Yes** |
| 6 | [#8 A-05 Style profiles](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/8) | A-02 | 464 / 467 | 0 | none | none | **Yes** |
| 7 | [#9 A-06 Director judge](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/9) | A-05 | 470 / 473 | 0 | none | none | **Yes** |
| 8 | [#10 A-04 Console status API](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/10) | A-06 | 477 / 480 | 0 | none | none | **Yes.** Grok's C PRs are based on it |
| 9 | [#11 A-03 Authority levels](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/11) | A-04 | 485 / 488 | 0 | none | none | **Yes** |
| 10 | [#12 A-07 Evidence adapter](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/12) | A-03 | 498 / 501 | 0 | none | none | **Yes** |

The 3 skipped tests in every run are the existing opt-in tests (skipped on `main` too).

**Combined check:** A-07 with B-01 and B-02 merged in gives **512 / 515 passed, 0 failed**, with no merge conflicts. This is the state `main` will be in after clicks 1–10.

## After the stack: the other open PRs

| PR | Author | Base | Status | When |
|---|---|---|---|---|
| [#19 B-06 Qualification records](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/19) | Opus | A-07 | 510 / 513 passed, 0 failed. AWAITING OWNER: Q1–Q3 fields; whether a camera-mode change should drop qualification | After #12. Can merge any time after |
| [#18 A-08 Replay effect sink](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/18) | Sol | A-07 | Merges cleanly onto the stack; Opus review: no blocking items | After #12 |
| [#13 C-01 Director gallery states](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/13) | Grok | A-04 | Merges cleanly; review: no blocking items | After #10. **Merge before #14 and #16** |
| [#17 C-04 Style settings](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/17) | Grok | A-04 | Merges cleanly; review: no blocking items, two suggestions (temp-file fallback, overwriting an unreadable file) | After #10 |
| [#14 C-02 Mode control](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/14) | Grok | A-04 | **Don't merge yet.** Blocking review: the view takes the gallery fake instead of `DirectorConsoleControlling`, and the refusal message lives on the fake. Also conflicts with #13 in `MultiviewGallery.swift` | After Grok fixes the review and rebases on #13 |
| [#16 C-03 Next-shot line and badge](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/16) | Grok | A-04 | Review: no blocking items. **Conflicts with #13** in `MultiviewGallery.swift`, `InputTileView.swift` and `integration-requests.md` | After #13, once Grok rebases |
| [#15 D-02 Shadow record schema](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/15) | Astra (Sol) | `main` | Docs only; merges cleanly. Marked **AWAITING OWNER review**. Opus review: no blockers for B-04, five requests | When you've read it. Sol's A-09 builds on it |

## Who rebases what after each merge

- **After #3:** GitHub retargets #5 and #6 to `main`. Nobody needs to act.
- **After #10:** Grok's #13, #14, #16 and #17 retarget to `main`. Grok rebases onto `origin/main` and pushes.
- **After #12:** Sol's #18 and Opus's #19 retarget to `main`. Each author rebases and pushes.
- **After #13:** Grok rebases #14 and #16 onto `main` and resolves the conflicts in its own files.

## Not covered here

- No live camera, `[SOAK]` or rehearsal run was part of this check. All evidence is unit / synthetic.
- B-03 (the Director controller) is the next PR from Opus. It is built on the combined A-07 + B-01 + B-02 + B-06 state, and shrinks to its own diff once those merge.
