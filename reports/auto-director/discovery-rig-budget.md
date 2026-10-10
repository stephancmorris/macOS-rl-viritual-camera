# D-03 — Named-rig discovery budget worksheet

**AWAITING OWNER — all performance cells unmeasured; no qualification.** Prepared 2026-10-10. Companion to the [workload protocol](workload-plan.md). Candidate study alias `D03-local-Mac16-8` identifies the available host for planning, not an owner-selected or certified event rig.

Read-only inventory: `sysctl -n hw.model` → `Mac16,8`; `sw_vers -productVersion` → `26.6.2`; `sw_vers -buildVersion` → `25G83`. No serial, camera or route was queried/opened. Do not infer chip, RAM, thermal capacity or production suitability from this model ID. Runtime `osVersion` uses `ProcessInfo.operatingSystemVersionString`; the inventory version above is not a fabricated exact fingerprint value.

Options are to confirm this host and its real event wiring, nominate another rig, or defer discovery and reuse observations only. Recommend confirming a named rig, then collecting both real routes separately. This costs more trials but prevents a cheap rehearsal-sink result from being mistaken for real delivery evidence. Source evidence is [AdmissionFingerprint](../../CinematicCoreMacOS/CinematicCoreMacOS/MultiInputAdmission.swift), [ShowCoordinator](../../CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift) and the [actual routes](../../CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift); workload pilot evidence does not yet exist.

## Budget table ready for owner calibration

Duplicate each row for every actual show standard/input configuration; do not pool rows. `TBD` is a missing required value, never a default or zero measurement.

| Candidate rig / route | Show standard and inputs | Requested scan budget | Existing admission evidence | Pilot / proposed pass limits | Current disposition |
|---|---|---|---|---|---|
| `D03-local-Mac16-8` / `display` — Direct output (HDMI / USB-C) | TBD exact standard; two admitted inputs, formats/rates/profiles/modes/wiring TBD; at most one eligible off-air unlocked input | `r_offair` TBD Hz; aggregate `R = r_offair`; burst rule TBD | Exact runtime fingerprint and certified R2 record missing; real display/consumer TBD | Service distribution, output cadence, paired cost, sustained exposure, limits and margin all TBD | INCOMPLETE; no authorized scan budget or workload approval |
| `D03-local-Mac16-8` / `virtualCamera` — Virtual Camera | TBD exact standard; two admitted inputs, formats/rates/profiles/modes/wiring TBD; at most one eligible off-air unlocked input | `r_offair` TBD Hz; aggregate `R = r_offair`; burst rule TBD | Exact runtime fingerprint and certified R2 record missing; receiving app/configuration TBD | Same separate pilot and frozen bars; cannot inherit display result | INCOMPLETE; no authorized scan budget or workload approval |
| Owner-nominated rig / either real route | Additional machine/OS or configuration must get its own row | TBD from its own pilot | New exact fingerprint required | No extrapolation from model family alone | NOT MEASURED |

One input has no off-air discovery target. Three/four-input budgets are deferred behind INPUTS-N, not enabled by `sum(r_i)`. `rehearsal` (“Rehearsal · no output”) may test logic with explicit synthetic provenance but never fills either real-route row.

## Exact existing admission binding

Store the structured fingerprint alongside its existing `key`; preserve unavailable optionals rather than treating the key's placeholders as observed values. Capture it through the runtime API, not by reconstructing a guessed key from this worksheet.

| Existing field | Required study binding |
|---|---|
| `policyVersion` | Exact admission policy version used by the run |
| `machineModel`, `osVersion` | Exact runtime strings; model inventory confirmed, full OS fingerprint still missing |
| `showStandard`, `route` | Runtime standard/title and route title. Route enum identifiers in the budget table are explanatory, not substitutes for the fingerprint's actual strings. Nil route cannot prove real output. |
| `inputs[].channel` | Actual admitted channels; preserve Program/Preview timeline separately |
| `inputs[].deviceModelID` | Optional model ID, not a unique physical-device identity; never add serial numbers |
| `inputs[].deliveredWidth`, `deliveredHeight` | Actual delivered dimensions or unavailable, never requested dimensions substituted |
| `inputs[].captureFPS` | Runtime configured capture rate where supplied; do not relabel it measured delivered cadence |
| `inputs[].captureProfile`, `mode` | Actual profile and `wide`/`track`/`manual`/`pan` mode; changes require reevaluation |

Admission status is `unknown`, `provisional`, `certified` or `unsupported`. Measured provisional admission is not certification; certified R2 admission is not Director qualification. The existing fingerprint contains no discovery-rate, detector/model-version, authority-level, signature, expiry or workload-budget fields.

**Requested integration, not existing API:** a versioned workload record referencing the structured admission fingerprint, source/build identity, discovery implementation and parameters version, explicit rates/burst rule, enabled evidence/model configuration, telemetry schema, opaque run ID, evidence class, role/generation timeline, power/thermal context, real consumer configuration, frozen limits/exposure, result/missingness, and owner/operator/reviewer attestations. Setup aliases must be controlled and contain no person/device-identifying text. Detail needed to reproduce physical wiring may be maintained in a separate approved setup register, not unrestricted log notes. Workload changes invalidate that record without pretending to erase unrelated R2 evidence.

## Owner freeze sheet and missing pilot data

| Required item | Proposed source of value | Value / evidence now |
|---|---|---|
| Named rig, route, standard, actual inputs and R2 certification | Owner-confirmed setup and runtime fingerprint per row | Missing |
| Per-input rate, aggregate rate and burst semantics | Pilot service distribution plus measured Program headroom and useful-discovery latency | Missing; no production rate proposed |
| Warm-up, paired/held-out exposure, soak duration and repeats | Owner-approved study design, preserving separate R2 prerequisites | Missing |
| Absolute base-pipeline limits | Applicable frozen R2 record and route criteria | Missing; source-code provisional defaults are not approval |
| Additional timing/CPU/thermal/memory limits and stop conditions | Paired pilot deltas, variation and owner-selected margin | Missing; unsupported tail statistics remain unavailable |
| Useful-discovery opportunity definition and latency/coverage bar | Pre-labelled eligible scenarios, nomination/ambiguity rules and pilot | Missing; no invented success percentage |
| Zero-violation invariant bar | Protocol authority/privacy/boundedness faults and opportunity counts | Proposed, AWAITING OWNER; no run performed |
| Take overlap rule for already-running full-frame Vision | Owner interpretation plus B-10 cancellation/eligibility design | Open; do not delay manual Take or report rejected results as cancelled computation |
| Per-input telemetry, retention/export and external output evidence | Instrumentation/API integration requested in protocol | Missing; `[SOAK]` alone insufficient |
| C1/C2 selection and evaluation signatories | Owner decision; owner + event operator + independent reviewer for per-level qualification | Unrecorded here; no level qualified |

A scored outcome requires the complete frozen sheet and all required measurements. A violated bound is **FAIL**; absent exposure, provenance, bound or measurement is **INCOMPLETE**, never PASS. Discovery cannot be granted an approved budget merely because no limit was entered. Different routes/classes remain distinct even when summaries share a report.

Ordinary metadata expires after 30 days under C3/AI-4; export must be explicit and sanitized. No media without E3, no audio, no show-time network, no inferred names or children as targets. Synthetic/replayed results may inform calibration but cannot substitute for measured live rig evidence or per-level authorization. No workflow in this worksheet grants control or restores it after manual takeover.
