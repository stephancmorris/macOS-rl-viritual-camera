# Webcam “in use” feasibility

Date: 5 November 2026. Scope: Journey 5; investigation only. No extension, entitlement, Info.plist or XPC changes ship with M1.

## Recommendation

Use **(a), a host-side read of `kCMIODevicePropertyDeviceIsRunningSomewhere`**, for the first implementation. It answers the journey's Boolean question without replacing or re-activating the extension. Keep an explicit **unknown** result, and validate the signal on the owner's rig before shipping the affirmative status. Use (b) only if the rig shows that the property is unavailable or unreliable for Alfie's device, or if a later requirement needs a client count.

The label means that a client has started the virtual camera stream. Neither option proves that Zoom, Meet or FaceTime is displaying the latest Program frame, sending it into a call, or delivering it to another participant. The UI must not name a receiving app from this signal alone.

## Evidence in this checkout

Inspected at `7a8e035aa684f971c37416b46ddd68a8f807f81f`:

- [`CinematicCoreExtensionProvider.swift`](../../../CinematicCoreMacOS/CinematicCoreExtension/CinematicCoreExtensionProvider.swift): `ExtensionStableIDs.device` fixes the extension's device UUID; its stream has direction `.source`. `startStream()` and `stopStream()` call `startStreaming()` and `stopStreaming()`. Those maintain `_streamingCounter` under `stateLock` and start or stop playout. A positive counter is evidence of stream activity; the name alone does not establish the number of distinct consuming apps.
- [`CinematicCoreXPCProtocol.swift`](../../../CinematicCoreMacOS/Shared/CinematicCoreXPCProtocol.swift): the current methods send frames, report host capture state, set playout rate, and ping. There is no consumer query.
- [`VirtualCameraOutputSink.swift`](../../../CinematicCoreMacOS/CinematicCoreMacOS/VirtualCameraOutputSink.swift): the host supplies frames over XPC. It does not start a CMIO capture stream on its own virtual device. Therefore host frame production should not by itself make the device a consuming client; this is an inference to check on the rig.

Apple's public CoreMediaIO API presents camera extensions through the same device interface used for DAL devices. See [WWDC22: Create camera extensions with Core Media IO](https://developer.apple.com/videos/play/wwdc2022/10022/). The SDK's `CMIOHardwareDevice.h` documents the [running-somewhere property](https://developer.apple.com/documentation/coremediaio/kcmiodevicepropertydeviceisrunningsomewhere) as a `UInt32` that reports whether the device runs in any process. It is a Boolean, not a count or an app identity.

## Options

| Option | Benefit | Cost and limits |
| --- | --- | --- |
| **(a) Read the CMIO device property in the host** | No extension deployment; observes activity independently of the host's frame/XPC state; fits “in use” versus “not in use yet”. | Must resolve the correct device and handle disappearance, read errors and delayed notifications. Provides no count, app identity or frame-delivery proof. Property support and transitions still need rig verification. |
| **(b) Add an XPC reply with streaming count** | Can return an extension-side snapshot and later support richer diagnostics. | Changes shared protocol and extension implementation; owner must re-activate the extension. Old installed extensions may not implement the selector. Needs version/capability negotiation, timeout and disconnect handling. Does not prove downstream display or call delivery. |

For (b), don't expose `_streamingCounter` as an exact app count without checking callback semantics. Apple's [`CMIOExtensionStream.streamingClients`](https://developer.apple.com/documentation/coremediaio/cmioextensionstream/streamingclients) is the direct client collection; its SDK header marks it key-value observable. Prefer its count if an actual stream-client count becomes necessary. A client collection still does not guarantee one entry per user-visible application. Keep the existing app-group-prefixed service name and signing checks.

## Suggested host implementation

1. Resolve the Alfie virtual device to a current `CMIODeviceID` using its persistent UID, never its display name alone. Verify the actual UID exposed from Alfie's fixed extension UUID on the rig; don't assume a string format. Re-resolve after device-list changes or extension restart; device IDs are not persistent identities.
2. Check `CMIOObjectHasProperty`. Read global scope, main element with [`CMIOObjectGetPropertyData`](https://developer.apple.com/documentation/coremediaio/cmioobjectgetpropertydata(_:_:_:_:_:_:_:)); accept only a successful, correctly sized `UInt32` value of 0 or 1.
3. Read initially, then register a property listener and refresh on app activation/device-list changes. Marshal observable updates onto the main actor and remove listeners when monitoring ends. A slow bounded refresh while Webcam is live can cover missed notifications; measure its need on the rig.
4. Return `inUse`, `notInUse`, or `unknown`. On missing device, unsupported property, failed read or stale observation, clear the prior result to `unknown` rather than retaining a green label or converting failure to zero.
5. The monitor only reads properties. It must not create an `AVCaptureSession`, start a CMIO stream, request camera access, or turn on pre-Start previews. If a future host preview consumes the virtual device, this Boolean will include that preview and the wording must be reconsidered.

| Observation | Suggested copy |
| --- | --- |
| Known 1 | “Alfie camera · in use” |
| Known 0 | “Alfie camera · not in use yet”; help: “Choose Alfie as the camera in your meeting app.” |
| Unknown | “Alfie camera · use status unavailable”; keep installation/connection recovery separate. |

## Prototype and remaining verification

A scratch Swift probe compiled with local Xcode 27.1 and ran under a 15-second limit. It enumerated CMIO devices and was prepared to read this property with no stream-start calls. The sandboxed probe saw **zero devices**. This verifies API compilation only; it establishes neither property support nor transitions on an installed Alfie device. The probe is not shipped. These are established public APIs; hosted Xcode 26.2 compilation remains part of implementation validation.

Required owner-rig checks before wiring the label:

- Start Alfie's Webcam output with no consumer: known zero; host XPC frame traffic alone must not show “in use”.
- Select Alfie in Zoom, Meet and FaceTime separately: known one while each actually captures, then zero after release. Check camera-off and camera-selection previews as well as calls.
- Use two consumers; closing one must retain “in use”, closing the last must clear it. Never infer the number of consumers from the Boolean.
- Check denied consumer permission, client crash, extension restart and device disappearance. Unknown must remain distinct from zero; status must recover without activating a camera preview.

No rig, receiving app, release or privacy gate is certified by this note or by software tests. There is no owner decision needed to proceed with (a); observed rig failure would trigger the documented fallback to a separately reviewed extension change.

## UX-M3 implementation (6 November 2026)

`WebcamUsageObserver` is model-only. Track A calls `setMonitoring(mode:isLive:)` from the actual session lifecycle. It samples immediately and about once a second only in live Webcam mode, never during stopped previews. Stop/mode exit clears evidence to unknown. Reads run off the main actor; an independent tick expires old evidence after 2.5 seconds, and generation tokens reject completions from an ended session. A read taking longer than that freshness bound is unknown too.

`CMIOWebcamUsageReader` resolves the current device list on every read and accepts only a single persistent UID that parses as the existing extension's fixed device UUID. It never matches a display name. If the installed device exposes a different UID format, this conservative implementation returns unknown: the actual UID format still needs the owner-rig check above. Unsupported, failed, malformed and non-Boolean property reads return unknown. No capture session, stream start, permission request, XPC change or extension change is involved.

The injected reader and monotonic clock cover the live-mode gate, positive/zero/unknown transitions, stale evidence, slow reads, overlapping refresh suppression, stopped-session override and late-completion rejection. They do not certify the property transitions on installed hardware or what any receiver displays.
