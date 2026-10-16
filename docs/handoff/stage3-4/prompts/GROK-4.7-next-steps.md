# Grok 4.7: next steps (Group C), 10 Oct 2026

Paste everything below the line into the running Grok 4.7 session. It updates your original prompt (`prompts/GROK-4.7-ui-tooling.md`). Where they conflict, this one wins.

---

## What changed since you started

Group A's types now exist, but **nothing is merged to `main` yet**. They're in a stack of open PRs (owner merges in order):

`#3 B-00 → #6 A-01 → #7 A-02 → #8 A-05 → #9 A-06 → #10 A-04 → #11 A-03 → #12 A-07`

The branch **`origin/s3/a/A-04-console-status-api`** (PR #10) contains everything you need:

| You need | Where it is on that branch |
|---|---|
| `NextShotStatus.DirectorSection` v2 (replaces your mirror) | `Director/DirectorConsoleAPI.swift` |
| `DirectorConsoleControlling` + `DirectorControlResult` | `Director/DirectorConsoleAPI.swift` |
| `DirectorPreferences` v2, `DirectorStyle`, `SegmentType` | `Director/DirectorPreferences.swift` (A-05) |
| `DirectorShot` (wraps `OperatorCommand.Preset`, has `.title`) | `Director/DirectorProposal.swift` (A-01) |

**Base every Group C branch on `origin/s3/a/A-04-console-status-api` and open your PRs against that branch, not `main`.** GitHub retargets them automatically as the stack merges. Don't base on A-03 or A-07; you don't need them.

## Your tickets right now

| Ticket | Card | Status | Do now? |
|---|---|---|---|
| **C-01** Director gallery states | https://trello.com/c/8UiB9wGU | Built but **uncommitted**, still on your local mirror | **Yes, first:** commit, move to your worktree, switch to the real type |
| **C-02** Mode control and Hand to Alfie | https://trello.com/c/4FVemMN9 | Unblocked (A-04 on the base branch) | **Yes** |
| **C-03** Next-shot director line and AUTO badge | https://trello.com/c/PA87fkd9 | Unblocked (A-04) | **Yes** |
| **C-04** Style settings and preferences store | https://trello.com/c/tE0tzjNz | Unblocked (A-05 is on the base branch) | **Yes** |
| C-06 Next-cut notice UI | https://trello.com/c/auY6HYtj | View and Esc binding can be built now; the live check needs B-08 | Optional, after C-04. Mark the live check pending |
| C-05 Shadow report script | https://trello.com/c/6RaMJbfT | **Blocked:** needs A-09, which needs Astra's D-02 schema | No |
| C-07 Run sheet editor | https://trello.com/c/JAU8oFd7 | **Blocked:** needs A-13 | No |
| C-08 Subject pick display | https://trello.com/c/7BJdvATP | **Blocked:** needs A-14 and B-10 | No |
| C-09 Backup alerts | https://trello.com/c/DRRk4TJu | **Blocked:** needs B-12 | No |
| C-10 Learned scorer training | https://trello.com/c/7HOi1AOx | **Blocked:** needs C-05 and real shadow data | No |

## Step 0: move off the owner's checkout (do this before anything else)

You're working in the owner's main checkout (`/Users/stephanmorris/Documents/macOS-rl-viritual-camera`), which also holds the owner's **uncommitted plan docs**. Never run `git add -A`, `git add .` or `git commit -a` there.

1. **Commit only your C-01 files**, on your branch `s3/c/c-01-director-gallery-states`, with explicit paths:

   ```sh
   git add CinematicCoreMacOS/CinematicCoreMacOS/Console/FakeConsoleModel.swift \
           CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/MultiviewGallery.swift \
           CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorDemo.swift \
           CinematicCoreMacOS/CinematicCoreMacOS/InputTileView.swift \
           CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorGalleryCatalog.swift \
           CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorSectionMirror.swift \
           CinematicCoreMacOS/CinematicCoreMacOSTests/GalleryDirectorStateTests.swift \
           docs/gallery-screenshots/README.md docs/gallery-screenshots/director-*.png
   git commit -m "C-01 gallery states (mirror; switching to A-04 next)"
   ```

   Don't commit:
   - `docs/handoff/**` (including your `integration-requests.md` note); the owner commits plan docs;
   - `docs/auto-director/**`;
   - the older `input-*`, `pill-*` and `setup-*` PNGs in `docs/gallery-screenshots/`, which aren't yours;
   - anything under `CinematicCoreMacOS/build_out/`.
2. **Hand the checkout back:**

   ```sh
   git switch r2/engine
   ```

   The owner's uncommitted docs carry over unchanged. Confirm `git status` still shows them.
3. **Create your worktree and rebase onto the base branch:**

   ```sh
   git fetch origin
   git worktree add ../alfie-s3-c s3/c/c-01-director-gallery-states
   cd ../alfie-s3-c
   git rebase origin/s3/a/A-04-console-status-api
   ```

   The rebase should be clean, because your files don't overlap Group A's. From now on, work only in `../alfie-s3-c`.
4. Build with your own derived-data folder, so you don't fight other agents' builds:

   ```sh
   xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS \
     -destination 'platform=macOS' -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO \
     -derivedDataPath /private/tmp/s3c-dd -resultBundlePath /private/tmp/s3-<ticket>.xcresult
   ```

5. Move the C-01 card to 🚧 In Progress. It's still in Agent Queue.

## Step 1: finish C-01 on the real type

Replace `DirectorSectionMirror` with `NextShotStatus.DirectorSection`, then **delete `Director/UI/DirectorSectionMirror.swift`**.

| Your mirror | Real type |
|---|---|
| `Level` (manual/assist/auto/backup, `title`) | `DirectorSection.Level`: same cases and titles |
| `Activity.active(reason: String)`, etc. | `Activity.active(ActiveReason)`, `.paused(PauseReason)`, `.inhibited(InhibitReason)`, `.abstaining(AbstainReason)`. **Typed reasons**; read `activity.text` for the sentence |
| `Activity.kind` / `Kind` | `Activity.kind` / `Activity.Kind`: same |
| `PreparedShot(input:, shotName: String)` | `PreparedShot(input:, shot: DirectorShot)`, for example `DirectorShot(preset: .stage(.waistUp))`; `.line` gives "Cam B · Waist Up" |
| `NextCut(input:, countdown:, cancellable:)` and `nextCutLine` | `NextCut(...)`: same fields; `nextCut?.line` gives "Next: Cam B · 2 s · Esc to cancel" |
| `secondsText(_:)` | `NextCut.seconds(_:)` |
| `Qualification` / `.none` / `allows` | same; also `section.canSelect(_:)` |
| `alfieSetShot`, `showsAutoBadge(on:)` | same |
| `handedToAlfie` | same |
| `RunSheetStrip(current:, next:)` | `RunSheetLine(current:, next:)` |
| `statusLine`, `preparedLine`, `unqualifiedCaption`, `autoBadge` | `statusLine`, `preparedLine`, `DirectorSection.notQualifiedCaption`, `DirectorSection.autoBadge` |
| `modeChips`, `handControl`, `badgeChannel`, accessibility labels | Not in the model; they're UI helpers. Keep them as a small view-model in `Director/UI/` built from the section |

Every gallery case must use a real typed reason. If a state you want has no matching reason, **don't invent text**: add a request to `docs/handoff/stage3-4/integration-requests.md` asking Group A for the reason, and leave that case out. Use `DirectorSection.atLaunch(qualified:)` for every launch state.

Then:
- re-run the screenshots;
- update `GalleryDirectorStateTests`;
- open the PR against `s3/a/A-04-console-status-api`;
- comment the PR link on the card and move it to 👀 Human Review.

## Step 2: C-02, C-03, C-04 (one branch and PR each, all based on `origin/s3/a/A-04-console-status-api`)

**C-02 Mode control and Hand to Alfie**
- Build against `DirectorConsoleControlling`. Add a fake controller for the gallery in `Director/UI/` or `Console/Gallery/`, not in Group A files.
- Unqualified levels show greyed out with `DirectorSection.notQualifiedCaption`. If the controller returns `.refused(message)`, show the message and never pick another level.
- The Manual / Hand to Alfie toggle is always visible. `takeOver()` and `handToAlfie()` are the only calls.
- Pick a Hand to Alfie / Manual shortcut that doesn't collide with existing ones (today only ⌘⌥⇧S is used) and document it. **Esc is reserved for `cancelNextCut()`** (C-06).
- Done when every launch shows Manual, VoiceOver labels are on every control, and there are gallery screenshots for each state.

**C-03 Next-shot director line and AUTO badge**
- Add a third line or strip to `NextShotPanel` from `section.preparedLine` and `section.statusLine`.
- The AUTO badge goes in `InputTileView.directorBadgeReserve`, only when `section.showsAutoBadge(on:)` is true.
- **If the 600×70 panel can't fit the line, stop and ask the owner.** Don't resize shared layout on your own (U1 is open).

**C-04 Style settings and preferences store**
- Add a settings screen to edit a `DirectorStyle` per `SegmentType`. A Live event style is required.
- Add `DirectorPreferencesStore` (put it in `Director/UI/`):
  - versioned JSON in Application Support;
  - read through `DirectorPreferences.migrate`, so unknown or old versions fail closed with a visible message;
  - write only validated preferences;
  - **never store an authority level**.
- **No invented defaults.** With nothing stored, show "No style set" and let the owner enter values. T1–T3 are open, and the numbers come from data later.
- Saving calls an injected `onPreferencesChanged(DirectorPreferences)` closure. Opus wires it to the Director (B-03) later, so don't reach into the engine.

## Rules that still apply (from your original prompt)

- **Only edit Group C files:**
  - Console views and `InputTileView.swift`;
  - `Console/Gallery/**` and `Console/FakeConsoleModel.swift`;
  - Settings views and `Director/UI/**`;
  - `CinematicCoreMacOS/scripts/director_*.py` and `training/*director*`.
- **Not yours:**
  - `Console/NextShotStatus.swift`, `Director/DirectorConsoleAPI.swift` and the rest of `Director/*.swift`;
  - `Console/LiveConsole.swift` and `Console/ConsoleActions.swift`;
  - `project.pbxproj`, entitlements and `Info.plist`.

  Need something there? Use `integration-requests.md`.
- **UI rules:** plain words only; ≤15 Hz refresh; no per-frame `@Published`; `import Combine` and `import CoreGraphics` explicitly where used.
- **One ticket = one branch = one PR.** Never merge. Never move a card to Done.
- **Every PR includes:**
  - the ticket and card link;
  - the "done when" checklist with evidence;
  - screenshots of each new state;
  - test counts from the result bundle;
  - the evidence class ("synthetic / gallery");
  - what's not done.

## When the stack merges

The owner merges in the order at the top. When `s3/a/A-04-console-status-api` lands on `main`, rebase each open Group C branch onto `origin/main` and push. GitHub will already have retargeted the PRs.

## Stop and ask the owner when

- a state or reason you need isn't in `DirectorSection`;
- the layout budget doesn't fit;
- anything would need a change outside Group C's files.
