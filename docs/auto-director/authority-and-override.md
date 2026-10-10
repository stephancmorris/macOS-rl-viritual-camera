# Director authority and operator override

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Recorded contract

Alfie is a live-event backup technical producer with static cameras and an operator always present (UC-1, S1). Every launch starts in Manual. Selecting a qualified level and handing control to Alfie are explicit actions; saved preferences never restore authority. Qualification is per level and rig, not implied by a build or replay pass (U2).

| Operator level | Permitted contract behavior | Boundary |
|---|---|---|
| Manual | Operator runs the show | No Director effects |
| Assist | Prepare the off-air Preview shot | Operator makes every cut; no Program mutation |
| Auto | Qualified automatic cuts to Preview with a visible, cancellable notice | A3 one-shot permit and current R2 Take checks; notice details A4 remain open |
| Backup | Qualified automatic directing while the present operator is busy | Safe-wide fault fallback details R1/R2 remain open; no bypass of the router |

Shadow/Suggest is internal, may propose or record what it would do, and has no camera or output effects. The public labels are Manual, Assist, Auto and Backup (U2), not Auto Prepare / Auto Direct.

A1 makes any manual camera action, including an attempted action and Edit Live, an immediate global takeover: stop preparing and cutting, retire outstanding work, and show why. One **Hand to Alfie** action requests fresh authority after current prerequisites are checked. A stale callback cannot resume it. Return to Wide remains an operator action, never an automatic Director escape hatch.

N1 specifically governs an operator Take: Assist retires old work and starts fresh on the new Preview without pausing; Auto/Backup treat it as a nudge and hold the operator's shot for at least the configured minimum shot duration before continuing. The Manual toggle is full takeover. This exception does not turn another manual camera command into a nudge. Numeric durations remain study parameters.

## A-07 implementation boundary

`DirectorAuthority.Level` is `off`, `suggest`, `assist`, `auto`, `backup`; the UI maps internal shadow to Manual. Actions are `propose`, `prepare`, `take`. Prerequisites include current nominations, Preview availability, source/output health, admission and a set of qualified levels. Epoch-bound grants are invalidated on takeover and relevant changes; choosing an unqualified level is refused, never substituted.

At this stack revision, preparation is permitted only in Assist/Auto/Backup with current prerequisites and evidence; `mayTake` and `autoTakeQualified` remain false. A3 requires later permit/Take integration and qualification. A-07 still pauses Auto/Backup on operator Take pending that integration; this is not the final N1 behavior. Program motion is not enabled by these Preview-only APIs; N2 remains open.

A-07 also starts a fresh epoch without pausing for **Suggest** operator Take. N1 records Assist and Auto/Backup, not Suggest. This extension needs owner confirmation; see the [open questions](event-authority-contract.md#owner-questions).

## Remaining choices — AWAITING OWNER

| Decision | Options | Recommendation and tradeoff | Evidence needed |
|---|---|---|---|
| A2 pin | Pin Program intent; person; pixels | Retain the register's proposed Program-intent pin, with tracking allowed and explicit handback; clearer intent but requires distinct UI from Manual | Operator comprehension and event ordering tests |
| A4 notice | Countdown; confirm each cut; no countdown | Auto cancellable notice and Backup visible next cut as proposed; notice adds response time but can slow useful cuts | Cancellation and readability trials before freezing any duration |
| N2 on-air movement | Preview-only; separately bounded Program moves | Evaluate slow moves only within qualified Auto/Backup; adds continuity but expands the effect boundary | Dedicated Program-motion and takeover proof, separate from preparation tests |

No open choice grants authority. Cuts must be checked in the same turn as `ShowCoordinator.take`, may never target anything but current Preview, and must not survive refusal, cancellation, role change, takeover or expiry.
