# Inspector

S1 specification · 5 November 2026. Inventory checked against `InspectorDrawer.swift` and `InspectorShowSection.swift` at `3dd0d2d`.

## Find and navigate it

Replace the “⌥” handle with a toolbar button: sidebar icon plus **Inspector**. Keep the word visible. Tooltip and accessible name are **“Show Inspector”** when closed and **“Hide Inspector”** when open; expose expanded/collapsed state and the drawer relationship. The menu is **View › Show Inspector ⌥⌘I**, changing to **Hide Inspector** while open. Publish `\.alfieShowInspector` from the operator scene; do not modify the app's command wiring.

Opening announces “Inspector shown” and places focus at the drawer heading. Closing uses **Close Inspector** (accessible name and help), announces “Inspector hidden” and restores focus to the toolbar button. A drawer is not a modal: keyboard users can move between it and the operator controls. Do not bind Escape to close it while Escape belongs to Cancel Detect or Done Editing Live. The menu and button use the same toggle.

The drawer heading is **Inspector**. Two disclosure groups follow: **Show**, initially expanded, and **Engineering**, initially collapsed. Remember disclosure choices while this drawer instance remains open; a new app session starts with these defaults. Accessible labels are “Show” and “Engineering”, with expanded/collapsed values; standard disclosure actions toggle them. Explain Engineering with **“Details for troubleshooting.”** Do not relocate an active fault's only recovery into Engineering.

## Show: row-by-row order

Every row reads “{label}: {value}” to VoiceOver. Explicit empty/waiting text replaces unexplained dashes. Named actions below use the same accessible name, with the input name added for repeated actions. Long values wrap or reveal their full text accessibly.

| Position / label | Value and source | Action / empty or exceptional copy |
| --- | --- | --- |
| Camera (Single Cam/Webcam) | Selected device's display name | **Change camera…** chooser; **“No camera selected”** if absent. While change is unavailable: **“Stop the session to change this camera.”** |
| Program (Multi Cam) | `{camera label} · {device name}` from existing role detail | Read-only; **“No Program camera”** if none. |
| Preview (Multi Cam) | `{camera label} · {device name}` | Read-only; **“No Preview camera”** if none. |
| Controls affect (Multi Cam) | `{camera label} · Preview` or `{camera label} · Live Program` | Read-only. Preserve **“Editing live”** as a worded badge when active. |
| Inputs (Multi Cam) | One row per assigned camera: name, device, current shot and health | Health: **“Not running”**, **“Camera disconnected”**, **“Camera pair unsupported”**, or **“Running · {rate} fps”**; before a rate exists **“Running · Measuring frame rate…”**. **Reconnect {camera label}** appears for missing sources. Reconnect errors use [faults](faults.md). |
| Program output | Effective route's name: **Alfie camera**, actual Direct destination, or **Rehearsal** | **Output settings…**. Status: **“Off”**, **“Starting…”**, **“Sending Program”**, or actual fault explanation. Rehearsal: **“No external output”**. Routing is not receiving-app proof. |
| Output picture (Multi Cam router summary) | **“{camera label} is feeding Program”**, **“Waiting for the first frame”**, **“Holding the last good frame”**, or **“Sending black. {camera label} is disconnected.”** | Read-only. Keep detailed timeout/router data in Engineering. No automatic Take action. |
| Format | Configured output width × height, frame rate and colour, e.g. **“1920 × 1080 · 30 fps · Rec. 709”** | **Output settings…** may share the preceding button. Unknown: **“Output format not available”**. Do not present delivered source size as configured output. |
| Source picture | Delivered source dimensions, e.g. **“3840 × 2160”** | Read-only. Stopped: **“Camera is off”**; running without a frame: **“Waiting for a camera frame”**. Include existing capture-profile explanation in normal text. |
| Framing | Current shot name | **Framing settings…** opens the existing framing page. Detailed timing/tuning values move below. |
| Alfie camera (only on virtual route) | Installation/readiness wording from [readiness](readiness.md); while Webcam runs, stream-use wording from [webcam](webcam.md) | Same one recovery action as readiness when required; no install affordance for a Direct route that does not need it. |
| Next shot (Multi Cam) | Existing human-readable Take readiness/reason, e.g. **“Ready”** or the current refusal explanation | Read-only here. Keep the reason next to TAKE as well. Codes and frame ages move below. |
| What happened | Latest session events | [Exact format and empty state](faults.md). No action, no raw stack traces. |

Retain **Refresh devices** and **Cameras…** next to the camera choice if they provide distinct existing functions: discovery refresh and device details respectively. Accessible names **“Refresh cameras”** and **“Show camera details”**; refreshing announces “Camera list updated” when complete, not “Camera ready”. A refresh never turns cameras on. Show the camera name under the stopped mode picker too; operators need not open this drawer to know what will start.

## Engineering: row-by-row migration

This split changes presentation, not authority, qualification, pipeline behaviour or release flags. Preserve all existing data and conditional visibility. Section heads use these sentence-case names, not uppercase abbreviations.

