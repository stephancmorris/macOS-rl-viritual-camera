# [S2] Extract Channel — two isolated sessions, one routed output

**Astra role:** coding agent. Implement this session only.  
**Trello:** https://trello.com/c/4sFQx8lb  
**Depends on:** S1 zoom + command dispatcher feeling right on one camera.  
**Unblocks:** S3 (Sunday A/B UI), S5 (hardware binds to a channel).

## Prompt (paste this file as the whole prompt)

You are implementing Alfie Session 2: extract a Channel boundary and prove two real cameras can run independent modes with one routed output.

This is IMPLEMENTATION. Do not start S3 (A/B pill, two HDMI outputs), S4, or hardware. Do not add a second CMIO virtual camera. Do not implement Blackmagic SDI.

## Why this session exists

`CameraManager` is the whole show: capture, detection, composition, crop, and it **owns** `ProgramOutputManager`. A second instance would create a second virtual-camera sink and fight over the extension and the persisted Program Display. `CropEngine.renderCrop` uses a **static** serial queue, so naïve duplication serializes every lane through one GPU path.

S2 is the architecture proof, not the Sunday UI.

## What is true in the code today

- `CameraManager` (`@MainActor`) holds one `AVCaptureSession`, one `PersonDetector`, one `ShotComposer`, one `CropEngine?`, one `ProgramOutputManager`.
- `OperatorCommand.Target` is `cameraA` or `session`. That name is the future channel address. There is no Channel type yet.
- Detection is operator-initiated, ≤1080p proxy, one job in flight, ROI around the lock.
- Output: Program Display (default) or virtual camera fallback. One active route.
- `ProgramDisplaySelection` is a single UserDefaults display ID.
- XPC (`CinematicCoreXPCProtocol`) is one host → one extension, one frame stream.

## Goal

Two channels, A and B:

- A can track a subject while B auto-pans (and can zoom).
- Each has its own session, detector, composer, crop engine, mode, zoom, pan phase, last-good program buffer.
- One output sink is fed by **one chosen** channel program.
- Unplug / failed start / detector restart on B does not reset A.
- Operator UI may be crude. Do not build the S3 A/B pill or two Program Displays.

## Architecture (locked)

**A Channel owns one `AVCaptureSession`.** N channels = N sessions. Apple documents Mac multi-camera; a shared session couples start/stop and failure. Independent sessions give independent format checks and recovery. They do **not** create USB bandwidth or guarantee any UVC pair — the proof must use two real devices.

| Per channel | Shared (show / app) |
| --- | --- |
| Stable ID (`A` / `B`), display name, source device identity | Device discovery, camera permission, exclusive device allocation |
| Session, configuration queue, capture delegate, frame gate, generation | Show standard (`ShowStandard.beginSession`) |
| `PersonDetector`, observation store, face gallery, `ShotComposer` | Fair perception / render scheduling |
| `CropEngine` motion, `OperationMode`, preset, zoom, pan phase, manual point | `CommandDispatcher` |
| Latest input, last-good rendered output, timestamps, health | Output router, **one** CMIO connection, one Program Display for this slice |
| Channel diagnostics | Session diagnostics aggregation, extension activation |

A channel produces a **channel program frame**. It does not own the virtual camera or the display preference.

### Required extractions

1. **Move `ProgramOutputManager` out of `CameraManager`.** A show-level object owns sinks. Channels only publish program frames + metadata (channel id, sequence, capture time, render time, freshness).
2. **Replace `CropEngine`’s static `renderQueue` with a bounded fair scheduler.** Two channels must not silently share one queue with unlimited enqueue. One render in flight per channel. If both are ready, alternate. Do not invent an unbounded GPU thread pool.
3. **Give capture start/stop and device configuration their own serial executors.** Do not multiply blocking `lockForConfiguration` / `startRunning` work on MainActor.
4. **Keep short deterministic state transitions on MainActor** (mode, lock, command admission) for this slice.
5. **Latest-frame mailboxes + per-channel generations.** A stale B render must not complete onto A’s generation.
6. **Commands carry an explicit channel target.** Today `cameraA` is fine as the default; add `cameraB` (or `channel(id)`). Capture the target when the command is created, not when it is applied later.

