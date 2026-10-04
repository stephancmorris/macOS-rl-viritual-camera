# Metrics window implementation and synthetic evidence

4 October 2026 (Australia/Sydney). Unit 3, parents https://trello.com/c/jiY5JFaH and https://trello.com/c/D6KPsTw4. Pre-change source: fresh `origin/main` `a89644b865e31d179ab9bee5f41fe25b760d2f34`; `recordLatency` remains identical after consent-boundary commit `bb7e692bd422aa1f41bb0889b58568475e54c560`. Implementation follows setup-truth commit `1bcb3d6`. Synthetic fake sink and standalone algorithm evidence only: no capture, receiver, physical presentation-latency, privacy or release qualification. Live intermittent beta lag remains unmeasured.

## Verified current source and pre-change reproduction

The current default 5,000-frame/250 µs test already supplies `index / 50` to its four compose/cropRender/mainActor/total latency calls. The older [instrumentation investigation](instrumentation-investigation.md) describes an earlier wall-clock form. The current opt-in study explicitly compares wall-clock and source-clock injection; production continues to use monotonic `CACurrentMediaTime`. The fake sink reports no xpcSend duration.

Root ran the unchanged app-host investigation serially before editing (`/private/tmp/alfie-quality-u3-baseline-study.xcresult`: one passed definition/run, zero failures/skips). Three repetitions per mode/size, nominal thermal, low power off. Raw rows are preserved unchanged in [app-host-before.json](metrics-window-evidence/app-host-before.json).

| Frames | Wall median µs/frame (range) | Retained wall | Source median µs/frame (range) | Retained source |
| ---: | --- | ---: | --- | ---: |
| 500 | 68.07 (66.96–75.41) | 2,000 | 94.39 (93.25–101.61) | 1,004 |
| 1,000 | 121.08 (120.71–131.57) | 4,000 | 133.41 (132.50–150.07) | 1,004 |
| 2,000 | 229.31 (226.93–230.99) | 8,000 | 157.35 (153.42–158.49) | 1,004 |
| 5,000 | 546.86 (543.08–548.86) | 20,000 | 173.37 (172.24–179.89) | 1,004 |

The existing default test also passed at 182.14 µs/frame over 5,000, row aggregation 0.011 ms in the preceding Unit 1 full run; its copied [benchmark text](metrics-window-evidence/default-benchmark-before.txt) is separate from the controlled comparison. Different fixtures/runs are not pooled into one measurement cohort.

## CPU and allocation profile before editing

The [standalone probe](metrics-window-evidence/baseline-probe.swift) faithfully copies the current method's raw accumulators, dictionary/local-array append, five-second `removeAll` expiry and reassignment. It supplies one timestamp/frame and four stage calls, omitting app actor/publish/input/send work. Apple Swift 6.2.3, `swiftc -g -Onone`, arm64 macOS; the same build flags are retained with the evidence. These algorithm-only costs are distinct from app-host timings.

Serialized, unprofiled 5,000-frame repetitions: wall median 753.90 µs/frame (749.88–761.26), retained 20,000; source median 216.58 µs/frame (215.98–220.23), retained 1,004. CPU time is recorded per repetition in [standalone-profile-before.json](metrics-window-evidence/standalone-profile-before.json).

A two-second `sample` CPU profile (1 ms sampling interval) attributed 1,498/1,514 stacks (98.9%) to `recordLatency`'s `removeAll(where:)` ancestry, including `firstIndex`, `_halfStablePartition` and generic Array subscript allocator work. Eleven stacks (0.7%) were at append/copy-on-write ancestry, including buffer copying and `memmove`. Thus repeated expiry scanning dominates this isolated Debug profile; copying exists but is a smaller sampled contributor.

The [malloc-family interposer](metrics-window-evidence/malloc-probe.c) counted actual malloc/calloc/realloc requests during the loop and sampled every 1,024th request, up to 64 backtraces. Representative [allocation and CPU stacks](metrics-window-evidence/standalone-profile-stacks.txt) repeatedly lead through Array subscript → `firstIndex` → `_halfStablePartition` → `removeAll(where:)` → `recordLatency`. Profiled source repetitions each requested approximately 27.86 million allocations/879.85 MB cumulative requested bytes; the latter two wall repetitions each requested 100.05 million/3.98 GB. These are cumulative allocation requests, **not resident footprint, peak memory, or app allocations**. The interposer changes allocator/timing behavior: its first wall repetition crossed five seconds and retained 15,544 rather than 20,000. All raw repetitions remain visible. Initial overlapping exploratory timings were excluded.

