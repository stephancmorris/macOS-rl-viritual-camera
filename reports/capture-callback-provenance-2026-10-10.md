# Capture callback provenance — 10 October 2026

Status: implementation delivered for Human Review; physical reconnect and release acceptance remain open.

Parents: [DEVICES](https://trello.com/c/F96mnFgL), [CHANNEL](https://trello.com/c/4sFQx8lb), [SCHEDULER](https://trello.com/c/IaUgLHbE). Child: [CAPTURE-CALLBACK-PROVENANCE](https://trello.com/c/LDE5b8sA).

## Verified defect and repair

The AVCapture delegate discarded its originating output identity. An old output callback arriving after a processing-gate reset could obtain a fresh lease, then process a frame as belonging to the current capture generation. Source loss intentionally retains running state for output hold; the running flag alone did not reject that callback. Old dropped-frame callbacks also contaminated the current session counters.

Both production completion paths now retain the originating AVCaptureOutput across the MainActor hop and require identity with the current video output, live-camera source, running state and a present source. The strong immutable box prevents address reuse while queued. Existing processing-gate lease checks and deferred release remain in place. Rejection precedes frame processing, hop accounting and upstream drop accounting.

A DEBUG seam drives those same completion helpers with synthetic IOSurface-backed CMSampleBuffers. Tests exercise replaced output, source loss, reset without an output, stopped capture and clip source, plus valid current callbacks. A rejected frame releases its lease so the following valid callback can render. The probe uses an in-memory channel output port; no capture authorization, device configuration, microphone, receiving display, extension activation or active output is used.

## Evidence

Environment: Xcode 26.2 (17C52), arm64 Apple M4 Pro, macOS 26.6.2 (25G83); CODE_SIGNING_ALLOWED=NO, parallel testing disabled. Counts are read from xcresult summary and test tree; parameterized case runs are counted separately from definitions.

| Run | Passed definitions | Failed definitions | Skipped definitions | Passed case runs | Failed case runs | Skipped case runs |
|---|---:|---:|---:|---:|---:|---:|
| Before fix: new callback suite | 0 | 2 | 0 | 2 | 8 | 0 |
| Targeted after fix | 40 | 0 | 0 | 50 | 0 | 0 |
| Complete macOS test target | 524 | 0 | 5 | 734 | 0 | 5 |

The new suite contains 2 definitions / 10 parameterized cases. Targeted regression suites: CaptureCallbackProvenanceTests, CameraSwitchLifecycleTests, PipelineLifecycleTests, CaptureDeviceRegistryTests and ProgramTakeTests.

Result bundles: `/private/tmp/alfie-oct10-callback-baseline.xcresult`, `/private/tmp/alfie-oct10-callback-targeted.xcresult`, `/private/tmp/alfie-oct10-callback-full.xcresult`; companion logs and exported counts are in the same temporary directory. Temporary bundles are not durable release evidence; these recorded outcomes are committed.

Five unchanged full-suite skips: accelerated instrumentation stress, cadence-realistic instrumentation benchmark, accelerated clock-window comparison, consented replay folder and two-webcam opt-in integration. No skip establishes hardware qualification.

## Remaining acceptance

Run actual source loss/replacement/reconnect on a pinned signed candidate with named devices and inspect the receiving Program output. This repair proves callback ownership in the synthetic pipeline; it does not prove hardware reconnect, presentation cadence, physical latency, privacy compliance or a qualified release. Broader parent acceptance stays unchecked and the child remains open in Human Review.