```
ShowCoordinator
  ├── CommandDispatcher
  ├── OutputRouter  →  VirtualCamera | one Program Display
  ├── DeviceDirectory (exclusive claim)
  ├── Channel A  (session, detect, compose, crop, last-good)
  └── Channel B
```

Suggested type names (use these unless a clearer name already exists in-tree): `Channel`, `ChannelID`, `ShowCoordinator`, `OutputRouter`. Do not create a general “broadcast graph” framework.

## Proof UI (intentionally limited)

Keep the existing dual pane.

- Right pane = the **routed** program (whatever is actually going downstream). Label it with the routed channel.
- Left pane = the **control** channel’s wide view. If the operator is driving B, label it `Control B`.
- Add the smallest possible Take control (even a temporary inspector button is acceptable) that routes B only after a fresh B program frame exists. Retain A until the switch is atomic.
- Do **not** label a B preview as the live downstream feed.
- Do **not** cut A when the operator clicks B’s preview for control. Control target ≠ output route.

This mismatch is why S3 exists. S2 only has to make the lie impossible.

## Failure isolation

- B fail-to-start: A keeps running; B shows a health error; output stays on A if A was routed.
- B hot-unplug: B goes `faulted` / missing source; A unchanged; if B was routed, **do not** silently remap onto A’s display or steal A’s program. Hold B’s last-good or go to a black/standby **for that route only** and tell the operator. Virtual camera is not an ATEM failover.
- B detector crash/restart: A’s identity gallery and lock stay intact.

## Performance budget (engineering, unmeasured)

- Keep the show cadence (50 / 59.94 / 60). Do not silently drop an output to 30.
- Perception: 10–12 Hz per **tracking** channel, ROI / ≤1080p, one job per channel. Manual/pan channels should not run full tracking perception.
- Compose + state: aim < 1 ms/channel/frame. Inspect MainActor occupancy.
- Render: aim ≤4–5 ms/channel at 1080p. Both channel renders + overhead must fit the frame period if they share a scheduler.
- Bound queue age. Never trade smoothness for a growing backlog.
- Soak target (human, after code): 60 min, two moving subjects, no progressive memory growth, A survives B unplug.

Shed in this order if over budget: extra UI/diagnostics → pose/face refresh (keep acquisition identity) → detection toward 8 Hz → proxy toward 720 only if the subject still fills → declare the lower-priority channel “Tracking reduced”. If ingest itself misses, mark the config unsupported. Do not weaken identity matching to keep a green status.

Memory illustration (not USB bandwidth): one 3840×2160 BGRA frame ≈ 33 MB; 50 fps ≈ 1.66 GB/s of pixel payload per channel. Enforce bounded retention of capture / proxy / render / preview buffers.

## Files you will likely touch

- New: `Channel.swift`, `ChannelID.swift`, `ShowCoordinator.swift` (names flexible)
- `CameraManager.swift` — shrink toward “channel internals” or become the Channel
- `CropEngine.swift` — render scheduler
- `ProgramOutputManager.swift`, `DisplayOutputSink.swift`, `XPCConnectionManager.swift`
- `OperatorCommand.swift` — channel target
- `OperatorPill.swift` / `ContentView.swift` — only crude Take + labels
- Tests: new channel isolation tests; do not delete S1 framing tests

`CinematicCoreXPCProtocol.swift` and the extension stay **single-output**.

## Acceptance

- Two real capture devices can start in one app session.
- A tracks while B pans (and zoom on B still works).
- Independent lock, mode, crop, command cancellation.
- B start failure and B unplug leave A running.
- One routed output; Take is explicit; no automatic switch.
- Still one virtual camera device.
- Render scheduler does not deadlock and does not let one channel starve the other for >2 frames while both are producing.
- Tests cover: exclusive device claim, generation isolation, recovery on A cannot be stolen by B’s lock events.

## Out of scope

- A/B segmented pill, two HDMI Program Displays (S3)
- Channel C
- “Alfie A / Alfie B” virtual devices
- Direct SDI
- Speech, HardwareLink
- Rewriting T5a eased auto-pan

## Open questions (do not block S2)

- Exact Sunday display topology → S3 / DECIDE Q6.
- Whether Take stays in S3’s church UI (default is **no Take**; fixed feeds). S2 Take is proof-only.
