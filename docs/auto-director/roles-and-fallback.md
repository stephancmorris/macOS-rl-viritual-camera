# Input roles and safe-wide fallback

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Recorded boundaries

UC-2 gives each physical camera one input with one shot. Program and Preview are current routing roles, not permanent camera identities or multiple virtual shots from one camera. Alfie sends an input through the existing `ShowCoordinator.take` / `ProgramRouter` path; it does not publish raw source pixels, create another output or silently change output destinations.

S1 includes a qualified Backup level with safe-wide fallback. A3 permits Director cuts only in qualified Auto/Backup with a one-shot permit checked in the same turn as the existing Take checks. Assist never cuts. P2 prefers a wider shot holding everyone under ambiguity; a Wide preset alone proves neither coverage nor freshness. N5 subject loss is separate from loss of a camera source.

## Open role and fault design — AWAITING OWNER

| Question | Options | Recommendation and tradeoff | Required evidence |
|---|---|---|---|
| R1 role assignment | Reserved verified safe wide; interchangeable inputs; optional fallback | Keep a verified safe-wide input as proposed, trading one flexible shot camera for known coverage | Rig-specific framing, health and fresh-render checks; operator can identify the wide |
| R2 Program source loss | Pause/ask; widen same live input; take verified safe wide | The product contract proposes one Backup fallback inside the router hold window, then pause. It preserves continuity but adds a fault-time cut boundary | Fault drills proving current eligibility, permit, destination, bounded timing and no repeat fallback |

**R2 is not recorded.** The open decision-register recommendation mentions Auto/Backup fallback, while the product contract narrows it to Backup and pauses Assist/Auto. Recommend the narrower Backup-only trial, but the owner must choose. Do not infer approval from S1's broad backup-producer scope or silently resolve this discrepancy in code.

R2's existing hold/standby route remains authoritative until an approved and separately qualified fallback is implemented. A-07 has no authorized automatic Take. Never reuse an old preparation or permit merely because Program failed; current Preview must be the intended verified wide and pass all current cut and route checks. If no safe candidate exists, retain router hold/standby and show the fault. A destination fault is not permission to swap cameras or outputs.

A manual camera action/Manual toggle wins over fallback; revoke and stop immediately. An operator Take follows N1, not a generic all-Takes-pause rule. Reconnect creates a new source generation and cannot revive a prior grant. Hand to Alfie rechecks current health, admission and qualification. Pin semantics and fault interactions remain A2 open.

## Acceptance evidence

Keep synthetic fault injection, consented recorded playback and live rig drills separate. Cover missing Preview, missing Program, both unavailable, destination loss, expired render, reconnection, operator takeover, duplicate callback, permit refusal and hold-window expiry. Observe the downstream rendered Program as well as logical state. A simulator pass does not qualify fallback, Auto or Backup. Freeze numeric parameters and the per-level protocol only through owner review; this reconciliation supplies no new timing default.
