# Readiness evidence median

10 October 2026. Branch codex/alfie-quality-sprint-2026-10-04; unit base 9019bce5ac1f60a35c922063c0d48826ba86b712. [READINESS-MEDIAN](https://trello.com/c/WH5u0x7F), parent [READINESS-STUDY](https://trello.com/c/arj1CKTN).

The offline readiness harness sorted selected source-pixel subject heights and took heights[count/2], reporting the upper middle sample for even populations. Actual externally supplied consented clips can have any selected-frame count. evaluate() now uses an extracted evidence-row builder which averages the middle two samples for even counts. Odd populations and empty/unknown median remain unchanged, as do target selection, annotations, denominators, identity proxy and CSV schema.

Three new Swift Testing fixtures assert both measurement and exact CSV for unsorted even [300,100]→200, odd [300,100,200]→200 and no selected subject→empty field. The baseline extraction preserves old arithmetic and fails only the even fixture. Existing synthetic decoder and clip lifecycle tests remain independent.

| Bundle under /private/tmp | Passed definitions | Failed definitions | Skipped | Passed runs | Failed runs |
| --- | ---: | ---: | ---: | ---: | ---: |
| alfie-oct10-median-baseline.xcresult | 11 | 1 | 1 | 16 | 1 |
| alfie-oct10-median-targeted.xcresult | 12 | 0 | 1 | 17 | 0 |
| alfie-oct10-median-full.xcresult | 519 | 0 | 5 | 707 | 0 |

Counts read from xcresulttool summary/tests, with argument runs replacing definition parents. Targeted ReadinessEvaluationTests includes one absent-consented-folder skip. Full five skips remain accelerated stress, cadence study, clock-window study, consented-folder readiness and two-real-webcam test. xcodebuild test uses CinematicCoreMacOS project/scheme, platform=macOS, parallel-testing-enabled NO, CODE_SIGNING_ALLOWED=NO, derivedDataPath /private/tmp/alfie-quality-sprint-dd; targeted selects ReadinessEvaluationTests, full selects CinematicCoreMacOSTests. Matching .log files retain console output. Xcode26.2(17C52), arm64 M4Pro, macOS26.6.2(25G83). git diff --check passed.

Harness arithmetic/CSV correctness only. No consented dataset evaluated, readiness threshold calibrated, real-camera identity recovery, physical latency or editorial qualification. Broad study acceptance remains open. Separate pushed commit, Human Review, primary checkout preserved, no main merge.
