# Instrumentation benchmark investigation

2 October 2026. Base `7691e6e1046ab40bca9b4e27a80e0b500f409c83`; production and existing benchmark code unchanged. Synthetic fake-output investigation; no capture, receiver, physical latency or editorial qualification.

## Measured contributor

The existing `DiagnosticsLogTests.swift:230` benchmark runs 5,000 source frames with timestamps index/50 (100 source seconds) in a short wall-clock loop. Its four `recordLatency` calls default to CACurrentMediaTime. Five-second expiry therefore retains nearly the whole accelerated batch rather than a normal five-second 50 fps window.

`ProgramOutputManager.recordLatency` copies the stored array into a local, appends, scans it with removeAll and assigns it back for each sample. Copy-on-write/allocation and repeated scans are plausible cost mechanisms; no allocation profile was taken. The measurable contributor is retained sample count and workload shape. Coalesced publish/aggregate time and wall-clock scheduling add variance. The benchmark is a Debug aggregate-path smoke bound, not an isolated diagnostics-only production budget.

## Controlled comparison

New test-only InstrumentationInvestigationTests uses the unchanged APIs with a 16×16 buffer and accepting fake sink. Three repetitions, 500/1,000/2,000/5,000 frames, wall/source timestamp variants, alternating mode order. All runs in one host. Wall variant uses one current timestamp per frame for the four calls (near-original workload, not identical four default timestamp reads); source variant explicitly supplies index/50 so retention advances at 50 fps. Reflection observes retained private sample counts after timing, not in the measured loop. No artificial performance assertion or changed 250 µs bound was added.

| Frames | Wall median µs/frame (range) | Retained wall samples | Source median µs/frame (range) | Retained source samples |
| ---: | --- | ---: | --- | ---: |
| 500 | 43.85 (41.93–44.53) | 2,000 | 60.69 (58.05–61.56) | 1,004 |
| 1,000 | 77.69 (75.55–81.87) | 4,000 | 82.80 (81.03–91.82) | 1,004 |
| 2,000 | 141.14 (140.00–148.98) | 8,000 | 99.48 (96.88–100.92) | 1,004 |
| 5,000 | 334.96 (327.58–337.44) | 20,000 | 109.70 (107.46–109.98) | 1,004 |

Thermal state was nominal in all 24 samples. Raw synthetic rows, including wall/CPU time and low-power flag, are preserved in [instrumentation-study-synthetic.json](instrumentation-study-synthetic.json). Source mode remains accelerated, not a real-time 50 fps capture or hard performance guarantee. Both modes share input/send calls; no diagnostic CSV session is opened by this fixture. Its source-clock variant is investigation-only, not a recommendation to change production clock domains.

Earlier evidence on the degradation/readiness candidate: default full suite failed the existing 250 µs assertion at 269.2904834 µs/frame; full one-host recheck passed. Source was unchanged between those runs. The controlled study reproduces an over-bound batch even in one host, so parallelism alone does not explain the issue. Exact run-to-run attribution (host scheduling, arrays, warm-up, thermal) requires profiling/more controlled traces. Live intermittent beta lag remains unmeasured.

## Reproduction and result bundles

```sh
TEST_RUNNER_ALFIE_INSTRUMENTATION_STUDY=1 xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:CinematicCoreMacOSTests/InstrumentationInvestigationTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-operator-audit-dd \
  -resultBundlePath /private/tmp/alfie-instrumentation-study-final.xcresult
```

Final bundle: one passed definition/run, zero failures/skips; read authoritative summary/tree, not console duplication. Initial `/private/tmp/alfie-instrumentation-study.xcresult` failed to build on investigation-only Mirror.Children.last use; converted to Array before the final run. JSON was captured at the test host temp directory and copied without editing to the report. The fixture prints JSON/path to captured test output; it does not upload it.

## Follow-up

Separate an accelerated batch-growth stress test from a cadence-realistic instrumentation benchmark with explicit warm-up, repetitions, environment and clock semantics. Profile array scanning/copy costs before choosing a storage change. Keep original failures visible; do not raise the bound to manufacture a pass. Do not add a live reset or optimize production based solely on this synthetic result.

The final harness is opt-in via ALFIE_INSTRUMENTATION_STUDY=1 in the test host (TEST_RUNNER_ prefix supplied to xcodebuild). Verified opt-in bundle `/private/tmp/alfie-instrumentation-study-optin.xcresult`: one passed definition/run, zero failures/skips. Default audit bundle `/private/tmp/alfie-audit-default-tests.xcresult`: study explicitly skipped. The independent opt-in repeat raw data is [instrumentation-study-optin-synthetic.json](instrumentation-study-optin-synthetic.json); the table above retains the original controlled measurement cohort.
