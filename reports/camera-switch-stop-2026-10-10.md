# Camera switch Stop ownership

10 October 2026. Branch codex/alfie-quality-sprint-2026-10-04; unit base 0c3d573ee120b68a93ef965254b691da35ee07d0. [CAMERA-SWITCH-STOP](https://trello.com/c/G9eMDFpv), parents [DEVICES](https://trello.com/c/F96mnFgL) and [CHANNEL-CMD](https://trello.com/c/f3cIWbfc).

## Result

restartWithCamera stopped a live channel and slept500ms, then selected/restarted without checking lifecycle ownership. The deterministic baseline proved channel Stop, show Stop, removal of Preview, a newer selection, cancelled Task and synchronous Stop from isRunning/selectedCamera observers could lose to that continuation.

A separate cameraSwitchRevision retires selection intentions on Start, Stop and new selection. The switch expects only its own internal Stop increment, checks cancellation/revision after the stop delay and after selection publication, and starts only if still current. A reentrant Stop cannot be absorbed as the switch's own revision. Stopped selection still changes preference without starting capture or retiring a running clip's source; ordinary live switch restarts exactly once. Source-generation, Start/admission, output standard and routing policies are unchanged.

DEBUG-only pause/start seams keep the production500ms delay and startCapture default, while tests use a noncooperative suspended continuation and a restart spy. Seven new Swift Testing definitions/nine runs: three Stop contexts, newer choice, cancellation, two publication reentrancy cases, healthy switch and stopped selection. These tests access no camera authorization/configuration/start.

## Exact verification

| Bundle under /private/tmp | Passed definitions | Failed definitions | Skipped | Passed runs | Failed runs |
| --- | ---: | ---: | ---: | ---: | ---: |
| alfie-oct10-switch-baseline.xcresult | 2 | 5 | 0 | 2 | 7 |
| alfie-oct10-switch-targeted.xcresult | 56 | 0 | 1 | 63 | 0 |
| alfie-oct10-switch-full.xcresult | 516 | 0 | 5 | 704 | 0 |

Targeted nonzero suites: CameraSwitchLifecycleTests7/9, CaptureDeviceRegistryTests12/12, ChannelCommandTests11/11, ReadinessEvaluationTests9/14 (one consented-data skip), ProgramTakeTests17/17. Authoritative xcresulttool summary/tree counts; argument runs replace parent definitions. Full skips remain accelerated stress, cadence study, clock-window study, consented-folder readiness and two-real-webcam test.

xcodebuild test uses CinematicCoreMacOS project/scheme, platform=macOS, parallel-testing-enabled NO, CODE_SIGNING_ALLOWED=NO, derivedDataPath /private/tmp/alfie-quality-sprint-dd. Baseline selects CameraSwitchLifecycleTests; targeted selects suites above; full selects CinematicCoreMacOSTests. Logs use bundle basename+.log. Xcode26.2(17C52), arm64 M4Pro, macOS26.6.2(25G83). git diff --check passed.

## Remaining acceptance

Synthetic lifecycle/observer tests only. No actual live switch, reconnect, external consumer, physical latency, privacy or release qualification. Parent device/channel acceptance remains open; child Human Review, not Done. Main checkout preserved, no main merge.
