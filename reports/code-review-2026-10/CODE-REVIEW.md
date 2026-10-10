# Alfie code review — 10 October 2026

Reviewed commit: `bcc4ae7f27fd82f423d5bcbd9a3d4967293ba904` (`bcc4ae7`, "Merge pull request #16").
Date: 10 October 2026.
Baseline: `xcodebuild test` of `CinematicCoreMacOSTests`, `CODE_SIGNING_ALLOWED=NO`, derived data `/private/tmp/review-dd`, result bundle `/private/tmp/review-unit.xcresult`.
Result: **Passed. 586 passed, 0 failed, 3 skipped** (589 definitions). `** TEST SUCCEEDED **`.

This document is being written as the file pass proceeds. The checklist below is the resume point. A box is ticked only after that file has been read in full.

## Compiler warnings (findings)

Unique warnings from that test build:

| Warning | Where |
|---|---|
| `CVPixelBuffer` captured in a `@Sendable` closure | `CropEngine.swift:491` |
| main-actor `cards` used from a nonisolated test | `DirectorModeControlTests.swift` (open PR #28) |
| retroactive `CustomTestStringConvertible` | `DirectorModeControlTests.swift:143`, `GalleryDirectorStateTests.swift:181` |
| main-actor `Hashable` of `FramingCapability.Reason` | `FramingCapabilityTests.swift` |
| main-actor `Equatable` of `CropEngine.CropRect` | `FramingCapabilityTests.swift` |
| `nonisolated(nonsending)` closure vs `@Sendable` key path | `TakeBarTests.swift` |
| unnecessary `nonisolated(unsafe)` on a `Sendable` `CIContext` | `PersonDetector.swift:196` |
| main-actor `channel` / `channelA` from a nonisolated test | `ProgramTakeTests.swift:45–46` |

## Summary

Counts and the top 10 are filled in when the file pass finishes. Confirmed so far:

| ID | Severity | One line |
|---|---|---|
| CR-001 | Critical | Personal email and legal name in the public release script |
| CR-002 | High | Signed app, archive and DMG are tracked (about 142 MB) |
| CR-003 | High | XPC caller check uses the process id and the bundle id only; it never validates the signature |
| CR-004 | Medium | Extension startup crashes with `fatalError` / a force-unwrap if CMIO setup fails |
| CR-005 | Medium | Virtual-camera device and stream ids are a new UUID on every launch |
| CR-006 | Medium | Release builds still show the clip-playback module |
| CR-007 | Medium | Microphone and USB sandbox access are injected by build settings |
| CR-008 | Medium | Crop render captures a non-Sendable pixel buffer (compiler warning) |
| CR-010 | Medium | Training recorder writes body boxes and pose keypoints to Documents when consent is on |
| CR-012 | Medium | `alfie-diagnostics.log` is appended forever, with no cap |
| CR-013 | Medium | Latency samples are copied and filtered on the main thread for every stage sample |
| CR-014 | Medium | The first standby frame is a per-pixel fill on the main thread |
| CR-015 | Medium | Leaving Direct output restores every display's permanent mode |
| CR-016 | Medium | The host never checks that the Mach listener is the extension |
| CR-017 | Medium | A failed properties request can still report the extension as installed |
| CR-018 | Medium | Extension replacement always returns `.replace`, including a downgrade |
| CR-019 | Medium | Removing channel A after a Take to B makes `channelA` trap |
| CR-027 | High | A hot-unplug leaves capture running, so a later buffer is still rendered and sent |
| CR-028 | High | Preview layers show an IOSurface without retaining the pixel buffer |
| CR-036 | Medium | Start still begins the session when virtual-camera install fails |
| CR-037 | Medium | A saved director style never reaches the running controller |
| CR-039 | Medium | The extension compiles the output manager, which imports SwiftUI, and does not use it |
| CR-040 | Medium | The shared scheme launches Release |
| CR-048 | Medium | Preview evidence is not refreshed when Preview changes channel |
| CR-049 | Medium | Turning Edit Live off leaves the pause reason "editing Program live" |
| CR-050 | Medium | The same tick can mark health restored while admission is still refused |
| CR-051 | Medium | Reloading a style number that does not fit in `Int` traps the settings editor |

## Repo hygiene

The repo is public. These paths were excluded from the file-by-file pass.

| Bucket | Files | Size | Recommendation |
|---|---|---|---|
| `CinematicCoreMacOS/build_out/**` | 292 | 141.8 MB | Stop tracking. Signed app, system extension, xcarchive, DMG, zip. `.gitignore` currently re-includes this folder (`!CinematicCoreMacOS/build_out/`). |
| `.codex-derived-data/**`, `.deriveddata*/**` | 39 | 0.1 MB | Stop tracking. Build caches. `info.plist` files contain a local project path. |
| `*.log` and `reports/**` data | logs 5 (0.3 MB); reports 32 (0.2 MB) | | Stop tracking logs and evidence dumps. Several files contain a home-directory path and local movie filenames under Downloads. |
| images (icons and gallery PNGs) | 39 | 4.6 MB | App icons should stay. Gallery PNGs are product evidence; owner decides. |
| `training/models/bc_test.zip` and `.mlpackage` manifests | 3 | 0.1 MB | Small. Keep the manifests; the zip is a test fixture. |
| `test_decklink` | 1 | 59 KB | Compiled binary with no source-only reason to be tracked. Stop tracking the binary; keep `test_decklink.cpp`. |
| `training/=2.14.0`, `training/=7.0` | 2 | 8 KB | Accidental `pip` logs (a redirect into a filename). Delete candidates. Not secrets; they mention a local `./venv`. |

No private keys, `.p8`, `.p12`, or app-specific passwords are tracked. The release script's comment shows the notary profile name and tells the reader to pass a password on the command line; the password value is not in the file.

CR-001. `CinematicCoreMacOS/build_release.sh` lines 10 and 23. Type: personal email address and legal name, in comments, on a public branch. Do not copy them into other docs. Remove them from the script and from git history if this file has been public.

The Apple team id appears in `project.pbxproj`, the XPC service name, the extension `Info.plist`, and several docs. It is required for the app-group Mach service prefix. It is an organisation identifier, not a credential. Leaving it in source is consistent with that design.

`CinematicCoreMacOS/.claude/settings.local.json` contains one local absolute path (a username and an old Desktop checkout). Low. It is not a secret.

## File-by-file review

### `CinematicCoreMacOS/build_release.sh`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-001 | Critical | Confirmed | Privacy | 10, 23 | The notarisation comment contains a personal email address and a legal name. The repo is public. The script itself uses `set -euo pipefail` and quotes variables. | Replace both with placeholders. Do not store the notary Apple ID in git. |

### `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift`

Full pass of the listener, frame queue, device init, and stream start. Re-checked the High item below against the source.

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-003 | High | Confirmed | Security | 54–87, 749–759 | The listener rejects a mismatched bundle id, so the check is not a no-op. The guest is resolved with `kSecGuestAttributePid` (`connection.processIdentifier`), which can be reused before `SecCodeCopyGuestWithAttributes` runs. `SecCodeCopySigningInformation` is called and only `kSecCodeInfoIdentifier` is compared to `Morris.CinematicCoreMacOS`. There is no `SecCodeCheckValidity`, and no team-id check. An ad-hoc signature with that identifier passes. `sendVideoFrame` then `IOSurfaceLookup`s whatever id arrived and accepts it when the size and `32BGRA` match. | Read `newConnection.auditToken`, pass `kSecGuestAttributeAudit`, and accept only after `SecCodeCheckValidity` against the host identifier and the team. |
| CR-004 | Medium | Confirmed | Crash | 211, 221–225, 657–668, 697 | `description!` force-unwraps a format description that `CMVideoFormatDescriptionCreate` may leave nil. `addStream` / `addDevice` failures call `fatalError`, which kills the system extension. `startStream` / `stopStream` also `fatalError` if the source type is unexpected. | Return the `OSStatus` / throw. Keep a stable failure path that does not abort the extension process. |
| CR-005 | Medium | Confirmed | Correctness | 199–215 | Device and stream ids are `UUID()` on every launch. The comments say to replace them. Clients that bind to a device id see a different camera after the extension restarts. | Persist one device UUID and one stream UUID. |
| CR-020 | Low | Confirmed | Crash | 272 | `CMTimeCopyAsDictionary(...)!` force-unwraps a nullable return when applying the host frame rate. | Return false from `updatePlayoutFrameRate` when the copy fails. |
| CR-021 | Low | Confirmed | Correctness | 645–646 | `setStreamProperties` stores a client `activeFormatIndex` and only logs when it is out of range. | Ignore indexes outside `formats`. |

The frame queue stores surface ids only (cap 5) and drains to the newest frame. The host keeps the last 10 pixel buffers in `VirtualCameraOutputSink.recentlySentBuffers` (`CameraManager.swift` around 2711 and 2859). That retention holds for the real host, so a missing use-count on the extension queue is not a separate High finding. `authorizedToStartStream` returns `true` for every CMIO client, which is what a virtual camera is for. The playout timer holds `stateLock` across lookup and `stream.send` (lines 363–380). That can stall an enqueue; it is not raised on its own because the work inside the lock is one frame.

### `CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift`

Haven't found a separate defect. The Mach service name is app-group prefixed and matches the extension `Info.plist`. `sendVideoFrame` carries a surface id. That is safe only while CR-003 holds: the extension will look the id up globally. The team id is hardcoded here and in `Info.plist`, while the entitlement uses `$(TeamIdentifierPrefix)`. Those three strings have to move together.

### `CinematicCoreMacOS/CinematicCoreExtension/Info.plist`

Haven't found anything vulnerable or badly coded beyond CR-005's service name, which matches the protocol. Both `NSExtensionAttributes` and the top-level `CMIOExtension` entry carry the same Mach service name.

### `CinematicCoreMacOS/CinematicCoreExtension/main.swift`

Haven't found anything vulnerable or badly coded. Starts the CMIO provider and runs the run loop.

### `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS.entitlements`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-007 | Medium | Confirmed | Security | entitlements file; `project.pbxproj` 539–546 and 589–596 | The checked-in plist grants sandbox, app group, system-extension install, camera, and IOSurface. The target also sets `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT` and `ENABLE_RESOURCE_ACCESS_USB`. The tracked export summary shows those became `com.apple.security.device.audio-input` and `com.apple.security.device.usb` on the signed app. No Swift code opens a USB device. Speech code exists, so the microphone may be intentional. | Owner decides whether USB stays. If not, turn the USB resource setting off. Do not edit entitlements in this review. |

### `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtension.entitlements`

Haven't found anything vulnerable or badly coded. Sandbox, the same app group, and IOSurface. No camera or USB.

### `CinematicCoreMacOS/BuildInfo.plist`

Haven't found anything vulnerable or badly coded. One build setting placeholder for the source fingerprint.

### `CinematicCoreMacOS/CinematicCoreMacOS/ShowStandard.swift`

Haven't found anything vulnerable or badly coded. `sessionStandard` is `nonisolated(unsafe)` and every read and write takes `sessionLock`. 59.94 uses 60000/1001.

### `CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-006 | Medium | Confirmed | Correctness | 5–7, 16, 338 in `InspectorDrawer.swift` | The file header says operator builds keep every flag false. `exposeClipPlaybackControls` is `true` with no `#if DEBUG`. The inspector then shows a Playback module that can route a validation clip. `exposeMultiviewGallery` is also true, but the gallery type is wrapped in `#if DEBUG`, so Release does not compile it. The Debug-only director and rehearsal flags are `false` in `#else`. `latencyConsoleLogging` and `verboseFrameLogging` are false. | Default `exposeClipPlaybackControls` to false, or wrap the inspector row in `#if DEBUG`. |

### `CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-008 | Medium | Confirmed | Concurrency | 483–496 | `renderCrop` hops to `renderQueue.async`, a `@Sendable` closure, while capturing `pixelBuffer` (`CVPixelBuffer` is not `Sendable`). The comment says the capture gate and a retained buffer make this safe. It is still a Swift 6 error waiting to happen, and the compiler warned. | Box the buffer the same way `SendablePixelBuffer` is boxed elsewhere, and keep the gate. |
| CR-034 | Medium | Confirmed | Correctness | 35–38, 547–566 | `Config.useHighQuality` and `Config.enableVignette` are never read. `processCrop` picks Lanczos or bilinear from a hard-coded `0.7` scale and never applies a vignette. The settings form still binds both toggles. | Honor the toggles, or remove them from `Config` and the form. |
| CR-045 | Low | Confirmed | Performance | 555 | Every strong downscale allocates `CIFilter(name: "CILanczosScaleTransform")!`. A missing filter name traps the render queue. | Cache one filter on `renderQueue`. |

### `CinematicCoreMacOS/CinematicCoreMacOS/TrainingDataRecorder.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-009 | Low | Confirmed | Leak | 487–501, 504–506 | Each flush appends a `Task` to `pendingWriteTasks` and only clears that array in `finishPendingWrites`. A long recording keeps every completed task. | Remove the task in the completion handler, and cap in-flight batches. |
| CR-010 | Medium | Confirmed | Privacy | 318–397, 183–186, 198–201, 245 | With consent (default false), each sampled frame writes a body box and head/waist keypoints to plaintext `frames.jsonl` under Documents, kept for 30 days. No pixel buffer is written. The inspector toggle is off in Release (`exposeTrainingRecorderControls` is false), and the writer stays in the app. Session metadata always records `fps: 30`. `outputDirectory` force-unwraps the documents directory URL. | Keep the consent gate. Write the real show rate. Replace `first!` with a thrown error. |

### `.gitignore`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-002 | High | Confirmed | Privacy | 78–80 | `build_out/` is explicitly re-included. That tracks a signed app, extension binary, archive and DMG in a public repo. | Remove the exception and untrack `build_out/` when the owner agrees. Do not delete the files in this review. |

### `CinematicCoreMacOS/.claude/settings.local.json`

Haven't found a secret. One local absolute path (see hygiene). Low, no separate finding id beyond the hygiene note.

### `training/requirements.txt`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-041 | Medium | Confirmed | Security | 1–8 | Every dependency is a lower bound only (`>=`), with no upper bound and no hashes. A fresh install floats to whatever is current. | Pin exact versions and hashes in a lockfile. |

### `training/=2.14.0`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-011 | Low | Confirmed | Dead code | whole file | This is a `pip` download log committed under a filename that looks like a broken redirect (`=2.14.0`). Same for `training/=7.0`. | Stop tracking both. |

### `CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-012 | Medium | Confirmed | Leak | 16–57 | `AlfieDiagnosticsLog.append` writes `Library/Logs/Alfie/alfie-diagnostics.log` with no size cap, rotation, or prune. Connect, failure, and retry paths call it. It does not write frames or face data. | Cap or rotate the file. |
| CR-013 | Medium | Confirmed | Performance | 848–881 | `recordInputFrame` and `recordLatency` run on the main actor. Each sample copies that stage's window and `removeAll`s timestamps outside a 5-second window. `@Published` stats are coalesced; the array copy is not. | Keep one ring per stage and overwrite in place. |

### `CinematicCoreMacOS/CinematicCoreMacOS/ProgramRouter.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-014 | Medium | Confirmed | Performance | 247–261 | The first standby frame of a given size is filled with a nested per-pixel loop (1920×1080 by default). `faultTick` runs that on the main thread at the moment Program has gone missing. Later ticks reuse `standbyBuffer`. | Fill with `memset` or a cached buffer, off the main thread. |
| CR-022 | Low | Confirmed | Leak | 266–280 | The watchdog and fault timers are scheduled on `RunLoop.main` and invalidated from `channelStopped`. There is no `deinit`. Releasing the router without that call leaves the timers on the run loop. They capture `self` weakly, so the router itself is not retained. | Invalidate both timers in `deinit`. |

### `CinematicCoreMacOS/CinematicCoreMacOS/ProgramTake.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/DisplayOutputSink.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-015 | Medium | Confirmed | Correctness | 468–472 | `release()` calls `CGRestorePermanentDisplayConfiguration()`, which restores the permanent configuration for every display, not the locked port. Deselecting Direct output can snap other displays back to their permanent mode. | Save the previous mode for that display id and restore only that mode. |
| CR-023 | Medium | Plausible | Concurrency | 67–73 | `deinit` is nonisolated and then calls `MainActor.assumeIsolated` to close the window. That traps if the last reference is dropped off the main thread. | Hop to the main queue and close the window there. |
| CR-024 | Medium | Plausible | Lifetime | 162–175 | `lastSentBuffer` keeps one pixel buffer. The comment says releasing the previous one is safe because the compositor has already sampled it. `layer.contents` holds the IOSurface, and this return does not wait for the window server. A second look did not show a torn frame, so this stays Plausible rather than High. | Retain a short ring of sent buffers. |

### `CinematicCoreMacOS/CinematicCoreMacOS/RehearsalOutputSink.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/XPCConnectionManager.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-016 | Medium | Confirmed | Security | 86–90 | The host resumes the Mach connection and later sends surface ids, without checking the listener's audit token, team id, or designated requirement. The service name is app-group prefixed, which blocks an unrelated sandboxed app from registering it. | Before `resume`, require the listener to satisfy the extension identifier and the team. |

### `CinematicCoreMacOS/CinematicCoreMacOS/DiagnosticsLog.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-025 | Low | Confirmed | Privacy | 293–298 | `prune` deletes only `.csv` files older than 30 days, so `alfie_session_*.json` sidecars accumulate. The manifest stores capture device name and model. It does not write frames, face crops, or keypoints. | Prune the sidecars with the CSVs. |

`DiagnosticsFileWriter` is `@unchecked Sendable` because `handle` is only touched on its serial queue. That annotation is justified. Directory and write failures are swallowed with `try?` (lines 247–261). Low, and covered by the same cleanup as CR-025 rather than a separate id.

### `CinematicCoreMacOS/CinematicCoreMacOS/SystemExtensionActivationManager.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-017 | Medium | Confirmed | Correctness | 640–647 | If the properties request fails, status becomes `.installed` whenever `alfie.systemExtensionInstalled.<id>` is true. A stale default then reports the virtual camera ready when macOS did not confirm it. | On properties failure, stay `.unknown` until a successful properties or activation result. |
| CR-018 | Medium | Confirmed | Correctness | 678–686 | `actionForReplacingExtension` always returns `.replace`, including when the bundled build is older than the installed one. | Compare bundle versions and return `.cancel` for a downgrade. |
| CR-026 | Low | Confirmed | Privacy | 288–294 | Activation logs `Bundle.main.bundleURL.path` with `privacy: .public`. That path contains the home-directory username. | Log the bundle id. |

### `CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-019 | Medium | Confirmed | Crash | 41, 100–102 | `channelA` force-unwraps `channels[.a]`. `removeChannel` drops any channel that is not the current Program channel, so after a Take to B it will remove A. The next `channelA` access traps. Live console code only removes B today. | Return `CameraManager?`, or refuse to remove A. |

### `CinematicCoreMacOS/CinematicCoreMacOS/DebugLaunchHooks.swift`

Haven't found anything vulnerable or badly coded in Release. The window dump is inside `#if DEBUG` and only runs when `ALFIE_DEBUG_WINDOW_DUMP` is set.

### `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-027 | High | Confirmed | Correctness | 1790–1792, 2469–2481 | `handleSourceLost()` bumps `captureGeneration`, clears the hold buffers, and stops the session asynchronously. It leaves `isRunning` true and sets `sourceMissing`. `processFrame` returns only when `isRunning` is false. It never reads `sourceMissing`. A buffer that arrives after the generation bump is rendered and submitted, and it replaces the hold the disconnect just cleared. | Set `isRunning = false` before resetting the gate, and return from `processFrame` when `sourceMissing` is set. |
| CR-029 | Medium | Confirmed | Leak | 1267–1291, 2383 | `stopCapture()` never calls `setSampleBufferDelegate(nil, queue: nil)` or removes the output. `AVCaptureVideoDataOutput` retains its delegate, so the session keeps the manager after the show drops the channel. | Clear the delegate and remove the output on stop. |
| CR-030 | Medium | Confirmed | Performance | 2059–2076 | Every wide and tracking frame assigns `cropEngine.config.transitionSmoothing`. `config` is `@Published`, so the setter fires `objectWillChange` at capture rate and overwrites the Crop Settings slider. | Keep the live smoothing factor off `@Published`. Write `config` only when the operator's value changes. |
| CR-031 | Medium | Confirmed | Correctness | 2113–2118 | A nil render permit still calls `renderCrop`. Nil means both "no scheduler" and "the scheduler cancelled or superseded this turn". A stop during `acquire` therefore queues another crop. | Render without a permit only when `scheduler` itself is nil. |
| CR-032 | Medium | Confirmed | Correctness | 715–719 | `discoverCameras()` drops any device whose name contains "test". The comment says "TEMP Testing". It is not inside `#if DEBUG`, and it is the list the operator picks from. | Delete the filter. |
| CR-033 | Medium | Confirmed | Performance | 3001–3014 | `didDrop` starts a `.userInitiated` main-actor `Task` for every system drop. The success path avoids per-drop logging because that work makes overload worse. | Count drops on the capture queue and publish one coalesced total. |

### `CinematicCoreMacOS/CinematicCoreMacOS/CameraChannel.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/CameraPreviewView.swift`

Haven't found anything vulnerable or badly coded. `Image.init(decorative:)` and `sharedDisplayContext` (lines 170–187) have no callers. Low, not given an id.

### `CinematicCoreMacOS/CinematicCoreMacOS/CaptureDeviceRegistry.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/CaptureProfilePolicy.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/ChannelFrame.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/CropPreviewView.swift`

The High Quality, Vignette, and smoothing controls write fields that CR-030 and CR-034 already cover. No separate finding.

### `CinematicCoreMacOS/CinematicCoreMacOS/CropRenderer.metal`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-046 | Low | Confirmed | Dead code | 28–155 | Nothing dispatches `cropAndScale`, `cropAndScaleSmooth`, or `cropWithVignette`. `CropEngine` crops with Core Image. | Delete the shader, or wire one kernel and delete the copies. |

### `CinematicCoreMacOS/CinematicCoreMacOS/DetectionFrame.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/DetectionOverlayView.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-035 | Medium | Confirmed | Performance | 875–899 | While a lock is active and Vision returns more than one person, `assignTracks` formats a line per detection and logs it on every update. Detection runs on the main actor at the shipping interval of 2, so a two-person stage logs about 25 times a second. This path is not behind `latencyConsoleLogging`. | Log only when the bind or coast state changes. |

The `nonisolated(unsafe)` on the cached `CIContext` is the compiler warning already listed. The context is `Sendable`, so the annotation is unnecessary.

### `CinematicCoreMacOS/CinematicCoreMacOS/FaceSignatureExtractor.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/FrameWorkScheduler.swift`

Haven't found anything vulnerable or badly coded.

### `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift`

Haven't found a live-path defect. `shotFraming`, `configuredStageRect`, `stagePriorityScore`, and `horizontalPaddingMultiplier` are stored and not read by `composeFromTrackedBounds`. Low dead code.

### `CinematicCoreMacOS/CinematicCoreMacOS/PixelBufferPreviewView.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-028 | High | Plausible | Lifetime | 76–86 | `display` assigns `takeUnretainedValue()` to `layer.contents` and does not keep the `CVPixelBuffer`. The comment says the published property upstream retains the current buffer. That property is replaced on the next frame, which releases the previous buffer before the layer is guaranteed to have dropped it. `VirtualCameraOutputSink` keeps ten buffers for this reason. The preview and `ProgramDisplayContentView` do not. A torn frame was not reproduced. | Retain the buffer currently installed as `contents` until the next `display` replaces it. |

### `CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-036 | Medium | Confirmed | Correctness | 205–218 | `startCamera` still dispatches `.startSession` when `ensureInstalledForSessionStart()` returns false. `showSystemExtensionStatus` is set and has no reader, so there is no alert. | Return before dispatch when install fails, and present the failure. |

### `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOSApp.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-037 | Medium | Confirmed | Correctness | 59–64 | `SettingsWindow` keeps the default `onDirectorPreferencesChanged`, which is `{ _ in }`. `DirectorController.preferencesChanged` is never called from the app, and the controller does not load the style file at launch. A save writes the file and does not update the running director. | Pass a callback that calls `show.director.preferencesChanged`, and load the file when the director attaches. |

### `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgent.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-038 | Medium | Confirmed | Correctness | 286–293 | Speaker velocity is always `delta * 30`. The training env multiplies by the session frame rate. At 50, 59.94, or 60 the live observation is not the vector the policy was trained on. The ML agent toggle is off in Release (`exposeMLAgentControls` is false). | Multiply by the show rate. |

### `CinematicCoreMacOS/CinematicCoreMacOS/SettingsWindow.swift`

CR-037. `onDirectorPreferencesChanged` defaults to a no-op and is copied onto the editor in `onAppear` (lines 78, 121–123).

### `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.pbxproj`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-039 | Medium | Confirmed | Build | 68–76, 565, 615 | The extension's exception set adds `CropRenderer.metal`, `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, and `ShowStandard.swift`. Extension source uses `ShowStandard` only. `ProgramOutputManager.swift` imports SwiftUI and AppKit, so that UI is compiled into the system extension. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the app target only. | Drop the three unused files from the extension membership. Set the same isolation on every target that compiles the shared files. Do not edit the project file until the owner agrees. |

### `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/xcshareddata/xcschemes/CinematicCoreMacOS.xcscheme`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-040 | Medium | Confirmed | Build | 57–58 | `LaunchAction` `buildConfiguration` is Release. The test action is Debug. Run from Xcode therefore omits `#if DEBUG` and runs optimized. | Launch Debug. |

### `training/=7.0`

Same accidental pip log as CR-011.

### `training/detector.py`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-042 | Medium | Confirmed | Correctness | 52–72 | `model_complexity` is accepted and never used. The landmarker is always `pose_landmarker_full.task`. The error text names an unpinned MediaPipe `latest` URL. The script does not download it. | Select the asset from the flag, or remove the flag. Pin a checksum if a URL stays. |

### `training/train_ppo.py`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-044 | Medium | Plausible | Security | 44–53 | `PPO.load` deserializes a Stable-Baselines3 `.zip`. Current SB3 does that with cloudpickle, so a hostile checkpoint is code execution. This repo does not call `pickle` itself. The same call is in `export_coreml.py`. | Load only a trusted checkpoint, or a weights-only format. |

### `training/export_coreml.py`

CR-044. Same `PPO.load` path, on a path the operator passes.

### `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITests.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-043 | Medium | Confirmed | Tests | 26–32 | `testExample` launches Alfie and does not assert any UI state. | Assert one visible operator state, or delete the test. |

### `CinematicCoreMacOS/CinematicCoreMacOSTests/CinematicCoreMacOSTests.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-047 | Low | Confirmed | Tests | 15–17 | `example` has no `#expect`. Later crop tests use `try! #require`, so a nil crop crashes the runner instead of recording a failure. | Delete `example`. Use `try #require`. |

No `pickle`, Python `eval`/`exec`, or `subprocess(..., shell=True)` in the training scripts. `downloader.py` passes the URL as an argument list. `build_release.sh` already has CR-001; `set -euo pipefail` is present.

Haven't found anything vulnerable or badly coded in: `CapabilityReport.swift`, `CinematicAgentSettingsView.swift`, `ControlTarget.swift`, `DegradePolicy.swift`, `DetectionSettingsView.swift`, `FramingCapability.swift`, `InputStripView.swift`, `InputTileModel.swift`, `InputTileView.swift`, `InspectorDrawer.swift`, `InspectorShowSection.swift`, `LiveShowSetup.swift`, `MultiInputAdmission.swift`, `OperatorPill.swift`, `OverlayLayer.swift`, `PairCheckPanel.swift`, `RecorderSettingsView.swift`, `RecoveryState.swift`, `SetupCheck.swift`, `ShowSetupModel.swift`, `ShowSetupView.swift`, `StoppedScreen.swift`, `StripDemo.swift`, `ValidationClipPlaybackView.swift`, `CinematicCoreMacOS-Bridging-Header.h`, `diagnostics_report.py`, `source_fingerprint.py`, `test_diagnostics_report.py`, `bc_dataset.py`, `canvas.py`, `cinematic_env.py`, `env_loader.py`, `env_reward.py`, `schema.py`, `make_test_model.py`, `extract_frames.py`, `test_env.py`.

The unit tests scanned below had real assertions. A line-by-line read is still open for the files named under Not reviewed: `CaptureDeviceRegistryTests`, `CaptureProfilePolicyTests`, `ChannelCommandTests`, `ChannelIsolationTests`, `ConsolePresentationTests`, `DegradePolicyTests`, `DirectOutputFormatTests`, `FramingCapabilityTests`, `InputStripTests`, `InstrumentationInvestigationTests`, `MultiviewGallerySnapshotTests`, `NextShotStatusTests`, `OperatorPresetSharingTests`, `OutputRateRegressionTests`, `PillTargetTests`, `PipelineLifecycleTests`, `PrivacyAuditTests`, `RealCameraTests`, `RecoveryStateTests`, `ShowSetupTests`, `SingleCameraConsoleTests`, `TakeBarTests`.

### `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorController.swift`

Two proposed High races did not hold. The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the unit build did not warn on the `sourceMissing` sink or on `LiveConsole.reconnect`. Both types are main-actor by that default. `Task { }` in `reconnect` inherits it.

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-048 | Medium | Confirmed | Correctness | 227–232 | `authority.evidenceAvailable` starts `true` and changes only when the event's channel is the current Preview. An Assist Take does not recompute it, so `mayPrepare` can still describe the previous input. | When Preview changes, set the flag from that channel's adapter state. |
| CR-049 | Medium | Confirmed | Correctness | 105–106, authority 109 | Turning Edit Live off sends `.editLive(false)`, which clears the flag and does not clear `paused`. `apply` only stores a new pause reason when pausing begins, so the status stays "Paused: editing Program live". | Clear that reason when editing ends, and keep the pause only if another reason still holds. |
| CR-050 | Medium | Confirmed | Correctness | 217–223, authority 108 | The same `tick()` applies `.admissionLost` and then `.healthRestored` whenever sources and output are healthy. `healthRestored` sets `healthy` back to true and does not look at admission. | Require `admissionCurrent` before `healthRestored`. |

### `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorAuthority.swift`

Haven't found a separate defect. CR-049 and CR-050 are the `apply` cases at lines 108–109.

### `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorShotPolicy.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-053 | Low | Confirmed | Dead code | 58–59 | `Abstention.minimumDuration` and `.movement` are never returned. `rank` validates movement fields and does not use them to abstain. | Drop the unused cases, or abstain on them. |

### `CinematicCoreMacOS/CinematicCoreMacOS/Director/Replay/DirectorReplay.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-054 | Medium | Confirmed | Correctness | 144–157 | `audit` never reports `evidenceUnavailable`, so a commit made without evidence is not counted. Superseded by PR #18. | Start after PR #18 merges. Do not re-implement it on this commit. |

### `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorStyleEditor.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-051 | Medium | Confirmed | Crash | 69–72 | `text()` uses `Int(whole)` for any finite whole number. `DirectorStyle.validated()` allows values outside `Int`, and `Int(_:)` traps on those. Reloading that saved style crashes the editor. | Use `Int(exactly:)` and fall back to the full number. |

### `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/FakeDirectorConsole.swift`

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-052 | Medium | Confirmed | Correctness | 27–32 | `setLevel` for Assist, Auto, or Backup sets `handedToAlfie` and leaves `activity` at `.paused(.manualMode)`. The gallery still reads as Manual. This stand-in is Group C. | Set activity to `.active(.watching)` when a directing level is accepted. |

### `CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveConsole.swift`

Haven't found anything vulnerable or badly coded. The reconnect task was checked against the app target's main-actor default and dropped. See `DirectorController.swift`.

### `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorControlDemo.swift`

The main-actor `cards` warning is real and is already fixed on open PR #28. Start after that PR merges. Group C.

Haven't found anything vulnerable or badly coded in the rest of `Director/` (authority, console API, evidence adapter, judge, preferences, proposal, qualification store, replay fixtures, gallery catalog, gallery presentation, mode control, preferences store, style settings view), `DirectorEvidenceReadings.swift`, `Console/` other than the files above, `Speech/`, or `Hardware/`.

## Checklist

- [ ] `.gitattributes`
- [x] `.gitignore`
- [x] `CinematicCoreMacOS/.claude/settings.local.json`
- [x] `CinematicCoreMacOS/BuildInfo.plist`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtension.entitlements`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/Info.plist`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/main.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.pbxproj`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/xcshareddata/xcschemes/CinematicCoreMacOS.xcscheme`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Assets.xcassets/AccentColor.colorset/Contents.json`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Assets.xcassets/Contents.json`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CameraChannel.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CameraPreviewView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CapabilityReport.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CaptureDeviceRegistry.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CaptureProfilePolicy.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ChannelFrame.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgent.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgentSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS-Bridging-Header.h`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS.entitlements`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOSApp.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ChannelID.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ConsoleActions.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ConsolePresentation.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ConsoleSnapshot.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/FakeConsoleModel.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorControlDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/DirectorNextDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/MultiviewGallery.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/NextPanelDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/PanesDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/PillDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/Gallery/TakeBarDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveConsole.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveTilePicture.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/MultiviewConsoleView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/MultiviewLayout.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/NextShotPanel.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/NextShotStatus.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/PaneOverlayState.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ProgramPreviewPane.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/SingleCameraConsole.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/TakeAvailability.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Console/TakeBarView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ControlTarget.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CropPreviewView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CropRenderer.metal`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DebugLaunchHooks.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DegradePolicy.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionFrame.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionOverlayView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DiagnosticsLog.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorAuthority.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorConsoleAPI.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorController.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorEvidenceAdapter.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorJudge.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorPreferences.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorProposal.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorQualificationStore.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/DirectorShotPolicy.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/Replay/DirectorReplay.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/Replay/DirectorReplayFixtures.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorGalleryCatalog.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorGalleryPresentation.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorModeControl.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorPreferencesStore.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorStyleEditor.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/DirectorStyleSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Director/UI/FakeDirectorConsole.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DirectorEvidenceReadings.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DisplayOutputSink.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/FaceSignatureExtractor.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/FrameWorkScheduler.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/FramingCapability.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/HardwareLink.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/HardwareWireCodec.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/SimulatedHardwareDevice.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/InputStripView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/InputTileModel.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/InputTileView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/InspectorDrawer.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/InspectorShowSection.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/LiveShowSetup.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/MultiInputAdmission.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OperatorCommand.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/OperatorPill.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/OverlayLayer.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/PairCheckPanel.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/PixelBufferPreviewView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramRouter.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramTake.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/RecorderSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/RecoveryState.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/RehearsalOutputSink.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/SettingsWindow.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/SetupCheck.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SetupDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposerSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowSetupModel.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowSetupView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowStandard.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Speech/SpeechCommandGrammar.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/Speech/VoiceCommandAdapter.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/StoppedScreen.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/StripDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/SystemExtensionActivationManager.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/TrainingDataRecorder.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ValidationClipPlaybackView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/XPCConnectionManager.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureDeviceRegistryTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureProfilePolicyTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ChannelCommandTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ChannelIsolationTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSTests/CinematicCoreMacOSTests.swift`
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
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/InstrumentationInvestigationTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/LiveConsoleTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/LockedTrackMatcherTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ManualActionHookTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/MultiInputAdmissionTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/MultiviewGallerySnapshotTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/NextShotStatusTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/OperatorPresetSharingTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/OutputRateRegressionTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/PillTargetTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/PipelineLifecycleTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/PrivacyAuditTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramPreviewPaneTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramRouterTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ProgramTakeTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ReadinessEvaluationTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/RealCameraTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/RecoveryStateTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SetupCheckTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ShowSetupTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SingleCameraConsoleTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/SpeechCommandTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/TakeBarTests.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITestsLaunchTests.swift`
- [x] `CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift`
- [x] `CinematicCoreMacOS/scripts/diagnostics_report.py`
- [x] `CinematicCoreMacOS/scripts/source_fingerprint.py`
- [x] `CinematicCoreMacOS/scripts/test_diagnostics_report.py`
- [ ] `LICENSE`
- [ ] `docs/user-guide/index.html`
- [ ] `docs/user-guide/styles.css`
- [ ] `test_decklink`
- [ ] `test_decklink.cpp`
- [x] `training/=2.14.0`
- [x] `training/=7.0`
- [x] `training/bc_dataset.py`
- [x] `training/canvas.py`
- [x] `training/cinematic_env.py`
- [x] `training/detector.py`
- [ ] `training/downloader.py`
- [x] `training/env_loader.py`
- [x] `training/env_reward.py`
- [x] `training/export_coreml.py`
- [x] `training/extract_frames.py`
- [x] `training/make_test_model.py`
- [ ] `training/models/bc_test.zip`
- [x] `training/requirements.txt`
- [x] `training/schema.py`
- [x] `training/test_env.py`
- [ ] `training/test_training.py`
- [ ] `training/train_bc.py`
- [x] `training/train_ppo.py`
- [ ] `training/writer.py`
- [ ] `update_xcode.rb`
- [x] `CinematicCoreMacOS/build_release.sh`

## Docs and `.md` files to review

Not started.

## Not reviewed

Every unchecked box above. Capture, output, app, Python, director, and console are written up. Docs, and the unit tests named in those sections, are still open. Two proposed High races in the director controller and live console were dropped: the app target's default isolation is MainActor, and the unit build did not warn on those lines. Open Stage 3 pull requests that are not in this commit: #18 (A-08 replay), #21 (A-09 shadow record), #23 (C-06 next-cut notice), #25 (A-10 assist policy), #26 (A-11 take permit), #28 (C-02 test warnings), #29 (CI docs and workflows, not product code).

## Coverage

Filled in when every finding has an owner. Nothing is assigned twice. Group C files with open PRs stay on the "For Grok later" list.
