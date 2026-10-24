# Alfie quality sprint — 4 October 2026

Freshly fetched base: `a89644b865e31d179ab9bee5f41fe25b760d2f34` (`origin/main`). Managed worktree and branch `codex/alfie-quality-sprint-2026-10-04`; primary checkout's build artifacts and documents preserved. No merge to main. No applicable repository AGENTS.md found; `/Users/stephanmorris/.codex/AGENTS.md` is empty.

## Unit 1 — consent boundary

Card: https://trello.com/c/4iO4c3N9. Parent: https://trello.com/c/ecKr4f2R.

Current source confirmed the audit finding before edits: public consent mutation persisted to standard defaults regardless of injected defaults; Start checked consent and recordFrame checked only recording. Stop suspended while holding mutable session state, allowing immediate restart to replace that state; synchronous Published notifications also expose a reentrant restart path.

Consent now mutates through `setTrainingDataConsent`. MainActor serializes frame admission and Stop/revoke. A private plain admission gate closes before state notifications; the active writer also prevents restart until the shared shutdown operation drains buffered and queued observations, finalizes metadata, and closes. Stop/revoke callers await the same operation. Already accepted data is preserved. Consent can be revoked in settings during recording. Injected defaults, temporary root and writer factory keep tests outside operator storage. Ordered batch task chaining preserves JSONL order; UUID session suffixes prevent same-second restarts from overwriting files.

Four Swift Testing definitions / five runs cover no-consent writer refusal, injected defaults, queued accepted batches plus buffer drain, frames posted before/after the revocation boundary, both proved Stop/revoke entry orders, attempted restart with and without renewed consent, synchronous observer reentrancy, ordinary Stop, and distinct renewed sessions. Two pre-existing privacy audit definitions also pass.

Actual persisted `frames.jsonl` is read in tests using the production writer. Top-level keys: `t`, `frame_idx`, `speaker`, `keypoints`, `current_crop`, `ideal_crop`, `interpolating`. Speaker contains position, depth proxy, bounding box and confidence; pose contains normalized head/waist coordinates and confidence; crops contain coordinates/zoom and ideal label source. `metadata.json` includes camera name, resolution, times and configurations. Observations do not contain raw images/face feature prints in this schema; timestamps, camera/configuration and human observations are not anonymous. This is not privacy/Store compliance or runtime macOS camera-permission qualification.

Final targeted bundle `/private/tmp/alfie-quality-u1-targeted-final.xcresult`: 6 passed definitions / 7 passed case runs, 0 failed, 0 skipped. Initial targeted/full runs also passed; one observer-reentrancy regression and deterministic ordering refinement were then added, so the final bundles are authoritative for the commit.

Final complete target bundle `/private/tmp/alfie-quality-u1-full-final.xcresult`: **447 passed definitions / 552 passed case runs, 0 failed, 3 skipped**. Skips: opt-in instrumentation investigation, unconfigured consented readiness clips and real two-webcam rig test. The unchanged 250 µs benchmark passed. No skip is live qualification.

All builds use `xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd`. Targeted runs select named suites. Exact definitions come from `xcresulttool get test-results summary/tests`; parameter Arguments children replace their parent definition for case-run counts. Xcode 26.2 (17C52), arm64 macOS 26.6.2 (25G83).

No entitlement, microphone permission, Store disclosure, diagnostic retention/deletion or manifest change. Existing training retention controls remain; revocation itself does not run cleanup or delete files. Remaining parent acceptance: approved-candidate camera-permission refusal/revocation, lifecycle/export runtime inspection, retention/disclosure decisions and Store review.