| Section / existing rows | Destination and wording | Action / accessibility |
| --- | --- | --- |
| Composition: Target hold, Deadzone, Spring ease | **Framing details**: “Target hold”, “Dead zone”, “Spring ease” with existing units | **Framing settings…**; absent engine value: **“Not available while stopped”**. |
| Source: Crop Geometry, Color | **Picture details**: “Crop geometry”, “Colour format”; keep enlargement/native wording and Rec. 709 / 8-bit values | Read-only; don't manufacture a capability when none is reported. |
| `PipelineStagesSection`, all existing stage/rate/timing rows | **Pipeline stages**, preserving its existing order and measurements | Existing actions retained, accessible names expanded from abbreviations. Unknown value: **“Not measured”**. |
| `SetupCheckSection`, current state/results and check actions | **Setup check**, preserving current results and safety guards | Keep operator-blocking failure/fix in Show/stopped setup as well. Never relabel a software pass as a rig certification. |
| Show detail: Router internal state/timeout | **Router details** | Read-only; prose output status remains in Show. |
| Show Inputs: source generation and shot revision | **Input revisions**, one camera-labelled row each | Read-only; mono values only. |
| Next shot: reason code, failing checks, frame/source ages and revision | **Next shot details** with “Readiness code”, “Checks not ready”, “Frame age”, “Source age”, “Shot revision” | Human-readable reason remains in Show; unknown age: **“Not measured”**. |
| Admission: Status, Decision, reason codes/bottlenecks/messages | **Admission details**; preserve evidence meaning and all refusal reasons | Read-only. A status is never upgraded by moving it. |
| Workload and last transition reasons | **Workload**; preserve `InspectorWorkloadDetail` wording and **“Last change: {reasons}”** | Appears only when an existing policy exists, including a one-input show; no invented normal/recovery event. |
| Modules: Composer | **Components**, “Composer”; retain version/status | Opens framing settings. |
| Modules: Output | Consolidate operator route information in Show; engineering component detail only here if distinct | Opens output settings; do not label every route “Virtual camera”. |
| Modules: Playback, Cinematic Agent, Recorder | **Developer tools**, preserving their existing flag gates and actions | Use worded **“Developer”** badge and active/inactive/recording state; never enable hidden tools to fill the section. |
| Built-in camera testing | **Developer tools**, same toggle and detail, visible only under its existing conditions | “Built-in camera testing, on/off”; persistent disabled reason **“Stop all cameras before changing built-in camera testing.”** |
| Diagnostics: Build, Extension, GPU | **Diagnostics**, “Build”, “Camera extension”, “Graphics processor” | Values keep versions/identifiers; state says **“Installed”**, **“Not installed”**, **“Installing…”**, **“Approval needed”**, **“Unavailable”** or **“Could not check”** as applicable. |
| Reveal logs in Finder | End of Diagnostics | **Reveal logs in Finder**, same accessible name. Failures appear beside it with the actual recovery. |

Pipeline stages retain these rows in order: **Delivered**, **Admitted**, **Handoff accepted**, **Repeated (hold)**, **Presented**, **Capture dropped**, **Gate skipped**, **Render failed**, **Handoff refused**, **No route**. Each accessible row reads “{stage}, {window rate or count}, session total {total}” where a total exists. Presented remains **“Unknown”**, with no invented total. Window heading: **“Last {partial/full} window · {seconds} s”**. Empty: **“No measurements yet. Counts appear about 5 seconds after capture starts.”** Supporting line: **“Handoff means the output accepted the frame. Alfie cannot tell when another app or display shows it.”** These rows are read-only.

Setup check states retain their model meanings: idle **“Measures this camera and output for about {seconds} seconds while they run. Nothing is changed.”**, action **Run setup check**; warming **“Warming up…”**, action **Cancel**; sampling **“Measuring · window {current} of {needed}”**, action **Cancel**; finished, the existing **Supported / Limited / Unverified** verdict and reasons, action **Run again**; cancelled, **“Setup check cancelled. {reason}”**, action **Run again**. When capture is stopped, disable Run and show **“Start capture before running this check.”** in secondary text. Results retain delivered fps, handoff fps, milliseconds per frame, skipped percentage, measured duration and the existing qualification disclaimer. Accessible labels mirror the full text; announce phase changes once, not every metric refresh. This check is never automatically run by expanding Engineering.

All headings, labels, help, badges and values are at least **11 pt**, sentence case. Use the system proportional face for words and mono only for measured values, versions and codes. Status always has words or shape, not colour alone. Use colour roles and the shared button family. Apply Increase Contrast, Reduce Transparency, Reduce Motion and Differentiate Without Colour as specified in [DECISIONS](DECISIONS.md); do not hard-code styling here.

Implementation captures: closed labelled button; default open drawer; Engineering expanded; single camera and Multi Cam; long device names; no-camera/no-frame/output-off states; every router state; missing input/reconnect failure; workload absent/present; empty/populated log; light/Navy night; all accessibility settings. Verify VoiceOver reading order, focus restoration and Full Keyboard Access on the real app. Camera and receiver claims still require a rig check.
