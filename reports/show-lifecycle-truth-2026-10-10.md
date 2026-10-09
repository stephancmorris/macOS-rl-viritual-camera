# Aggregate show lifecycle truth — 10 October 2026

Status: implemented and verified for Human Review. Parents: [SHOW-SETUP](https://trello.com/c/ztw0PPkU), [CONSOLE](https://trello.com/c/Ck2EP2Yg), [CHANNEL](https://trello.com/c/4sFQx8lb). Child: [SHOW-LIFECYCLE-TRUTH](https://trello.com/c/h6sgju5S). Unit base: f662620ed0e860e5954b9186948eeb126023890e.

## Problem and resulting behavior

The app's console selection, setup lifecycle and Stop menu used Camera A's state. After an explicit Take to B, stopping now-Preview A exposed stopped setup even though Program B and the output continued. Setup could then change devices, standard or output and request another Start. B starting while A was stopped also left setup unlocked.

ShowCoordinator now caches each registered channel's running/starting publication payload before publishing one aggregate activity snapshot. Aggregate getters use that plain current truth, avoiding synchronous @Published willSet getter lag. Reentrant publication settles the snapshot after observers stop or replace another channel. Removal checks source-instance identity after Stop and unregisters retired subscriptions; late old instances cannot own replacement activity.

ContentView observes the optional show and selects live Stage Multiview while any channel runs. Starting-only shows retain setup with its mutations locked. LiveShowSetupModel guards actual setters and both Start methods using aggregate activity, including a second check at each deferred Start body before preparation or device selection. The application Stop menu is enabled while any channel runs or starts. Stop all restores stopped setup behavior. Stage/Webcam presentation, explicit Start/Take, output routing and preflight remain the existing policy.

This does not wire the separate format-switch helper into Settings or choose new Settings control-target authority. That integration gap remains in the overall status audit.

## Verification

Ten new Swift Testing definitions execute 15 cases through actual ShowCoordinator, ProgramRouter, ProgramOutputManager, LiveShowSetupModel, ContentView's production resolver and its observation bridge. Fixtures use fake running/starting state, an in-memory sink, isolated defaults, fake device metadata and a Start callback counter. No device authorization/configuration/start, microphone, physical receiver or installation occurs.

Coverage includes Take B then Stop A, B starting only, newly created setup while B active, single-A stopped/starting/running and profile/flag behavior, actual guarded setup actions, Stop all, deferred Start overtaken by B starting, removal/new-show preparation, retired instances and reentrant observer replacement/Stop/mutation attempts.

| Run | Passed definitions | Failed definitions | Skipped definitions | Passed case runs | Failed case runs | Skipped case runs |
|---|---:|---:|---:|---:|---:|---:|
| Before source fix, new lifecycle suite | 2 | 8 | 0 | 4 | 11 | 0 |
| Targeted after fix | 58 | 0 | 0 | 70 | 0 | 0 |
| Complete macOS test target | 534 | 0 | 5 | 749 | 0 | 5 |

Targeted: ShowLifecycleAuthorityTests (10/15), ShowSetupTests (25/32), ConsolePresentationTests (3/3), ProgramTakeTests (17/17), SingleCameraConsoleTests (3/3). Counts read from xcresult summary/test tree, parameterized argument children counted instead of definition parents. Source fingerprint: `99acd79a34675766421c00dfe5b3e292ee021628556520356abc633c188139c7`.

Bundles: `/private/tmp/alfie-oct10-show-baseline.xcresult`, `/private/tmp/alfie-oct10-show-targeted.xcresult`, `/private/tmp/alfie-oct10-show-full.xcresult`. Matching logs, summary/tree exports and counts are retained temporarily. Full command: xcodebuild test, CinematicCoreMacOS project/scheme, platform=macOS, parallel-testing-enabled NO, only-testing:CinematicCoreMacOSTests, CODE_SIGNING_ALLOWED=NO, derivedDataPath /private/tmp/alfie-quality-sprint-dd. Xcode 26.2 (17C52), arm64 M4 Pro, macOS 26.6.2 (25G83).

Five full-suite skips remain opt-in instrumentation stress, cadence benchmark, clock-window comparison, consented readiness folder and two-real-webcam integration. They are not qualification passes. Independent peer review found no material defect in the intended aggregate repair; it did not execute builds. Root ran the above tests and git diff --check. Diagnostics Python suite also passed all 14 definitions at this final source.

## Open acceptance

Rehearse real A/B Take, Preview Stop/source EOF/loss and B startup at the final installed candidate; inspect the actual receiving Program output, minimum window and VoiceOver behavior. These synthetic regressions establish source authority and app presentation decisions; they do not establish physical camera/output/latency, privacy or release qualification. Child stays open in Human Review; broad parent acceptance remains unchecked. Primary checkout preserved; no merge to main.
