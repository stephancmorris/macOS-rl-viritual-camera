# Preparation and the two readiness bars

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Recorded contract

P1 separates **prepare-ready** (confirmed lock, settled) from stricter **cut-ready** (also face visible, not mid-stride, framing landed). P2 requires a wider shot that holds everyone when identity is ambiguous, rather than guessing a close-up. Neither bar may disable an otherwise legal **operator** Take. A3 adds deterministic permission and R2 route/render checks to automatic cuts; readiness alone is never permission.

A proposal names an input and the app preset for its single shot (UC-2, N3). Preparation changes current Preview only. Assist never changes Program or cuts. An operator nomination wins; E1 also permits visible-rule subject selection without a nomination, with the pick shown and one-tap override. That autonomous selection is not supplied merely by an evidence sample.

## Actual A-07 values and units

`DirectorReadiness.Inputs` contains `take: TakeAvailability`, categorical `identity: IdentityEvidence`, `framingSettledFor` in seconds, `motion` in normalized frame units per second, and `cropConverged`. `Bar` is `prepare` or `cut`.

| Injected parameter | Unit / constraint | Use |
|---|---|---|
| `minimumSettledTime` | Finite nonnegative seconds | Prepare bar |
| `maximumMotion` | Finite nonnegative normalized frame units/s | Prepare motion limit unless `cutOnMotionAllowed` permits it |
| `minimumCutSettledTime` | Seconds, at least `minimumSettledTime` | Stricter cut bar |
| `maximumCutMotion` | Same speed unit, no greater than `maximumMotion` | Cut motion limit regardless of the prepare flag |
| `cutOnMotionAllowed` | Boolean | Despite the name, it does not bypass the cut bar's motion or landed-crop checks |

Both bars require `.confirmed` and legal R2 Take availability. Cut additionally requires `cropConverged`. The readiness reasons are `compositionUnavailable`, `evidenceUnavailable`, `takeUnavailable`, `invalidParameters`, `invalidEvidence`, `identityUncertain`, `framingUnsettled`, `moving`, and `cropMoving`.

There is **no `faceVisible` field** in `ChannelEvidenceSample`. At A-07, `.confirmed` is used as the face-visibility proxy; it means a fresh tracked lock with a ready gallery, not an independent current face observation. The gap against P1 is an [owner question](event-authority-contract.md#owner-questions), not an approved relaxation of P1 or evidence of cut qualification.

## Proposal, dispatch and composition

`DirectorProposal` binds target/shot to authority epoch, source/control/shot revisions, route generation, policy and nomination revisions, and host-clock creation time. `DirectorProposalValidator` rechecks those values at the effect boundary. The request lease and the resulting composition are different: expiry refuses late dispatch; a successfully prepared composition can remain while readiness is refreshed. Do not turn every refresh into a new preset or use a deadline to force a cut.

A request/receipt must refer to the same intent, target and revisions. Acknowledgement checks current roles, authority and expected post-effect revisions; duplicate, replaced or late results cannot create a current composition. Evidence gaps inhibit effects immediately; `wideWaiting` is declared identity loss (N5), not a temporary gap. Source restart, takeover and nomination changes retire work. N1 starts fresh on a new Assist Preview after an operator Take.

Use a common monotonic host clock for ages, with finite nonnegative readings. Processing/observation timestamps are not camera exposure times and cannot prove physical latency. Parameter validity and stale rejection need explicit tests, including future/out-of-order observations. The A-07 adapter's debounce path has a review finding about delaying stale-evidence inhibition; its current behavior is not the desired freshness guarantee.

## Choices and study plan — AWAITING OWNER

P3 options are revision binding alone or revision binding plus a bounded request lease. Recommend the latter to reject delayed work, trading fewer stale effects for possible missed preparations. N4 options are repeated Preview changes or at most one per tenure with readiness refresh; recommend the latter for a truthful stable Preview, trading flexibility for predictability. Both remain open; no duration or change budget is approved here.

Collect metadata on settlement, observation gaps, rejected requests, useful preparations and operator cuts; compare parameter candidates before freezing a named revision. Label synthetic, recorded and live evidence separately. Recorded media collection requires E3 first. No synthetic or replay pass qualifies a level; live use requires that level's sign-off.
