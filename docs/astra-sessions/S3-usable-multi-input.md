# [S3] Usable multi-input — A/B pill + two Program Displays

**Astra role:** coding agent. Implement only after S2’s dual-capture proof is real.  
**Trello:** https://trello.com/c/Ck2EP2Yg  
**Depends on:** S2 Channel + DECIDE Q1 (feeds) and Q6 (rig).  
**Unblocks:** Sunday two-camera booth use. Speech channel addressing (`Alfie, camera two, …`).

## Prompt (paste this file as the whole prompt)

You are implementing Alfie Session 3: make two channels operator-usable for a church ATEM, with fixed independent program feeds.

This is IMPLEMENTATION. Do not start S4 speech, S5 hardware, a third channel, multiple virtual cameras, or Blackmagic Desktop Video SDI.

If S2 is not in the tree (no `Channel` / `ShowCoordinator` / routing moved out of `CameraManager`), stop and say so. Do not re-extract S2 inside this session.

## Why this session exists

S2 proves two pipelines. Sunday still needs a volunteer to drive B without cutting A, and two physical pictures into the ATEM. Selection is **control**, not a cut.

## Locked church workflow (DECIDE Q1 default = A)

```
Camera A ──▶ Channel A ──▶ Program Display A ──▶ HDMI ──▶ converter ──▶ ATEM input 1
Camera B ──▶ Channel B ──▶ Program Display B ──▶ HDMI ──▶ converter ──▶ ATEM input 2
Operator window stays on the Mac’s built-in (or a third) screen
```

- Clicking B changes **control target and preview**. A keeps tracking. A’s cable stays A.
- Right-pane badge: `B · to ATEM input 2`. Not `On Air`. Alfie has no ATEM tally.
- Return to Wide, Manual, presets, push/pull act on the **visibly selected** channel.
- Never remap a disconnected output onto the other channel’s display.
- A missing physical route stays missing. Virtual camera is not an ATEM failover.

### Alternative (only if Stephan explicitly chose DECIDE Q1 = B)

One HDMI/virtual-camera program. Keep control vs Take separate. Permit Take only after a fresh render of the incoming channel. This is not the default.

## What is true after S2

- Two channels, one router, one CMIO device, one Program Display endpoint (proof).
- `ProgramDisplaySelection` is still conceptually one persisted display unless S2 already parameterized it. Today’s shipping code (pre-S2) uses one UserDefaults key and `DisplayOutputSink` resolves a single `targetDisplayID`.
- Operator window is a 50/50 wide | program split.

## Goal

Volunteer-usable two-camera Alfie:

1. Compact **A / B** (and disabled/hidden **C**) in the pill — mode + health dots, not another toolbar.
2. Dual panes show **only the selected channel**: left = that channel’s wide, right = that channel’s actual rendered program.
3. Two `DisplayOutputSink` instances, each with an **explicit endpoint** (display ID). Kill the one global preference as the only mapping.
4. Per-route health in the inspector: connected, size, refresh, last frame age.
5. One-click recovery (Return to Wide, unlock) on the selected channel.
6. Qualify physical delivery at the ATEM **before** enabling C. C stays hidden or disabled until the budget and topology pass.

## UI rules

- Do not turn the booth into a video wall of all inputs.
- Do not put channel chrome in a menu.
- Verify the pill at 1280-pt width with `A|B`, Push in / Pull out, and long camera names. No scrolling pill.
- Label both panes and the pill with the selected channel letter.
- Voice (S4) must name a channel once more than one is running. You do not implement speech here; keep `Command.target` explicit so S4 can say `camera two`.

## Output architecture

```
OutputRouter
  ├── ProgramDisplaySink(endpoint: displayA)  ← Channel A frames only
  ├── ProgramDisplaySink(endpoint: displayB)  ← Channel B frames only
  └── VirtualCameraSink (optional / fallback for the *selected* or a dedicated channel — do not steal a display)
```

- Extend `DisplayOutputSink` to take endpoint configuration in `init` / `connect`. No singleton “the” program display.
- Persist `channelA.displayID` and `channelB.displayID` separately.
- If display B unplugs: tear down sink B, show fault on B, leave sink A fullscreen on display A.
- Operator window must refuse to go on a display that is claimed as a program endpoint.
- Bring-up checks: each program display should be 1920×1080 at the show rate (50 Hz for the church 1080p50 path). Matching Hz is necessary, not sufficient — this is still T1a’s human confirmation.

## Performance

Same budgets as S2, now with two display presents. Two 1080p50 CALayer presents are cheap compared with two 4K captures. Do not add extra SwiftUI @Published 50 Hz previews; keep the IOSurface layer path.

Do not enable Channel C in this session.

## Files

- `DisplayOutputSink.swift`, `ProgramOutputManager.swift`, `ProgramDisplaySelection`
- `ShowCoordinator` / output router from S2
- `OperatorPill.swift`, `ContentView.swift`, `CropPreviewView.swift`
- Inspector source / output sections
- Settings: two display pickers, labeled A and B
- Tests: endpoint isolation (unplug B does not move A’s window); Take is absent in the default church layout

## Acceptance

- Volunteer can lock and track on A, switch control to B, set B to Auto Pan, and A’s ATEM input keeps showing A’s crop.
- Both Program Displays stay on their assigned screens across control switches.
- Unplug of B’s HDMI display does not move A’s program window.
- Return to Wide on B does not wide A.
- Pill remains readable at 1280 pt.
- No second virtual camera. No C.

## Out of scope

- Alfie A/B/C CMIO devices (later, OBS-centered)
- Direct Desktop Video SDI
- Speech UI (mic toggle is S4)
- Hardware Arm STOP (S7)
- Video wall

## Human gate (not Astra)

Stephan must list, on the DECIDE card or in chat:

- Mac model / chip / RAM
- Capture devices and delivered formats
- Which physical displays are ATEM-bound vs operator

Until that list exists, implement the software mapping and refuse to “enable C.”
