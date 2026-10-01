# DEGRADE / READINESS-STUDY validation repair

1 October 2026. Isolated review candidate. No runtime integration, real-dataset evaluation, release qualification, merge, PR or Trello writes.

## Source and delivery

Base: freshly fetched `origin/r2/engine`, `7691e6e1046ab40bca9b4e27a80e0b500f409c83`. Branch: `codex/readiness-degrade-validation`. Implementation commit: `64ec925267d4bf01461a9256d8fb348b5872e25e`. This report is a subsequent documentation commit.

Imported only DegradePolicy, its tests, ReadinessEvaluationTests and the study protocol from reviewed `origin/r2/sol` at `8b4b284dbd014c3614c36e6e7aed41b05c3e0997`. Existing engine files and concurrent work were preserved.

## Repairs

[DEGRADE](https://trello.com/c/hBhrDnIQ): explicit threshold initialization is failable. Nonfinite/out-of-domain thresholds and nonpositive window counts reject rather than silently clamp. Existing default initialization retains old provisional study values, not approved production budgets. Invalid/negative candidate age blocks the additional Take gate. Invalid workload measurements block that gate and cannot count as healthy recovery. CPU/deadline fractions must be normalized, finite and within [0, 1]; render ages must be finite and nonnegative. Future adapters must supply those domains. Existing manual Take validation remains authoritative; this pure policy cannot grant Take or change Program.

[READINESS-STUDY](https://trello.com/c/arj1CKTN): supplied annotations must be nonempty and finite, with nonnegative timestamps, no duplicate timestamps, and coordinates in [0, 1]. Points sort by time; equal-distance ties select the earlier point. Annotated misses cannot fall back to the tallest person. Missing annotation files are labelled `annotated=no`. Missing dataset configuration explicitly skips; partial/invalid configuration and empty clip folders fail. The independent synthetic decoder/CSV check remains synthetic. No identity-loss or annotation-coverage thresholds were invented.

No app call sites reference DegradePolicy. Capture, output, orchestration, UI, hardware, speech, project settings, entitlements and build scripts were not edited. Director decision approvals remain unchanged.

## Exact validation

Commands run in the managed worktree:

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests/DegradePolicyTests \
  -only-testing:CinematicCoreMacOSTests/ReadinessEvaluationTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-ticket-validation-dd \
  -resultBundlePath /private/tmp/alfie-ticket-targeted-final.xcresult

xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/alfie-ticket-validation-dd \
  -resultBundlePath /private/tmp/alfie-ticket-full.xcresult

# Full recheck: same command, plus -parallel-testing-enabled NO,
# with /private/tmp/alfie-ticket-full-recheck.xcresult as result bundle.

xcrun xcresulttool get test-results summary --path RESULT_BUNDLE --format json
xcrun xcresulttool get test-results tests --path RESULT_BUNDLE --format json
```

Authoritative xcresult summary/tree counts, excluding repeated console lines:

| Run | Passed definitions | Failed definitions | Skipped definitions | Passed case runs |
| --- | ---: | ---: | ---: | ---: |
| Targeted final | 14 | 0 | 1 | 17 |
| Initial full, default parallel configuration | 423 | 1 | 2 | 494 |
| Full recheck, one host | 424 | 0 | 2 | 495 |

Targeted: one parameterized definition, four argument runs; 14 − 1 + 4 = 17 passed runs. Full: 15 parameterized definitions, 86 argument runs; 424 − 15 + 86 = 495 final passed runs. Nonparameterized definitions count once. Device/configuration counts agree. Final total definitions: 426 (424 passed, two skipped).

Skips: `RealCameraTests/twoWebcamsRenderPicturesAndBJoinsWithoutCrashing()` and unconfigured `ReadinessEvaluationTests/replayConsentedFolderWhenConfigured()`. Neither is a qualification pass. Numeric/annotation fixtures and decoder check are synthetic; no consented clips were evaluated.

Preserved failures/limitations:

- `/private/tmp/alfie-ticket-targeted.xcresult`: first build failed on missing inner `try` in new Swift Testing assertions; corrected before targeted final. No tests ran in that failed build.
- `/private/tmp/alfie-ticket-full.xcresult`: existing `ProgramOutputMetricsTests/perFrameInstrumentationCostIsSmall()` measured 269.2904834 µs/frame against its unchanged 250 µs limit. Output and benchmark code were untouched. Full recheck passed without source changes using one host. This is configuration-sensitive timing evidence, not a proven root cause or production performance guarantee.
- `/private/tmp/alfie-ticket-benchmark-recheck.xcresult`: an attempted isolated selector selected zero tests (`result: unknown`); excluded from pass counts. The subsequent complete suite covered the benchmark.
- Logs have corresponding `/private/tmp/alfie-ticket-{targeted,targeted-final,full,full-recheck,benchmark-recheck}.log` names. Summary/tree JSON uses `/private/tmp/alfie-ticket-{targeted,full,full-recheck}-{summary,tests}.json`.

## Remaining acceptance

DEGRADE needs calibrated budgets and readiness bounds, runtime scheduler/status integration and real sustained-load/recovery testing. READINESS-STUDY needs a consented dataset, frozen train/held-out split, physical-person review, error denominators, abstention and tradeoffs. Study status remains “No real dataset evaluated.” Neither whole ticket is complete from this repair.

Setup admission semantics, stale operator documentation, R1 and two-input R2 real-camera/downstream-output qualification remain separate work. Director integration, automatic Take, motion and microphone gates remain closed.
