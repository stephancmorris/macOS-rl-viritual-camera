# Alfie — Autonomous Live Framing Intelligence Engine

## Why "Alfie"?

Alfie is an acronym: **A**utonomous **L**ive **F**raming **I**ntelligence **E**ngine.

It is also a name. The project earned a name the moment it stopped being a generic "virtual camera driver" and became an autonomous operator that sits in a church's media booth every Sunday and does the job a human volunteer used to do. Tools don't need names; teammates do. A volunteer camera operator who is smart, unobtrusive, and dependable earns one — and that is what this software aspires to be.

The acronym is honest about the ambition (autonomous, intelligent, live) and the name is honest about the posture (a quiet helper, not a spectacle). When a livestream director says "Alfie has the pastor" or "put Alfie back on wide," they should mean it the way they'd mean it about a trusted crew member.

## Product mission

Alfie is an autonomous live camera operator for church-stage livestreams. Given one fixed wide-angle camera covering the full stage, Alfie detects the active speaker, follows them smoothly as they move, maintains a broadcast-usable waist-up or chest-up composition, and delivers a clean program feed to the downstream switcher — with a human-visible override available at all times.

**In one sentence:** Alfie turns a single wide stage shot into a tracked, composed program feed, without a volunteer behind a PTZ controller.

## Mission constraints

- **One fixed wide camera** covering the full stage — no physical PTZ
- **One active speaker at a time** — typically a pastor at a lectern or moving across the stage
- **Indoor church lighting** — predictable, not cinematic
- **Livestream-grade output**, not broadcast cinema — latency tolerant to ~100–150 ms
- **Operator is a volunteer**, not an engineer — UI must be legible under pressure
- **Failure modes must be recoverable** without a restart — manual override and return-to-wide are always one click away

## Architecture

Alfie is a macOS 14+ application with a companion CoreMediaIO system extension. The app owns capture, perception, composition, and rendering. The extension owns the virtual-camera surface that downstream apps (OBS, ATEM Software Control, Zoom, NDI tools) consume.

```
┌─────────────────────────────────────────────────────────────┐
│ Host App (sandboxed, @MainActor orchestration)              │
│                                                             │
│ ┌──────────┐   ┌───────────┐   ┌──────────┐   ┌──────────┐  │
│ │ Capture  │──▶│ Perception│──▶│Composition│──▶│  Render  │  │
│ │ AVFoundat│   │  Vision   │   │ShotCompose│   │  Metal   │  │
│ └──────────┘   └───────────┘   └──────────┘   └────┬─────┘  │
│                                                    │        │
│                                              ┌─────▼─────┐  │
│                                              │ Program   │  │
│                                              │ Output    │  │
│                                              │ Routing   │  │
│                                              └─────┬─────┘  │
└───────────────────────────────────────────────────┬─────────┘
                                                    │ XPC (IOSurface zero-copy)
                                                    ▼
                              ┌─────────────────────────────────┐
                              │ CMIO System Extension           │
                              │  ├── Virtual Camera device      │
                              │  └── Feeds OBS/ATEM/Zoom/NDI    │
                              └─────────────────────────────────┘
```

## Perception stack

**Status:** Shipping.

- `VNDetectHumanRectanglesRequest` — body bounding boxes per frame
- `VNDetectHumanBodyPoseRequest` — joint keypoints for pose-aware framing
- Vision is already deep-learning-backed and ANE-accelerated. Perception is the layer where machine learning earns its keep in Alfie; everything downstream is deterministic.

## Composition stack

**Status:** Shipping, tunable.

`ShotComposer` is the controller that decides, per frame, what rectangle the program feed should crop to. Key behaviors:

- **Sticky speaker selection** with configurable target-hold duration so the camera does not jump between people when a second person briefly appears on stage.
- **Manual subject lock** — operator taps a detected person in the preview to force that person as the active target.
- **Chest-up / Waist-up framing** anchored to the full subject detection, so vertical extent scales with subject height rather than the tighter tracked-torso region.
- **Deadzone** on subject movement to suppress jitter from small detection noise.
- **Aspect correction** — the crop rectangle is computed in Vision's normalized (0–1) coordinate space and corrected for source pixel aspect, so a normalized "16:9" rect maps to a real 16:9 region regardless of source resolution.
- **Frame-only clamping** — the crop can follow a speaker to the physical edge of frame; stage-margin settings are used for subject selection, not for fencing the crop.

The composer is heuristic, by design. See "Deep learning policy" below.

## Rendering stack

**Status:** Shipping.

- Metal compute kernel does the crop-and-scale in a single dispatch to a fixed output size (1920×1080 MVP default).
- Lerp-based interpolation between target crops produces cinematic motion without visible stepping.
- Output pixel buffers are IOSurface-backed for zero-copy handoff to the system extension.

