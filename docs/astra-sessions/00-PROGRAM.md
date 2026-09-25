# [PROGRAM] Next: zoom → channels → speech → hardware

**Astra role:** design reader only. Do not implement from this file. Do not open a PR. Use it to refuse work that belongs in a later session.

**Trello:** https://trello.com/c/hvK9YzKN  
**Source memo:** `reports/ALFIE_DESIGN_PROGRAM_2026-09-19.md`  
**Session briefs:** `docs/astra-sessions/`

## One-sentence program

Alfie stays a volunteer church-booth operator. After digital zoom works as a shot move, prove two isolated cameras, let the operator speak eight commands, then move a cheap linear actuator that yaws an existing tripod.

## Sequence and gates

| Session | Deliverable | Start only when | Stop before |
| --- | --- | --- | --- |
| S1 | Command dispatcher + zoom | — | Channels, speech, hardware |
| S2 | Channel extraction, two sessions, one routed output | S1 zoom feels right one-handed | Sunday A/B UI, second HDMI, second CMIO device |
| S3 | A/B pill + two Program Displays | S2 dual-capture proof + DECIDE Q1/Q6 | Third channel, virtual-camera A/B/C, Blackmagic SDI |
| S4 | Offline speech → same dispatcher | Command layer stable | LLM crop policy, spoken Stop, physical motion by voice |
| S5 | HardwareLink USB/simulator, e-stop | S2 ownership + HARDWARE-OPTIONS read | Motor motion, image servo |
| S6 | One-axis jog/goto on the real actuator | S5 green + parts on bench | Closed-loop visual yaw |
| S7 | Hybrid physical yaw + digital zoom/fine pan | S6 stop-distance measured | IK, multi-axis head, tripod replacement |
| DOCS | Spec/README match shipping behavior | After each landed session | Rewriting historical Phase 1 docs |

S4 may be *designed* after S1 while S2/S3 proceed. It must not delay S2 or S3. Hardware stays last in the product sequence.

## What is already true in the tree

- One `CameraManager`, one `AVCaptureSession`, one `PersonDetector`, one `ShotComposer`, one `CropEngine`, one `ProgramOutputManager`.
- `OperatorCommand` / `CommandDispatcher` exist (`OperatorCommand.swift`). Target is `cameraA` or `session`. This is an address, not a Channel implementation.
- `CropEngine.renderCrop` runs on a **process-wide static serial queue** (`com.cinematiccore.cropRender`). Two engines would share it and serialize every lane.
- `CameraManager` constructs `ProgramOutputManager` with `VirtualCameraOutputSink` + `DisplayOutputSink`. Instantiating two managers would fight over the CMIO extension and the one persisted Program Display.
- Program Display is the default route. One global `ProgramDisplaySelection` in UserDefaults.
- Deployment target in the Xcode project is **26.2**. Product copy still says macOS 14+.
- Checked-in entitlements: sandbox, camera, app group, IOSurface, system-extension install. Audio-input is enabled in build settings, not in the entitlements plist. No serial entitlement yet.

## Couplings that must not happen

1. Zoom as a fifth `OperationMode` (blocks zoom-while-track / zoom-while-pan).
2. Composer and UI both owning final crop size (breathing).
3. Global zoom / mode state (breaks channel independence).
4. Using *requested* width, not rendered width, for auto-pan travel.
5. Treating digital crop phase or crop center as actuator stroke.
6. Binding which output is live to which channel the operator is looking at (silent cut).
7. Speech or firmware writing `CropEngine` directly.

## Shared architecture to grow, not to invent twice

```
Pill / validated speech / hardware events
                 ↓
   Command(target, origin, id, epoch, expiry)
                 ↓
         CommandDispatcher
        ↙                 ↘
 channel control         show / session
    ↓         ↓               ↓
 crop intent  hardware     output router
    ↓         ↓               ↑
CropEngine  HardwareLink   channel program frames
```

Reserve on the command enum when a session needs them, do not implement early: `Take`, `Arm`, `Disarm`, `EmergencyStop`.

A **Channel** (S2) owns: source, session, detector, composer, crop engine, mode, zoom, pan phase, last-good program, health.  
A **show coordinator** owns: show standard, device discovery, exclusive camera allocation, command dispatcher, output router, one CMIO connection until a later virtual-device project.

## Current P1 church-MVP cards still stand

Show-rig soak, HOLD/Resume pill, volunteer Applications install, eased auto-pan (T5a), `enterAutoPan` (T5b). Those close Sunday reliability. This program is the next feature line. Do not delete or re-scope them from an S2–S7 session.

## DECIDE defaults (until Stephan comments otherwise)

From Trello [DECIDE](https://trello.com/c/9civ34Dy):

1. Independent HDMI/SDI feeds into separate ATEM inputs.
2. Keep a macOS 14+ *product* story; the project is currently 26.2 — do not silently require 26.2 APIs in S2/S3.
3. Zoom owns size until a preset is re-selected (S1; later refined to one-rung shot moves).
4. Keep the ~4× digital floor with honest limit status.
5. Wake-prefix speech on a close-talk mic.
6. Qualify **two** inputs first. Three is conditional.
7. Hardware location still open — bench is short USB; stage run is a later transport behind the same protocol.
8. Prefer a rigid bidirectional actuator, not a pull-only cable.
9. After physical yaw, Return to Wide = stop the arm + show the current full camera view. Not a guaranteed original whole-stage shot.

## Wait list (do not build in any current session)

Third-channel promises, multiple virtual cameras, direct Blackmagic SDI, speech-driven motors, multi-axis robotics, cloud speech, unsandboxed motor helpers.
