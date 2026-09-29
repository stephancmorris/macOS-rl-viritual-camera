# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| A1 Manual override scope? | Global pause; affected channel only; temporary suppression | Global pause, explicit resume: understandable with two cameras and no delayed reversal | AD-OVERRIDE, authority integration | Yes, requalify |
| A2 What does pin protect? | Current Program composition intent; person only; fixed pixels | Pin Program shot intent; preserve existing tracking, prohibit director preparation/Take while pinned | AD-OVERRIDE, UI | Yes |
| A3 Who may cut? | Never; qualified Auto Direct; fallback-only auto | Only separately qualified, explicitly enabled Auto Direct; ship Auto Prepare first | AD-TAKE | Yes, requalify |
| A4 Countdown? | None; cancellable countdown; confirmation per cut | Auto Prepare has none; proposed cancellable 3 s notice for later Auto Direct | AD-TAKE/UI | Yes |

Status: proposals, not approvals. Source baseline: `origin/r2/engine` at `33a3faf`, reviewed 2026-09-30. Paths below are relative to `CinematicCoreMacOS/CinematicCoreMacOS/`. No running-app changes authorised here.

## Existing mechanisms and missing authority

| Existing code | What it actually guarantees / proposed addition |
|---|---|
| `ShowCoordinator.swift`: `ShowCommand`, `controlTargetRevision`, `makeCommand`, `dispatch`, `setEditLive` | Binds UI intent to its channel and target revision; Program edits require Edit Live. Revision changes on retarget, **not every manual action**. Proposed: revoke director grant before admitting manual intent. |
| `OperatorCommand.swift`: `CommandDispatcher` | Per-channel epoch increments on acceptance; expiry and ID deduplication. Origins currently operatorUI/safety/automaticRecovery, no director or voice origin. Proposed origin alone is not authorization; require authority token. |
| `ChannelFrame.swift`: `ChannelRevisions`, `RenderedChannelFrame.matches` | Source generation and shot revision gate frame identity; matching intentionally excludes control epoch. Proposed director proposal captures all three, with the post-prepare epoch/revision acknowledged explicitly. |
| `ProgramTake.swift`: `TakeRequest`, `TakeRules`; `ShowCoordinator.take` | Request stores expected roles and route generation only. Eligibility is checked synchronously against latest render; there is no director pending-Take queue or stored shot revision in TakeRequest. Proposed outer director permit carries proposal revisions and is checked in the same serialized turn as `take`. |
| `ProgramRouter.swift`: `ProgramRouter.commitTake`, `routeGeneration` | Sink acceptance precedes role change; old-route sends reject. Not a director authorization check or physical downstream acknowledgement. |

Do not implement the older spec's future-output-tick reservation as if it already exists. Existing R2 commit is synchronous. Integrate an atomic **validate director permit → existing Take** operation; an asynchronous gap would reintroduce the race.

## Proposed authority state machine

Represent `requestedMode = Off | Suggest | AutoPrepare | AutoDirect` and `inhibition = none | paused(reason) | pinned(shotIntent)`. Fault latch is a pause reason; show-stopped is Off. Effective capabilities are the intersection of mode, inhibition, show health and signed qualification. Keep requested mode visible while inhibited.

| Mode / inhibition | Observe and explain | New Preview command | Take |
|---|---|---|---|
| Off | No new director proposals | No | Operator only |
| Suggest / none | Yes | Only operator acceptance | Operator only |
| AutoPrepare / none | Yes | Current Preview only | Operator only |
| AutoDirect / none | Yes | Current Preview only | Qualified permit + all R2 checks |
| Any paused or pinned | Status/reason only; no executable proposal | No | Operator only |

Every revocation increments a proposed show-wide `authorityEpoch`, cancels proposal/countdown/queued work and retires its continuation tokens. Cancellation does not reset admitted R2 tracking or stop independent operator-owned motion. A director-owned preparation already admitted must lose ownership of future effects at override; hand off current crop to existing manual/recovery rules without a jump. This ownership hook is proposed, not supplied by target revision alone.

