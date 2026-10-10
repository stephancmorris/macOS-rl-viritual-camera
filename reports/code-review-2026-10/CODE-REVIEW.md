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

Not fully read. The test build warning is confirmed in source:

| ID | Severity | Confidence | Category | Line(s) | Finding | Suggested fix |
|---|---|---|---|---|---|---|
| CR-008 | Medium | Confirmed | Concurrency | 483–496 | `renderCrop` hops to `renderQueue.async`, a `@Sendable` closure, while capturing `pixelBuffer` (`CVPixelBuffer` is not `Sendable`). The comment says the capture gate and a retained buffer make this safe. It is still a Swift 6 error waiting to happen, and the compiler warned. | Box the buffer the same way `SendablePixelBuffer` is boxed elsewhere, and keep the gate. |

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

Haven't found anything vulnerable or badly coded. Floors are pinned with `>=`, not exact versions. No URL downloads in this file.

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

## Checklist

- [ ] `.gitattributes`
- [x] `.gitignore`
- [x] `CinematicCoreMacOS/.claude/settings.local.json`
- [x] `CinematicCoreMacOS/BuildInfo.plist`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtension.entitlements`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/Info.plist`
- [x] `CinematicCoreMacOS/CinematicCoreExtension/main.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.pbxproj`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj/xcshareddata/xcschemes/CinematicCoreMacOS.xcscheme`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Assets.xcassets/AccentColor.colorset/Contents.json`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Assets.xcassets/Contents.json`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CameraChannel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CameraPreviewView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CapabilityReport.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CaptureDeviceRegistry.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CaptureProfilePolicy.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ChannelFrame.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgent.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicAgentSettingsView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS-Bridging-Header.h`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOS.entitlements`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CinematicCoreMacOSApp.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Console/ChannelID.swift`
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
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ControlTarget.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CropEngine.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CropPreviewView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/CropRenderer.metal`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DebugLaunchHooks.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DegradePolicy.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionFrame.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionOverlayView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/DetectionSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DiagnosticsLog.swift`
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
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/DisplayOutputSink.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/FaceSignatureExtractor.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/FrameWorkScheduler.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/FramingCapability.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/HardwareLink.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/HardwareWireCodec.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/SimulatedHardwareDevice.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InputStripView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InputTileModel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InputTileView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InspectorDrawer.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/InspectorShowSection.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/LiveShowSetup.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/MultiInputAdmission.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OperatorCommand.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OperatorPill.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/OverlayLayer.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/PairCheckPanel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/PersonDetector.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/PixelBufferPreviewView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramRouter.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ProgramTake.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/RecorderSettingsView.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/RecoveryState.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/RehearsalOutputSink.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SettingsWindow.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SetupCheck.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/SetupDemo.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposer.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShotComposerSettingsView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShowSetupModel.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ShowSetupView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/ShowStandard.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Speech/SpeechCommandGrammar.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/Speech/VoiceCommandAdapter.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/StoppedScreen.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/StripDemo.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/SystemExtensionActivationManager.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/TrainingDataRecorder.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOS/ValidationClipPlaybackView.swift`
- [x] `CinematicCoreMacOS/CinematicCoreMacOS/XPCConnectionManager.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureDeviceRegistryTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/CaptureProfilePolicyTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ChannelCommandTests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSTests/ChannelIsolationTests.swift`
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
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITests.swift`
- [ ] `CinematicCoreMacOS/CinematicCoreMacOSUITests/CinematicCoreMacOSUITestsLaunchTests.swift`
- [x] `CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift`
- [ ] `CinematicCoreMacOS/scripts/diagnostics_report.py`
- [ ] `CinematicCoreMacOS/scripts/source_fingerprint.py`
- [ ] `CinematicCoreMacOS/scripts/test_diagnostics_report.py`
- [ ] `LICENSE`
- [ ] `docs/user-guide/index.html`
- [ ] `docs/user-guide/styles.css`
- [ ] `test_decklink`
- [ ] `test_decklink.cpp`
- [x] `training/=2.14.0`
- [ ] `training/=7.0`
- [ ] `training/bc_dataset.py`
- [ ] `training/canvas.py`
- [ ] `training/cinematic_env.py`
- [ ] `training/detector.py`
- [ ] `training/downloader.py`
- [ ] `training/env_loader.py`
- [ ] `training/env_reward.py`
- [ ] `training/export_coreml.py`
- [ ] `training/extract_frames.py`
- [ ] `training/make_test_model.py`
- [ ] `training/models/bc_test.zip`
- [x] `training/requirements.txt`
- [ ] `training/schema.py`
- [ ] `training/test_env.py`
- [ ] `training/test_training.py`
- [ ] `training/train_bc.py`
- [ ] `training/train_ppo.py`
- [ ] `training/writer.py`
- [ ] `update_xcode.rb`
- [x] `CinematicCoreMacOS/build_release.sh`

## Docs and `.md` files to review

Not started.

## Not reviewed

Every unchecked box above. Four read-only passes are in progress for capture/crop, output/XPC, director/console, and the remaining app, tests, and Python. Open Stage 3 pull requests that are not in this commit: #18 (A-08 replay), #21 (A-09 shadow record), #23 (C-06 next-cut notice), #25 (A-10 assist policy), #26 (A-11 take permit), #28 (C-02 test warnings), #29 (CI docs and workflows, not product code).

## Coverage

Filled in when every finding has an owner. Nothing is assigned twice. Group C files with open PRs stay on the "For Grok later" list.
