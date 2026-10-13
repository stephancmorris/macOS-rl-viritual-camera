# AI-code hygiene report

**Status: in progress.** This commit records confirmed findings and the resume checklist. Batches are withheld until every in-scope file has been read, so a file is not locked into a batch before its other findings are known. Do not hand Prompt B out against this revision.

## Header

| | |
|---|---|
| SHA | `272c0659e766bfd5e4db6b68be0281f3c5501079` (`272c065`, Merge pull request #32, 2026-10-11) |
| Date | 2026-10-14 |
| Worktree | `/Users/stephanmorris/Documents/alfie-hygiene`, branch `review/ai-hygiene-2026-10` |
| Build | `xcodebuild build` scheme `CinematicCoreMacOS`, `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, derived data `/private/tmp/hygiene-dd`. **BUILD SUCCEEDED.** |
| Files | 202 in scope. This revision has finished a full read of the files marked read below. The rest are unchecked on the resume checklist. |
| Tools | `ruff 0.15.10` on `training/` and `CinematicCoreMacOS/scripts/` (`F401`, `F841`, `E722`, `T201`). `periphery`, `jscpd`, and `vulture` are not installed; they were not installed. |

### Build warnings

Seven `warning:` lines. Four are not source hygiene: AppIntents metadata extraction skipped (twice; the app does not link AppIntents), and the system extension is embedded under `Contents/Library/SystemExtensions` rather than `PlugIns` (CMIO packaging, not a code habit).

Hygiene-relevant warnings, all confirmed as findings below:

1. `LiveShowSetup.swift:59` and `:75` — call to main-actor-isolated `device` in a synchronous nonisolated context.
2. `PersonDetector.swift:196` — `nonisolated(unsafe)` is unnecessary for a `Sendable` `CIContext`.
3. `ShotComposer.swift:1501` — result of `MainActor.run` is unused.

### Open PRs (findings in these files wait)

| PR | Files |
|---|---|
| #29 | CI workflows, `docs/ci/**`, `scripts/ci/check_consistency.sh` (no in-scope source yet) |
| #28 | `Console/Gallery/DirectorControlDemo.swift`, `DirectorModeControlTests.swift` |
| #26 | `Director/DirectorAuthority.swift`, `DirectorAuthorityTests.swift` |
| #25 | `Director/DirectorConsoleAPI.swift`, `Director/Replay/DirectorReplay.swift` |
| #23 | `Console/Gallery/MultiviewGallery.swift` |
| #21 | none of these files exist on this SHA |
| #18 | `Director/Replay/DirectorReplay.swift`, `Director/Replay/DirectorReplayFixtures.swift` |

`DirectorReplay.swift` is in both #18 and #25. No finding in this revision touches an open-PR file.

## Summary so far

Counts below are only findings already verified against this SHA. They will grow as the unread files are finished. Plausible leads are not counted as batchable findings.

| Category | Confirmed | Of which Needs owner |
|---|---|---|
| C comments | 23 | 0 |
| D duplication | 1 | 0 |
| X dead code | 2 | 0 |
| E swallowed errors | 2 | 2 |
| S concurrency | 6 | 0 |
| T tests | 2 | 0 |
| P Python | 4 | 0 |
| **Total confirmed** | **40** | **3** (HY-0005, HY-0035, HY-0042) |

Severity of the 37: **0 High, 5 Medium, 32 Low.** The medium ones are the three compiler warnings, the duplicated team-identifier helper, and the DeckLink scripts that would reintroduce a removed route.

### Themes

1. **Closed-ticket labels in file headers and property comments.** `Ticket: APP-02`, `Task 2.3 - LOGIC-01`, `GFX-01`, `RL-01`, `VIS-01`, and `CR-036` / `CR-038` name the work item and not the invariant. Confirmed in 14 files so far. The Created-by lines around them stay (intentional pattern 6); only the ticket line goes.
2. **`@unchecked Sendable` / `nonisolated(unsafe)` is usually explained, and the unexplained ones are the finding.** Capture-session, crop-render, and diagnostics boxes already say why they are safe. Three boxes and two face-signature structs do not.
3. **The app target is MainActor by default; the extension and both test targets are not** (`SWIFT_DEFAULT_ACTOR_ISOLATION` is set only on the Alfie app configurations). Explicit `@MainActor` on app types is redundant, and it is load-bearing on anything the extension or tests compile. It is not a batch.
4. **Training constants are copied on purpose.** `CinematicAgent` and `training/cinematic_env.py` share pan/tilt/zoom speeds and `maxZoom = 4.0`. That is the training contract, not duplication to merge.
5. **`print` is not the app's logger.** App code uses `Logger(subsystem: "com.alfie", category:)`. `print` shows up in opt-in tests and in Python CLIs.

### Best value so far, for the risk

1. Delete `update_xcode.rb` and `test_decklink.cpp` (HY-0024). Running the Ruby script adds the removed DeckLink files back into the Xcode project.
2. Clear the three compiler warnings (HY-0007, HY-0010, HY-0021).
3. Give the app and the extension one `ownTeamIdentifier()` (HY-0025), so the XPC peer check cannot drift.
4. Delete the comment that narrates a removed per-frame `CIImage` (HY-0004). It invites someone to put the allocation back.
5. Add the missing safety comments on the unchecked Sendable boxes (HY-0008, HY-0011, HY-0033).
6. Drop unused Python imports and the unused `stats` binding (HY-0026–HY-0029).
7. Strip ticket-only comments (the C3 set). Low risk, and it stops the next agent treating a closed ticket as a requirement.
8. Make the UI-test launch check assert that the app is running (HY-0032).
9. Owner: should discovery keep hiding cameras whose name contains "Test"? (HY-0005)
10. Owner: should a failed camera switch surface the error? (HY-0035)

## Conventions

| Concern | Dominant pattern | Examples |
|---|---|---|
| Logging | `Logger(subsystem: "com.alfie", category:)` via OSLog. Not `print`. | `CameraManager.swift:211`, `PersonDetector.swift:19`, `CropEngine.swift:21` |
| Errors that matter | Typed errors (`CameraError`) and a published `error` the UI reads. `try?` is for best-effort IO (debug dumps, optional JSON in defaults). | `CameraManager.swift:166`, `InspectorDrawer.swift:252` (the exception, see HY-0035) |
| Actor isolation | App target: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Extension and tests: no default. Shared files keep an explicit isolation annotation. | `project.pbxproj` app Debug/Release; `ShowStandard.swift:14` is `nonisolated enum` because it is shared |
| Coordinates | Vision boxes are normalised, origin bottom-left, Y up. MediaPipe in `training/` is top-left; `vision_y = 1 - mp_y` is deliberate. | `PersonDetector.swift:57` |
| Training constants | Named in `training/cinematic_env.py` (`MAX_PAN_SPEED` 0.02, `MAX_ZOOM` 4.0) and repeated in `CinematicAgent` with a "must match" comment. Do not fold them together. | `cinematic_env.py:25-31`, `CinematicAgent.swift:36-40` |
| Tests | Swift Testing (`#expect`, `#require`). `@MainActor` on test types stays, because the test target has no default isolation. | `StartGateTests.swift:12` |
| XPC identity | Service name and app-group prefix live once in `CinematicCoreXPC` and are duplicated only where the extension Info.plist must match. Team-id *lookup* is copied as code and should not be. | `CinematicCoreXPCProtocol.swift:53`, HY-0025 |

## Per-file findings

### `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`

Partial read (headers, discovery, frame-path comments, `restartWithCamera`, `VirtualCameraOutputSink`). More findings may appear when the rest of the 3,099 lines is finished. Not batched yet.

#### HY-0001 · C3 ticket provenance · Low · Confirmed
**Where:** `CameraManager.swift:207-209`
**Current:**
```swift
/// Manages the AVCaptureSession pipeline for 4K video capture
/// Ticket: APP-01 - AVCaptureSession Pipeline
@MainActor
```
**Proposed:**
```swift
/// Manages the AVCaptureSession pipeline for 4K video capture
@MainActor
```
**Why:** The ticket line names a closed work item. The first line already says what the type does.
**Evidence:** n/a (comment-only)
**Behaviour change:** None
**Verify:** build only

#### HY-0002 · C3 ticket provenance · Low · Confirmed
**Where:** `CameraManager.swift:269-295` and `731`
**Current:**
```swift
    /// Person detector (Task 2.1)
    let personDetector = PersonDetector()

    /// Crop engine (Task 2.2 - GFX-01)
    let cropEngine: CropEngine?

    /// Shot composer (Task 2.3 - LOGIC-01)
    let shotComposer = ShotComposer()

    /// RL-trained CoreML agent (Task APP-02)
    let cinematicAgent = CinematicAgent()
```
and `// Initialize crop engine (Task 2.2 - GFX-01)` immediately above `self.cropEngine = CropEngine()`.
**Proposed:** delete those five doc comments and the initialize comment. Leave the declarations, including the later training-recorder comment's deletion:
```swift
    /// Training data recorder (Task 3.1 - RL-01)
    let trainingDataRecorder = TrainingDataRecorder()
```
becomes `let trainingDataRecorder = TrainingDataRecorder()` with no comment.
**Why:** Each comment restates the property's type and a ticket id.
**Evidence:** n/a (comment-only)
**Behaviour change:** None
**Verify:** build only

#### HY-0003 · C5 commented-out code · Low · Confirmed
**Where:** `CameraManager.swift:774-778`
**Current:**
```swift
//        
//        print("   Found \(devices.count) camera(s) (excluding MacBook Pro for testing)")
//        if devices.count != allDevices.count {
//            print("   ⚠️ Filtered out: \(allDevices.count - devices.count) camera(s)")
//        }
```
**Proposed:** delete lines 774–778.
**Why:** Commented-out debug prints. The live filter above them is HY-0005, not this finding.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

#### HY-0004 · C2 change narration · Low · Confirmed
**Where:** `CameraManager.swift:1871-1873`
**Current:**
```swift
        // NOTE: a `CIImage(cvPixelBuffer:)` used to be built here and never
        // used — one wasted image object per frame on the exact path the memory
        // investigation is looking at. Removed so it cannot muddy attribution.
```
**Proposed:** delete lines 1871–1873.
**Why:** The allocation is gone. The comment describes the edit, and the next lines (`bufferWidth` / `bufferHeight`) do not need it.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

#### HY-0033 · S1 unchecked Sendable without a safety comment · Low · Confirmed
**Where:** `CameraManager.swift:16-22`
**Current:**
```swift
private final class SendablePixelBufferBox: @unchecked Sendable {
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer

    nonisolated init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}
```
**Proposed:**
```swift
/// `CVPixelBuffer` is not `Sendable`. The frame path hands this box across a
/// task and does not touch the buffer again until that task finishes.
private final class SendablePixelBufferBox: @unchecked Sendable {
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer

    nonisolated init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}
```
**Why:** Intentional pattern 3 allows the box. This one, unlike `CaptureSessionBox` directly below it, never says why the unchecked conformance is safe.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

#### HY-0005 · X2 debug filter left in the discovery path · Needs owner
**Where:** `CameraManager.swift:769-773`
**Current:**
```swift
        // TEMP Testing: Filter out Cameras for debugging
        let allDevices = discoverySession.devices
        let devices = allDevices.filter { device in
            !device.localizedName.lowercased().contains("Test")
        }
```
**Question:** Should `discoverCameras()` keep hiding any device whose localized name contains "Test"? Removing the filter changes which cameras the operator can pick. It is not in a batch.
**Evidence:** `allDevices` is only used by this filter and by the commented-out prints in HY-0003.
**Behaviour change:** Yes, if the filter is removed.

### `CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift`

Partial read (header, downscale, `clearForInactiveMode`, `SendablePixelBuffer`).

#### HY-0006 · C3 ticket provenance · Low · Confirmed
**Where:** `PersonDetector.swift:15-17` and `55`
**Current:**
```swift
/// Detects and tracks people in video frames using Apple Vision framework
/// Ticket: VIS-01 - Person Detection
@MainActor
```
and
```swift
    /// Body pose keypoints for rule-of-thirds composition (Task 2.3 - LOGIC-01)
```
**Proposed:** delete the `Ticket:` line. Rewrite the keypoints comment to:
```swift
    /// Body pose keypoints for rule-of-thirds composition.
```
**Why:** The ticket ids add nothing the surrounding sentences do not already say.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

#### HY-0007 · S3 unnecessary `nonisolated(unsafe)` · Medium · Confirmed
**Where:** `PersonDetector.swift:196-203`
**Current:**
```swift
    nonisolated(unsafe) private static let downscaleContext = CIContext(options: [
```
**Proposed:**
```swift
    nonisolated private static let downscaleContext = CIContext(options: [
```
**Why:** The Release build warns that `nonisolated(unsafe)` is unnecessary for a constant of `Sendable` type `CIContext`. `nonisolated` must stay: `flushImageCaches()` is `nonisolated` and calls `Self.downscaleContext.clearCaches()` (`PersonDetector.swift:444-445`). Dropping the whole attribute would isolate the constant to the MainActor and break that call. The comment above the property (lines 190–192) still explains that this state is touched only from `processingQueue`; extend that sentence with "CIContext is Sendable, so the constant does not need unsafe."
**Evidence:** build log `/tmp/hygiene-build.log` line 508.
**Behaviour change:** None
**Verify:** build only. If `nonisolated` without `unsafe` fails to compile, stop and record it; do not silence the warning with `unsafe`.

#### HY-0008 · S1 unchecked Sendable without a safety comment · Low · Confirmed
**Where:** `PersonDetector.swift:468-470`
**Current:**
```swift
    private struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }
```
**Proposed:**
```swift
    /// `CVPixelBuffer` is not `Sendable`. Detection reads the buffer on
    /// `processingQueue` and does not write it.
    private struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }
```
**Why:** Same pattern as `FaceSignatureExtractor.swift:61-64`, which already has the one-line reason. This copy does not.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift`

Partial read (header, face-signature types, reacquisition hop).

#### HY-0009 · C3 ticket provenance · Low · Confirmed
**Where:** `ShotComposer.swift:6`
**Current:**
```swift
//  Ticket: LOGIC-01 - Rule-Based Shot Composer
```
**Proposed:** delete line 6. Leave the Created-by line and the doc comment at lines 17–22.
**Why:** Ticket label only.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

#### HY-0010 · S2 unused `MainActor.run` result · Medium · Confirmed
**Where:** `ShotComposer.swift:1012-1027` and `1500-1508`
**Current:**
```swift
    @discardableResult
    func finishReacquisitionScoring(
        generation: UInt64,
        visibilityRevision: UInt64,
        observationID: UInt64,
        scores: [ReacquisitionScore]
    ) -> Bool {
```
called as the only expression of:
```swift
            await MainActor.run {
                strong.finishReacquisitionScoring(
                    generation: generation,
                    visibilityRevision: visibilityRevision,
                    observationID: observationID,
                    scores: completedScores
                )
            }
```
**Proposed:** discard the `Bool` inside the hop so `run` returns `Void`:
```swift
            await MainActor.run {
                _ = strong.finishReacquisitionScoring(
                    generation: generation,
                    visibilityRevision: visibilityRevision,
                    observationID: observationID,
                    scores: completedScores
                )
            }
```
**Why:** The function is `@discardableResult` and returns `Bool`. As the closure's only expression, that `Bool` becomes the result of `MainActor.run`, which is not discardable. The build warns at column 29 of line 1501. The other `MainActor.run` at line 1374 is a multi-statement closure and does not warn. The hop itself stays: it is inside `Task.detached`, not already on the MainActor.
**Evidence:** build log line 512.
**Behaviour change:** None. The `Bool` was already discarded.
**Verify:** build only. The warning at `ShotComposer.swift:1501` must be gone.

#### HY-0011 · S1 unchecked Sendable without a safety comment · Low · Confirmed
**Where:** `ShotComposer.swift:777` and `792`
**Current:**
```swift
    struct FaceSignature: @unchecked Sendable {
        let featurePrint: VNFeaturePrintObservation
```
and
```swift
    struct FaceSignatureGallery: @unchecked Sendable {
```
**Proposed:** add to each doc comment, before the struct:
```swift
    /// `VNFeaturePrintObservation` is an immutable class and is not
    /// `Sendable`. It is not mutated after capture, so the struct can cross
    /// the re-acquisition task.
```
The gallery comment adds: "The gallery value is copied into that task; its methods mutate the copy, not a shared instance."
**Why:** The existing comments explain what the gallery is for. They do not say why `@unchecked Sendable` is safe. The annotation stays.
**Evidence:** `VNFeaturePrintObservation` is a class stored in a `let`. Gallery mutation is `mutating` on the struct (`append` at line 808).
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift`

Partial read (header, render queue, `init?()`).

#### HY-0012 · C3 ticket provenance · Low · Confirmed
**Where:** `CropEngine.swift:6` and `30-32`
**Current:**
```swift
//  Ticket: GFX-01 - Metal Crop Engine
```
and
```swift
        /// Smoothing factor for crop transitions (0 = instant, 1 = very smooth)
        /// 10% per frame as specified by LOGIC-01
        var transitionSmoothing: Float = 0.10
```
**Proposed:** delete line 6. Replace the smoothing comment with:
```swift
        /// Smoothing factor for crop transitions (0 = instant, 1 = very smooth).
        /// 0.10 moves 10% of the remaining distance per frame.
```
**Why:** The ticket ids are provenance. The 10% figure is the actual constant and stays.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

`CropEngine.init?()` at line 440 returns nil when `MTLCreateSystemDefaultDevice()` fails. The nil check in `CameraManager` after `CropEngine()` is live. See Refuted.

### `CinematicCoreMacOS/CinematicCoreMacOS/CropRenderer.metal`

#### HY-0013 · C3 ticket provenance · Low · Confirmed
**Where:** `CropRenderer.metal:6`
**Current:**
```metal
//  Ticket: GFX-01 - Metal Crop Engine
```
**Proposed:** delete line 6. Keep lines 8–12, which explain why the file is empty and why both targets still compile it.
**Why:** The emptiness comment is the reason the file exists. The ticket line is not.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only, including the extension target (the file is in both).

### `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgent.swift`

Header read. Rest of the 356 lines still pending, so this file is not batched.

#### HY-0014 · C3 ticket provenance · Low · Confirmed
**Where:** `CinematicAgent.swift:6`
**Current:** `//  Ticket: APP-02 - CoreML RL Agent Integration`
**Proposed:** delete line 6.
**Why:** The doc comment at lines 15–22 states the contract with `training/cinematic_env.py`.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgentSettingsView.swift`

#### HY-0015 · C3 ticket provenance · Low · Confirmed
**Where:** `CinematicAgentSettingsView.swift:6`
**Current:** `//  Ticket: APP-02 - CoreML Agent Settings`
**Proposed:** delete line 6.
**Why:** Ticket label only. The view's own doc comment remains.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposerSettingsView.swift`

#### HY-0016 · C3 ticket provenance · Low · Confirmed
**Where:** `ShotComposerSettingsView.swift:6`
**Current:** `//  Ticket: LOGIC-01 - Rule-Based Shot Composer Settings`
**Proposed:** delete line 6.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/CropPreviewView.swift`

#### HY-0017 · C3 ticket provenance · Low · Confirmed
**Where:** `CropPreviewView.swift:6`
**Current:** `//  Ticket: GFX-01 - Metal Crop Engine (Preview UI)`
**Proposed:** delete line 6.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/RecorderSettingsView.swift`

#### HY-0018 · C3 ticket provenance · Low · Confirmed
**Where:** `RecorderSettingsView.swift:6`
**Current:** `//  Ticket: RL-01 - Training Data Recorder Settings`
**Proposed:** delete line 6.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/TrainingDataRecorder.swift`

Header read. Rest pending.

#### HY-0019 · C3 ticket provenance · Low · Confirmed
**Where:** `TrainingDataRecorder.swift:6` and `36-37`
**Current:**
```swift
//  Ticket: RL-01 - Real-World Data Recording
```
and
```swift
/// Records per-frame training data to JSON Lines files for RL agent training.
/// Data format is designed for direct consumption by Gymnasium environment (Task 3.2).
```
**Proposed:** delete line 6. Rewrite the doc comment's second line to:
```swift
/// Records per-frame training data to JSON Lines files for RL agent training.
/// The JSONL schema is what `training/env_loader.py` reads.
```
**Why:** The task ids are provenance. The schema relationship is the useful part.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/CameraPreviewView.swift`

Partial read.

#### HY-0020 · C3 ticket provenance · Low · Confirmed
**Where:** `CameraPreviewView.swift:201`
**Current:** `// MARK: - Crop Indicator View (Task 2.2)`
**Proposed:** `// MARK: - Crop Indicator View`
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

### `CinematicCoreMacOS/CinematicCoreMacOS/LiveShowSetup.swift`

#### HY-0021 · S2 actor isolation warning · Medium · Confirmed
**Where:** `LiveShowSetup.swift:59`, `75`, and `172-174`
**Current:**
```swift
            devices: channelA.availableCameras.map(Self.device),
```
```swift
            .sink { [weak self] cameras in self?.setup.updateDevices(cameras.map(Self.device)) }
```
```swift
    private static func device(_ camera: CameraManager.CameraDevice) -> ShowSetupModel.Device {
        .init(uniqueID: camera.uniqueID, name: camera.name, modelID: camera.modelID)
    }
```
**Proposed:** mark the helper `nonisolated`, and mark `CameraManager.CameraDevice` `nonisolated` if the compiler still treats its stored properties as MainActor-isolated (it is a nested struct of lets: `id`, `name`, `modelID`, `uniqueID`, `maxResolution`, `supports4K`, `formatCount`).
```swift
    private nonisolated static func device(_ camera: CameraManager.CameraDevice) -> ShowSetupModel.Device {
        .init(uniqueID: camera.uniqueID, name: camera.name, modelID: camera.modelID)
    }
```
**Why:** The app target defaults to MainActor, so `device` is MainActor-isolated. Passing it to `map` calls it from a nonisolated function context. The Release build warns at both call sites. The function only copies strings into another value type.
**Evidence:** build log lines 496–506. `CameraDevice` is `CameraManager.swift:616-628`.
**Behaviour change:** None. Same fields are copied.
**Verify:** build only. Both LiveShowSetup warnings must be gone. This finding also touches `CameraManager.swift`, so it shares that file's batch once batches are assigned.

### `CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift`

#### HY-0022 · C2 change narration · Low · Confirmed
**Where:** `DeveloperFlags.swift:77-82`
**Current:**
```swift
    /// **Now 0 (off), deliberately.** This was a stop-gap that swept up the mess
    /// periodically. The real cause turned out to be autorelease pools that were
    /// never draining per work item — fixed at source in `PersonDetector`,
    /// `CameraManager` and `FaceSignatureExtractor`. Leaving both in place would
    /// mask whether that fix actually worked, so the flush stays off while the
    /// before/after soak is run. Set to 30 only to A/B it back.
```
**Proposed:**
```swift
    /// Off, so a periodic cache flush cannot mask the per-work-item autorelease
    /// drain in `PersonDetector`, `CameraManager`, and `FaceSignatureExtractor`.
    /// Set to 30 only to A/B the flush back on.
```
**Why:** The value is already `0` on the next line. The replacement keeps the reason and drops the story of the edit. The measurement comment above it (lines 69–75) stays; it records why a flush was ever considered.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

#### HY-0023 · C3 ticket / plan provenance · Low · Confirmed
**Where:** `DeveloperFlags.swift:40-41`
**Current:**
```swift
    /// counts. Use this when diagnosing choppy output — see the
    /// "as-a-senior-software-stateful-penguin" plan for expected baselines.
```
**Proposed:** delete that sentence. Keep the warning that the flag must stay false because it logs every frame.
**Why:** The plan name is an agent session label, not a baseline a reader can open.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** build only

`exposeMultiviewGallery = true` is not a Release leak: `MultiviewGalleryScene()` is inside `#if DEBUG` at `CinematicCoreMacOSApp.swift:68-72`. Not a finding.

### `CinematicCoreMacOS/CinematicCoreMacOS/ShowStandard.swift`

#### HY-0034 · S1 `nonisolated(unsafe)` without a safety comment · Low · Confirmed
**Where:** `ShowStandard.swift:24-29`
**Current:**
```swift
    /// Capture sessions must not follow preference changes live: the camera is
    /// configured once at start, while the picker explicitly says changes apply
    /// to the next capture. Keep that selected standard stable until output
    /// stops, including if the virtual-camera XPC link reconnects.
    private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var sessionStandard: ShowStandard?
```
**Proposed:** add one line on the property:
```swift
    /// Read and written only while `sessionLock` is held.
    nonisolated(unsafe) private static var sessionStandard: ShowStandard?
```
**Why:** The comment above explains the product rule. The unsafe annotation is safe because `activeSession`, `beginSession`, and `endSession` (lines 94–116) are the only users and each holds `sessionLock`. Say that on the property.
**Evidence:** those three methods are the only references (`git grep sessionStandard` is those plus the declaration).
**Behaviour change:** None
**Verify:** extension build. `ShowStandard.swift` is compiled into the app and the extension.

### `CinematicCoreMacOS/CinematicCoreMacOS/InspectorDrawer.swift`

Partial read.

#### HY-0035 · E1 swallowed camera-switch error · Needs owner
**Where:** `InspectorDrawer.swift:245-254`
**Current:**
```swift
            set: { newValue in
                guard let newValue else { return }
                cameraManager.selectedCamera = newValue
                if cameraManager.isRunning {
                    Task { try? await cameraManager.restartWithCamera(newValue) }
                }
            }
```
`restartWithCamera` (`CameraManager.swift:1695-1715`) stops the session, then `try await startCapture()`. A throw leaves the session stopped.
**Question:** When that restart throws, should the drawer set `cameraManager.error` (or otherwise show the existing camera error UI) instead of discarding the error with `try?`?
**Behaviour change:** Yes. Not in a batch.

### `CinematicCoreMacOS/CinematicCoreMacOS/XPCConnectionManager.swift`
### `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift`
### `CinematicCoreMacOS/CinematicCoreMacOSTests/XPCPeerRequirementTests.swift`
### `CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift`

#### HY-0025 · D1 duplicated helper · Medium · Confirmed
**Where:** `XPCConnectionManager.swift:41-50` and `CinematicCoreExtensionProvider.swift:68-77`
**Current:** both declare the same function:
```swift
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
```
**Proposed:** one `nonisolated` function on a new enum in `Shared/CinematicCoreXPCProtocol.swift` (already compiled into the app and the extension; add `import Security` to that file):
```swift
enum XPCSigningIdentity {
    /// Team identifier of this process, or nil when it is unsigned or ad-hoc
    /// signed. Each side of the XPC link reads its own signature.
    nonisolated static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
```
Delete both copies. Call `XPCSigningIdentity.ownTeamIdentifier()` from `XPCPeerRequirement.forExtension()` (`XPCConnectionManager.swift:37`), from `hostRequirement()` (`CinematicCoreExtensionProvider.swift:60`), and from `XPCPeerRequirementTests.swift:56`.
**Why:** The extension comment already says the check is "kept in step" with the app. The functions are the same. The service-name string stays duplicated on purpose (intentional pattern 5); this is the lookup code, not that string.
**Evidence:** `git grep ownTeamIdentifier` returns only the two definitions and the three call sites listed above. The extension compile of `CinematicCoreXPCProtocol.swift` is in the historical extension build log and the shared folder is a synchronized root group on both the app and extension targets (`project.pbxproj` `Shared` group `F90A3DB32F30C1000037BACD`).
**Behaviour change:** None. Both processes still read their own signing info.
**Verify:** app build and extension build, plus `XPCPeerRequirementTests`.

### `update_xcode.rb` and `test_decklink.cpp`

#### HY-0024 · X3 DeckLink leftovers · Medium · Confirmed
**Where:** `update_xcode.rb:1-21`, `test_decklink.cpp:1-19`
**Current:** `update_xcode.rb` opens the Xcode project and adds `DeckLinkOutputBridge.h`, `DeckLinkOutputBridge.mm`, and a bridging-header setting. `test_decklink.cpp` includes `DeckLinkAPI.h` and counts DeckLink devices.
**Proposed:** delete both files.
**Why:** No source file on this SHA references DeckLink except these two and a `.gitignore` note (`/.gitignore` lines 85 and 89, which can stay). `DeckLinkOutputBridge.mm` and `DeckLinkAPI.h` are not in the tree. The app build succeeds without them. Running `update_xcode.rb` would add the removed route back into the project.
**Evidence:** `git grep -i DeckLink` over tracked source, excluding `build_out/` and `*.md`, returns only these two files and `.gitignore`.
**Behaviour change:** None for the app. The scripts stop being runnable.
**Verify:** none beyond the deletion. Do not run the Ruby script.

### `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITests.swift`

#### HY-0031 · C4 template comments · Low · Confirmed
**Where:** `CinematicCoreMacOSUITests.swift:13-18`, `22-23`, `27`
**Current:** the Xcode template comments ("Put setup code here", "In UI tests it is usually best to stop immediately", "This measures how long it takes to launch").
**Proposed:** delete those comments. Keep `continueAfterFailure = false` and the test methods.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** not part of the unit-test scheme

#### HY-0032 · T1 launch test asserts nothing · Low · Confirmed
**Where:** `CinematicCoreMacOSUITestsLaunchTests.swift:21-32` (filed here because the two UI-test files change together)
**Current:** `testLaunch` launches the app, takes a screenshot, and attaches it. There is no assertion.
**Proposed:** after `app.launch()`, add:
```swift
        XCTAssertEqual(app.state, .runningForeground)
```
and delete the "Insert steps here" comment at lines 25–27.
**Why:** A screenshot attachment does not fail the test when the launch fails before a window exists. The state check is the smallest assertion that matches what the test already does.
**Evidence:** n/a
**Behaviour change:** None in the app. The test fails if launch does not reach the foreground.
**Verify:** UI-test scheme, when someone runs it. The unit-test command does not build this target's assertions.

### `training/bc_dataset.py`

#### HY-0026 · P1 unused import · Low · Confirmed
**Where:** `bc_dataset.py:21-27`
**Current:**
```python
from cinematic_env import (
    ASPECT_RATIO,
    MAX_PAN_SPEED,
    MAX_TILT_SPEED,
    MAX_ZOOM,
    MAX_ZOOM_SPEED,
)
```
**Proposed:** delete the `ASPECT_RATIO,` line.
**Why:** The name occurs only on that line. `MAX_PAN_SPEED`, `MAX_TILT_SPEED`, `MAX_ZOOM`, and `MAX_ZOOM_SPEED` are used.
**Evidence:** ruff F401 at `bc_dataset.py:22`. File read in full.
**Behaviour change:** None
**Verify:** `ruff check training/bc_dataset.py`

#### HY-0030 · C3 ticket provenance · Low · Confirmed
**Where:** `bc_dataset.py:5`, `cinematic_env.py:4`, `env_loader.py:4-6`
**Current (bc_dataset):** `ideal_crop data (YouTube/reference clips from Task 3.1b).`
**Proposed:** `ideal_crop data (YouTube/reference clips).` In `env_loader.py`, replace the two task bullets with "the Swift `TrainingDataRecorder` and `extract_frames.py`". In `cinematic_env.py`, replace "Tasks 3.1/3.1b" with "TrainingDataRecorder and extract_frames.py".
**Why:** The task numbers are provenance. The producer names are the useful part.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** none

### `training/cinematic_env.py`

Partial read (header and constructor). The unused-import claim was checked against every line.

#### HY-0027 · P1 unused import · Low · Confirmed
**Where:** `cinematic_env.py:21`
**Current:** `from env_loader import SessionData, scan_sessions`
**Proposed:** `from env_loader import scan_sessions`
**Why:** `SessionData` does not appear again in the file. `scan_sessions` is used at line 58.
**Evidence:** ruff F401 at line 21. Search of the file for `SessionData` returns only the import.
**Behaviour change:** None
**Verify:** `ruff check training/cinematic_env.py`

### `training/train_bc.py`

#### HY-0028 · P1 unused import · Low · Confirmed
**Where:** `train_bc.py:20`
**Current:** `import numpy as np`
**Proposed:** delete the line.
**Why:** `np` is never used. `torch` and `sys` are.
**Evidence:** ruff F401. File read in full.
**Behaviour change:** None
**Verify:** `ruff check training/train_bc.py`

### `training/make_test_model.py`

#### HY-0029 · P1 unused local · Low · Confirmed
**Where:** `make_test_model.py:52-58`
**Current:**
```python
        stats = train_bc(
            data_dirs=[data_dir],
            output_path=bc_path,
            epochs=3,
            batch_size=64,
            verbose=True,
        )
```
**Proposed:** call `train_bc(...)` without binding `stats`.
**Why:** `stats` is never read. Training still runs; the function's return value is only a stats dict.
**Evidence:** ruff F841 at line 52. No later use of `stats` in the file.
**Behaviour change:** None
**Verify:** `ruff check training/make_test_model.py`

### `CinematicCoreMacOS/build_release.sh`

#### HY-0040 · C1 stale step numbers · Low · Confirmed
**Where:** `build_release.sh:51-91`
**Current:**
```bash
# --- Step 4: Archive --------------------------------------------------------
echo "==> [1/6] Archiving…"
```
The same gap repeats: comment steps 5 through 9 against echo steps 2/6 through 6/6.
**Proposed:** renumber the six comments to `Step 1` … `Step 6`, matching the echoes.
**Why:** The comments describe steps that no longer exist. The echo on the next line is the real sequence.
**Evidence:** the comment says Step 4; the echo says `[1/6]`.
**Behaviour change:** None
**Verify:** none

### `training/env_loader.py`

#### HY-0041 · X2 exception that cannot be raised · Low · Confirmed
**Where:** `env_loader.py:64-74`
**Current:**
```python
                try:
                    with open(metadata_path, encoding="utf-8") as f:
                        meta = json.load(f)
                    fps = meta.get("fps", 30)
                    label_source = meta.get("label_source", "")
                    if "youtube" in label_source:
                        source = "youtube"
                    elif label_source in ("auto", "manual"):
                        source = "live"
                except (json.JSONDecodeError, KeyError):
                    pass
```
**Proposed:** `except json.JSONDecodeError:`.
**Why:** Both metadata reads use `dict.get`, which does not raise `KeyError`. `json.load` raises `JSONDecodeError` for a broken file. The `KeyError` arm never runs.
**Evidence:** the only operations inside the `try` are `json.load` and `.get`.
**Behaviour change:** None
**Verify:** `python -m unittest` is not wired here; a one-line read of the function is enough. Training tests if they import `scan_sessions`.

#### HY-0042 · E1 bad metadata becomes 30 fps · Needs owner
**Where:** the same `except` in `env_loader.py:73-74`
**Question:** A `metadata.json` that is not valid JSON is ignored and the session is kept at `fps = 30` (`env_loader.py:60`). Speaker velocity in `bc_dataset.py` multiplies by that fps. Should a broken metadata file skip the session, or fail the scan, instead of training as if the clip were 30 fps?
**Behaviour change:** Yes, if the fallback is removed. Not in a batch.

### `CinematicCoreMacOS/CinematicCoreMacOSTests/PillTargetTests.swift`

Partial read (the width test).

#### HY-0036 · S4 debug print beside an assertion · Low · Confirmed
**Where:** `PillTargetTests.swift:214`
**Current:**
```swift
                print("PILLWIDTH \(target) \(format) compact=\(compact) full=\(full)")
                #expect(compact <= availableWidth, "Compact \(target) pill width \(compact)")
```
**Proposed:** delete the `print` line.
**Why:** The `#expect` message already includes the target and the measured width. The app's pattern is `Logger`, and this print is not an assertion.
**Evidence:** n/a
**Behaviour change:** None. The expectations stay.
**Verify:** unit tests (`PillTargetTests`)

### `CinematicCoreMacOS/CinematicCoreMacOSTests/CinematicAgentVelocityTests.swift`

#### HY-0037 · C3 ticket provenance · Low · Confirmed
**Where:** `CinematicAgentVelocityTests.swift:5`
**Current:** `//  CR-038: the live observation scales speaker motion by the show rate, as`
**Proposed:** drop the `CR-038:` prefix. Keep the sentence.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** unit tests

### `CinematicCoreMacOS/CinematicCoreMacOSTests/StartGateTests.swift`

#### HY-0038 · C3 ticket provenance · Low · Confirmed
**Where:** `StartGateTests.swift:5`
**Current:** `//  CR-036: when the virtual camera cannot be installed, Start goes ahead only`
**Proposed:** drop the `CR-036:` prefix. Keep the sentence.
**Evidence:** n/a
**Behaviour change:** None
**Verify:** unit tests

## Files read, no change proposed

Clean: no changes proposed.

- `CinematicCoreMacOS/CinematicCoreExtension/main.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS-Bridging-Header.h`
- `CinematicCoreMacOS/scripts/source_fingerprint.py` (`print` is the script's only output)
- `CinematicCoreMacOS/CinematicCoreMacOS/DebugLaunchHooks.swift` (entirely `#if DEBUG`; intentional pattern 4)
- `CinematicCoreMacOS/CinematicCoreMacOS/CameraChannel.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/RecoveryState.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/DetectionFrame.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/ChannelFrame.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/RehearsalOutputSink.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/FrameWorkScheduler.swift` (the "no longer the hidden owner" sentence states the permit invariant; kept)
- `CinematicCoreMacOS/CinematicCoreMacOS/ControlTarget.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/CaptureDeviceRegistry.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/Console/ChannelID.swift` (C and D are reserved slots, not dead cases; the comment says they are not instantiated)
- `CinematicCoreMacOS/CinematicCoreMacOSTests/RealCameraTests.swift` (opt-in; prints sit next to `#expect`)
- `CinematicCoreMacOS/CinematicCoreMacOSTests/InstrumentationInvestigationTests.swift` (opt-in study; prints are the dumped JSON)
- `training/schema.py`
- `training/writer.py`

## Cross-file duplication

### Team-identifier lookup

HY-0025. One home: `XPCSigningIdentity.ownTeamIdentifier()` in `Shared/CinematicCoreXPCProtocol.swift`. Call sites: `XPCConnectionManager.swift:37`, `CinematicCoreExtensionProvider.swift:60`, `XPCPeerRequirementTests.swift:56`.

Not the same cluster: `CinematicCoreXPC.machServiceName` and the app-group prefix. Those stay duplicated with the extension's Info.plist (intentional pattern 5).

### Sendable pixel-buffer boxes

Five small boxes (`CameraManager`, `PersonDetector`, `ShotComposer`, `FaceSignatureExtractor`, `CropEngine`). Each is under five lines and exists so a file-local type does not inherit a MainActor class. Do not merge them into one shared type. The finding is the missing safety comment (HY-0008, HY-0033), not the repetition.

## Structural (draft, not batched)

These seams are from the type and `MARK` outline. They are not batches until the three files have been read through and each moved declaration's access (`private` vs `fileprivate`) is checked. A move inside the app target keeps behaviour. Widening `private` to internal so a method can live in another file of the same module is acceptable; changing a nested type's name is not.

### `CameraManager.swift` (3,099 lines)

| New file | What moves | Notes |
|---|---|---|
| `CaptureAdmission.swift` | `SendablePixelBufferBox`, `CaptureSessionBox`, `CaptureDropCoalescer`, `CaptureFrameProcessingGate` (lines 16–164) | Already file-level. |
| `CameraError.swift` | `CameraError` (line 166) | File-level. Same module, so call sites stay `CameraError`. |
| `VirtualCameraOutputSink.swift` | `VirtualCameraOutputSink` (line 2769) | File-level class, not nested. Keep its `@MainActor`. |
| `CameraManager+ValidationClip.swift` | validation-clip methods, as an `extension CameraManager` | Only if they are not `private`. `private` methods stay in this file. |

Leave `CameraDevice` and `InputSource` nested. Moving them would rename `CameraManager.CameraDevice` at every call site. That is a wider diff than a hygiene split should be.

### `ShotComposer.swift` (2,294 lines)

| New file | What moves |
|---|---|
| `ShotComposerConfig.swift` | `Config` and its nested enums (`FrameProfile`, `ShotFraming`, `CinematicFormat`, `AutoPanSpeed`, `TuningPreset`), if they can be moved without becoming `ShotComposer.Config` under a new name. They are nested today. Prefer an `extension ShotComposer` in the new file so the name `ShotComposer.Config` does not change. |
| `ShotLock.swift` | `FaceSignature`, `FaceSignatureGallery`, `LockState`, reacquisition types, as an `extension ShotComposer` |

`fileprivate struct SendablePixelBuffer` (line 26) stays in whichever file contains the `Task.detached` closures that use it, or moves with those closures. Do not make it a shared type.

### `ProgramOutputManager.swift` (1,532 lines)

| New file | What moves |
|---|---|
| `ProgramOutputSettingsView.swift` | `ProgramOutputSettingsView` (line 1248) |
| `ProgramOutputPreviewSinks.swift` | `PreviewOutputSink`, `PreviewSystemExtensionStatusManager` (lines 1495 and 1523) |
| `ProgramOutputDiagnostics.swift` | `AlfieDiagnosticsLog`, bring-up check types, latency sample types, if they are file-level |

`ProgramOutputManager`, `ShowStandard`, and `DiagnosticsLog` are shared with the extension. A split must keep those types in files the extension target already compiles, or the extension target's membership has to gain the new file. Do not move extension-compiled code into an app-only file.

## Needs owner

1. **HY-0005.** Should camera discovery keep excluding devices whose localized name contains "Test"? The comment says "TEMP Testing". The filter is live.
2. **HY-0035.** When `restartWithCamera` throws, the inspector's `try?` drops the error and the session may already be stopped. Should that error be written to `cameraManager.error` so the existing error UI shows it?

## Out of scope: possible bugs

None recorded beyond HY-0021 and HY-0035, which are already tracked. The LiveShowSetup warning is a Swift 5 isolation warning, not yet a demonstrated wrong camera list.

## Refuted in verification

Checked and dropped:

1. **`cropEngine == nil` after `CropEngine()` is not dead.** `CropEngine.init?()` (line 440) returns nil when there is no Metal device. The branch in `CameraManager` stays.
2. **Do not strip `@MainActor` off app types as a batch.** Only the Alfie app configurations set `SWIFT_DEFAULT_ACTOR_ISOLATION`. The extension and both test targets do not. A redundant annotation on an app-only type is real, and removing it is how a later move into the extension silently changes isolation.
3. **`displayedPersons` / `displayedStats` and the other `displayed*` mirrors** are intentional pattern 1. `PersonDetector.publishDisplayMirrors` copies them on a timer. Not reported.
4. **`maxZoom = 4.0` and `qualityMaxZoom` are not candidates to merge.** Not compared as duplicates. Training speeds in `CinematicAgent` match `cinematic_env.py` on purpose.
5. **Sendable boxes that already explain themselves:** `CaptureSessionBox` (`CameraManager.swift:24-26`), `ShotComposer.SendablePixelBuffer` (lines 23–25), `CropEngine.RenderSource` (lines 497–501), `DiagnosticsFileWriter` (the comment at `DiagnosticsLog.swift:230`). Not reported.
6. **XPC service name and app-group prefix** stay duplicated. Intentional pattern 5.
7. **Created-by file headers** stay. Intentional pattern 6.
8. **Empty `CropRenderer.metal`** stays. The comment says both targets list it and the kernels were removed. Only the ticket line is HY-0013.
9. **`DeveloperFlags.exposeMultiviewGallery = true` is not reachable in Release.** The scene is `#if DEBUG`.
10. **Opt-in test prints** in `RealCameraTests` and `InstrumentationInvestigationTests` sit next to real `#expect`s. Not deleted.
11. **`source_fingerprint.py` printing the digest** is the script. ruff T201 there is not a finding.
12. **ruff T201 on training CLIs** (`downloader`, `export_coreml`, `extract_frames`, `train_bc`, `train_ppo`, `make_test_model`, `test_env`, `test_training`, `checkpoint_trust`) is progress output of `__main__`. Not a finding. Unused imports are.
13. **`FrameWorkScheduler`'s "no longer the hidden owner"** explains why a permit exists. Kept.
14. **CameraManager comments that detection used to be awaited inline** explain why the frame path schedules detection instead of awaiting it. Kept. The CIImage note does not explain any current line, so HY-0004 stands.
15. **`ChannelID.c` and `.d`** are reserved slots with a comment that says they are not instantiated. Not dead cases.
16. **Pooled XPC output surfaces** were not reported. Intentional pattern 7.

## Leads not yet confirmed

- `FaceSignatureExtractor` is `final class …: @unchecked Sendable` (line 31). The class comment does not say why. The inner pixel-buffer box does (line 61). Confirm after reading the rest of the class whether mutable state is confined to `processingQueue`. Plausible, not batched.
- `ObservableObject` → `@Observable` is a modernisation candidate only. Several UI models are `ObservableObject`. Not a hygiene batch.

## Batches

**Withheld.** Assigning a file to a batch now would block a later finding in that same file from a different batch. The resume pass will group confirmed, behaviour-preserving findings with no file in two batches, open-PR files in their own batches tagged `after PR #N`, structural splits last, and this order: comments, dead code, dedup, errors, concurrency, tests, then splits.

Files that will share a batch once assigned, because one finding touches both:

- HY-0021 touches `LiveShowSetup.swift` and `CameraManager.swift`.
- HY-0025 touches `CinematicCoreXPCProtocol.swift`, `XPCConnectionManager.swift`, `CinematicCoreExtensionProvider.swift`, and `XPCPeerRequirementTests.swift`.

## Coverage

| ID | State |
|---|---|
| HY-0001 | confirmed, batch withheld (file not fully read) |
| HY-0002 | confirmed, batch withheld |
| HY-0003 | confirmed, batch withheld |
| HY-0004 | confirmed, batch withheld |
| HY-0005 | Needs owner |
| HY-0006 | confirmed, batch withheld |
| HY-0007 | confirmed, batch withheld |
| HY-0008 | confirmed, batch withheld |
| HY-0009 | confirmed, batch withheld |
| HY-0010 | confirmed, batch withheld |
| HY-0011 | confirmed, batch withheld |
| HY-0012 | confirmed, batch withheld |
| HY-0013 | confirmed, batch withheld (shared with extension) |
| HY-0014 | confirmed, batch withheld |
| HY-0015 | confirmed, batch withheld |
| HY-0016 | confirmed, batch withheld |
| HY-0017 | confirmed, batch withheld |
| HY-0018 | confirmed, batch withheld |
| HY-0019 | confirmed, batch withheld |
| HY-0020 | confirmed, batch withheld |
| HY-0021 | confirmed, batch withheld |
| HY-0022 | confirmed, batch withheld |
| HY-0023 | confirmed, batch withheld |
| HY-0024 | confirmed, batch withheld until the surrounding scripts are read (`build_release.sh` still pending) |
| HY-0025 | confirmed, batch withheld (extension provider not fully read) |
| HY-0026 | confirmed, batch withheld |
| HY-0027 | confirmed, batch withheld (`cinematic_env.py` not fully read) |
| HY-0028 | confirmed, batch withheld |
| HY-0029 | confirmed, batch withheld |
| HY-0030 | confirmed, batch withheld |
| HY-0031 | confirmed, batch withheld |
| HY-0032 | confirmed, batch withheld |
| HY-0033 | confirmed, batch withheld |
| HY-0034 | confirmed, batch withheld |
| HY-0035 | Needs owner |
| HY-0036 | confirmed, batch withheld |
| HY-0037 | confirmed, batch withheld |
| HY-0038 | confirmed, batch withheld |
| HY-0040 | confirmed, batch withheld |
| HY-0041 | confirmed, batch withheld |
| HY-0042 | Needs owner |

## Resume checklist

`[x]` full read, done. `[~]` partial read, findings above may be incomplete. `[ ]` not read in full yet.


- [~] `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/main.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CameraChannel.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/CameraPreviewView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CapabilityReport.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CaptureDeviceRegistry.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CaptureProfilePolicy.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ChannelFrame.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgent.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgentSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS-Bridging-Header.h`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOSApp.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ChannelID.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ConsoleActions.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ConsolePresentation.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ConsoleSnapshot.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/FakeConsoleModel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorControlDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorNextDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/MultiviewGallery.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/NextPanelDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/PanesDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/PillDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/TakeBarDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveConsole.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveTilePicture.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/MultiviewConsoleView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/MultiviewLayout.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/NextShotPanel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/NextShotStatus.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/PaneOverlayState.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ProgramPreviewPane.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/SingleCameraConsole.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/TakeAvailability.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/TakeBarView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ControlTarget.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/CropPreviewView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CropRenderer.metal`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DebugLaunchHooks.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DegradePolicy.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionFrame.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionOverlayView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DiagnosticsLog.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorAuthority.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorConsoleAPI.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorController.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorEvidenceAdapter.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorJudge.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorPreferences.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorProposal.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorQualificationStore.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorShotPolicy.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/Replay/DirectorReplay.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/Replay/DirectorReplayFixtures.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorGalleryCatalog.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorGalleryPresentation.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorModeControl.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorPreferencesStore.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorStyleEditor.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorStyleSettingsView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/FakeDirectorConsole.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DirectorEvidenceReadings.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DisplayOutputSink.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/FaceSignatureExtractor.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/FrameWorkScheduler.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/FramingCapability.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/HardwareLink.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/HardwareWireCodec.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/SimulatedHardwareDevice.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InputStripView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InputTileModel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InputTileView.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/InspectorDrawer.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InspectorShowSection.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/LiveShowSetup.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/MultiInputAdmission.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OperatorCommand.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OperatorPill.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OverlayLayer.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/PairCheckPanel.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/PixelBufferPreviewView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramRouter.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramTake.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/RecorderSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/RecoveryState.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/RehearsalOutputSink.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SettingsWindow.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SetupCheck.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SetupDemo.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposerSettingsView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShowSetupModel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShowSetupView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowStandard.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Speech/SpeechCommandGrammar.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Speech/VoiceCommandAdapter.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/StoppedScreen.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/StripDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SystemExtensionActivationManager.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/TrainingDataRecorder.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ValidationClipPlaybackView.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOS/XPCConnectionManager.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureDeviceRegistryTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureFramePathTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureProfilePolicyTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ChannelCommandTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ChannelIsolationTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSTests/CinematicAgentVelocityTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CinematicCoreMacOSTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ConsolePresentationTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DegradePolicyTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DiagnosticsLogTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectOutputFormatTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorAuthorityTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorConsoleAPITests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorControllerTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorEvidenceAdapterTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorEvidenceReadingsTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorJudgeTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorModeControlTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorNextShotTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorPreferencesTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorProposalTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorQualificationStoreTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorReplayTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorShotPolicyTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorStyleHookTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/DirectorStyleSettingsTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/FrameWorkSchedulerTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/FramingCapabilityTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/FramingRegressionTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/GalleryDirectorStateTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/HardwareLinkTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/IdentityEvidenceTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/IdentityRegressionTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/InputStripTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/InspectorShowDetailTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSTests/InstrumentationInvestigationTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/LiveConsoleTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/LockedTrackMatcherTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ManualActionHookTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/MultiInputAdmissionTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/MultiviewGallerySnapshotTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/NextShotStatusTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/OperatorPresetSharingTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/OutputRateRegressionTests.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOSTests/PillTargetTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/PipelineLifecycleTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/PixelBufferPreviewTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/PrivacyAuditTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramOutputReviewTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramPreviewPaneTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramRouterTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramTakeTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ReadinessEvaluationTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSTests/RealCameraTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/RecoveryStateTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SetupCheckTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ShowSetupTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SingleCameraConsoleTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SpeechCommandTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSTests/StartGateTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SystemExtensionReplacementTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/TakeBarTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/TrainingRecorderReviewTests.swift`
- [~] `CinematicCoreMacOS/CinematicCoreMacOSTests/XPCPeerRequirementTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITestsLaunchTests.swift`
- [~] `CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift`
- [x] `CinematicCoreMacOS/build_release.sh`
- [ ] `CinematicCoreMacOS/scripts/diagnostics_report.py`
- [x] `CinematicCoreMacOS/scripts/source_fingerprint.py`
- [ ] `CinematicCoreMacOS/scripts/test_diagnostics_report.py`
- [x] `test_decklink.cpp`
- [x] `training/bc_dataset.py`
- [ ] `training/canvas.py`
- [ ] `training/checkpoint_trust.py`
- [~] `training/cinematic_env.py`
- [ ] `training/detector.py`
- [ ] `training/downloader.py`
- [x] `training/env_loader.py`
- [ ] `training/env_reward.py`
- [ ] `training/export_coreml.py`
- [ ] `training/extract_frames.py`
- [x] `training/make_test_model.py`
- [x] `training/schema.py`
- [ ] `training/test_checkpoint_trust.py`
- [ ] `training/test_env.py`
- [ ] `training/test_training.py`
- [x] `training/train_bc.py`
- [ ] `training/train_ppo.py`
- [x] `training/writer.py`
- [x] `update_xcode.rb`
