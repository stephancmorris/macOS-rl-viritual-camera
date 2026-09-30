# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| R1 Reserve safe camera? | Fixed safe-wide + speaker camera; both interchangeable; optional fallback | Fixed safe-wide role for first qualification; provides a verifiable full-stage candidate | AD-ROLES, setup | Yes |
| R2 Automatic fault fallback? | Ask only; widen live automatically; qualified safe Take | Ask only in first scope and initially in Auto Direct; loss revokes authority | AD-ROLES/TAKE | Yes, requires separate fault qualification |

Status: proposed, 2026-09-30. Roles describe physical camera capability, independent of Program/Preview roles, which swap at Take.

| Proposed camera role | Eligibility / exclusions |
|---|---|
| Safe wide | Operator verifies complete intended stage coverage and lawful fresh rendered full view; no director crop tightening or physical movement. “Wide preset” is not proof of full view |
| Speaker | Operator nominates subject in this camera; available approved close/full-body presets within existing quality limits |
| Unassigned / unavailable | No director proposals; may be used manually under R2 rules |

With two cameras, keeping A safe-wide means no second close-up angle while B is Program. This is an explicit coverage tradeoff, not a hidden third-input requirement. Roles do not transfer automatically to a replacement source. Rebind invalidates verification and requires operator reassignment.

## Existing code and deterministic response

`ProgramRouter.swift` / `ProgramRouter` owns source-loss behavior: existing constants detect loss after 0.5 s and hold rendered output for 2 s before standby. `ShotComposer.swift` / `LockState` has separate subject-loss HOLD (existing 10 s) then wideWaiting. These are distinct conditions, not interchangeable director timers. `ShowCoordinator.swift` / `take` remains the only proposed director routing entry; `TakeRules` rejects stale/repeated candidates. `ChannelRevisions` retires old source work.

Priority order: Stop → source/output/admission fault → manual/pin/pause → identity failure → ordinary proposal. All simultaneous events resolve by the highest row; no fault is interpreted as permission to cut.

| State / event | Off, Suggest, Auto Prepare | Proposed initial Auto Direct | Existing Program behavior |
|---|---|---|---|
| Healthy nominated speaker, Preview available | Suggest or prepare if authorized | Prepare/Take only under ordinary qualified policy | Unchanged until Take commit |
| Preview subject lost/ambiguous | Cancel ready proposal; pause, ask to verify/nominate | Same | No source switch |
| Program subject lost, camera still healthy | Pause director; offer manual safe-wide candidate | Same; automatic safe Take deferred | Existing channel recovery may HOLD/widen under its previous tracking grant; director does not shorten it |
| Preview camera lost | Cancel work, pause, ask reconnect | Same | Current Program continues |
| Program camera lost; healthy safe wide elsewhere | Cancel work, pause; show “Program missing · Take A if suitable” | Same until separate fallback policy approved | Router hold/standby; manual R2 Take available if legal |
| Both sources lost / safe wide stale | Pause; no eligible alternate | Same | Hold/standby; no raw source fallback |
| Output destination missing | Pause; identify endpoint | Same | No source swap or destination substitution |
| Pair workload unsupported | Pause optional director; request explicit operator single-input action | Same | No silent rate/format reduction |
| Pin + subject/source loss | Clear pin into fault pause; show exact fault | Same | Pin never suppresses health reporting |
| Source returns / evidence recovers | Stay paused, new generations/evidence required | Same | Existing same-assigned-Program recovery may resume fresh render; not a Take |
| Stop show | Off; retire all grants | Same | Existing stop lifecycle |

Future alternative, **not recommended for initial wiring**: a separately approved `safeTakeOnProgramLoss` could issue a new permit for a verified current safe-wide Preview. It cannot revive a pre-fault permit, ignore operator revocation, bypass R2 readiness or treat a stale camera as safe. This would require revising the authority fault transition and qualifying it explicitly; no foundation default should enable it.

Acceptance: deterministic event permutations for every row, lost-subject vs lost-camera distinction, role rebinding, pin/fault conflict, manual Wide and rejected fallback. Inspect external output to prove no silent source switch in manual operation. Risks: safe-wide camera can be misframed; verify at setup and after any physical adjustment, even when image freshness is good.
