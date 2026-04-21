# Church MVP Task List

This task list narrows the project to the real ministry use case:

- One fixed wide camera covering the full stage
- Detect the active speaker
- Track the speaker smoothly as they walk
- Produce a stable waist-up shot in a second window/output
- Send that processed shot to an external switcher workflow

The goal is to ship a reliable autonomous camera assistant for church before investing further in advanced RL behavior.

## Product Goal

Build a dependable single-speaker digital PTZ system for church-stage use that can:

- ingest a wide stage feed
- follow the active speaker
- maintain a usable waist-up composition
- provide a clean program-style output for downstream switching

## Guiding Principles

- Prioritize reliability over intelligence
- Finish end-to-end output before expanding ML complexity
- Make the operator preview match the real output
- Keep a human override path available at all times
- Treat RL as polish, not as the critical path for MVP

## Current Readiness Summary

Implemented foundation:

- macOS camera capture pipeline
- Vision-based person detection and pose extraction
- Metal-based crop rendering
- Heuristic crop composition with stage-friendly waist-up framing
- Primary-speaker persistence and sticky target selection
- Configurable stage bounds and subject edge-safety margins
- Manual subject lock from the operator preview
- CoreML agent integration scaffolding
- Training-data recording
- Python training and export pipeline
- CMIO extension scaffolding
- Operator fallback controls for `Return to Wide` and `Resume Tracking`

Current blockers to MVP:

- processed output is not yet fully wired to external output
- Blackmagic ingest/output hardware path is not yet implemented or validated on real gear
- full runtime validation is still blocked by local toolchain limitations

## Phase 1: Lock The MVP Scope

### Task 1.1: Freeze the initial use case

- Define MVP as single-stage, single-active-speaker tracking
- Explicitly defer multi-camera, multi-speaker composition, and advanced cinematic behavior
- Document supported operating conditions:
  - fixed camera
  - one primary speaker at a time
  - speaker remains visible most of the time
  - indoor church lighting

Acceptance criteria:

- MVP scope is written down and agreed
- non-MVP features are clearly marked as deferred

### Task 1.2: Define the output target

- MVP downstream target is `ATEM 1 M/E Constellation HD`
- MVP ingest preference is `camera HDMI into laptop`
- MVP delivery preference is `processed output back to ATEM as SDI`
- Use Blackmagic-compatible hardware I/O as the primary path
- Keep NDI as a future extension, not the first implementation target

Acceptance criteria:

- one primary output method is chosen for MVP
- the team stops designing around multiple output paths at once
- signal-path assumptions are documented

## Phase 2: Make The Program Output Real

### Task 2.1: Send processed frames, not raw frames

- Audit the live frame path in `CameraManager`
- Ensure the frame handed to the output path is the crop engine result
- Remove any ambiguity between:
  - raw input frame
  - detection preview crop
  - actual program output frame

Acceptance criteria:

- output path receives the rendered crop result
- program output visually differs from the wide input when cropping is active

### Task 2.2: Complete host-to-extension wiring

- Ensure the host app explicitly connects the XPC manager at startup or capture start
- Ensure capture state is propagated to the extension
- Add reconnect and health logging for the full path

Acceptance criteria:

- host app successfully establishes XPC connection
- extension receives live frames during capture
- connection loss is visible and recoverable

### Task 2.3: Make the preview truthful

- Replace the current right-side display with the actual rendered output frame
- Label the windows clearly:
  - `Wide Input`
  - `Program Output`
- Keep detection/debug views optional, not primary

Acceptance criteria:

- operator sees the same processed composition that downstream systems receive

### Task 2.4: Deliver one switcher-ready output

- Finish the chosen MVP output path
- Validate it with the real downstream workflow
- Measure stability, resolution, and latency under real capture conditions

Acceptance criteria:

- downstream switcher/software can select the processed feed
- output remains stable for a full test session
- latency is acceptable for live church operation

## Phase 3: Improve Tracking For Church Stages

### Task 3.1: Replace generic box-following with stage-aware framing

- Upgrade the shot logic from simple padded bounding-box following to speaker framing
- Use pose signals when available to bias for waist-up framing
- Keep head and torso in safe visual positions
- Add minimum and maximum zoom limits appropriate for stage distance

Acceptance criteria:

- subject remains in a usable waist-up shot while walking naturally
- framing does not feel like a raw detection crop

### Task 3.2: Add subject persistence

- Keep tracking identity across brief detection failures
- Hold previous framing for short gaps
- Add reacquisition behavior that avoids snapping wildly

Acceptance criteria:

- short occlusions or missed detections do not immediately break the shot

### Task 3.3: Add primary-speaker selection rules

- Define logic for multi-person scenes:
  - prefer largest/most central podium speaker
  - ignore background musicians when appropriate
  - allow manual override
- Add deterministic ranking for candidates

Acceptance criteria:

