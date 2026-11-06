# Camera faults and recovery

S1 specification · 5 November 2026. Starts from all ten cases in `Readiness/FaultRecovery.swift` at `3dd0d2d`. The copy below is the proposed replacement contract; S1 changes no Swift.

## Placement and exact copy

Every row uses **a banner while the session is live, an alert while stopped**, through `FaultRecovery.evaluate(error, isSessionLive:)`. Determine liveness from the session, not whether the failed camera currently delivers frames. A lost camera in a live show must not turn its banner into a modal alert. Pre-Start previews are not a live Program session.

| `CameraError` | Title | One-line explanation | Buttons in order | “What happened” line |
| --- | --- | --- | --- | --- |
| `.noCameraAvailable` | No camera found | Connect a camera, then try again. | Reconnect; Choose camera…; Dismiss | No camera was found. |
| `.sessionConfigurationFailed` | Camera could not start | Try reconnecting this camera, or choose another camera. | Reconnect; Choose camera…; Dismiss | The camera could not start. |
| `.unsupportedFormat` | Camera format unavailable | Choose a camera that supports the show's frame rate. | Choose camera…; Dismiss | The camera does not support the show's frame rate. |
| `.authorizationDenied` | Camera access is off | Allow Alfie to use cameras in System Settings. | Open camera settings; Dismiss | Camera access was denied. |
| `.noValidationClipSelected` | Choose a video clip | Select a video file before starting playback. | Choose video clip…; Dismiss | Playback could not start because no video clip was selected. |
| `.invalidValidationClip` | Video clip could not be read | Choose a video file with a readable video track. | Choose video clip…; Dismiss | The selected video clip could not be read. |
| `.validationClipPlaybackFailed(_)` | Video clip playback stopped | Choose the clip again, or select another video file. | Choose video clip…; Dismiss | Video clip playback stopped. |
| `.deviceInUse(owner)` | Camera already assigned | This camera is assigned to {owner.cameraLabel}. Choose another camera. | Choose camera…; Dismiss | The camera was already assigned to {owner.cameraLabel}. |
| `.deviceMissing` | Camera disconnected | Reconnect this camera, or choose another camera. | Reconnect; Choose camera…; Dismiss | The selected camera disconnected. |
| `.noDeviceSelected` | Choose a camera | Select a camera for this input. | Choose camera…; Dismiss | No camera was selected for this input. |

“Already assigned” means another Alfie channel, not a guessed external application. Never show the raw playback failure string, file path or diagnostic code as the explanation; engineering logs can retain the existing detail. “Choose video clip” is operator wording for the existing validation-clip action, respecting its existing availability/DeveloperFlags.

## Actions, focus and announcements

| Label / accessible name | Existing action | Behaviour |
| --- | --- | --- |
| Reconnect | `.reconnect` | Retry only this input's selected source. Never silently substitute a camera or take it to Program. |
| Choose camera… | `.chooseAnotherCamera` | Open the camera chooser for this input, respecting live assignment/route guards. Cancel keeps the current assignment. |
| Open camera settings | `.openCameraPrivacySettings` | Open camera privacy settings. On app activation refresh readiness; do not Start automatically. |
| Choose video clip… | `.chooseValidationClip` | Open the existing file chooser. Cancel changes nothing. |
| Dismiss | `.dismiss` | Hide this presentation, retain fault status and log. Does not resolve the fault or change output. |

A banner has an attention icon and the title, explanation and fix buttons. Its VoiceOver label is “{input name}. {title}”; value is the explanation. Announce “{input name}. {title}. {explanation}” once per new fault or changed fault, without stealing focus from the live control. An alert uses the same title/explanation, is labelled for the input, and places initial focus on the first fix. Escape cancels/dismisses an alert and never stops the session.

During reconnect, replace its button text with **“Reconnecting…”**, disable only the pending action, and announce “Reconnecting {input name}.” Ignore duplicate requests. On success remove the fault presentation and announce “{input name} reconnected.” If stopped, return to the stopped screen and refresh readiness; never interpret recovery as consent to start Program. On failure replace the presentation with the newly evaluated fault and its fixes, and announce it once. A failed settings deep link must expose “System Settings could not be opened. Open System Settings, then Privacy & Security, then Camera.” beside the action, which remains available to retry.

If a chooser cannot change the input while live, show **“Stop the session to change this camera.”** in `secondaryText` alongside the unavailable control; keep Reconnect available when the model permits it. Do not bypass the existing live guard. The stopped alert's Dismiss returns focus to the originating control. Dismissing a live banner leaves the input's fault text and the Inspector entry discoverable; the same unchanged fault does not immediately reannounce itself.

## What happened

Place **What happened** at the end of the Inspector's expanded Show group. Empty: **“No events this session.”** No action is needed. Store a bounded, in-memory list for this session (latest 50 events, newest first); keep the just-ended session visible until the next Start. No new persistent telemetry is required.

Format: **`14:32:08 · Cam A · The selected camera disconnected.`** Use local time with seconds, the affected input name and the table's plain sentence. Accessible label: “At 14:32:08, Cam A. The selected camera disconnected.” Speak the localised time naturally. Log once per transition, not every failed frame or observer tick. Recovery adds **`14:32:15 · Cam A · Camera reconnected.`** A dismissal is not recovery. Announce new faults from the banner/alert only; the list does not echo them. Do not claim frames reached a receiver.

Implementation evidence: all ten faults in both placements, long input names, reconnect pending/success/failure, repeated-error suppression, chooser cancellation, permission recovery, empty/populated log, keyboard focus and VoiceOver. Check physical disconnect/reconnect and permission revocation on the rig; software tests are not that evidence.
