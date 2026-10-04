# Isolated voice transcript identity repair

4 October 2026. Card: https://trello.com/c/ozErn1Oq, child of [VOICE-TOKENS](https://trello.com/c/owpu13qI). Source base `31822f6` (documentation-only successor to runtime base `e7a32dd`). This is a text-only adapter repair; no microphone, recognizer, audio retention, entitlement, UI or running-app dispatch was added.

## Verified gap and change

Before this repair, `SpeechFinalTranscript.id` and `beginUtterance(id:world:)` accepted caller-chosen Strings. Starts, pending commands and recent IDs were bounded, but eviction allowed an old String to be used for a new start. A delayed old final could then remove the fresh start token and pass its new world/epoch validation. The foundation handoff documented the source-unique-ID requirement; the adapter did not enforce it. This was a verified source-level alias path in the isolated adapter, not evidence of an acoustic or running-app effect.

`beginUtterance(world:)` now mints an opaque `VoiceUtteranceID` and returns it on the start token. The identity combines a fresh private UUID namespace for each adapter with a checked UInt64 sequence. Its constructor is file-private; callers cannot inject a production namespace, choose an ID or reset the sequence. Final transcripts, pending values and bound commands carry that identity. UInt64.max is issued at most once; exhaustion then returns `invalidToken` rather than wrapping. The DEBUG-only initializer can start a new adapter near exhaustion and still creates a fresh namespace.

No unbounded tombstones were added. Starts, pending commands and recent IDs remain limited to `capacity` each. Recent duplicate finals retain `duplicateUtterance`; after history eviction, the same old identity receives `missingUtteranceStart` and cannot consume a newer start. Adapter replacement uses a fresh namespace even when the show snapshot and counter origin match.

The finite grammar, confidence/age thresholds, Preview-only target policy, world/session/role/source validation, manual/Wide/Take/mute/Stop invalidation and command mappings are unchanged. Track lock remains checked at final acceptance; its separate dispatch-boundary repair is outside this commit. All executable adapter callers were confined to `SpeechCommandTests.swift`, so only those callers needed migration. The integration handoff now requires one start call per utterance and preservation of its returned identity across final callbacks; recognizer-local names never authorize another start.

## Synthetic verification

New Swift Testing cases exercise a delayed final after capacity-one dedupe eviction while a fresh start is live; show-session change with and without Stop; adapter replacement at identical snapshot/counter origin; low-confidence and grammar-refused finals before and after eviction; checked sequence exhaustion; and bounded mixed start/pending/recent state with 64 distinct issued identities. Existing grammar, false-action text corpus, one-shot command, intervention and stale-world fixtures remain in the target.

Both runs passed on the first build at the same Swift source snapshot. Commands use the macOS destination, `CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled NO`, and derived data `/private/tmp/alfie-quality-sprint-dd`.

| Run / exact selector | Bundle | Passed definitions | Passed case runs | Failed | Skipped definitions / runs |
| --- | --- | ---: | ---: | ---: | ---: |
| Targeted `SpeechCommandTests` | `/private/tmp/alfie-followup-voice-targeted.xcresult` | 12 | 14 | 0 | 0 / 0 |
| Complete `CinematicCoreMacOSTests` | `/private/tmp/alfie-followup-voice-full.xcresult` | 473 | 608 | 0 | 5 / 5 |

Counts were read from `xcrun xcresulttool get test-results summary/tests --path BUNDLE --format json`. The targeted tree contains two parameterized definitions / four argument runs: 12−2+4=14. The full tree contains 25 parameterized definitions / 160 argument runs: 473−25+160=608. The five default skips are the opt-in accelerated instrumentation stress, opt-in cadence-realistic instrumentation benchmark, opt-in controlled instrumentation investigation, unconfigured consented readiness folder, and opt-in real two-webcam test. No opt-in or real-camera measurement is inferred from these skips.

Logs are `/private/tmp/alfie-followup-voice-targeted.log` and `/private/tmp/alfie-followup-voice-full.log`. Saved authoritative exports are `/private/tmp/alfie-followup-voice-targeted.xcresult-summary.json`, `/private/tmp/alfie-followup-voice-targeted.xcresult-tests.json`, `/private/tmp/alfie-followup-voice-full.xcresult-summary.json`, and `/private/tmp/alfie-followup-voice-full.xcresult-tests.json`. `git diff --check` passed.

These synthetic tests do not qualify acoustic false-action rate, recognition timing, microphone/privacy behavior, physical camera output or atomic running-app effect integration. V1–V5 product decisions and actual utterance/effect hooks remain open. No product decision was required to remove the caller-ID alias path.
