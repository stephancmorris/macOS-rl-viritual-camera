# Director authority and preparation lifecycle repair

30 September 2026. Isolated review candidate; **no app integration or directing qualification**. All 37 decisions remain OPEN and `DECISIONS.md` is unchanged. The proposed semantics in `decision-review.md` and `event-authority-contract.md` were implemented for review using explicitly selected `DirectorAuthority.ReviewPolicy.conservative`, not installed as a production default.

## Commits and isolation

- Fetched exact base: `origin/r2/engine` at **7691e6e1046ab40bca9b4e27a80e0b500f409c83**.
- Resulting implementation and integration-contract commit: **307d91f12a7822286a46d9dbf51ec0183f532192**.
- This report is delivered in the subsequent documentation commit on `codex/director-authority-lifecycle`; the final delivery SHA is reported in the chat and is discoverable with `git rev-parse codex/director-authority-lifecycle`. That commit changes this report only.
- Managed worktree: `/Users/stephanmorris/.codex/worktrees/director-authority-lifecycle/macOS-rl-viritual-camera`.
- Other fetched reviewed tips: Sol `830342ee5e62db55fea450bb121d01018164a776`; Astra hardware `f5bac15772645416039d51db0e9d9b90ff3e2b4d`; Astra `b4b447f148466b52f9c8c146563b7b26b937c862`.

Started from the current engine foundation, with no old-branch cherry-picks. No applicable AGENTS.md was found in the workspace/ancestor paths. The original checkout's concurrent build artifacts, untracked documents and other work were preserved. Changes are limited to four existing Director source files, four Director test files, `integration-requests.md` and this report. Hardware, Speech, app orchestration/UI, project settings, entitlements, capture/output and build scripts are unchanged. No PR, merge or Trello write was performed.

## Implemented invariants

1. `authorizes(epoch, action:)` distinguishes proposing, preparation and future Take. Suggest grants only proposing; every preparation checks `.prepare`. Auto Direct explicitly returns `autoDirectUnqualified`, preserving current level and epoch. `autoTakeQualified` remains false; `.take` always refuses and no Director routing call exists.
2. Every superseding grant, including same-level enable, retires the previous epoch. Disable/re-enable and Stop/restart cannot reuse tokens. UInt64 exhaustion is terminal, never wrapping. Explicit Resume needs all current prerequisites and issues a new epoch; it cannot enable Off or revive old work.
3. The selected conservative review profile globally revokes and latches Pause before camera/editorial admission, including refused Take attempts. Navigation/cosmetics have no effect. Edit Live exit, unpin, evidence return and aggregate health restoration never clear Pause.
4. Temporary insufficient evidence suppresses preparation/readiness without replacing identity or revoking a valid grant. Declared identity loss and source/output/admission faults revoke and pause. Loss declaration is an explicit test-world event; no identity-loss timeout or threshold was invented.
5. Proposal UUID, request UUID and exact receipt identity separate shot intent, one-shot dispatch lease, acknowledged composition and current readiness. Context binds stable channel/Preview role, authority epoch, source generation, control epoch, shot revision, route generation and nomination/policy revisions.
6. `DirectorPreparation.validate` is shared by enqueue and final effect; `commit` repeats it before recording simulated acceptance. Expired/refused/failed requests are discarded without renewal. Stale callbacks cannot discard replacement work. ACK accepts only the matching stored receipt and exact expected post-preparation revisions/current context; duplicates and retired work refuse.
7. Composition binds the **post-preparation** revisions and has no request timer lease. Current sufficient evidence, identity, settlement, motion and technical Take availability refresh readiness without reapplying framing. Evidence gaps preserve otherwise valid composition metadata. Ordinary renders/tracking interpolation do not increment shot revision or refresh identity observations.
8. `choosePreparation` may select moving Preview before minimum Program dwell. `recommendationDue` is separate future timing guidance. Wide/max-dwell reasons are advisory. Deterministic ordering and invalid numeric/clock rejection remain. R2 manual moving-shot Take code is unchanged; the replay's synthetic manual gate is independent of Director settlement/motion.

A cancellation retires queued/delayed Director effects and metadata. It does not jump a crop, undo an admitted preset/committed Take or stop already admitted R2 tracking. A delayed ACK after an earlier valid preparation can be rejected without claiming that the earlier effect never occurred.