- system consistently chooses the intended speaker in common church-stage layouts

### Task 3.4: Add stage bounds and dead zones

- Prevent camera drift to invalid stage regions
- Add configurable movement dead zone
- Add edge safety margins so the subject is not framed too tightly

Acceptance criteria:

- crop movement feels stable
- output avoids jitter and overreaction

## Phase 4: Add Operator Safety Features

### Task 4.1: Manual subject override

Status:

- Implemented in the operator preview with tap-to-lock and clear-lock controls

- Add operator ability to select or lock the target person
- Maintain lock until cleared or target is fully lost

Acceptance criteria:

- operator can recover quickly when auto-selection is wrong

### Task 4.2: Shot presets

Status:

- Implemented with `Wide Safety`, `Medium`, and `Waist Up` presets plus a secondary `Portrait Profile` frame mode

- Add simple presets:
  - `Wide Safety`
  - `Medium`
  - `Waist Up`
- Apply preset-specific zoom and framing rules

Acceptance criteria:

- operator can change shot style without touching code

### Task 4.3: Recovery controls

- Add:
  - `Recenter`
  - `Hold Shot`
  - `Return to Wide`
- Make these available even if detection is unstable

Acceptance criteria:

- operator always has a safe fallback path

## Phase 5: Stabilize Performance

### Task 5.1: Reduce debug noise in the hot path

- Remove or gate verbose frame-by-frame logging
- keep structured logs only for diagnostics

Acceptance criteria:

- logs are useful without overwhelming runtime performance

### Task 5.2: Profile end-to-end latency

- Measure:
  - capture latency
  - detection time
  - crop render time
  - output delivery time
- track these under realistic stage conditions

Acceptance criteria:

- performance budget is documented
- bottlenecks are known and ranked

### Task 5.3: Optimize frame processing flow

- Reduce blocking work in the frame loop
- confirm GPU path is efficient
- evaluate lower-frequency detection with interpolation if needed

Acceptance criteria:

- system runs smoothly for full live sessions
- dropped frames are rare and understood

## Phase 6: Harden Testing

### Task 6.1: Add unit tests for shot logic

- Cover:
  - crop bounds
  - zoom limits
  - dead zone behavior
  - target selection ranking
  - subject persistence logic

Acceptance criteria:

- critical framing logic is covered by repeatable tests

### Task 6.2: Add integration tests for frame flow

- Validate:
  - capture frame enters pipeline
  - detection updates crop target
  - rendered output frame is produced
  - output path receives processed frame

Acceptance criteria:

- end-to-end frame pipeline is testable without manual inspection alone

### Task 6.3: Create church-scene validation clips

- Build a small test set of representative footage:
  - speaker at podium
  - speaker walking left/right
  - two people on stage
  - speaker briefly occluded
  - low-motion sermon segment

Acceptance criteria:

- every release can be evaluated against the same church-specific scenarios

## Phase 7: Use RL Only Where It Helps

### Task 7.1: Keep heuristic framing as the production fallback

- Do not require the ML model for MVP operation
- Make sure heuristic mode is good enough for live use on its own

Acceptance criteria:

- system is still usable if the ML model is missing or disabled

### Task 7.2: Improve the training loop with real church footage

- Record real sessions from representative church environments
- Use those sessions to tune:
  - framing preferences
  - movement smoothness
  - target persistence

Acceptance criteria:

- training data reflects the real deployment environment

### Task 7.3: Evaluate RL against the heuristic baseline

- Only keep RL behavior if it beats the heuristic in:
  - smoothness
  - framing quality
  - robustness
- compare on church validation clips, not synthetic clips alone

Acceptance criteria:

- RL adoption is justified by measurable improvement

## Recommended Build Order

1. Freeze MVP scope
2. Choose one output method
3. Send processed frames end-to-end
4. Make preview match program output
5. Improve heuristic speaker framing
6. Add subject persistence and target selection
7. Add operator override controls
8. Profile and optimize
9. Add tests and validation clips
10. Revisit RL refinement

## Immediate Next Sprint

- Confirm laptop hardware/ports for Blackmagic I/O
- Implement and validate the physical Blackmagic output path
- Add stage-bound constraints and edge safety margins
- Add church-style validation clips and repeatable tracking checks
- Profile render, detection, and output latency on target hardware

## Definition Of MVP Done

The MVP is done when:

- a fixed wide camera can cover the full stage
- the software automatically tracks a single active speaker
- the program window shows a stable waist-up composition
- the downstream switcher can receive/select the processed feed
- an operator can safely recover using simple controls if tracking fails
- the system can run through a full church-style test session reliably

## Deferred Until After MVP

- multi-camera coordination
- multi-speaker autonomous switching
- advanced cinematic shot grammar
- RL-only control mode as a hard dependency
- general-purpose broadcast feature expansion beyond church-stage use
