# Sol results — 5 November 2026

## Merged work

| Item | PR | Merge commit | Local unit suite, Xcode 27.1 | Hosted unit suite, Xcode 26.2 |
| --- | --- | --- | --- | --- |
| M1: readiness, fault recovery, webcam feasibility | [#113](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/113) | `dd7ee58759a9d992bacf60dc60f9546262161c15` | 1,210 passed, 4 skipped, 0 failed; 1,214 total | 1,210 passed, 4 skipped, 0 failed; 1,214 total |
| M2: focused commands and text-safe cue keys | [#114](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/114) | `cf017e947b3ad88f361212afdc59dc0048cea037` | 1,233 passed, 4 skipped, 0 failed; 1,237 total | 1,233 passed, 4 skipped, 0 failed; 1,237 total |

Both PRs use merge commits and were merged only after the full local unit suite and all hosted CI checks were green. The hosted workflow also builds Release, runs report/training tests and checks consistency. No known detector-timeout rerun was needed. The four skips are existing opt-in tests.

- M1 CI: [run 42016115097](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/42016115097).
- M2 CI: [run 42019057348](https://github.com/stephancmorris/macOS-rl-viritual-camera/actions/runs/42019057348).
- Final main verification: `cf017e947b3ad88f361212afdc59dc0048cea037`, Xcode 27.1, 1,233 passed / 4 opt-in skips / 0 failures (1,237 total), using the full unit suite under a 30-minute limit; result at `/private/tmp/alfie-ux-sol-main-unit.xcresult`.

Work used a separate bare clone and worktree at `/private/tmp/alfie-ux-sol`, with DerivedData at `/private/tmp/alfie-ux-sol-dd`. The owner's checkout was read only and was never edited. Branches were `sol/ux-m1-models` and `sol/ux-m2-commands`. Commits staged explicit source/document paths only.

## M1 integration contract

`Readiness/ReadinessModel.swift` contains the pure nonisolated evaluator and its input/result values. Rows have stable order: camera access, virtual camera, Program output. `blockingRow` is the first required row that is missing or waiting. Ready/unnecessary rows and checks already in progress offer no redundant action. An unknown extension status offers Install: the existing properties check can fail while leaving that status unknown.

`Readiness/ReadinessObserver.swift` reads permission, source choice, mode, extension status and chosen-route status without starting cameras or installing anything. Call `refresh()` before Start and after recovery. Recreate it when the set of participating cameras changes. Webcam evaluates the virtual-camera route even when a saved preference names another route; Wave 2 must ensure the actual Start uses the matching route. Direct output follows the existing display-selection policy within that route, and does not borrow another route's ready status. Virtual XPC is normally idle before Start, so an idle registered sink passes preflight while installation remains a separate gate. Readiness does not prove frame delivery.

`Readiness/FaultRecovery.swift` exhaustively maps all ten CameraError cases without a default. Live faults specify a banner; stopped faults specify an alert. Raw decoder details do not become operator copy. Views still own recovery execution and presentation.

Tests include all 1,890 mode/route/input/permission/extension/output combinations, adapter and observation checks, each fault in live/stopped states, channel-specific ownership copy and detached pure evaluation. The M1 focused run passed 15 test declarations / 45 case executions.

## M2 integration contract

`AlfieCommandCatalog.swift` is the single key/title table, including reservations for standard macOS keys. TAKE has no key. Stop keeps ⌘⌥⇧S; Director hand keeps ⌘⇧H; run-sheet advance keeps ⌘⇧Return. Existing Director view handlers are unchanged.

`AlfieCommandFocus.swift` exposes an independent writable FocusedValues key per command, so Track B and Track C can publish from their own views without replacing each other's commands. For example, publish an `AlfieCommandAction` with `.focusedSceneValue(\.alfieCuePreview1, action)`. Withdraw the action when it is unavailable. Use `alfieCancel` for either Cancel Detect or Done Editing Live, with the appropriate action title and only in its active context. Keep TAKE published while live and let its existing refusal path explain an invalid attempt.

`AlfieCommands.swift` defines Session, Shot, Multi Cam, View/Inspector and Debug Director menus. No production view publishes the new keys in Wave 1, as instructed. Consequently the new menu commands, including Stop Session, remain disabled until Wave 2 publishers land. Preserve the show-level Stop action and its diagnostics when wiring it.

Bare character keys are listed explicitly in menu labels and dispatched by one native local event monitor. They are not SwiftUI menu key equivalents, which could consume typing before a text editor receives the event. The router reads the native responder on every event and passes the original event through for text clients, secure field editors, another window, modal/sheet windows, repeated/shortcut-modified events and absent actions. Only a published matching action consumes a key. The final full run includes all 23 M2 tests, including native text insertion and catalog uniqueness/reservations.

## Feasibility recommendation

Use host-side CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` first, with in-use / not-in-use / unknown states. This avoids an extension update and re-activation. It detects stream activity, not the receiving app's identity or proof of call/frame delivery. The scratch probe compiled but saw no devices in the sandbox; no installed-device behavior was validated.

The [feasibility note](../../ux/2026-11-05/webcam-in-use-feasibility.md) records Apple references, implementation guidance, limitations and the required owner-rig matrix. Use a versioned XPC reply only if rig evidence shows the property is unusable or a real client count becomes necessary. Do not equate the existing callback counter with distinct apps without verifying its semantics.

## Deferred work and gates

- Detect and the five shot-command keys remain unset and marked pending in the catalogue. Astra's `docs/ux/2026-11-05/keyboard-map.md` was absent from main. PR #114 is explicitly marked “keys pending Astra map”; no unspecified keys were invented.
- Track B journeys 6, 7, 8, Multi Cam faults in 9, and console Stop in 12 have not started. Their explicit start gate is the merge of Opus's Wave 1 palette, shared button styles and accessibility changes. At final main verification, F1/F7 are merged, but the Wave 1 shared AlfieButtonStyle family and the remaining Wave 1 foundation PRs are absent from main. Use a new `sol/ux-track-b-*` branch per journey or small series once that gate opens.
- Wave 2 view wiring for readiness/faults and focused commands belongs to the appropriate track. End-to-end SwiftUI TextField/TextEditor focus checks remain necessary when commands are published.
- Snapshot additions and gallery capture regeneration belong to the upcoming journey PRs; no journey UI changed in M1/M2. The real camera/ATEM rig, consuming apps and accessibility settings have not been checked by this run. No rig, camera pair, release or privacy gate is certified.
- Console hold-to-stop still depends on the shared Track A StopSessionLabel and Astra's stop spec. No replacement control was invented.
- Wave 3 review of Astra's Track C is deferred until its PRs exist.

## Owner questions

None. The next steps depend on programme deliverables and rig validation, not a new owner decision. Decisions D1–D6 are unchanged. No camera extension, XPC service name, Director authority, qualification record or DeveloperFlags release behavior was changed. TAKE remains an explicit operator action with no key equivalent.