## Output routing

**Status:** Virtual Camera shipping; Blackmagic SDI deferred.

`ProgramOutputManager` arbitrates between routes. Two sinks exist:

- **Virtual Camera (primary, MVP).** Processed frames flow over XPC to the CMIO extension, which advertises Alfie as a camera device. Downstream apps pick it up exactly like any USB webcam. This is the shipping path.
- **Blackmagic SDI (deferred).** Scaffolding exists for a Desktop Video SDK sink. Not integrated for MVP. See "Deferred" below.

The operator preview shows the *actual rendered program frame* — what downstream systems receive — so the right pane is truthful, not a separate debug view.

## Operator principles

1. **Truthful preview.** The right pane is the downstream feed, bit-for-bit.
2. **Always-available override.** Return to Wide and manual subject lock work even when detection is unstable.
3. **Minimal cognitive load.** Framing presets are named in shot-language (Wide Safety, Medium, Waist Up), not in technical parameters.
4. **Soft failure.** When tracking degrades, Alfie holds the last good shot rather than snapping to wide. The operator decides when to reset.
5. **No modal surprises.** No dialogs, no confirmations in the hot path. Everything that can fail silently is surfaced through a status pill, not a blocker.

## Deep learning policy

Perception (detection, pose) is deep learning. Control (composition, crop motion) is not, and will not be for MVP.

An RL-trained composition agent (`CinematicAgent`) exists in the project as scaffolding. It is compiled and reachable, but hidden behind a developer-only flag. It will not ship as the default controller until:

1. Real church footage has been collected from representative deployments,
2. A trained policy demonstrably beats the heuristic on smoothness, framing quality, and robustness on that footage, and
3. The failure mode of the RL agent under distributional shift is understood.

The working assumption is that single-speaker digital PTZ is a low-dimensional control problem with a smooth optimal policy — the kind of problem where a few hand-tuned rules are equivalent to or better than months of training. RL becomes interesting when Alfie takes on jobs the heuristic cannot express: speaker-intent prediction, multi-speaker shot grammar, church-specific style learning. Those are post-MVP.

## Performance targets

Stated as livestream-realistic targets, not cinema:

| Stage              | Target             | Status        |
|--------------------|--------------------|---------------|
| Capture → frame    | < 5 ms             | Not measured  |
| Detection          | < 30 ms            | Measured ~28 ms at 1080p (UI readout) |
| Composition        | < 2 ms             | Not measured  |
| GPU crop/scale     | < 8 ms             | Logged per-frame in CropEngine stats |
| XPC → extension    | < 5 ms             | Not measured  |
| **End-to-end**     | **< 100 ms**       | **Not measured** |
| Sustained run      | 60 min, no drops   | Not validated |

End-to-end measurement instrumentation is a pre-deployment task.

## Success criteria for MVP

Alfie is MVP-ready when, in a realistic church-stage test session:

1. The CMIO virtual camera installs and appears in OBS's device picker on a fresh Mac.
2. A single speaker is detected, framed waist-up, and followed as they walk across the stage without visible jitter or oversteer.
3. The program feed runs for a full 60-minute test without drops, restarts, or manual intervention.
4. The operator can recover from a misidentified speaker with a single tap (manual lock) and return to wide with a single button.
5. End-to-end latency is under 150 ms measured from camera capture to downstream frame receive.
6. Logs from the session are clean enough to diagnose any issue after the fact without having been "there."

## Deferred

These are explicitly **not** part of MVP and should not shape the current design:

- Blackmagic SDI output via Desktop Video SDK
- NDI ingest or output
- Multi-camera coordination or switching
- Multi-speaker autonomous shot grammar (who-to-cut-to logic)
- Cinematic shot presets beyond the basic Wide/Medium/Waist set
- RL agent as default controller
- iOS or iPadOS companion control
- Mac App Store distribution (direct install is fine for church deployment)

## Non-goals

Things Alfie is explicitly not:

- Not a general-purpose broadcast tool. Optimizing for multi-purpose usage would dilute the church mission.
- Not a scripted pan/tilt automation tool. Alfie reacts to perception, not to a timeline.
- Not a post-production tool. No editing, no effects, no color.
- Not a replacement for a skilled live camera operator during high-production services. Alfie is for the normal Sunday where there isn't one.

## Current blockers to first production test

Tracked separately in the project task list, but summarized here for spec completeness:

1. CMIO system extension is not installed via `OSSystemExtensionRequest` on first launch.
2. Per-frame debug logging is active and will cost latency under load.
3. XPC auto-reconnect on extension crash is not implemented.
4. End-to-end latency has not been instrumented.
5. Speaker-selection rules have not been validated against real church footage.
