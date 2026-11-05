# Webcam guidance and use status

S1 specification · 5 November 2026. Uses [Sol's feasibility note](webcam-in-use-feasibility.md). Implementation and attended property validation remain separate work.

## First use

On the first selection of Webcam, show the nonmodal note beside its Start/output area:

**“In Zoom, Meet or FaceTime, choose Alfie as your camera.”**

Action **Got it**, accessible name **“Dismiss camera selection tip”**. VoiceOver reads the full note on first presentation without moving focus away from the mode picker. Remember dismissal per local user; no repeated modal on Start. Keep the same instruction available as output help after dismissal, and as persistent guidance when the stream is not in use. Selecting Webcam or displaying this note never opens a camera. Readiness and the explicit Preview cameras opt-in still apply.

## Exact states

| State / evidence | Visible text | Help / action | VoiceOver label or announcement |
| --- | --- | --- | --- |
| Stopped, previews off | Alfie camera is off. | Start session; readiness fixes if needed | “Alfie camera is off.” |
| Explicit previews on, Program stopped | Camera previews are on. Program output is off. | Turn previews off | Same sentence. |
| Starting | Starting Alfie camera… | No duplicate Start | “Starting Alfie camera.” |
| Live, fresh supported property value 1 | Alfie camera · in use | “An app has started the Alfie camera stream.” No fix button needed. | “Alfie camera is in use.” |
| Live, fresh supported property value 0 | Alfie camera · not in use yet | “In Zoom, Meet or FaceTime, choose Alfie as your camera.” No speculative launch-app button. | “Alfie camera is not in use yet. Choose Alfie as the camera in your meeting app.” |
| Live, unknown/unreadable/stale | Alfie camera · use status unavailable | “Check your meeting app to see whether Alfie is selected.” No reinstall action merely because this property is unavailable. | “Alfie camera use status is unavailable. Check your meeting app.” |
| Actual installation/connection/capture fault | Its specific readiness/fault title and fix | Use readiness or fault recovery, not the unknown-use label as a substitute | Announce the actual fault once. |

On transition to known zero after previous use, retain the specified “not in use yet” status but announce **“Alfie camera is no longer in use.”** This describes stream activity, not the end of the meeting. Announce changed states once, never every poll. Include a worded state and an icon/shape; colour alone is insufficient. Stop overrides any cached in-use value immediately when the lifecycle confirms output is off. Use the full ended-session sentence from [Stop](stop.md) where appropriate.

## Signal boundary

Use the host-side `kCMIODevicePropertyDeviceIsRunningSomewhere` approach from the feasibility note. It reports stream activity, **not** the receiving app's identity, audience, frame freshness, or successful delivery into a call. Do not say “Zoom connected”, “Live in your meeting”, or infer a client count. Host Program production alone is not proof of a consumer.

Unsupported property, a failed read, missing device, invalid value or stale observation means **unknown**, never known zero. Clear stale positive evidence. Monitoring must be read-only and must not create a capture session or turn on pre-Start previews. Until the owner-rig signal checks in the feasibility note pass, keep affirmative/negative status unqualified as implementation work; unknown is the honest fallback.

Implementation evidence: first-use note before/after dismissal, all states above, stopped override, errors and recovery, state announcements, no-camera-light test before explicit preview, menu/button accessibility, both appearances and system accessibility settings. Rig evidence must cover no consumer, each supported meeting app, two consumers, last-consumer release, crash, extension restart and denied permission. Never infer receiver presentation from software snapshots.
