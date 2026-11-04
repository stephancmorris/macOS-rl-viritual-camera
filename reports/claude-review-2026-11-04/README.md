# CLAUDE-REVIEW-1104: independent review of Claude Opus 5.5's 4 November PRs

Trello: [CLAUDE-REVIEW-1104](https://trello.com/c/C9cMNLBm). Reviewer: Grok 4.7, 4 November 2026.

**Reviewed main:** `7fd11cc` (merge of PR #108). The last code change under review is `7d08ecd` (merge of PR #107). Local toolchain Xcode 27.1 (27A9275). Hosted CI on that main was already green before this review.

I reviewed the merged diffs against the current callers and tests. Claude Opus 5.5 wrote these PRs and reviewed them only as their author. That authorship counts for nothing as evidence.

## Result

| | Count |
|---|---|
| Confirmed defects | **2** (both low, docs), fixed in this PR |
| Disproved concerns | the six priority questions below |
| Recorded, not fixed | 1 (a 500 ms residual on one CPU-span path) |

No code defect. `SWIFT_VERSION` stays 5.0. No Swift 6 CI job was added.

## Confirmed and fixed

### F1 (low): MODE-QA step 6 looks for the Cam B note during the wrong phase (#100)

- **Where:** `reports/director-study-evidence-2026-10-22/next-group.md`, checklist step 6. It said the waiting note appears while A is starting.
- **What:** `LiveShowSetupModel.startPair` sets `pendingPreviewStart` only after A has finished starting and `isRunning` is true (`LiveShowSetup.swift:211-218`). The console note is built from that flag (`LiveConsole.swift:155-157`): "Waiting for Cam A to reach the output before starting Cam B". During `isStartingSession` the note is absent. An operator following step 6 would look during startup, see no note, and could record a false failure.
- **Trigger:** Multi Cam, **Start show · A Program, B Preview**, while A is still configuring.
- **Fix:** step 6 now says the note appears after A is running, until the selected output accepts a new A frame, and that it does not appear during startup. The table row above the checklist already said this; the checklist now matches it.

### F2 (low): Multi Cam was described as enabled only with two cameras (#100, #102)

- **Where:** the same runbook's mode row, and `docs/ALFIE_MULTICAMERA_SPEC.md` (the Operator modes paragraph, previously "enabled only when two or more cameras are present").
- **What:** `OperatorModeChoice.choices` enables Multi Cam when `cameras.count >= 2`. With fewer cameras the segment shows "Connect a 2nd camera" and is enabled only when Multi Cam is already the current mode (`OperatorMode.swift:122-127`). The current mode is always kept selectable. The spec's Webcam sentence already had that exception; the Multi Cam sentence did not.
- **Trigger:** saved mode is Multi Cam, discovery sees one camera (Alfie's virtual camera is not counted). The segment stays enabled. The old sentence said it would not.
- **Fix:** both documents now state the current-mode exception. Picker locations were already right: above Start on the single-camera stopped screen (`StoppedScreen.swift:46`), the Show setup header (`ShowSetupView.swift:118`), and Settings › Show & cameras (`SettingsPages.swift:159-168`).

The degraded-operation note in the spec listed CPU, thermal state, missed Program slots and Preview age, and stopped at #98. `WorkloadMonitor` also passes whether two inputs are running, and a one-input window forces the level back to normal (`DegradePolicy.swift:93-98`, `ShowCoordinator.swift:113-114`). #107 starts the CPU span when the show goes live. The note now says both. That was an incomplete implementation note, corrected with F2, not a separate defect.

## Priority questions

### 1. #104, Swift 6 readiness

**Can `ShotComposer`, `CropEngine` or `PersonDetector` be released off the main actor, and does `isolated deinit` then defer teardown into a half-destroyed frame callback?**

They can be released off the main actor, and the deferral does not leave a half-destroyed object for a frame callback.

All three are main-actor classes (module default isolation) owned by `CameraManager`. The show owns every camera. `ShowCoordinator` already has `isolated deinit`, so its stored cameras are released on the main actor. `CameraManager` has no custom deinit; released on the main actor, it releases the three objects there, and their `isolated deinit` runs immediately and invalidates the 15 Hz timer before other stored properties are destroyed.

A background job can still be the last owner. `CropEngine.renderCrop` and `PersonDetector.performDetection` capture `self` strongly on their serial queues. If that block is the last reference, the release happens off the main actor and `isolated deinit` is scheduled onto the main actor later. Until that deinit starts, the object is still fully initialized. The timer's callback is `[weak self]` and only republishes the UI mirrors (`publishDisplayMirrors` / `publishDisplayMirror`). It does not run Vision or a crop. The in-flight render or detection holds `self` until it returns, so it cannot overlap property destruction. The signature tasks touch the composer only inside `MainActor.run`.

The deinit body is one call, `displayMirrorTimer?.invalidate()` (`ShotComposer.swift:179`, `CropEngine.swift:470`, `PersonDetector.swift:384`). Invalidating a main-run-loop timer on the main actor is the point of `isolated deinit`. A nonisolated deinit would have been the case that could invalidate the timer off the main thread.

**Are the `nonisolated static` workers and the `@unchecked Sendable` boxes justified?**

`runSignatureCapture` (`ShotComposer.swift:836`) and `runReacquisitionScoring` (`ShotComposer.swift:961`) take the extractor, a pixel-buffer box, a face rect, and (for scoring) landmark ratios plus the reference prints. They return a new print plus timing, or two distances. They do not read `self`.

`SignatureCaptureResult` carries the print created inside `extractSignature` back to the main actor. Nothing else keeps that request's observation after the extractor's queue resumes. That is a handoff of a new value.

`ReferencePrints` shares the gallery's existing `VNFeaturePrintObservation` instances with the main actor. The same justification already on `FaceSignature` (`ShotLock.swift:19-21`) holds: this code never mutates a print after capture. `computeDistance` is called only from the scoring worker, and `reacquisitionBatchInFlight` allows one batch. The main actor stores and appends prints; it does not call methods on them while a batch runs. The worker's box keeps the observations alive if the gallery evicts them.

The Vision work itself was already on `FaceSignatureExtractor`'s queue. Making the wrappers `nonisolated static` stops the wrapper from hopping to the main actor. It does not move the request.

**Does `FaceSignatureExtractor` touch main-actor state?**

No. The class (`FaceSignatureExtractor.swift:36`) holds a `let` queue and a `let` `CIContext`. `extractSignature` reads the caller's pixel buffer and dispatches to that queue. `distance` is a static function of its arguments. It does not read the composer, the detector, or any other main-actor property.

Swift 6 build result is in Validation. The project setting was not changed.

### 2. #107, CPU span

**Does every go-live path pass through `updateShowStandardLifetime`?**

Yes for the show. `isAnyChannelLive` is any channel `isRunning` or `isStartingSession` (`ShowCoordinator.swift:193-194`). Both properties call `sessionLivenessDidChange` from `didSet` (`CameraManager.swift:52`, `CameraManager.swift:820-821`). The show installs that callback in `observeChannelLiveness`, from `init` and from `addChannel`, before a channel can start. `isStartingSession = true` is the first live edge (`beginSessionStart`), so the restart runs then, not again when `isRunning` becomes true (`ownsShowStandard` is already set). A second input starting while the show is already live does not restart the span. Stop clears it only when no channel is running or starting. The app's show is the `ShowCoordinator()` in `CinematicCoreMacOSApp.swift`. The workload clock lives on that object; there is no second production clock.

**Can a restart while starting, before the first window opens, skew the sample?**

Not on a normal start. `outputPort.start()` opens the 5 s diagnostics window (`ProgramOutputManager.swift:366`, `ProgramOutputManager.swift:630`) in the same `startCapture` turn, a few statements after the starting flag. The pre-window gap is one main-actor hop.

On a camera change of the only live input, `restartWithCamera` stops the show, `beginSessionStart` restarts the span, then sleeps 500 ms before `startCapture` opens the next window (`CameraManager.swift:1862-1876`). That 500 ms of idle is inside the next `sample()` and outside the window, about a 9% dilution of one sample. Not fixed. Restarting only when `isRunning` becomes true would put the window that opens during startup back onto the pre-live span, which is the bug #107 removed. One window cannot change the level (three are required), and `runtimeWorkloadPolicy` is off.

**Is the injected `@Sendable` reading safe?**

Yes. `ProcessCPUClock` is a struct stored on the main-actor show. `restart` and `sample` run there. The production reading is `ProcessCPUClock.now`: `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)` and `ProcessInfo`, with no captured mutable state (`WorkloadMonitor.swift:72-80`). The test fake is `@unchecked Sendable` and is advanced and sampled on the test's main actor, one after the other. The app does not pass a custom reading.

### 3. #105, setup cameras

The production screen calls `LiveShowSetupModel(show:startChannelA:)` and does not pass `cameras` (`LiveShowSetup.swift:265-266`). `usesSuppliedCameras` is therefore false, and a discovery publication still applies the emitted list (`LiveShowSetup.swift:97-104`). Hot-plug still calls `discoverCameras()`. The only callers that pass `cameras` are tests (`ShowSetupTests.swift:349` and `:713`); both want the fixture to stay. No preview supplies a list and expects live discovery to replace it. `setAvailableCamerasForTesting` is inside `#if DEBUG` (`CameraManager.swift:1186-1190`).

### 4. #98, F1

`timerTick` and `refresh` are both synchronous and main-actor isolated. They cannot interleave. `refreshTick` increments only in `timerTick` (`LiveConsole.swift:166-169`), so an action refresh does not flip the skip. The next timer tick still skips or runs on its own count. `refresh()` always updates the snapshot, rates, the unmeasured-pair check and the 5 s log. Nothing else reads `refreshTick`. With the flag off, `reducesOptionalUI` is false and every tick runs.

The regression test fails without the fix. I restored the skip to the top of `refresh()`, rebuilt, and ran `LiveConsoleTests/reducedWorkloadNeverDropsAnActionsRefresh()`. It failed (exit 65): the second `setPaneView(.shot)` left `snapshot.paneView` at `.source`. The identifier needs the trailing `()`; without it xcodebuild reports success and runs 0 tests. I put the fix back before the suite below.

### 5. #101 and #103

#101 marks `CropEngine.CropRect` and `FramingCapability.Reason` `nonisolated` and puts `ProgramTakeTests.Rig` on the main actor. Both types are plain values. The test annotation does not change what the tests assert. No app behaviour change.

#103: the handle's label follows `isOpen` (`InspectorDrawer.swift:705-732`). Closed, the only control is the handle, and it says "Open Inspector". The chevron exists only in the open drawer and is hard-coded to "Close Inspector" (`InspectorDrawer.swift:93-94`). The drawer is the later layer and covers the handle (`ContentView.swift:160-177`), so the visible control matches the words. The test checks those two strings.

### 6. #100 and #102, other claims

Checked and left as written:

- Refusal copy matches `OperatorModeSwitch.decide` (`OperatorMode.swift:162-166`): "Remove Cam B or stop the show to leave Multi Cam." and "Cam B is Program. Stop the show to leave Multi Cam."
- The first-frame parenthetical matches `ProgramRouter.submit`: a non-repeat frame the sink accepts records `ProgramHandoff` (`ProgramRouter.swift:192-195`). B is added only once `hasProgramHandoff(from: .a)` (`LiveShowSetup.swift:220-227`). That is host acceptance, not receiver presentation.
- The degraded-operation note is right that the only applied effect is halving the periodic console refresh, that action refreshes always run, and that pose/face, Preview perception, render shedding, the Take veto and the unsupported latch are not applied. `ShowCoordinator.applyWorkloadWindow` stores the level and writes a diagnostics note. `WorkloadMonitor` forces the two budget flags true, so the latch cannot trip from a window.
- Runbook: fresh-install title is "SINGLE CAM · SESSION STOPPED" (`StoppedScreen.swift:32`, `OperatorMode.title`). Legacy keys are `cinematicFormat` = `stage` / `webcam` (`OperatorMode.swift:209-214`). Advance is ⌘⇧↩ (`RunSheetStrip.swift:45-47`). `followDirector` does not call `changed()`, so it does not set "Unsaved run sheet changes." (`RunSheetEditor.swift:95-99`). The sheet background is `windowBackgroundColor` (`ShowRunSheetPanel.swift:63`). `runDirectorShadow` is on in Debug and off in Release. `easedAutoPan` and `runtimeWorkloadPolicy` are `false`. The six pan CSVs exist; transit and dwell match `reports/pan-ease-2026-11/README.md` (Slow 33.3 s, Normal 16.7 s, Fast 11.1 s, dwell 1.5 s). `build_release.sh` is the fingerprint path, as `reports/release-check-2026-11/README.md` says.

#99, #106 and #108 are handoff documents. They don't change the product. No finding.

## Per-PR coverage

| PR | Reviewed | Outcome |
|---|---|---|
| #98 | `timerTick` vs `refresh`, `refreshTick`, the regression test reverted locally | Test fails without the fix (exit 65). No finding |
| #99 | Handoff rev 1 | No finding |
| #100 | Mode row, 12-step checklist, PAN-EASE, workload note, `build_release.sh` | **F1** and the Multi Cam half of **F2** fixed |
| #101 | `nonisolated` on two pure types; `@MainActor` on the test rig | No behaviour change. No finding |
| #102 | Picker locations, availability, first-frame parenthetical, degraded-operation note | **F2** fixed. First-frame and "only the refresh is applied" claims hold |
| #103 | Handle and chevron labels against `ContentView` visibility | Labels match the visible control. No finding |
| #104 | `isolated deinit`, both workers, both boxes, `FaceSignatureExtractor`; Swift 6 build | No finding. See priority question 1 |
| #105 | Production `LiveShowSetup` call, test-only closures, DEBUG seam | Production path unchanged. No finding |
| #106 | Handoff rev 2 | No finding |
| #107 | Every live edge, starting vs the first window, the injected reading | No finding. 500 ms camera-switch residual recorded above |
| #108 | Handoff rev 3 | No finding |

## Recorded, not fixed

- **C1 (#107): 500 ms of idle on a sole-input camera change.** Described under priority question 2. Not fixed, because the restart has to stay on the starting edge so the window that opens during startup is not charged to the pre-live span. One window cannot change the level, and the flag is off.

## Validation

- F1's regression test, with the skip moved back into `refresh()`: **1 test, 1 failed**, exit 65. `snapshot.paneView` stayed `.source` on the second `setPaneView(.shot)`. The fix was restored before the suite.
- Full `CinematicCoreMacOSTests` on this tree (Xcode 27.1, unsigned): **1,185 tests, 1,181 passed, 0 failed, 4 opt-in skips** (instrumentation comparison, consented-folder replay, real cameras, Core ML interop). `xcresulttool` summary `totalTestCount` 1185, `passedTests` 1181.
- Swift 6 `build-for-testing` (`SWIFT_VERSION=6` on the command line only, separate DerivedData): **TEST BUILD SUCCEEDED**. The project setting is still Swift 5.
- Python: **127** script tests and **16** Director dataset/training tests, all passed.

This review does not certify a rig, a release, or a qualification gate.

## Not reviewed

- Runtime behaviour on real cameras or a receiver, signed builds, and VoiceOver in the running app. That is owner or rig work.
- Code outside these PRs.
- Whether to switch the project to Swift 6 or add a Swift 6 CI job. Both stay with the owner (`reports/swift6-readiness-2026-11/README.md`).
