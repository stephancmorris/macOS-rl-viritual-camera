# Isolated candidate review

2 October 2026. Review of Director `7553a9d23a7faebe5aaaff9d922c171bcf520e45` and local degradation/readiness `8b9f71236252a7c37b1b216b8b3913aaae811c45` (implementation `64ec925`). Both derive from engine `7691e6e`. Working trees were clean before review and not edited. Director is pushed; degradation/readiness remains local following the earlier automatic push-approval rejection. No merge, PR, Trello write or live hooks.

## Finding

**P2 — replay committed-stale metric is not independent.** In `Director/Replay/DirectorReplay.swift:150`, staleEffectsCommitted increments only inside the branch entered after validation is valid and commit accepted. The tested rejection APIs still matter, but zero here is structurally guaranteed by the branch condition. It does not independently audit effects committed outside this guarded path. Before treating it as qualification evidence, record actual simulated effect identity/context at sink mutation and independently classify committed effects; keep rejected stale attempts as a separate denominator. No live stale-effect or UI latency measurement exists.

## Director review

Action-specific authorization separates propose/prepare/Take; Suggest cannot prepare, Auto Direct refuses without substitution and automatic Take remains unavailable. Disable/re-enable, same-level superseding grants, Pause/Resume and Stop/restart retire epochs; exhaustion does not wrap. Temporary evidence gaps differ from identity/source/output/admission faults; healthy evidence does not clear a latch. Requests and receipts have stable identities, ACK requires post-prepare revisions, leases are not renewed, and compositions can persist with readiness refreshed. Early preparation is separated from recommendation dwell. Tests exercise these proposed conservative semantics; all 37 decisions remain OPEN.

Integration blockers remain explicit: ShowDirectorWorld is a read-only incomplete bridge, with no live nomination/policy/evidence ownership. Its default evidence is unavailable, so it cannot accidentally qualify a live preparation. Production final-effect serialization/atomic sink checks, actual R2 preset/full-view mapping, control-target/cue/lock bindings and truthful UI projection must be designed after choices and Stage 2 evidence. Retain the authority owner/generation across lifecycle replacement or add non-reusable session identity before reconstructing an owner; UInt64 tokens alone cannot distinguish arbitrary new instances initialized at the same epoch. This is an adapter constraint, not proof of a current running-app race because Director is unwired.

## Degradation/readiness review

Failable explicit threshold initialization rejects invalid configuration, and invalid candidate/workload data block the additional gate. Existing technical manual Take remains authoritative. Normalized CPU/deadline fraction [0,1] is distinct from DiagnosticsLog CPU cores/percentage; the future adapter must normalize, not pass CPU cores directly. Numerical defaults remain provisional.

Annotation constructor/decoder reject empty/nonfinite/domain-invalid/duplicate points; nearest time is deterministic; annotation misses abstain rather than switching to the tallest person. Absent configuration skips; partial/invalid configuration fails. Nearest-point temporal coverage, physical-person ground truth, held-out data and live freshness remain study dependencies. No new production defect was established in these isolated validation repairs.

## Evidence boundaries

Fresh targeted review bundles: `/private/tmp/alfie-candidate-director-review.xcresult` and `/private/tmp/alfie-candidate-readiness-review.xcresult`; exact authoritative counts are in the work-package report. Prior full-suite bundles/results remain tied to their exact commits, not rerun totals. Synthetic decoder/replay evidence is not camera/output, safety, editorial, identity calibration or measured override-latency qualification. No full-ticket completion or approval is inferred.
