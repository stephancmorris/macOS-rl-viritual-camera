# Swift 6 language-mode readiness (4 November 2026)

Trello: SWIFT6-READINESS. Agent: Claude Opus 5.5.

**Result.** With this change, the app, the CMIO extension and every test target compile under `SWIFT_VERSION=6`, the Swift 6 language mode with full data-race checking. The project's setting is still **Swift 5** (`SWIFT_VERSION = 5.0`). Switching it, and choosing whether CI should enforce Swift 6, is the owner's decision. Everything here also builds in Swift 5 mode, with **0** Swift warnings in app and test sources.

## Method

Starting from the isolation-warning cleanup (ISOLATION-WARNINGS), I repeatedly ran `xcodebuild build-for-testing … SWIFT_VERSION=6` and fixed whatever the compiler reported, until the build succeeded. Every fix is the narrowest available. None changes logic, timing, frame publishing, routing, Take or Director authority.

## What changed, and why it's safe

| Kind | Where | Why |
|---|---|---|
| `nonisolated` Sendable boxes | `CropEngine.RenderSource`, `PersonDetector.SendablePixelBuffer`, `ProgramRouter.StandbyFrameBox`, `ShotComposer`'s file-scope `SendablePixelBuffer` | Under `default-isolation=MainActor` these boxes' initializers were MainActor-isolated, yet they're built off the main actor. `ShotComposer`'s comment even says the box sits "at file scope so it doesn't inherit main-actor isolation", which isn't true under default isolation. |
| `nonisolated` pure value types | `CropEngine.CropRect`, `CropEngine.QualityFloor`, `FramingCapability` (and its `Reason`), `PersonDetector.LockProbation` / `LockedResolution`, `PlayoutRateHandshake` (`ShowStandard.swift`), `ProgramOutputManager.Route` | These are plain values. Their doc comments already call them "pure… no actor". `ShowStandard.swift` and `ProgramOutputManager.swift` also compile into the extension, which builds unchanged. |
| `isolated deinit` | `ShotComposer`, `CropEngine`, `PersonDetector` | Each deinit invalidates the 15 Hz UI-mirror `Timer`. The codebase already uses `isolated deinit` in four places (`ShowCoordinator`, `ProgramRouter`, `DisplayOutputSink`, …). This is also *more* correct: a `Timer` must be invalidated on the run loop it was scheduled on, which is the main one. The deployment target is macOS 26.2. |
| `nonisolated` worker statics, plus result boxes | `ShotComposer.runSignatureCapture` / `runReacquisitionScoring`; `SignatureCaptureResult`, `ReferencePrints` | Their comments call them "pure non-isolated" workers, but they were MainActor-isolated, so each detached task hopped to the main thread for its wrapper. They now run where the comments say. Vision `VNFeaturePrintObservation` values cross actors only in `@unchecked Sendable` boxes, on the same basis as the existing `FaceSignature` (the prints are immutable after capture). |
| `nonisolated` class | `FaceSignatureExtractor` (already `@unchecked Sendable`) | Its async `extractSignature` only reads `let` properties and dispatches to its own queue, so it needs no main-actor isolation. |
| Tests | `TakeBarTests` key-path arguments become `& Sendable`; `ProgramTakeTests.Rig` gets `@MainActor` (ISOLATION-WARNINGS) | Swift Testing arguments must be Sendable. |

**Disproved concern:** whether face-print Vision work ran on the main thread because the worker statics were MainActor-isolated. It didn't: `extractSignature` already performs the Vision request on the extractor's own `DispatchQueue`. Only the thin wrapper hopped to the main thread.

## Verification

Local runs on Xcode 27.1, unsigned:

| Mode | Build | Full CinematicCoreMacOSTests |
|---|---|---|
| Swift 6 (`SWIFT_VERSION=6`) | **TEST BUILD SUCCEEDED** (app, extension, tests) | **1,180 tests, 1,176 passed, 0 failed, 4 opt-in skips** |
| Swift 5 (project setting) | succeeded, **0** Swift warnings in a clean build | 1,180 tests, 1,175 passed, **1 failed** (see the flake below), 4 skipped |

**The one Swift 5 failure is a pre-existing test-isolation flake, not caused by this change.** It was `ShowSetupTests.liveSetupLocksForBOnlyLivenessAndGuardsActionsBeforeTheUIRefresh`.
- Rerun alone, it passes 3 of 3 times on this branch and 2 of 2 on main's build.
- The failed state shows the setup's devices replaced by this Mac's real "MacBook Pro Camera". During the full parallel run, a camera connect/disconnect notification makes `LiveShowSetupModel` rediscover on channel A, and its `$availableCameras` observer overwrites the test's injected fixture cameras, so `canStartPair` reads false.
- No file this change touches is involved. It is filed separately as SETUP-TEST-FLAKE.

## Recommendation (owner)

1. **Switch to Swift 6 now or later.** Set `SWIFT_VERSION = 6.0` for the app, extension and test targets. After this change the switch is a one-line project edit, but it adds runtime isolation checks: a wrong `MainActor.assumeIsolated` or a misplaced callback traps instead of warning. Run the attended MODE-QA first in a Swift 6 Debug build if you want that safety net exercised on the rig.
2. **Or keep Swift 5 and add a non-blocking CI job** that builds with `SWIFT_VERSION=6`, so regressions show up early. That's a CI policy choice, so it isn't added here.