Instruments Allocations was attempted first. The launcher stalled with the probe suspended and no CPU activity; interrupt/terminate did not release it. Only those two temporary processes were force-stopped, and no usable Instruments trace was claimed. The independent CPU sample and allocator backtraces above succeeded before implementation.

## Window and clock contract

`LatencySampleWindow` is a per-stage FIFO ring owned by `ProgramOutputManager` on MainActor. Appends reuse slots, evict only the oldest expired entries, and resize geometrically. There is no per-append dictionary array copy or full-window predicate scan. Means are still reduced in chronological sample order at the existing publication cadence, using the same arithmetic as the original array reduce.

- Production timestamp default remains `CACurrentMediaTime`; no stage definition, clock domain, output standard, routing, duration acceptance, raw duration accumulator/counter behavior, or 0.5-second publication cadence changes.
- Every finite timestamp is admitted. Equal timestamps stay separate. A backwards timestamp starts a new epoch for that stage only. Nonfinite timestamps reject the window observation, while the existing clock-independent mainActor/total accumulators still count the call.
- On a stage append at time `t`, samples with timestamp `< t − 5` expire. Exactly five seconds old remains. Other stages and idle publication do not acquire new expiry behavior.
- If a stage's successive timestamps are separated by at least Δ seconds, retention is bounded by `floor(5 / Δ) + 1`. Uniform 50/59.94/60 Hz fixtures therefore retain at most 251/300/301 samples per stage (59.94 uses exactly 60000/1001). This is an explicit arrival-density contract, not a claim that real scheduling enforces minimum spacing.
- Backing capacity and retained count differ. The ring starts at 64 slots, grows by doubling, shrinks when at most one-quarter full, and releases oversized storage on a backwards epoch reset. After a large burst fully expires, it returns to 64 slots; fresh uniform 50/60 Hz fixtures need at most 256/512. General capacity is bounded by `max(64, 4 × retainedCount)` after appending, including prior-burst transitions.

An arbitrary burst can contain arbitrarily many distinct observations inside five seconds. A universal hard count cap would discard observations or change exact expiry/means. This implementation preserves the requested exact average and bounds retention under the stated time-and-arrival-density contract; a universal burst cap remains an explicit tradeoff requiring a separate decision.

## Tests and benchmark separation

Eight deterministic Swift Testing definitions cover inclusive cutoff, irregular clocks against a simple ordered-array reference, FIFO wrap/growth/eviction, uniform 50/59.94/60 Hz bounds, same-timestamp lossless bursts and released capacity, backwards epochs, nonfinite timestamp rejection, per-stage isolation, unchanged raw duration counters, no per-sample publication, ordered stage means and Start reset. Existing synthetic pipeline/counter tests remain included.

The existing 5,000-frame source-clock workload is now explicitly opt-in accelerated stress (`ALFIE_METRICS_STRESS=1`). Its **250 µs assertion is unchanged**. The opt-in wall/source investigation (`ALFIE_INSTRUMENTATION_STUDY=1`) remains available, with scalar retained-count observation after timing rather than reflection tied to the old array representation.

The separate nominal 50 Hz fixture (`ALFIE_METRICS_CADENCE=1`) waits at least 20 ms between invocations, warms up one complete five-second clock window, then records three 250-frame windows. Actual invocation rate is recorded. Instrumentation work excludes scheduled waits; process CPU includes fixture scheduling and the manager's normal coalesced refresh/watchdog during each window. These remain synthetic instrumentation measurements, without camera/output-delivery or presentation claims. Cadence is run in its own test-host invocation so accelerated work cannot contaminate its process CPU.

## Verification evidence

Initial targeted bundle `/private/tmp/alfie-quality-u3-targeted.xcresult` failed to build with `Cannot find type 'LatencySampleWindow' in scope` in CinematicCoreExtension. Authoritative summary: zero test definitions/runs, result unknown. The extension already compiles ProgramOutputManager from the app folder through explicit membership; the new helper was added alongside those existing shared sources in project.pbxproj. No entitlement or build-setting edits were needed. The failed bundle/log remain preserved.

Final targeted bundle `/private/tmp/alfie-quality-u3-targeted-final.xcresult`, `CODE_SIGNING_ALLOWED=NO`, serialized runner: **21 definitions/case leaves: 20 passed, zero failed, one skipped**. No parameter expansion; the sole skip is the deliberately separate cadence benchmark. All eight deterministic window definitions passed. The unchanged **250 µs** accelerated assertion was explicitly enabled and passed at **19.27 µs/frame**, row aggregation 0.008 ms; raw [stress text](metrics-window-evidence/accelerated-stress-after.txt) is preserved.

