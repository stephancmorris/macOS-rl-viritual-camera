# PR-REVIEW-1104: review of PRs #85–#96, #29 and #97

Trello: [PR-REVIEW-1104](https://trello.com/c/0U0ZMxZl). Reviewer: Claude Opus 5.5, 4 November 2026.

**Reviewed main:** `823a0c3c` (docs-only handoff on top of `8c9f438`). Local toolchain Xcode 27.1 (27A9275); hosted CI uses Xcode 26.2.

I reviewed the merged diffs (`gh pr diff` / merge-commit diffs) against the current callers and tests, not against the PR descriptions. Some of these PRs were written by an earlier Claude session; that authorship counts for nothing as evidence.

## Result

| | Count |
|---|---|
| Confirmed defects | **1** (low), fixed in this PR with a regression test |
| Disproved concerns | 2 |
| Unconfirmed concerns / observations, not fixed | 3 |

## Confirmed and fixed

### F1 (low): under workload pressure the Multiview console dropped action-driven refreshes (#92)

- **Where:** `Console/LiveConsole.swift`, `refresh()` (before the fix, the skip lived at the top of `refresh()`).
- **What:** #92 thinned the console to every other refresh when `show.reducesOptionalUI` is true. The counter sat inside `refresh()`, and `refresh()` isn't only the 15 Hz timer: `take()`, `setEditLive`, `setPaneView`, `advanceDirectorSegment`, `reconnect` and others call it for immediate feedback. Every other one of those calls returned early, so after an operator action the snapshot (pane view, Take message, Edit Live banner) stayed stale until the next timer tick ran.
- **Trigger:** only with `DeveloperFlags.runtimeWorkloadPolicy` on (it is off by default) and the policy at `optionalUI` or above. Then call `setPaneView(.source)` followed by `setPaneView(.shot)`: the second call is skipped and `snapshot.paneView` stays `.source`.
- **Evidence:** the new `LiveConsoleTests.reducedWorkloadNeverDropsAnActionsRefresh` fails on the pre-fix code (rc 65, 1 failure) and passes with the fix.
- **Fix:** a new `timerTick()` owns the thinning; the timer calls it, and `refresh()` always runs. Behaviour with the flag off is unchanged.

## Disproved

- **D1 (#86): could a route change mid-session leave Cam B waiting forever?** `ProgramRouter.submit` records a handoff only when none is stored (`ProgramRouter.swift:194`), and `hasCurrentHandoff` also compares the route. If the active route could switch while running, a stale handoff would never be replaced. It can't: `ProgramOutputManager` freezes `sessionRoute` while capture runs (`ProgramOutputManager.swift:937`). The route is either that one or nil while its sink is unavailable, so it never changes to a different route mid-session.
- **D2 (#92): do frame-pacing repeats count as missed Program frames?** `WorkloadMonitor.programDeadlineMissFraction` (`WorkloadMonitor.swift:31`) counts `repeated`. The only repeat sources are render-failure HOLD (`CameraManager` `isRepeat: isProgramHolding`) and router hold/standby (`ProgramRouter.swift:301/303`), not capture-rate pacing. A 30 fps camera therefore doesn't read as 40% misses.

## Unconfirmed concerns and observations (not fixed)

- **C1 (#92): the miss fraction under-reports.** It counts explicit failures (repeats, refusals, no route, render failures) but not frames a slow pipeline simply never produces. A Program running at 40 of 50 fps without failures reads as 0% misses. CPU and Preview age still feed the policy. Thresholds and inputs are provisional until MULTI-QA, so this is a calibration question for the rig, not a code fix here.
- **C2 (#92): the first CPU sample.** `ProcessCPUClock` starts at `ShowCoordinator` init, so the first window's CPU fraction averages over everything since launch. One window can't trigger a level change (three are needed), so this has no effect in practice.
- **C3 (#97): stale reason text.** The Workload row shows the last transition's reasons. After recovery it reads "Normal · Recovering after pressure" until the next change. That's accurate ("last change") but could read as ongoing. The copy is the owner's call; I left it as is.

## Per-PR coverage

| PR | Reviewed | Outcome |
|---|---|---|
| #85 | Integration merge: the user-guide conflict and the B12 split against #81 | The kept Settings path ("Diagnostics → Session log → Logs → Reveal in Finder") and "Record Training Data" match `SettingsPages.swift:1097-1107` and `RecorderSettingsView.swift:20`. #81's `CameraManager` edits (`sessionLivenessDidChange`, `lifetimeID`, recorder injection, `requestStopRecording`) are present after the split. No finding |
| #86 | Router handoff, show mirror, pair-start wait, console note | Re-reads live router state after every wake, so dropped AsyncPublisher emissions are harmless. Stop, mode departure, A stopping and session replacement all wake the waiter. D1 disproved. No finding |
| #87 | Plan doc | Superseded by #96. No finding |
| #88 | Move-only claim, checked mechanically | All 560 removed lines reappear verbatim. The only non-move edit is the declared `reacquisitionConsecutiveFrames` private → internal. No finding |
| #89 | `followDirector`, panel background, presenter `onChange` | Following doesn't mark edits unsaved; unknown IDs are ignored; nothing is per frame. No finding |
| #90 | AD-RECONCILE report | Spot-checked the cited tests and code (`DirectorAuthority.apply`, `DirectorAssistPolicy` movement guard). The claims hold. No finding |
| #91 | `AutoPanMotion`, the flag, tests | The curve is continuous and monotonic, the flag is a `false` constant, and phase timing is unchanged. No finding |
| #92 | Observer hook, `WorkloadMonitor`, show wiring, console thinning | **F1 fixed.** C1 and C2 recorded; D2 disproved. The extension-compiled `ProgramOutputManager` change uses only `DiagnosticsWindow`, which the extension already has |
| #93 | Digest method and counts | Method is sound. It classifies gates by keyword, so treat (a) as "recommend", as it says |
| #94 | Figures and captions; checklist wording | Captions label the renders synthetic; the checklist forbids treating them as evidence. No finding |
| #95 | `nonisolated` on three pure members | All three are pure (no MainActor state). No finding |
| #96 | Handoff doc | No finding |
| #29 | `ci.yml`, time limits, artifact and summary steps, Release build, consistency step; the hosted gallery sizing fix | A failed test step fails the job. There are time limits at three levels (job 60, step 50, process alarm 45 min). Signing workflows stay manual. No tests or size assertions were dropped. No finding |
| #97 | `InspectorWorkloadDetail`, the 2 Hz `TimelineView`, VoiceOver copy, tests | Reads `level` and `transitions.last` together at 2 Hz; hidden when the policy is nil; no published state. C3 recorded. No finding |

## Validation

- Baseline main `823a0c3`, before the fix: 1,179 tests, 1,175 passed, 0 failed, 4 opt-in skips.
- With the fix: 1,180 tests, 1,176 passed, 0 failed, 4 opt-in skips. Python: 127 script and 16 Director training tests passed.
- The regression test fails on the pre-fix code and passes after.

## Not reviewed

- Runtime behaviour on real cameras or a receiver, signed builds, and VoiceOver in the running app. All of that is owner or rig work.
- Code outside these PRs (this isn't a repository-wide audit).
- Grok should independently review this PR's fix: F1 and its test.
