# Clip source retirement

10 October 2026. Branch `codex/alfie-quality-sprint-2026-10-04`; unit base `00fef71a2d32f0ee206e4c02421836c7026af27d`. [CLIP-RETIREMENT](https://trello.com/c/AGbc6NFC), parents [CAPTURE](https://trello.com/c/Ed2ctBWc), [DEVICES](https://trello.com/c/F96mnFgL), [TAKE](https://trello.com/c/4ryww7PK). Fresh origin/main remains `a89644b865e31d179ab9bee5f41fe25b760d2f34`; primary checkout artifacts/documents preserved. No merge.

## Result

Natural EOF or decoder completion stopped clip playback but retained its source generation and prepared frame. The baseline actual six-frame synthetic decoder/render test froze freshness at the ended frame and proved Take committed Preview B, changed the route and sent the ended buffer. The repair increments captureGeneration and clears latestRenderedFrame before stopping the channel. Existing source/detection generation checks reject retired work, and repeated or superseded completions cannot retire a newer source. Ordinary Start, manual Take and routing policy stay intact.

CameraManager gains a DEBUG-only completion seam. ReadinessEvaluationTests adds actual natural EOF plus current EOF/cancel/failure and stale replacement cases (three definitions, seven runs), using an in-memory sink. Its existing public missing-file decoder test also now checks retirement. Tests prove A keeps running and its revisions/route are unchanged by B ending; fresh replacement Preview remains Take-eligible.

## Exact verification

| Bundle under /private/tmp | Passed definitions | Failed definitions | Skipped | Passed runs | Failed runs |
| --- | ---: | ---: | ---: | ---: | ---: |
| alfie-oct10-clip-baseline.xcresult | 7 | 2 | 1 | 10 | 4 |
| alfie-oct10-clip-targeted.xcresult | 40 | 0 | 1 | 45 | 0 |
| alfie-oct10-clip-full.xcresult | 509 | 0 | 5 | 695 | 0 |

Baseline is the previous behavior plus test seam/regressions. Targeted additionally checks actual decoder-failure retirement. Targeted suites: ReadinessEvaluationTests (9/14 passed, one consented-data skip), ProgramTakeTests (17/17), CaptureDeviceRegistryTests (12/12), PipelineLifecycleTests (2/2). Counts read from xcresulttool summary and tests tree; argument runs replace their parent definition. Full five skips: accelerated stress, cadence study, clock-window study, consented-folder readiness and two-real-webcam test. No sums across builds.

All builds use xcodebuild test, CinematicCoreMacOS project/scheme, platform=macOS, parallel-testing-enabled NO, CODE_SIGNING_ALLOWED=NO, derivedDataPath /private/tmp/alfie-quality-sprint-dd. Targeted suite selectors above; full selects only CinematicCoreMacOSTests. Logs use each bundle basename plus .log. Xcode26.2(17C52), arm64 M4Pro, macOS26.6.2(25G83). git diff --check passed.

## Remaining acceptance

Synthetic clip pixels, fake output and lifecycle tests establish source retirement only. No camera capture, physical receiver, end-to-end latency, privacy, real-rig or release qualification. Broad parent acceptance and real-rig gates remain open; child goes to Human Review, not Done.
