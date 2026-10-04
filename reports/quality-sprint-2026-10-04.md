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

## Merged foundation card reconciliation

The original coding repair commits are present in fresh main ancestry: AD-VALIDATION `61518b30731d7d159999b23d404e9909f275ede5`; AD-REPLAY-TRUTH `d18575383fff1da6e89c798de3d70b62038cb1e4`; HW-SIM-SAFETY `f5bac15772645416039d51db0e9d9b90ff3e2b4d`; VOICE-TOKENS `830342ee5e62db55fea450bb121d01018164a776`. Current foundation tests in the Unit 1 final full bundle pass: DirectorAuthority/Proposal/ShotPolicy 22 definitions / 45 runs; DirectorReplay/EffectAudit 12 / 22; HardwareLink 29 / 29; SpeechCommand 6 / 6 (including internal corpus loops). All have zero failures. These are current-test totals for the named suites, not sums of old candidate runs.

Evidence added and cards moved from Agent Queue to Human Review: https://trello.com/c/nPoIqkTe, https://trello.com/c/X0OTOpra, https://trello.com/c/AkZj4BJB, https://trello.com/c/owpu13qI. None marked Done. The consent parent has a separate evidence checklist; the connector's 2,048-character description limit prevented appending without truncating its existing acceptance text, so that text was preserved.

Replay lifecycle `307d91f` and independent raw-world effect audit `a89644b` postdate the candidate review finding. The latter independently classifies recorded effect context, but `CommittedEffect` still does not independently record `evidenceAvailable` or active request identity; those rejection reasons currently rely on the preparation validator. Live latency/labelled editorial qualification remains open. Director product choices and live evidence adapters remain open; hardware remains motion-disabled and needs target/firmware/physical stop evidence; voice remains text-only and needs privacy/recognizer choices, session-unique IDs and actual utterance/effect hooks. All 37 product decisions remain OPEN. No synthetic test closes these gates.

## Unit 2 — setup truth

Card: https://trello.com/c/kMmbRuhn. Parent: https://trello.com/c/ztw0PPkU.

Current source confirmed the stored record match uses Mac/OS, standard, route and camera model IDs while running `AdmissionFingerprint.key` additionally includes delivered format/rate/profile/mode. The stopped screen claimed certification “on this exact setup” and its measurement rows said “Passed”. LiveConsole already starts measurement after Preview renders; that live path was preserved.

The setup model now exposes `historicalPass` and `historicalUnsupported` with required measurement dates. Historical rows and VoiceOver labels say “in stored record”; only the distinct-device selection fact stays a current pass. The panel says “PAIR EVIDENCE” and uses neutral historical-success styling. Details explain the compatible historical scope and that current delivered format/profile/mode are unverified. Unknown pairs remain “current setup unmeasured” and may Start as an unmeasured trial; no pre-Start measurement is invented. Full stored fingerprint keys are retained for explicit exact-match checks against running fingerprints.

Start/admission behavior is preserved, including conservative precedence of stored unsupported history, A-only fallback, and exact live admission store lookup. No output standard, Program route, camera start, Take or admission-policy change. Profile, host and device-metadata changes clear a check in progress alongside the existing selection/standard/route invalidation.

Five added definitions / eight runs cover changed mode, delivered format, rate and profile versus exact certified store status; old dated history, unknown records, stale policy/host context, active-check invalidation, dated unsupported results and retained Start refusal. Existing selection/output/device/accessibility cases were adapted to explicit historical states.

Final targeted bundle `/private/tmp/alfie-quality-u2-targeted-final.xcresult`: **96 passed definitions / 102 passed case runs, 0 failed, 0 skipped**. Suites: ShowSetupTests, LiveConsoleTests, AdmissionRecordTests, PairAdmissionTests, ProgramTakeTests, ChannelIsolationTests, OutputRateRegressionTests, DirectOutputFormatTests. Two parameterized definitions have eight argument runs (96−2+8=102). Final complete target `/private/tmp/alfie-quality-u2-full.xcresult`: **452 passed definitions / 560 passed case runs, 0 failed, 3 skipped** (same opt-in study/dataset/real-rig skips as Unit 1). The unchanged 250 µs assertion passed. Summary and tree were read with xcresulttool; unsigned Debug build using the same single-host command above.

