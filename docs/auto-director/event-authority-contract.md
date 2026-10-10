# Event and authority contract

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Decision and implementation boundary

This document reconciles the recorded live-event backup-producer contract with the open A-07 stack; it does not approve remaining product choices or certify implementation. The owner alone records decisions. The register's Recorded section overrides its older open-row wording and stale proposed headers elsewhere.

Recorded: UC-1 (present operator), E2 (no audio), UC-2 (one shot/input), S1 (qualified live-event steps), A1 (takeover/handback), A3 (qualified permit-bound cuts), E1 (visible subject selection/override), P1/P2 (two bars/wider ambiguity), N1/N3/N5 (Take semantics/presets/declared loss), U2 (four visible levels), AI-1/AI-2/AI-4 (bounded local ranking/no show network/metadata training), and C3 (bounded metadata retention/export). Other register choices remain **AWAITING OWNER**.

## Events and required effect boundaries

| Event | Contract consequence | A-07 status / remaining work |
|---|---|---|
| Launch / show stop | Manual; no carried grant, cut or pending preparation | Authority and console value defaults support this; live integration is separate |
| Manual camera action, Manual toggle, Edit Live | Immediate global takeover; stop preparation/cutting and retire pending work | Pure authority handles events; every live attempt, including refused commands, must reach it |
| Hand to Alfie | Recheck current prerequisites and that level's qualification; fresh work only | Authority API exists; not an unconditional resume token |
| Assist operator Take | Fresh epoch/work for new Preview, no pause (N1) | Implemented in pure authority; no inherited old request |
| Auto/Backup operator Take | Nudge, minimum configured hold before continuation (N1) | Still pauses at A-07; later integration needed |
| Evidence gap / operator gesture | Inhibit immediate effects; no guessed readiness | Adapter exists; stale-sample debounce review finding must be resolved |
| `wideWaiting` / changed nomination | Declared loss or new subject invalidates affected work; loss pauses (N5) | Adapter emits typed loss/nomination events; wiring must consume them |
| Role, route, source/control/shot revision change | Reject stale intent/receipt; never retarget it to new Program/Preview | Proposal/preparation validation exists; effect boundary must repeat checks |
| Output/admission fault | Pause, retire grants; no silent alternate output | Must preserve existing R2 routing contract |
| Program source loss | Existing R2 hold/standby; only separately approved/qualified fallback may cut | R2 choice unresolved; A-07 cannot authorize Take |
| Refused/cancelled automatic cut | No delayed cut; require fresh decision and permit | Atomic permit/Take integration is later work |

The recorded A3 boundary is a one-shot permit checked in the same turn as R2's existing `ShowCoordinator.take` checks. Assist never cuts. At A-07 `mayTake` and `autoTakeQualified` remain false for every level. A judgement, displayed countdown or ready composition cannot substitute for that permit. Preview preparation cannot mutate Program; N2's possible on-air moves are a separate open effect boundary.

## Owner questions

Both questions below are **AWAITING OWNER**. They are not changed or decided by this documentation PR.

| Question | Options | Recommendation / tradeoff | Source evidence |
|---|---|---|---|
| Suggest operator Take extends N1 | Preserve pause in internal Suggest; explicitly extend the fresh-epoch/no-pause Assist rule to Suggest | Confirm the extension explicitly if shadow continuity is desired; improves uninterrupted metadata comparisons but goes beyond N1's named Assist case | A-07 `DirectorAuthority` handles `.suggest` and `.assist` together; recorded N1 names Assist and Auto/Backup |
| Is confirmed evidence sufficient for P1 “face visible”? | Independently expose a current face observation; explicitly accept the proxy for a bounded study | Recommend direct current evidence before claiming the cut bar satisfies P1; extra plumbing and study cost buys a testable distinction | A-07 `ChannelEvidenceSample` has no `faceVisible`; `DirectorReadiness` uses `.confirmed`, whose gallery/lock/freshness test does not independently observe a face now |

R2 also needs owner resolution: the open register recommendation says Auto/Backup fallback, while the product contract proposes Backup-only. [Roles and fallback](roles-and-fallback.md) records options and the narrower recommendation without choosing for the owner. A2/A4/P3/N2/N4, style values, run-sheet details and qualification protocol/signatories remain open.

## Evidence and acceptance

Test the final effect, not just proposed state: no mutation after takeover, no stale target after Take, no duplicated commit after a late receipt, and no cut after cancellation/refusal. Inject clock, input order, parameters and judge outcomes; check stale/future/out-of-order evidence, loss, recovery and source generations. Keep replay counters tied to real requests/receipts and preserve original judgement freshness when replaying recorded outcomes. Existing review findings are not waivers of these invariants.

Synthetic tests prove the exercised software properties. Recorded evidence preserves its original provenance, age and consent limits. Live trials establish rig/operator behavior. Report classes separately and freeze parameters before scored evaluation; none alone substitutes for explicit per-level owner sign-off. Qualification budgets and signatory details remain Q1–Q3 open; this reconciliation sets no numeric defaults.

C3/AI-4: bounded metadata, 30-day expiry, explicit export, metadata-only training. E2: no audio. AI-2: no network during a show. No frames, crops, embeddings, video or transcripts in Director logs; separate media collection requires E3 first. No inferred names, cross-camera identity or children as inferred targets.
