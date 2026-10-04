# Independent simulated Director effect audit

4 October 2026. Follow-up [AD-EFFECT-AUDIT](https://trello.com/c/7c873pMF), linked to [AD-REPLAY-TRUTH](https://trello.com/c/X0OTOpra). Baseline `648be4601afbea561f69448d21c654fd08b9db85`, branch `codex/alfie-quality-sprint-2026-10-04`. This repair changes only the isolated replay, its tests and this report. The running Director remains unwired; this is synthetic accounting evidence.

## Verified gap and repair

The earlier independent audit recorded authority, roles, route, channel revisions, policy/nomination and lease facts, but omitted raw evidence and the current request UUID. Thus unavailable evidence and replaced/retired requests could be prevented by the preparation validator without being independently classified at the simulated sink.

`CommittedEffect` now captures candidate/current request UUIDs and raw authority evidence availability, subject presence, observation timestamp, confidence, movement, maximum evidence age and minimum confidence. It reads `preparation.request`, rather than the replay's mirrored `activeRequest`, before `commit` or `discard` clears state and before channel revision mutation. The audit recomputes evidence validity separately; it does not call the validators or reuse their derived `evidenceAvailable` value.

Evidence must be present and available, finite, within the supplied age/confidence domains and fresh at application. Age and confidence cutoffs are inclusive. Movement must be finite and nonnegative; moving preparation remains allowed, with editorial readiness still separate. The timestamp contract matches the existing relative freshness expression: no new absolute nonnegative observation-timestamp requirement was added; replay event clocks already reject negative times. Thresholds remain caller-supplied and unapproved as real-world calibration.

A missing or different authoritative request UUID independently produces `requestReplaced`; invalid or unavailable evidence produces `evidenceUnavailable`. The report adds per-reason committed-effect counts. One mutated effect increments `staleEffectsCommitted` once even when several reasons apply. Rejected attempts remain a separate denominator.

## Fault injection and boundaries

`SimulatedExecutor.guarded` is the default and preserves existing replay behavior. The explicitly selected `faultyPreviewMutation` bypasses the final preparation gate solely to demonstrate an actual stale simulated mutation reaching the independent audit. It still refuses targets that are Program or no longer Preview, and creates no acknowledgement receipt or composition. The two named synthetic request events retire or replace the authoritative request while retaining the already queued callback. No Program route, automatic Take, hardware, microphone, entitlement or production adapter changed.

Tests pair guarded and faulty execution for absent/nonfinite/stale evidence and global evidence gaps, plus retired and different request UUIDs. They prove a valid guarded commit is audited before its UUID is cleared, combined faults count one effect, duplicate/failed callbacks cannot inflate commits, and even the faulty executor cannot mutate a target that became Program. Direct raw-fact tests cover missing/future/nonfinite timestamps, confidence values and thresholds, movement, evidence age configuration and inclusive bounds. All Director cut counts remain zero.

## Validation

macOS arm64, scheme `CinematicCoreMacOS`, `CODE_SIGNING_ALLOWED=NO`, one host with `-parallel-testing-enabled NO`. Exact counts below were read from `xcresulttool` summaries and trees using `/private/tmp/alfie-xcresult-counts.py`, rather than console case lines.

| Run | Passed definitions | Passed case runs | Failed definitions / runs | Skipped definitions / runs | Bundle |
| --- | ---: | ---: | ---: | ---: | --- |
| Final three replay suites | 20 | 55 | 0 / 0 | 0 / 0 | `/private/tmp/alfie-followup-effect-targeted-final.xcresult` |
| Complete unit target | 467 | 600 | 0 / 0 | 5 / 5 | `/private/tmp/alfie-followup-effect-full.xcresult` |

The targeted run includes `DirectorReplayTests`, `DirectorEffectAuditTests` and `DirectorEffectFaultInjectionTests`. Its four parameterized definitions contain 39 argument runs: 20−4+39=55. Logs and summary/tree JSON retain the corresponding bundle names with `.log`, `-summary.json` and `-tests.json` suffixes. `git diff --check` passes.

The five full-target skips remain accelerated instrumentation stress, cadence instrumentation benchmark, opt-in instrumentation investigation, unconfigured consented readiness folder and real webcams. These skips provide no new performance or live-data evidence.

The initial bundle `/private/tmp/alfie-followup-effect-targeted.xcresult` is preserved: 19 passed definitions / 54 passed runs, one failed definition/run, zero skips. An existing backwards-lease test also made its observation timestamp future after evidence auditing was added. Its fixture now isolates lease expiry with fresh evidence, and a separate assertion retains the combined expiry/evidence failure. No failed run is included in the passing totals.

Reproduction:

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:CinematicCoreMacOSTests/DirectorReplayTests \
  -only-testing:CinematicCoreMacOSTests/DirectorEffectAuditTests \
  -only-testing:CinematicCoreMacOSTests/DirectorEffectFaultInjectionTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd \
  -resultBundlePath /private/tmp/alfie-followup-effect-targeted-final.xcresult
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -parallel-testing-enabled NO -only-testing:CinematicCoreMacOSTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd \
  -resultBundlePath /private/tmp/alfie-followup-effect-full.xcresult
python3 /private/tmp/alfie-xcresult-counts.py \
  /private/tmp/alfie-followup-effect-targeted-final.xcresult \
  /private/tmp/alfie-followup-effect-full.xcresult
```

Use fresh result-bundle paths when repeating these commands. Independent accounting for the two missing reasons is repaired; production effect serialization, real subject evidence, measured override latency, editorial qualification and Director product decisions remain open.