Remaining human/rig acceptance: candidate setup/VoiceOver/1280-point walkthrough and actual two-camera capture/delivered formats, matching full running fingerprint and required soak. The real two-webcam test is opt-in and absent hardware is an explicit skip, not a two-camera qualification pass.

## Unit 3 — exact latency windows and benchmark separation

Card: https://trello.com/c/EiASM9uE. Parents: https://trello.com/c/jiY5JFaH and https://trello.com/c/D6KPsTw4. [Detailed profile, raw evidence and clock contract](release-1/metrics-window-2026-10-04.md).

Current source was checked against the older report before editing: the current default 5,000-frame/250 µs assertion already supplies source timestamps for four stages. The separate app-host wall/source study reproduced retained growth; actual malloc-family backtraces and CPU sampling of a faithful standalone Debug algorithm reproduction attributed the main measured cost to repeated removeAll expiry scans. The standalone probe is not an app allocation profile, and requested allocation bytes are not resident footprint. Failed Instruments capture was excluded.

ProgramOutputManager now owns per-stage reference FIFO windows. Admission/strict expiry, exact chronological summation, stage definitions, production monotonic clock default, raw counters and 0.5-second publication cadence are preserved. Nonfinite timestamps affect the window only, while backwards finite clocks reset only that stage. Backing storage shrinks after burst expiry. Deterministic reference tests cover wrap/growth/shrink, equal/inclusive timestamps, invalid clocks, all stages, reset, raw counters and publication behavior; uniform 50/59.94/60 Hz fixtures are covered.

Retention is bounded by the stated finite-clock and arrival-density contract: with minimum per-stage spacing Δ, at most floor(5/Δ)+1 observations in the inclusive window (251 at 50 Hz, 300 at 60000/1001 Hz, 301 at 60 Hz). Backing capacity after an append is at most max(64,4×retained count). Arbitrarily dense or equal-timestamp bursts remain lossless and cannot have a universal hard sample cap while preserving every observation's exact expiry/mean. That additional cap requires a separate drop/aggregation policy decision; it was not guessed or silently implemented.

The accelerated 5,000-frame source-clock stress is now opt-in; the **250 µs assertion is unchanged and passed at 19.27 µs/frame**. The updated opt-in wall/source study preserves counts and raw comparison data: at 5,000 frames medians were 19.91 µs/frame wall and 19.13 source, retained 20,000 and 1,004. These are new same-fixture host measurements; they are distinct from the earlier default benchmark's 182.14 µs value. No real lag or physical presentation-latency improvement is inferred.

Final targeted `/private/tmp/alfie-quality-u3-targeted-final.xcresult`: **20 passed definitions / 20 passed runs, 0 failed, 1 skipped** (cadence intentionally run separately). Full `/private/tmp/alfie-quality-u3-full.xcresult`: **459 passed definitions / 567 passed case runs, 0 failed, 5 skipped**. Default full skips are accelerated stress, cadence benchmark, investigation study, missing consented readiness dataset and real two-webcam rig. Stress and investigation were explicitly exercised in the targeted bundle; the cadence result is recorded below. All exact counts come from xcresult summary/tests, with unsigned one-host Debug builds.

Initial Unit 3 build failed because the extension target also compiles ProgramOutputManager but lacked the new helper source membership. Adding exactly one helper membership entry fixed it; `/private/tmp/alfie-quality-u3-targeted.xcresult` and .log retain the compile failure (no tests ran). Initial cadence method selection matched zero tests despite the command's success message; `/private/tmp/alfie-quality-u3-cadence.xcresult` is excluded as evidence. Actual cadence verification uses a suite selector and independent host after the full suite.

No entitlements, permissions, Store disclosures, diagnostics retention/deletion or guessed manifest changes. No Director app hooks, automatic Take, 3–4 live-input feature, hardware motion or microphone recognition were implemented.

## Completion and next evidence

Units 1 and 2 are fully implemented and verified within their source/test scope. Unit 3's FIFO cost repair, exact-window/reference tests and explicit benchmark separation are implemented; a universal count cap for arbitrary bursts is deferred as described above. None of these tests closes their broad release/real-rig acceptance.

Next evidence: candidate consent/permission/export and setup/VoiceOver walkthrough; two actual inputs, delivered formats/full admission fingerprint and required soak; affected-build lag logs, before/during/after CPU/memory/thermal and receiver observations. Physical presentation latency needs receiving-output measurement. Privacy retention/disclosure/Store choices and all Director/hardware/voice gates remain open. No merge to main.
