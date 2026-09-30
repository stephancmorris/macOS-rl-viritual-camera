# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| C1 Initial analysis workload? | Reuse video observations; additional video model; audio/LLM pipeline | Reuse bounded existing observations; add no model before measured benefit | AD-COMPUTE/SUBJECT | Yes |
| C2 Admission scope? | Reuse R2 certification; extend workload fingerprint; generic Mac minimum | Separate director workload qualification tied to R2 fingerprint and policy | AD-COMPUTE/QA | Yes |
| C3 Director log retention? | None; sanitized bounded local log; media/transcript log | Sanitized local event log with proposed 30-day expiry; explicit export | AD-COMPUTE/privacy | Data disclosure irreversible |

Status: measurement plan, **not run**, 2026-09-30. All new budgets are proposed starting values requiring pre-run approval.

## Existing diagnostics and gaps

`CapabilityReport.swift` / `CapabilityReport`, `CapabilityThresholds` evaluate measured windows, with provisional limits; short check is not certification. `DiagnosticsLog.swift` / `DiagnosticsWindow`, `DiagnosticsSessionIdentity` log stage timing, system/memory and build/route identity. `MultiInputAdmission.swift` / `PairAdmission`, `AdmissionFingerprint`, `AdmissionRecordStore` fingerprint machine/OS/input format/mode/route/policy, but do not include director/speech/model workload. `CameraChannel.swift` / `RouterChannelPort` forwards detailed diagnostics only for Program; add evidence for Preview explicitly. `origin/r2/sol:DegradePolicy.swift` is a pure proposed shedding policy, not proof that the app applies it.

## Paired measurement design

On every proposed supported rig and output route, first satisfy `origin/r2/sol:reports/release-2/multi-qa.md`. Freeze app/build, camera cards/ports/hubs, actual delivered size/rate, OS, power/temperature and R2 evidence. Proposed starting sequence: 10 min warm-up, 10 min R2 baseline, 10 min director-enabled comparison, then 60 min enabled soak; repeat baseline/enabled in reversed order to expose thermal/order bias. Track+Track, Track+Pan, exchanged roles, subject loss/recovery, repeated overrides, Preview/source/output loss all required. No real qualification can be inferred from a simulator.

| Measure | Evidence / proposed initial additional budget |
|---|---|
| Capture/output | Delivered vs configured frames, accepted handoffs, repeats, deadline misses, external presentation cadence. Must pass frozen R2 gates; proposed enabled increase in deadline misses ≤0.1 percentage point |
| Timing | Per-channel capture→MainActor hop, perception queue/wall/age, render queue/wall, director decision, manual revoke→last permitted effect, Take request→commit; median/p95/p99/max where instrumentation supports it. Proposed director p95 synchronous occupancy ≤1 ms; no awaited inference on frame path |
| Memory | RSS/physical footprint, GPU/IOSurface distinct count/high water, optional-work queue length. Proposed incremental director metadata ≤20 MiB and post-warm-up growth ≤1 MiB/min; media/model buffers separately budgeted |
| Thermal/CPU | CPU attribution and ProcessInfo thermal timeline; proposed no new serious/critical sustained state attributable to director; preserve R2 thresholds |
| Analysis cadence | Existing observation cadence vs proposed decision evaluation 5 Hz maximum; authority/manual cancellation event-driven, never waits for cadence |
| Readiness | Preview true freshness and director eligibility duty cycle, preparation success/latency/expiry; proposed eligible useful preparation coverage ≥80% on labelled opportunities |

These budgets are hypotheses to distinguish negligible coordination from a new inference workload. Report confidence/variation and failed configurations; do not average away worst-case thermal/latency failures. Existing aggregated means do not provide p99: add bounded histograms or traces in later instrumentation, and label unavailable statistics rather than infer them.

Proposed scheduler: one latest-only director snapshot and one decision in flight; no retained CVPixelBuffer copies, stale-result cancellation at final effect; no periodic full-frame detector for directing alone. Shed director inference/proposals first under pressure, revoke Auto Direct and pause. Then existing qualified R2 degradation rules apply. Never lower Program standard, expand queues, weaken identity vetoes or silently stop a source to claim success. Recovery of compute does not restore authority.

Proposed workload fingerprint adds director policy/schema, enabled evidence/model/version, analysis cadence, recognizer and language/asset versions if present. Changing any makes director qualification unknown; it does not erase valid R2-only evidence. Unknown machines remain labelled trial-only, with Auto Direct unavailable.

## Privacy/data inventory

| Data | Proposed use / retention / export |
|---|---|
| Camera pixels | Existing pipeline only, in-memory buffers; Program intentionally leaves via selected output. No new director recording |
| Identity vectors | Existing lock-local memory; no event-log vectors; verify clearing on Wide/Stop/rebind |
| Nominations/rundown | Local settings aliases; use opaque runtime IDs in exported traces; no real person names by default |
| Proposal/authority events | Monotonic times, channel/revisions, reason codes, policy hash and results; bounded local metadata log, proposed 30 days with explicit delete/export |
| Hardware telemetry (future) | Device ID, actual/unknown position, faults; no camera media; redact serial IDs on export |
| Voice/audio (future) | Disabled absent privacy approval; bounded ephemeral memory only; no transcripts/audio in default logs |
| Study fixtures | Separate consent register and expiry in subject-evidence memo, private storage; never bundled with diagnostics |

Audit basis: `origin/r2/sol:docs/privacy/privacy-audit.md` distinguishes CSV prune from unpruned manifests/text logs. Proposed retention must cover all new files and be verifiable without relying only on the next capture session. Acceptance includes denied/revoked permission, mute/Stop cleanup, offline packet inspection, actual export contents and crash-log inspection. No run or collection occurred in this discovery round.