| Event / actor | From → to | Cancels / retained behavior |
|---|---|---|
| Enable mode / operator | Off → chosen qualified mode, uninhibited | New grant/epoch; fresh proposals only; Auto Direct unavailable without sign-off |
| Change level / operator | Any active mode → chosen level | Revoke old grant first; escalation requires explicit operator action; no inherited countdown |
| Pause / operator | Any enabled → paused | Revoke all director work; preserve current channel state |
| Manual camera action, Wide, operator Take attempt / operator | Enabled → paused (pinned remains pinned with manual reason) | Revoke before admission even if action rejects; avoids queued automation surprising operator |
| Enter or exit Edit Live / operator | Enabled → paused | Revoke before target revision changes; never direct Program during Edit Live |
| Pin / operator | Enabled → pinned(current Program intent) | Revoke all director work; pin is editorial ownership, not frozen video |
| Unpin / operator | Pinned → paused | Clear pin; no implicit resume |
| Resume / operator | Paused → requested mode / none | Only if fault cleared, qualification current and not Edit Live; new epoch, no old proposal |
| Source/output/admission failure / fault | Enabled or pinned → paused(fault) | Revoke grant and pin; retain requested mode; router handles hold/standby, no silent Take |
| Source restored / fault cleared | Paused → paused | Reconnect never resumes authority |
| Stop show / operator or lifecycle | Any → Off | Revoke first, then `stopShow` retires channel work; no restart grant |
| Proposal ready/expired, countdown elapsed / director | State unchanged | May update proposal or request eligible Take; never self-escalate/resume/unpin |
| Director Take commits / director | AutoDirect → AutoDirect | Retire consumed proposal; route revision invalidates prior work; fresh proposal on new Preview |
| Rejected Take / director | AutoDirect → same mode, no proposal | No retry of old request; reason shown; health fault additionally pauses |
| Repeated pause/off/stop / any permitted actor | Same state | Idempotent cancellation; all unlisted transitions reject without effects |

## Race schedule and testable contract

| Race | Required serialization / R2 mapping |
|---|---|
| Manual vs queued prepare | Revoke authority before manual dispatch; compare authority epoch and channel epoch immediately before effect; no pre-manual director continuation may mutate afterward |
| Manual vs queued Take/countdown | Cancel notice, reject outer permit by authorityEpoch; existing `TakeRequest.routeGeneration` alone cannot catch same-route manual edits |
| Operator Take while preparing | Pause first. Use operator's current R2 eligibility; do not wait for preparation. If ready commit; if not reject. Late prepare cannot land on new Program; verify target revision, channel identity and route generation |
| Director Take committed just before manual | Commit is already history, cannot undo it. Bind manual intent to its creation-time target; stale-target rejection stays truthful; never retarget silently |
| Edit Live vs prepare | Pause, increment target revision through existing path; retire director work even on the other channel |
| Source loss/rebind | Source generation retires frames; cancel proposal and grant; router alone holds last rendered Program then standby |
| Stop vs every continuation | Revoke show grant before teardown; source generations/epochs retire work; no callback can reactivate show/output |

Required invariant tests: (1) no director command created before a manual command may take effect after its revocation boundary; (2) no automatic Take in Off/Suggest/AutoPrepare/paused/pinned; (3) preparation never changes Program route; (4) proposal channel remains Preview at effect time; (5) old source/shot/authority/policy/route revisions reject; (6) accepted prepare's own new epoch and shot revision are recorded, not mistaken for interference; (7) one proposal permits at most one Take; (8) countdown expiration grants nothing by itself; (9) failed sink acceptance preserves roles; (10) Stop and faults cannot auto-resume; (11) manual Wide remains one action; (12) pin does not promise frozen crop or suppress source-fault truth.

Use deterministic executor-order permutations: each event before admission, after admission/before effect, before commit, after commit. Include duplicate callbacks, stale epochs and rapid Take double-clicks. Acceptance is zero forbidden effects in all permutations, plus a live override timing run in the qualification protocol; not merely matching state enum values.

## Next-shot seam

`Console/NextShotStatus.swift` → `NextShotStatus.DirectorSection` currently has Mode off/suggest/auto, proposal ChannelID?, reason String?, countdown TimeInterval?, authority operatorOnly/directorMayCue/directorMayTake. `NextShotStatus.make` always sets director nil for R2.

| Field | Proposed mapping/change |
|---|---|
| mode | Distinct off/suggest/autoPrepare/autoDirect; never label both autonomy levels “Auto” |
| proposal | Keep channel for routing; add immutable proposal ID, shot summary, subject alias and lifecycle (suggested/preparing/ready/stale). ChannelID alone cannot identify a shot |
| reason | Stable reason code + localized explanation; pause/fault reason separate from editorial reason |
| countdown | nil unless qualified Auto Direct has an eligible cancellable notice; proposed 3 s starting value gives intervention time, measured in volunteer rehearsal; monotonic deadline is truth |
| authority | Effective current permission; inhibited modes always operatorOnly. “May cue” needs separate distinction between Suggest and AutoPrepare |
| proposed new fields | requested mode, inhibition, authorityEpoch/snapshot revision, canResume, pin summary; not inferred from strings |

Snapshot must publish proposal and authority atomically with route state. Take button retains `TakeAvailability`'s R2 reason; separate “Director waiting: identity uncertain” must not disable a legal manual Take. Main risk: conflating editorial readiness with existing technical readiness, or epoch checks at enqueue but not at final effect.
