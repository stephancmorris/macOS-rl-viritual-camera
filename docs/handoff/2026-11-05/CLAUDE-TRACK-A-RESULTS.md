# Claude Track A results (UX J3, J4, J5, J12)

6 November 2026. Claude Opus 5.5 claimed Track A at 12:45 AEDT, while Sol and Astra were out of usage. The claim is #124, the PR that carries this work. Astra skips Track A and finishes Track C; Sol keeps Track B and reviews this PR in Wave 3.

## What changed

**J4 · shape the shot on air** (`OperatorPill`)
- **Four groups, 12 pt apart:**
  - Subject: the target chip, the lock state and Detect.
  - Shot: Wide, Full Body and Waist Up, or Wide and Tight on Webcam.
  - Move: Crop, Manual, Auto Pan, Pull out, Push in and Return to Wide.
  - Session: Stop.

  Controls inside a group are 4 pt apart, and each group is a VoiceOver container named for it. The section order is unchanged, so the existing pill tests still hold. The pill got narrower, because three group gaps replaced eight dividers.
- **Every disabled control says why,** in its help tag and as the VoiceOver hint. For example: "Zoom limited by the source.", "Already at the tightest shot.", "Lock a subject first." and "Turn off Manual or Auto Pan to detect." The pill's "ZOOM LIMITED" line now reads "Zoom limited by the source".
- **Already done in F3:** Manual and Auto Pan toggles with an on/off indicator, the active shot shown as selected, and the 11 pt labels.

**Keys** (`OperatorPillCommands.swift`)
- **Only the live single-camera pill publishes** (Single Cam and Webcam):
  - Detect (D), or Cancel Detect on Escape while Detect waits for a click.
  - Wide, Full Body and Waist Up (W, F, U). Webcam publishes only W.
  - Push In and Pull Out (] and [), while each is possible.
  - Stop Session (⌘⌥⇧S), which takes precedence over the app fallback.
- **Withdrawn when unavailable,** so the menu item disables and the key passes through.
- **Announcements** follow keyboard-map.md. A refused command announces its reason, never success.
- **TAKE and the cue keys are never published here.** The Multiview console's pill publishes nothing; its commands belong to Track B.

**J12 · the pill's Stop**
- It's `AlfieHoldToStopButton`.
- The confirmation names the active route from stop.md's table. Direct says "Direct Program output", because the destination's identity is never inferred.
- A refused Stop shows "Try stopping again".
- `StopRouteCopy.helper(for:)` holds the header lines, so Track B can use them.

**J3 · lock a subject** (`TrackingHints.swift`, `CameraPreviewView`, `DetectionOverlayView`)
- **A lock glyph sits beside "Locked" in every setting** (F4 showed it only under Differentiate Without Colour). The pill reserves its width, so locking doesn't shift the pill.
- **While a click picks a person** (Detect waiting, or Hold or Wide-waiting), the candidate under the pointer gets a wash and a heavier outline, and the pointer becomes the pointing hand. Nothing else in the app uses it.
- **In Hold and Wide-waiting,** "Click the person to pick them up again." shows on a scrim along the bottom of the picture, and is announced once.
- **On the first lock only** (persisted per user), "Locked. To follow someone else, press and hold on them." shows for five seconds and is announced.
- **Under Reduce Motion** the hints don't fade. Under Reduce Transparency the scrims are opaque. The steady acquiring outline came in F4.

**J5 · Webcam in a call** (`Webcam/WebcamCallOverlay.swift`)
- **While Webcam is live,** a chip under the identity stack reads "Alfie camera · in use", "· not in use yet" or "· use status unavailable". Each has its own symbol, its help and its spoken line from webcam.md.
  - It comes from Sol's `WebcamUsageObserver`, which only this view drives, only while live.
  - Changes are announced once. "No longer in use" follows earlier use.
  - Stop clears it at once.
- **The one-time note,** "In Zoom, Meet or FaceTime, choose Alfie as your camera.", has **Got it** (accessible name "Dismiss camera selection tip"). It's remembered per user. After that it stays as the not-in-use help.
- **Wide and Tight's selected state** came in F3.

**ContentView** (Track C's file) gets two small insertions in the live single-camera layer, away from Astra's J1, J2 and J9 hunks: `tracking:` on the crop preview, and the Webcam overlay.

## A copy correction

The round-two plan's first-lock tip said "Click someone else to switch. Hold to retarget." The app deliberately never changes a locked shot on a click, so a stray press mid-show can't cut; only a hold retargets. The tip says what the app does instead.

## Tests

- `TrackAPillTests`: the groups, published commands for each state, no TAKE or cue key, menu titles, unavailable reasons, stop.md's route lines.
- `TrackATrackingWebcamTests`: who is clickable, the once-only first-lock tip, letterbox hit-testing, webcam.md's words and announcements, and never claiming a call is receiving.
- `TrackAGallerySnapshotTests`: `track-a-*.png` (synthetic picture). The captures that show the pill or its lock dot are regenerated.

## Not verified by software

Attended checks on the running app:
- the real pointer and pointing hand over people, and hover over moving boxes;
- the hold gesture, keyboard and VoiceOver confirmation on the pill's Stop;
- each bare key with a real keyboard, and non-US layouts;
- VoiceOver announcements;
- the Webcam use signal with real meeting apps (no consumer, one, two, last release, crash, extension restart, denied permission), per webcam-in-use-feasibility.md;
- each macOS display setting switched on for real.
