# Track lock at the isolated voice dispatch boundary

4 October 2026. [VOICE-LOCK](https://trello.com/c/Yagzoy0P), parent [VOICE-TOKENS](https://trello.com/c/owpu13qI). Branch `codex/alfie-quality-sprint-2026-10-04`, source baseline `660a585e35f616071b2110ccd6155cdde38be65c`.

## Verified gap and fix

Final transcript acceptance checked the Preview subject lock for Track, but `prepareDispatch` did not repeat that check. A pending Track could therefore yield a bound autoTracking command after the subject lock was lost between the two calls. This is an isolated text-adapter defect; no microphone or running-app dispatch exists.

Tests were added before changing the adapter. Both Preview A and Preview B cases failed against the unchanged source, while the Program subject stayed locked. The baseline passed all existing voice tests and all seven new non-Track controls. The expected-failing result is retained separately.

The dispatch boundary now checks `world.subjectLocked(value.target)` only for Track, after the existing provenance, expiry, role/source checks and one-shot pending removal. It returns the existing `subjectNotLocked` refusal and “Pick a subject.” message. A refused pending command stays consumed even if the lock returns; a fresh locked utterance remains eligible. Other intents still require no subject lock.

Changed files: `VoiceCommandAdapter.swift` (three added lines), `SpeechCommandTests.swift` (two parameterized definitions and a default-preserving helper argument), and this report. Independent read-only review found no material issue. Grammar, mappings, utterance identity, source/role/intervention rules and the coordinator are unchanged.

## Verification

Xcode 26.2 (17C52), arm64 macOS 26.6.2 (25G83), serial one-host Debug tests with `CODE_SIGNING_ALLOWED=NO`. Exact definitions and Arguments case runs were read from xcresult summary/tests using `/private/tmp/alfie-xcresult-counts.py`; exports and counts JSON are preserved beside each bundle.

| Run | Definitions passed / failed / skipped | Case runs passed / failed / skipped | Bundle |
| --- | ---: | ---: | --- |
| Unchanged adapter, regression baseline | 13 / 1 / 0 | 21 / 2 / 0 | `/private/tmp/alfie-followup-track-baseline.xcresult` |
| Fixed SpeechCommandTests | 14 / 0 / 0 | 23 / 0 / 0 | `/private/tmp/alfie-followup-track-targeted.xcresult` |
| Fixed complete unit target | 479 / 0 / 5 | 625 / 0 / 5 | `/private/tmp/alfie-followup-track-full.xcresult` |

The targeted tree has four parameterized definitions with thirteen argument runs: 14−4+13=23. Tests cover lock loss on each bound Preview while Program stays locked, refusal consumption after restoration, fresh locked Track, and detect/manual/pan/Return to Wide/waist-up/push-in/pull-out without any lock. Full-target skips remain the three opt-in instrumentation studies, absent consented readiness clips and the opt-in real two-webcam test. They are not qualification passes. Baseline exit65 is expected; fixed targeted/full exit0 and report TEST SUCCEEDED. `git diff --check` passes.

Reproduction, using fresh bundle paths:

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -parallel-testing-enabled NO -only-testing:CinematicCoreMacOSTests/SpeechCommandTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd \
  -resultBundlePath /private/tmp/alfie-followup-track-targeted.xcresult
```

The full command substitutes `-only-testing:CinematicCoreMacOSTests` and its full bundle path. Logs have matching baseline/targeted/full names under `/private/tmp`.

This closes the existing isolated Track rule at its bound-command boundary. Actual onset/snapshot hooks and a synchronous coordinator check through the final camera effect remain future integration work, alongside the open recognizer/privacy decisions. No automatic Take, Director integration, microphone, entitlement or physical control was added. Synthetic text validation does not qualify recognition, live identity, latency or privacy.