## Event and transition table

| Explicit event | Immediate authority/work consequence | Recovery |
| --- | --- | --- |
| Available-level enable | Refuse if paused, inhibited, exhausted or prerequisites absent; otherwise replace grant/epoch and retire old work | No automatic preference restoration |
| Auto Direct enable | Explicit refusal; current level/epoch retained | Separate qualification and product decision required |
| Manual camera/editorial command, Take attempt, policy/nomination change | Revoke all pending Director work, latch Pause; Take may still be technically refused | Explicit Resume with current prerequisites |
| Enter Edit Live | Revoke/pause before retarget/admission | Exit only removes Edit Live inhibition |
| Navigation / cosmetic edit | No epoch change | No Resume needed |
| Temporary evidence unavailable | Preparation/readiness unavailable, composition retained if context-valid | Current sufficient evidence may recover under same grant |
| Declared identity loss | Revoke and pause | Explicit nomination/continuity prerequisite, then explicit Resume |
| Source loss / restart / rebind | Revoke and pause; source generation invalidates old context | Restore current sources, then explicit Resume |
| Output fault / admission loss | Revoke and pause | Aggregate healthy/current prerequisites, then explicit Resume |
| Healthy sources/output/admission or evidence return | Remove relevant inhibition only | Does not clear latched Pause |
| Pause / Pin | Revoke and pause | Unpin leaves Pause; explicit Resume required |
| Explicit Resume | Require running, healthy, no Edit Live/Pin and all five supplied prerequisites; issue new grant epoch | Old requests/receipts remain retired |
| Stop | Retire all work and runtime grant, Off before teardown | Restart stays Off; deliberate available-level enable required |
| Expired request / failed sink / stale callback | Discard matching future request, no composition/effect credit | Never silently renew; explicit new work only |
| Accepted preparation + matching ACK | One effect and one composition bound to accepted revisions | Refresh evidence without repeated presets |

Grant prerequisites are explicit caller snapshots: current nominations, Preview availability, source health, output health and admission. `healthRestored` is an aggregate adapter declaration, not proof gathered by this module.

## Review policies and dependencies

The global Pause scope, graduated evidence handling, persistent composition, preparation during movement, settlement/motion readiness and preparation-before-dwell behavior remain **unapproved review policy** (especially A1/A2/A3, E1/P1/P2/P3/R2, F2/F3 and T1/T2/T3). The explicit constructor has no default policy. Test-world thresholds and historical `.proposed`/preference values are study inputs, not approved numerical recommendations. No general policy framework was added.

Reconcile stale register/memo recommendations later after Stephan chooses: proposal-wide five-second expiry, dwell-blocked preparation, Pin/countdown UI, blanket loss/recovery wording and inconsistent old/revised timing values. This report does not edit the register or infer approvals.

Future integration requires the precise event ingress owners, atomic snapshots, accepted post-revision acknowledgement, matching-request cancellation and serialized final-effect checks in `integration-requests.md`. Current Stage 2 incompatibilities:

- No universal coordinator Director revocation before manual/Take/Edit Live/Stop admission; control-target revision alone does not represent every intervention.
- CommandDispatcher has no Director provenance/authority/request validation or Director-only continuation cancellation. Existing tracking ownership must be preserved.
- CameraManager has no atomic acknowledged Director preparation with expected post-command revisions; separate async preset/mode calls are insufficient. This review API requires accepted source unchanged and both control/shot revisions increased.
- The unwired `ShowDirectorWorld` lacks current identity evidence, nomination and policy revisions; evidence defaults false, so it cannot authorize preparation.
- TakeRequest has no Director permit context; any future Take permit needs synchronous one-shot validation with the existing technical/output checks. No execution permit can be issued here.
- NextShotStatus's legacy `.auto` projection lacks distinct level and active/paused/inhibited status. Product/UI decisions remain required; Director readiness must not restrict technically legal manual Take.

`origin/r2/sol:reports/release-2/multi-qa.md` was read and remains **Not run**. The named-rig two-camera, sustained workload and external downstream-output gates remain missing. Synthetic evidence establishes no real source timing, identity accuracy, physical safety, usefulness/editorial qualification or live Auto Direct permission. No hardware motion, microphone input or automatic cuts were enabled.

## Replay coverage and accounting

