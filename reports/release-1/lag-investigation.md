# Intermittent lag investigation

2 October 2026 · source `7691e6e` · [LAG-DIAG](https://trello.com/c/D6KPsTw4). **Status: affected-run evidence unavailable; no cause or memory leak confirmed.** The synthetic instrumentation study is separate from live beta lag. No reset, automatic restart or production code change is proposed without measured evidence.

## Existing diagnostics

Session zero is the first processed capture frame, not first detection. `detection start` marks Vision activation. Collect matching `alfie_soak_<stamp>.csv`, `alfie_memory_<stamp>.csv`, `alfie_session_<stamp>.json` from Settings Output Session Log. Inspector Reveal logs opens the separate extension/routing text log. Stop flushes a partial window; marker rows carry no metric measurements. CSV cadence is approximately five seconds, not per-frame latency.

Useful columns/stages: hop lag and queue wait, Vision wall time, MainActor/frame time, observation age, delivered/admitted/gate-skipped/capture-dropped/render-failed/routed/handoff/refused/repeated counts, thermal/low-power/CPU/thread count, footprint and memory/heap breakdown. CPU cores is CPU-seconds per wall second and may exceed 1; percentage can exceed 100. It must not be passed directly into DegradePolicy's normalized fraction field.

Accepted handoff is not physical presentation. `presented` is unknown; use a receiver-side recording or timing method for downstream cadence. Process memory counters narrow hypotheses but do not attribute ownership to a particular allocator/GPU object by themselves. Do not claim flat heap proves Core Image is the cause.

## Reproduction protocol

1. Pin source/app/extension fingerprints and named Mac/OS, power/low-power state, cameras/hubs/input mode, delivered resolution/rate, show standard and output. Mark old/missing fingerprints explicitly; do not relabel old logs as current evidence.
2. Start in rehearsal with authorized input. Record wall-clock and session-relative time at start, detection enable and reported onset. Record whether Source, Preview, Program, controls and external receiver each lag. Keep screenshot/recording permissions separate.
3. Compare before/onset/after windows under the same workload. Separate full, partial and marker rows. Note external app launches, open Inspector/Settings, thermal transitions, lock/crossings, Take and reconnect.
4. Continue only while the rehearsal is safe; then Stop to flush, copy the three matched files, and inspect the receiver record. If operator restarts, preserve the pre-restart files and record interruption; do not automatically restart a live show.
5. Repeat with one variable changed: same candidate detection off vs on, single vs pair, same source/output and same windows open/closed. Run paired baselines rather than attributing improvements from a different build/rig.

## Cause ranking from future evidence

| Signal | Candidate hypothesis | Required discriminator |
| --- | --- | --- |
| Thermal/CPU change at onset | Sustained workload/power limit | Matched-load repeat; thermal correlation alone does not prove cause. |
| Hop/queue rises, Vision stable | MainActor or scheduling contention | Activity/sample trace tied to event; distinguish UI refresh and queued work. |
| Vision/observation age rises | Detection cost/stale evidence | Source/proxy size, cadence, tracking state and off/on comparison. |
| Gate drops rise | Admitted processing not keeping pace | Separate capture upstream drops, render time and queued main work. |
| Handoff healthy, receiver stutters | Downstream display/extension/receiver cadence | Independent receiver record, route/clock details. |
| Footprint/retained counters trend upward | Retention or cache pressure | Identify object/buffer owner with a trace; plateau/end cleanup comparison. |

Core Image cache flush interval is currently disabled (0); renderer disables cache intermediates. The diagnostic flush hook's existence is not evidence of a fix. No auto memory-threshold restart exists. Any processing-reset design must preserve output/ownership and pass its own fault rehearsal before implementation.

## Evidence sheet

Candidate/rig: pending. Onset and affected views: pending. Matched files: pending. Receiver presentation: pending. Ranked causes: unmeasured. Fix/regression case: blocked on evidence. Repeat affected workload: not run.
