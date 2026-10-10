# Grok 4.7: research, then build a CI/CD pipeline for Alfie

Paste everything below the line into Grok 4.7. **Start only after C-01 to C-04 are finished** (PRs #13, #14, #16 and #17 are up and their review comments are addressed).

---

## Goal

Alfie is a **macOS app** (Swift/SwiftUI) with an embedded **CMIO camera system extension**. The pipeline you build must make it very hard for a change to break a release.

There are **two distribution channels**, and the pipeline must serve both:

1. **Now: Developer ID DMG.** The app is signed, notarized, stapled and shipped as `Alfie.dmg` outside the store.
2. **Later: the Mac App Store.** The owner plans a **basic and a paid version**, which are **not defined yet**. Design the pipeline so a second product variant and StoreKit can slot in later. **Don't invent tiers, prices, product IDs or features.** Mark every such slot **AWAITING OWNER**.

Work in two phases. **Phase 1 is research and design (a written doc). Phase 2 is the build.** Don't write workflow files until Phase 1's doc is committed.

## Facts about this repo (verified 10 Oct 2026; re-check anything you rely on)

**Repository and tools**
- Repo: `github.com/stephancmorris/macOS-rl-viritual-camera`. It is **public**, and the default branch is `main`. There is **no `.github/` directory yet**.
- Local toolchain: Xcode 26.2 (17C52).
- Project: `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`.
  - Targets: `CinematicCoreMacOS` (the app, product name **Alfie**), `CinematicCoreExtension` (the CMIO extension), `CinematicCoreMacOSTests` and `CinematicCoreMacOSUITests`.
  - **Only the `CinematicCoreMacOS` scheme is shared** (`xcshareddata/xcschemes`). The extension builds as an app dependency.

**Build settings**
- `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, approachable concurrency, `MemberImportVisibility`, Swift 5 language mode.
- Some files compile into **both** the app and the extension: `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, `ShowStandard.swift` and `CropRenderer.metal`. A change there can break only the extension build, so CI must build the extension.

**Tests**
- Unit tests use Swift Testing; the test module name is `Alfie`.
- The local command is:
  ```sh
  xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS \
    -destination 'platform=macOS' -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO
  ```
- Python tests: `CinematicCoreMacOS/scripts/test_diagnostics_report.py`, plus `training/test_env.py` and `training/test_training.py` (`training/requirements.txt`).

**Signing and release**
- Entitlements:
  - **app:** app sandbox, application groups, `com.apple.developer.system-extension.install`, camera, iosurface;
  - **extension:** app sandbox, application groups, iosurface.
- The team ID is `EPZDEPSV69`. The XPC service name must stay **app-group-prefixed** (`EPZDEPSV69.…`). A CI check that this prefix and the app and extension version/build numbers stay consistent is valuable.
- Current release script: `CinematicCoreMacOS/build_release.sh`. It runs in this order:
  1. archive in Release, stamping `ALFIE_SOURCE_FINGERPRINT` from `scripts/source_fingerprint.py`;
  2. export with Developer ID using `build_out/ExportOptions.plist`;
  3. notarize with `notarytool` (keychain profile `alfie-notary`);
  4. staple, then `spctl` and `codesign --verify --deep --strict`;
  5. sign the DMG.

  It must keep working locally. Don't break or rewrite it; CI may call it or mirror its steps.
- Development overrides (`DeveloperFlags`) are **Debug-only** by design. A Release build must not contain them (see commit `a89644b`).

**Repo hygiene**
- About 290 files of release output under `CinematicCoreMacOS/build_out/` are **tracked in git**, along with some `.deriveddata*` / `.codex-derived-data` folders. CI must not depend on them.
- Recommend what to do about them in your doc, but **don't delete them**; the owner decides.

**Other agents** are working on `s3/*` branches (Stage 3). Your work must not touch Swift source, `project.pbxproj`, entitlements or `Info.plist`. If CI needs a change there (for example, sharing the extension scheme), write it as a request in `docs/handoff/stage3-4/integration-requests.md` and tell the owner.

## Phase 1: research and design

Research current (2026) practice, citing a source for every claim that matters. Topics:

1. **CI platform options for a macOS app:**
   - GitHub Actions hosted macOS runners: which Xcode 26.x versions are available, the runner images, Apple silicon, and cost for a public repo;
   - a self-hosted Mac runner;
   - Xcode Cloud;
   - fastlane or plain `xcodebuild` / `notarytool` / `altool`.

   Recommend one, with trade-offs.
2. **Signing in CI for both channels:**
   - **Developer ID Application** for the DMG;
   - **Apple Distribution** plus provisioning profiles for the Mac App Store;
   - how the **system extension** is provisioned in each (does the `system-extension.install` entitlement and a CMIO camera extension pass App Store review, and what's required?);
   - temporary keychains, and an App Store Connect API key versus an app-specific password.
3. **Notarization in CI:** `notarytool` with an API key, stapling, and verification (`spctl`, `codesign`, `stapler validate`).
4. **Mac App Store path:**
   - the archive/export method (`app-store-connect`);
   - validation before upload;
   - TestFlight for macOS;
   - how a **basic and paid** model is usually built: one app with in-app purchase/StoreKit versus two products. Present it as **options for the owner**, not a decision.
5. **Protecting releases on a public repo:**
   - secrets are never exposed to fork PRs;
   - protected environments with required reviewers for signing and upload jobs;
   - branch protection with required checks;
   - pinning actions to a commit SHA;
   - least-privilege `permissions:`.
6. **What "won't break a release" means here.** Turn it into concrete gates, for example:
   - the Release configuration builds and archives;
   - the extension builds;
   - unit tests pass;
   - no Debug-only flags in Release;
   - entitlements and plists are consistent across app and extension;
   - version and build numbers increase;
   - the archive validates for the App Store channel;
   - a notarization dry run on release branches.

**Output:** `docs/ci/CI-CD-RESEARCH.md`. Include:
- the options compared in a table;
- the recommendation, and why;
- the gates list (each gate's job, trigger and failure meaning);
- the design for both channels;
- secrets the owner must create (names only);
- costs;
- open questions marked **AWAITING OWNER**.

Commit it on branch `ci/research-and-pipeline` and open a **draft PR**.

**Stop and ask the owner before Phase 2 if** your recommendation needs:
- a paid service;
- a self-hosted runner on the owner's machine;
- any change to signing settings in the project.

Otherwise continue.

## Phase 2: build the pipeline

Work on the same branch, in your own worktree (never the owner's checkout). Suggested shape; adjust to your research:

1. **`ci.yml`, on every pull request and push to `main`:**
   - check out and select a pinned Xcode version;
   - cache SwiftPM and derived data sensibly;
   - build the app in Debug with `CODE_SIGNING_ALLOWED=NO`, which also builds the extension;
   - run `CinematicCoreMacOSTests`, uploading the `.xcresult` as an artifact and summarising pass and fail counts in the job summary;
   - **build the Release configuration** (unsigned) to prove Release compiles without Debug-only code;
   - run the Python tests;
   - run consistency checks as a small script in `scripts/ci/`: app and extension version/build match, the XPC/app-group prefix, entitlements unchanged unless the PR is labelled to allow it, and no `DeveloperFlags` compiled into Release.

   Keep it fast. Run UI tests in a separate optional job if they can't run headless.
2. **`release-dmg.yml`, manual (`workflow_dispatch`) or on a version tag:**
   - runs only in a **protected environment** with secrets;
   - archives, exports with Developer ID, notarizes, staples, verifies and builds the DMG;
   - uploads it as an artifact or a draft GitHub Release.

   It **must fail** if any `ci.yml` gate fails for that commit.
3. **`release-appstore.yml`, manual only:**
   - archives and exports for App Store Connect, then **validates only**;
   - leaves upload and TestFlight behind a separate, manually approved step;
   - leaves StoreKit and tier slots as clearly marked TODOs, **AWAITING OWNER**;
   - if the App Store build needs project changes (a separate configuration, provisioning, or entitlements), **don't make them**; list them in the research doc and the integration requests.
4. **`docs/ci/README.md`:**
   - what each workflow does;
   - how to run each locally;
   - the exact **secrets and settings the owner must add** (repo secrets, environments, branch protection rules) as a checklist.

   **You never create, enter or handle credentials.** The owner adds them.

**Verify:**
- lint the workflow YAML with `actionlint` if available;
- get `ci.yml` green on the draft PR;
- show that it **goes red** on a deliberately broken commit (a failing test, or a Release-only compile error), then revert that commit;
- signing and release workflows can't run without secrets, so dry-run what you can and say plainly what's untested.

## Rules

- Only add or edit `.github/**`, `scripts/ci/**` and `docs/ci/**`, plus a request in `docs/handoff/stage3-4/integration-requests.md` if needed.
- Commit explicit paths only (no `git add -A`). One branch and one PR. Never merge. Don't change branch protection or repo settings yourself; list them for the owner.
- Pin every third-party action to a full commit SHA. Set `permissions:` to the minimum per job.

## Final report (in chat and in the PR body)

Include:
- the recommendation, with a link to the research doc;
- each workflow and the gates it enforces;
- run links showing green, and red on the deliberate break;
- what's untested and why;
- the owner checklist (secrets, environments, branch protection);
- questions marked **AWAITING OWNER**, including the basic/paid model options.