Extended the existing DirectorReplay harness. It calls the repaired authority, request validation/commit, ACK and readiness APIs; there is no parallel harness. Tests cover queued preparation after manual command/refused Take/successful Take and role swap, Edit Live entry/exit, temporary gap versus declared identity loss, source restart/rebind, output/admission faults, policy/nomination revision changes, Stop/restart/explicit Resume, expiry, replacement and duplicate callbacks, Suggest preparation refusal, unavailable Auto Direct without level substitution, persistent composition and early moving preparation with readiness withheld.

All evidence is `.synthetic`. UI override latency stays `nil` / **N/A**. Reports distinguish attempted/refused requests, actual simulated preparation commits, accepted/rejected ACKs and stale effects that commit. Tests require zero stale committed effects and zero Director cuts. `staleProposalsRejected` is a per-proposal, first-rejection reason histogram, not a denominator of committed effects; multiple reasons may describe one rejected proposal. `manualOverridesHonoured` counts interventions while pending work exists; delayed-effect assertions provide the actual cancellation check, and it is not measured UI responsiveness. Operator cuts and dwell/oscillation metrics stay separate from Director cuts; a legal manual cut below a Director study dwell is not an R2 failure.

## Exact validation

My Mac, arm64, macOS 26.6.2 build 25G83; scheme **CinematicCoreMacOS**, `CODE_SIGNING_ALLOWED=NO`. No UI test target was requested. Result-bundle summaries and test trees were read with `xcresulttool`, not inferred from repeated console case lines.

| Run | Passed / failed / skipped test definitions | Passed / failed / skipped case runs | Dynamic parameter definitions / argument runs | Result bundle |
| --- | --- | --- | --- | --- |
| Current engine base | 410 / 0 / 1 | 478 / 0 / 1 | 14 / 82 | `/private/tmp/director-lifecycle-base.xcresult` |
| Final targeted Director | 32 / 0 / 0 | 65 / 0 / 0 | 3 / 36 | `/private/tmp/director-lifecycle-targeted-final.xcresult` |
| Final full unit target | 425 / 0 / 1 | 526 / 0 / 1 | 17 / 118 | `/private/tmp/director-lifecycle-full-final.xcresult` |

Counting: top-level summary counts and test-tree `Test Case` nodes count definitions; device/configuration totals count parameterized case runs. For the final full run: **425 − 17 + 118 = 526** passed runs. For targeted: **32 − 3 + 36 = 65**. Baseline: **410 − 14 + 82 = 478**. Added 15 definitions and 48 passed case runs relative to this exact base. The unchanged skip is `RealCameraTests/twoWebcamsRenderPicturesAndBJoinsWithoutCrashing()`; it supplies no real-camera/output qualification evidence. No unrelated unit failure remains.

Commands (run from the managed worktree):

```sh
# Exact current-base run, before edits
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/director-lifecycle-base-dd \
  -resultBundlePath /private/tmp/director-lifecycle-base.xcresult

# Final targeted run
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests/DirectorAuthorityTests \
  -only-testing:CinematicCoreMacOSTests/DirectorProposalTests \
  -only-testing:CinematicCoreMacOSTests/DirectorShotPolicyTests \
  -only-testing:CinematicCoreMacOSTests/DirectorReplayTests CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/director-lifecycle-dd \
  -resultBundlePath /private/tmp/director-lifecycle-targeted-final.xcresult

# Final full unit target
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/director-lifecycle-dd \
  -resultBundlePath /private/tmp/director-lifecycle-full-final.xcresult

xcrun xcresulttool get test-results summary --path /private/tmp/director-lifecycle-full-final.xcresult --format json
xcrun xcresulttool get test-results tests --path /private/tmp/director-lifecycle-full-final.xcresult --format json
git -c core.fsmonitor=false diff --check
```

Logs use the matching `/private/tmp/director-lifecycle-{base,targeted-final,full-final}.log` names. Result-tree exports use `-tests.json`. Intermediate bundles `targeted-1` through `targeted-4` preserve the corrected old-behavior assertion failures and test macro compilation repair; they are not claimed as passing runs. `targeted-5` and the interim `full.xcresult` passed, then the final shared request validator/current-prerequisite checks were verified by both final runs above. Result bundles are local temporary artifacts, not a portable qualification record.
