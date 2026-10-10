# Grok 4.7: full code-base review, plus two fix prompts (Sol 6.1 and Opus 5.5)

Paste everything below the line into Grok 4.7. **Start only after C-01 to C-04 are finished** (PRs #13, #14, #16 and #17 are up and their review comments are addressed). This can run alongside or after the CI/CD prompt, but not inside the same branch.

---

## Goal

Most of Alfie's code was written by AI agents over several months. Do a **file-by-file review** of the whole code base for:
- leaks;
- concurrency bugs;
- security and privacy problems;
- crash risks;
- performance problems on the frame path;
- dead or duplicated code;
- weak tests;
- outdated docs.

**You review and report; you don't fix code and you don't delete files.** Your outputs are:

1. **One review document** with a section for every file.
2. **Two fix prompts**, one for **Sol 6.1** and one for **Opus 5.5**. Every file with findings is assigned to exactly one of them, so their work never overlaps.

## Setup

1. Use your own worktree from `origin/main`. Never use the owner's checkout (`/Users/stephanmorris/Documents/macOS-rl-viritual-camera`).
   ```sh
   git fetch origin
   git worktree add ../alfie-review origin/main -b review/code-review-2026-10
   ```
2. **Record the commit SHA you reviewed** at the top of the report. Every finding refers to that commit.
3. Build and run the unit tests once, so you know the baseline:
   ```sh
   xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS \
     -destination 'platform=macOS' -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO \
     -derivedDataPath /private/tmp/review-dd
   ```
   Note the counts and every compiler warning. Warnings are findings too.
4. List the files in scope: `git ls-files`, with the exclusions below. Put that list in the report first, as a checklist, and tick each file off as you finish it. This lets you resume if the session is interrupted, so **write the report as you go**, not at the end.

## Scope

**Review every tracked file of these kinds:**
- Swift (`.swift`) in the app, extension, `Shared/`, unit tests and UI tests;
- Metal (`.metal`);
- Python (`CinematicCoreMacOS/scripts/`, `training/`);
- shell and other scripts (`build_release.sh`, `update_xcode.rb`, `test_decklink.cpp`);
- entitlements, `Info.plist`, `BuildInfo.plist`;
- the shared scheme. Skim `project.pbxproj` only for target membership, build settings and anything odd, like a file compiled into the wrong target.

**Docs (`.md`), separate section:** review every `.md` for whether it's still current. **Don't delete or edit any doc.** List each one as one of current, outdated, superseded by `<file>`, duplicate of `<file>`, or historical (keep as a record), with a one-line reason and a recommendation. The owner decides later.

**Exclude from file-by-file review, but report as repo-hygiene findings:**
- `CinematicCoreMacOS/build_out/**` (about 290 tracked build artifacts: DMG, xcarchive, app bundle);
- `.deriveddata*/**` and `.codex-derived-data/**` (tracked build caches);
- the `build_*` / `build_release_*` folders;
- `*.log`, images, `.mlmodel` / `.mlpackage` binaries, `reports/**` data files.

Report on whether these should be tracked, their size, and any secrets or personal data they might expose. **The repo is public.**

## Context you need

**Project and build**
- The project is `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`, with the app (product **Alfie**), the CMIO system extension `CinematicCoreExtension`, unit tests (Swift Testing, module `Alfie`) and UI tests.
- Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, approachable concurrency (`NonisolatedNonsendingByDefault`), `MemberImportVisibility`, Swift 5 mode. Pure logic types are marked `nonisolated`.
- **Shared with the extension:** `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, `ShowStandard.swift` and `CropRenderer.metal` compile into both targets. App-only references there break the extension.

**Pipeline**
- The pipeline is capture → detect (Vision) → compose (`ShotComposer`) → crop (Metal `CropEngine`) → output (XPC to the extension; pooled output surfaces).
- Known rules:
  - no per-frame `@Published` mutations on the frame path; UI mirrors at most 15 Hz;
  - pooled output surfaces need per-route retention (the XPC 10-frame FIFO);
  - detection is operator-gated (no full-frame multi-person scan);
  - the XPC service name must stay app-group-prefixed.

**Stage 3 (Auto Director)**
- This is active on `s3/*` branches by other agents (Group A Director core: Sol; Group B engine: Opus; Group C UI: you; Group D docs: Astra).
- Code under `Director/` on `main` may be superseded by open PRs. Check `gh pr list` and note "superseded by PR #N" instead of reporting a finding that a PR already fixes.

## What to look for (check every file against this)

1. **Memory and resource leaks:**
   - retain cycles (closures capturing `self` strongly in stored closures, Combine `sink` stored on `self`, `Timer`, `NotificationCenter` and KVO observers never removed);
   - AVCapture delegates;
   - `CVPixelBuffer` / `IOSurface` / `MTLTexture` / `CMSampleBuffer` lifetime and pools;
   - unbounded arrays, caches or logs;
   - file handles left open.
2. **Concurrency:**
   - MainActor violations;
   - data races on vars touched from capture queues;
   - `@unchecked Sendable` and `nonisolated(unsafe)` without justification;
   - `DispatchQueue` closures capturing actor state;
   - `Task {}` without cancellation;
   - `await` inside locks.
3. **Crash risks:** `try!`, `!` force unwraps on external data, `fatalError` / `precondition` on runtime input, array indexing without bounds checks, integer overflow outside `&+=`.
4. **Security and privacy:**
   - XPC message validation and peer checks;
   - entitlements broader than needed;
   - file paths and permissions;
   - any image, face or personal data written to disk or logs;
   - **anything secret or personal in tracked files** (the repo is public): emails, team IDs, keys, tokens, passwords, notary profile details;
   - Python `pickle`, `eval` or `subprocess` with shell=True, or unpinned downloads;
   - shell scripts without `set -euo pipefail`, or with unquoted variables.
5. **Frame-path performance:** allocations per frame, `@Published` per frame, synchronous work on the main thread, Vision requests rebuilt per frame, logging per frame.
6. **Correctness and design:** logic errors, wrong units or coordinate systems (Vision is bottom-left origin), silently swallowed errors, duplicated logic, dead code (unused types, functions, flags, files), Debug-only code reachable in Release.
7. **Tests:** tests that assert nothing, tests depending on wall-clock time or ordering, missing tests for risky code, disabled tests.

**Severity:**

| Severity | Meaning |
|---|---|
| **Critical** | Crash, data loss, a security or privacy exposure, or a broken release |
| **High** | A leak or race likely to hit a live show, or wrong output |
| **Medium** | A real defect with limited impact, or a missing test on risky code |
| **Low** | Cleanliness, dead code, naming, small improvements |

**Confidence:** **Confirmed** (you traced it or reproduced it) or **Plausible** (it needs a runtime check). Don't report hunches without code evidence.

## Output 1: the review document

Write `reports/code-review-2026-10/CODE-REVIEW.md` with this structure:

1. **Header:** commit SHA, date, baseline build and test counts, the warnings list, and how many files were reviewed.
2. **Summary:**
   - counts by severity;
   - the top 10 findings;
   - themes, such as patterns that repeat across files.
3. **Repo hygiene:** tracked build artifacts and caches, secrets or personal data in tracked files, `.gitignore` gaps.
4. **File-by-file review: every in-scope file gets its own section**, in path order:

   ```markdown
   ### `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`
   | ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
   |---|---|---|---|---|---|---|
   | CR-041 | High | Confirmed | Leak | 812–830 | `sink` captures `self` strongly and is stored on `self`… | Use `[weak self]`; store in `cancellables`… |
   ```

   **If you found nothing in a file, still list it:**

   ```markdown
   ### `CinematicCoreMacOS/CinematicCoreMacOS/ShowStandard.swift`
   Haven't found anything vulnerable or badly coded.
   ```

   Finding IDs are unique (`CR-001` and up) and stable; the fix prompts refer to them.
5. **Docs and `.md` files to review:** a table of every `.md` with path, status, reason and recommendation (keep / update / archive / delete candidate). **Nothing is deleted in this task.**
6. **Not reviewed:** anything you skipped, and why.

Before finishing, **re-check every Critical and High finding** against the code a second time, and downgrade or drop any that don't hold up.

## Output 2: two fix prompts (no overlap)

Once the review is done, **you decide** which files go to which agent, based on what each model is better at and on how the code clusters. As a starting point:
- Opus 5.5 has owned the engine, capture, output, Take and router, and concurrency-heavy code.
- Sol 6.1 has owned the Director core (pure logic, policy, replay) and tends to do well on pure Swift logic and tests.
- Python scripts and training code can go to either.

Explain your reasoning in one short paragraph at the top of each prompt.

**Hard rules for the split:**
- **Every file with findings goes to exactly one agent.** A file never appears in both prompts.
- Keep tightly coupled files together, for example a type and its tests, or files that must change together.
- **Files touched by an open Stage 3 PR:**
  - Assign them to the agent whose Stage 3 group owns that PR: Group A → Sol; Group B → Opus; Group C → put them in a short **"For Grok later"** list in the review doc, not in either prompt; Group D docs aren't in scope.
  - Mark those findings **"start after PR #N merges"**.
- Add a **coverage table** at the end of the review doc: every file with findings, which agent owns it, and its finding IDs. It must account for 100% of the findings exactly once.

**Write each prompt as a standalone file** that the owner pastes into a fresh session:
- `reports/code-review-2026-10/FIX-PROMPT-OPUS-5.5.md`
- `reports/code-review-2026-10/FIX-PROMPT-SOL-6.1.md`

**Each fix prompt must contain:**
1. Who the agent is, what the review was, the reviewed commit SHA, and a link to `CODE-REVIEW.md`.
2. **The exact list of files this agent may edit**, and the instruction to edit no others, plus a pointer to the other agent's list so they never collide.
3. Its findings, ordered by severity, as a checklist of IDs with a one-line summary each. The details stay in `CODE-REVIEW.md`.
4. **Grouping into PRs:** small, related fixes per PR, on branches `review/<agent>/<topic>` from the latest `main`; Critical issues first in their own PRs; findings marked "start after PR #N merges" last.
5. **Rules:**
   - fix the finding without changing behaviour beyond it;
   - add or adjust a test for every Critical and High finding;
   - build the CMIO extension too when touching the shared files;
   - keep pure types `nonisolated` and follow the MainActor rules above;
   - commit explicit paths only;
   - never merge;
   - if a finding turns out wrong, mark it "not reproduced" with evidence instead of forcing a change.
6. **The test command**, with a separate derived-data path for this agent.
7. **Stop and ask the owner when** a fix needs a product decision, touches entitlements, signing or `project.pbxproj`, or needs a file owned by the other agent.
8. **End-of-session report:** finding IDs fixed, PR links, test counts, and findings marked not reproduced or deferred.

## Rules for you

- **Write only under `reports/code-review-2026-10/`.** No code changes, no doc edits, no deletions.
- Commit those files on `review/code-review-2026-10` with explicit paths only, and open **one PR** (docs only). Never merge.
- Quote at most a few lines of code per finding, with line numbers. If you find a real secret, **don't copy its value** into the report: give the file, line and type only, and flag it to the owner in chat straight away as Critical.
- Be thorough rather than fast: read each file in full. If the session runs long, commit progress, and say in chat which files remain.

## Final report (in chat)

- the PR link;
- counts by severity, and the top 5 findings;
- how many files had no findings;
- the Opus/Sol split, with file and finding counts each and the reasoning;
- the "For Grok later" list;
- docs flagged outdated or for deletion (the owner decides);
- any secret found, flagged first.
