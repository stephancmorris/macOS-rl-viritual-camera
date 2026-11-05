# Get ready

S1 specification · 5 November 2026. Baseline: `3dd0d2d`, including M1 and M2. This is the implementation contract, not a claim that these screens already ship.

## Placement and lifetime

On the stopped screen, place **Get ready** between the mode/camera choice and **Start session**. Supporting line: “Finish these steps before starting.” Multi Cam uses the same checklist on its stopped setup screen; Track B owns that placement. No setup modal on launch.

Show the checklist exactly when `readiness.canStart == false`: at least one **required** row is not ready. Here “missing” includes a required step still **waiting**; hiding a waiting blocker would strand the operator. Keep the model's order: `cameraAccess`, `virtualCamera`, `programOutput`. Show all required rows while the checklist is present, including completed rows, and omit `notNeeded` rows. Hide the checklist when all required rows become ready; announce “Ready to start.” Reappear on regression, mode change or route change; announce “Setup needs attention. {first blocking row title}.” Do not steal focus on a background update.

Use a checkmark plus “Ready”, a waiting symbol plus “Waiting”, or an attention symbol plus “Action needed”. Colour is supplementary. All copy is at least 11 pt. VoiceOver reads each row as “{title}. {status}. {explanation}”; button labels below are also their accessible names. Announce transitions once, not every observer refresh. When a focused row disappears after recovery, move focus to Start session.

## Exact rows and model mapping

The table supplies the complete row text after its title. A dash means **no action button**, matching `Row.action == nil`; do not invent a redundant button on a ready or in-progress row. No new readiness enum cases are needed. Detailed permission and extension copy comes from the same source snapshot used to evaluate the row; the three-state enum alone cannot distinguish denial from an unanswered prompt.

| Row title / ID | Input and resulting state | Exact status and explanation | One button → action |
| --- | --- | --- | --- |
| Camera access / `cameraAccess` | `.notDetermined` → `.missing` | Action needed. Alfie needs camera access to frame your shot and send Program video. | Allow camera access → `.requestCameraAccess` |
| Camera access | `.denied` → `.missing` | Action needed. Allow Alfie to use cameras in System Settings. | Open camera settings → `.openCameraPrivacySettings` |
| Camera access | `.restricted` → `.missing` | Action needed. Camera access is restricted on this Mac. Check System Settings; you may need your administrator. | Open camera settings → `.openCameraPrivacySettings` |
| Camera access | `.unknown` → `.missing` | Action needed. Alfie cannot check camera access. Check System Settings. | Open camera settings → `.openCameraPrivacySettings` |
| Camera access | `.authorized` → `.ready` | Ready. Alfie can use your cameras. | — |
| Camera access | `.waiting` | Waiting. Answer the camera access prompt to continue. | —; see transient prompt rule below |
| Alfie camera / `virtualCamera` | `.notInstalled` → `.missing` | Action needed. Install Alfie camera to use Program video in another app. | Install Alfie camera → `.installVirtualCamera` |
| Alfie camera | `.unknown` → `.missing` | Action needed. Alfie camera has not been confirmed installed. | Install Alfie camera → `.installVirtualCamera` |
| Alfie camera | `.failed(.retryInstall)` → `.missing` | Action needed. Alfie camera could not be installed. Try again. | Install Alfie camera → `.installVirtualCamera` |
| Alfie camera | `.failed(.openSystemSettings)` → `.missing` | Action needed. Check Alfie camera approval in System Settings. | Open extension settings → `.openExtensionSettings` |
| Alfie camera | `.activationRequested` → `.waiting` | Waiting. Installing Alfie camera… | — |
| Alfie camera | `.awaitingUserApproval` → `.waiting` | Waiting. Approve Alfie camera in System Settings. | Open extension settings → `.openExtensionSettings` |
| Alfie camera | `.installed` → `.ready` | Ready. Alfie camera is installed. | — |
| Program output / `programOutput` | `.missing` | Action needed. Choose an available Program output. | Choose output… → `.chooseOutput` |
| Program output | `.waiting` | Waiting. Preparing {output name}… | — |
| Program output | `.ready` | Ready. Program will go to {output name}. | — |

Display “Alfie camera” for the model's `virtualCamera` row, whose current model title is “Virtual camera”. Display output names “Alfie camera” or the selected Direct destination, such as “ATEM”. Never infer an ATEM merely from an HDMI connection; use “Direct output” if its identity is unknown.