The explicitly enabled post-change wall/source study also passed. At 5,000 frames, wall median **19.91 µs/frame** (19.89–19.91), retained **20,000**; source median **19.13** (19.13–19.29), retained **1,004**. Exact retention remains lossless, while the per-append scan cost is removed. All sizes/repetitions/environment rows remain in [app-host-after.json](metrics-window-evidence/app-host-after.json). The before/after study uses the same app-host fixture and alternated ordering, but is synthetic one-host Debug evidence, without production timing guarantees.

An initial cadence-only method selector in `/private/tmp/alfie-quality-u3-cadence.xcresult` selected zero definitions/runs despite console `TEST EXECUTE SUCCEEDED`; this is not a cadence pass. The reliable suite selector was used for the completed run below.


Final cadence bundle `/private/tmp/alfie-quality-u3-cadence-final.xcresult` used `test-without-building`, only the ProgramOutputMetricsTests suite and only `ALFIE_METRICS_CADENCE=1`. Authoritative summary/tree: **four definitions/case leaves: three passed, zero failed, one skipped**. The three passes are the two short functional counter tests and the actual cadence benchmark; accelerated stress was explicitly skipped. The five-second warm-up separates those functional calls from measured windows. The cadence fixture passed with all three measured repetitions and 1,000 synthetic accepted frames including warm-up.

Cadence raw rows are preserved in [cadence-realistic-after.json](metrics-window-evidence/cadence-realistic-after.json). Warm-up took 5.509 s. Minimum 20 ms waits produced actual invocation rates **45.675, 45.082, 45.288 Hz**, with instrumentation work **165.28, 190.46, 191.20 µs/frame** and process CPU **0.145, 0.252, 0.166 s** per 250-frame window. Retained four-stage counts were **916, 904, 908**, backing capacity **1,024** slots throughout. Thermal was nominal and **low power was on** in this cohort, unlike the accelerated-study cohort. This is a nominal 50 Hz schedule with actual observed invocation cadence, not a demonstrated 50 fps delivery chain. The Debug host's source fingerprint field is `unrecorded`; source correspondence is supplied by the retained bundle, reviewed diff and sprint commit evidence, not invented in the JSON.

Complete default CinematicCoreMacOSTests target `/private/tmp/alfie-quality-u3-full.xcresult`, `CODE_SIGNING_ALLOWED=NO`: **459 passed definitions / 567 passed case runs, zero failed, five skipped definitions/runs** (464 definitions / 572 total case leaves including skips). Twenty parameterized definitions expand to 128 runs. The five skips are opt-in accelerated stress, opt-in cadence, opt-in investigation, unconfigured consented-folder validation, and real two-webcam integration. Separate nonzero targeted/cadence bundles above exercise all three instrumentation opt-ins; the two external-input prerequisites remain unqualified.

## Repeat the test cohorts

Both commands use the existing project/scheme, macOS destination, no parallel testing and code signing disabled. Choose new result bundle paths rather than overwriting preserved evidence.

```sh
TEST_RUNNER_ALFIE_METRICS_STRESS=1 TEST_RUNNER_ALFIE_INSTRUMENTATION_STUDY=1 \
  xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:CinematicCoreMacOSTests/LatencySampleWindowTests \
  -only-testing:CinematicCoreMacOSTests/ProgramOutputLatencyWindowTests \
  -only-testing:CinematicCoreMacOSTests/ProgramOutputMetricsTests \
  -only-testing:CinematicCoreMacOSTests/DiagnosticsLogTests \
  -only-testing:CinematicCoreMacOSTests/InstrumentationInvestigationTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd \
  -resultBundlePath /private/tmp/alfie-metrics-targeted-repeat.xcresult

TEST_RUNNER_ALFIE_METRICS_CADENCE=1 \
  xcodebuild test-without-building -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:CinematicCoreMacOSTests/ProgramOutputMetricsTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd \
  -resultBundlePath /private/tmp/alfie-metrics-cadence-repeat.xcresult
```

Run the cadence command after the first host exits, with stress/study opt-ins absent. Inspect `xcresulttool get test-results summary` and `tests` for nonzero actual runs; the empty XCTest console shell is not the Swift Testing result. Probe source, allocator interposer, raw rows and representative stacks are checked in; huge/stalled traces are not. Further live-rig beta-lag or physical presentation claims require independent measurements from the existing release latency protocol.

