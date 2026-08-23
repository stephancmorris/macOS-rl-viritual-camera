# Alfie — Autonomous Live Framing Intelligence Engine

An autonomous virtual camera operator for church-stage livestreams. Alfie ingests one fixed wide 4K shot of the stage, finds the active speaker, and publishes a digitally panned and zoomed 1080p50 program crop as a macOS virtual camera (plus a fullscreen Program Display feed for HDMI→converter chains). A volunteer operator can always override it: tap-to-lock a subject, Return to Wide, Resume Tracking.

## System Architecture

**Input**
4K video feed (3840×2160) from a stationary camera via a UVC capture card (e.g. Elgato Cam Link 4K). Capture runs at the persisted show standard — default **1080p50**, switchable to 59.94/60.

**Processing (macOS host app)**
1. **Perception:** Apple's Vision framework (`VNDetectHumanRectanglesRequest`, `VNDetectHumanBodyPoseRequest`, `VNDetectFaceLandmarksRequest`) on a ≤1080p proxy, off the frame path, scoped to an ROI around the locked subject.
2. **Control:** `ShotComposer` — deterministic, rule-based framing (tap-to-lock acquisition with a face-signature gallery, Steady Follow hold-band, HOLD → wide → face-print re-acquire). An RL agent exists as scaffolding behind a developer flag and is not the shipping controller.
3. **Rendering:** Core Image crop-and-scale (Metal-backed `CIContext`) to 1920×1080, rendered off the main thread with critically damped spring interpolation.

**Output**
- **Program Display (default route):** borderless fullscreen window on a chosen display, for an HDMI→SDI converter into an ATEM. Blackmagic Desktop Video SDK integration is *not* implemented; SDI remains deferred.
- **Virtual Camera:** frames cross XPC as IOSurface IDs to a CoreMediaIO system extension ("Alfie" camera) that drains at the show standard and feeds OBS/ATEM Software Control/Zoom/NDI tools.

## Hardware Requirements

- **Host:** Apple Silicon Mac (M1/M2/M3/M4…)
- **Camera:** 4K-capable camera
- **Input Device:** Elgato Cam Link 4K or equivalent UVC capture card

## Development Setup

1. Install Xcode 15 or later.
2. Clone the repository.
3. Open `CinematicCoreMacOS.xcodeproj`.
4. Select the Alfie app target and build. On first run, approve the system extension installation when macOS prompts.

## Status

Shipping for single-speaker church MVP: capture pipeline, Vision perception, ShotComposer control, Core Image render, CMIO virtual camera + Program Display routes, per-session diagnostics CSVs (memory/latency soak), operator recovery paths. Not yet validated: full-length (60 min) Sunday soak without intervention, and end-to-end latency against the 100–150 ms target on the show rig.

## License

Proprietary / Internal Use Only