The current evaluator never emits `.waiting` for camera access, and the production observer never emits `.waiting` for output. The camera waiting copy is a **view-local request-in-progress presentation**, while the underlying permission remains `.missing` and blocking. Disable the row's Allow action during the one outstanding request; restore its mapped action after the result. Do not claim the evaluator emitted a new state. Output waiting copy covers a future/injected `.waiting` value already supported by the model; no simulated delay is required in production.

`notNeeded` is a requirement, not a fourth state: the evaluator uses `.notNeeded/.ready/nil`. Omit these rows. If exposed in an engineering detail, use “Camera access: Not needed for video clips”, “Alfie camera: Not needed for this output”, or “Program output: Not needed for rehearsal”, with no action; VoiceOver reads the same sentence.

## Which steps are required

| Mode | Effective route | Camera access | Alfie camera | Program output |
| --- | --- | --- | --- | --- |
| Single Cam | Virtual camera | Required for live camera | Required | Required |
| Single Cam | Direct | Required for live camera | Not needed | Required |
| Single Cam | Rehearsal | Required for live camera | Not needed | Not needed |
| Multi Cam | Virtual camera | Required if any participating input is a live camera | Required | Required |
| Multi Cam | Direct, including an ATEM | Required if any participating input is a live camera | Not needed | Required |
| Multi Cam | Rehearsal | Required if any participating input is a live camera | Not needed | Not needed |
| Webcam | Virtual camera, regardless of saved route | Required for its live camera | Required | Required |

Clip-only sessions do not require camera permission. Pass only the inputs that will participate; recreate the observer when that set changes. Webcam's effective route is always `.virtualCamera`, including when the saved preference says Direct or Rehearsal. A virtual camera's idle connection is not a blocker: `ReadinessObserver` deliberately treats its unavailable idle sink as ready, and installation is checked separately. “Ready” means configured to start; it does not prove a frame reached the meeting or ATEM. Keep existing camera availability, pair admission and first-frame checks.

## Permission, preview and Start

Only **Allow camera access** invokes the system permission request. Keep its why-line visible before invocation. Do not request permission on launch, mode selection, observer refresh or Start. After any recovery and on return from System Settings call `refresh()`; do not automatically Start after a permission grant or installation.

**Preview cameras** is separate, off on launch and after Stop. Help and VoiceOver hint: “Turns on the selected cameras so you can check their pictures. Program output stays off.” While on, label the action **Turn previews off** and show “Camera previews are on. Program output is off.” Before permission is ready, activating Preview cameras points to Camera access using the refusal below; it does not launch a cold permission prompt. Turning previews off announces “Camera previews are off.” Preview-on is capture activity, not a live Program session. Starting uses the normal validated Start path; previews never implicitly start output or TAKE.

Start stays focusable so its refusal and fix are discoverable. Before any Start path, refresh and re-evaluate synchronously on the main actor. If blocked, do no capture/output work. Immediately below Start show **“Not ready to start. {blocking instruction}”**, announce that sentence once and move keyboard/accessibility focus to the first blocking row's action (or row if waiting). Use `blockingRow`, never choose a different priority in the view. Retain the reason until resolved or replaced by a new blocker; no flashing required.

| Blocker | Exact blocking instruction |
| --- | --- |
| Camera request needed | Allow camera access above. |
| Camera denied, restricted or unknown | Check camera access in System Settings. |
| Camera prompt in progress | Answer the camera access prompt. |
| Alfie camera install needed | Install Alfie camera above. |
| Extension approval/settings needed | Check Alfie camera in System Settings. |
| Extension activation in progress | Wait for Alfie camera to finish installing. |
| Program output missing | Choose a Program output above. |
| Program output waiting | Wait for Program output to finish preparing. |

On an accepted Start show “Starting session…” and prevent duplicate requests. Announce “Starting session.” If a later permission race causes `.authorizationDenied`, use [fault recovery](faults.md), without issuing another permission request. When live, remove the stopped checklist; handle failures as banners.

## Evidence required in implementation

Capture each table variant, notNeeded omission, all-ready disappearance, waiting-only visibility, regression, refusal/focus, explicit preview off/on, and route/mode combinations using injected observations. Include VoiceOver and keyboard checks, all accessibility settings in [DECISIONS](DECISIONS.md), light and Navy night. On the real rig check fresh permission, denial, approval, disconnect and Direct-to-ATEM with no extension installed. Synthetic captures cannot certify those checks.
