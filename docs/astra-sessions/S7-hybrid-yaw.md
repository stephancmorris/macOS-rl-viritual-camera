# [S7] Hybrid physical yaw + digital zoom / fine pan

**Astra role:** coding agent.  
**Trello:** https://trello.com/c/e3unhEFF  
**Depends on:** S6 stop-distance known. S1/S2 digital path stable.  
**Unblocks:** The original “Alfie turns the tripod” Sunday story.

## Prompt (paste this file as the whole prompt)

You are implementing Alfie Session 7: slow physical yaw plus digital zoom and fine pan, as **one** channel controller.

S6 jog must already be safe. If HardwareLink cannot arm and stop, stop this session.

Do not implement robot-arm IK, a second axis, optical camera zoom, autonomous homing, or speech-driven motors.

Read `docs/astra-sessions/HARDWARE-OPTIONS.md` for the linkage picture.

## Hybrid model (locked)

```
wide source image
      │
      ├─ digital: zoom + small pan (CropEngine) — fast, short
      └─ physical: yaw velocity from sensor-space error — slow, large
                 (HardwareLink velocity leases)
```

- **One** controller per channel. Do not run two independent “center the person” loops.
- Physical deadband **larger and slower** than Steady Follow’s digital band.
- Visual error is the subject (or pan target) in the **wide source**, versus a desired sensor anchor (usually center-x, or a slight lectern bias).  
  **Do not** use only the post-crop error — digital recentering can hide that the person is walking off the sensor.
- v1 physical law: low-gain bounded **proportional** yaw-velocity, no integral (avoids windup on the end switch).
- Translate requested yaw rate through the S6 calibration (stroke/yaw). The MCU still runs the faster current/limit loop.
- Image error = framing truth. Encoder/limits = travel safety. Neither replaces the other.

## Mode mapping

| Operator action | Digital | Physical |
| --- | --- | --- |
| Track | Follow + zoom rungs | Yaw if wide-image error stays outside the physical deadband |
| Manual | Operator crop | Physical autonomy **off** (S6 jog still available in inspector) |
| Auto Pan | Digital sweep if `hybridPan == digital` | **or** a separately calibrated yaw range + dwell if `hybridPan == physical`. Never both at once. Never send crop `phase` as `u`. |
| Return to Wide | Snap/clear digital wide | **Stop + disarm** in the same action. Show current full sensor. Do **not** auto-home the tripod. Home is a separate setup action. |
| Stop session | Stop video | Stop + disarm first |
| Lost subject / stale vision | Digital HOLD / last shot as today | **Stop physical immediately** (observation age + lease). Do not keep yawing for the 10 s digital HOLD. |
| Link loss | Digital continues in remaining FOV | Hardware local halt. UI: `Arm stopped · digital only` |
| Physical limit | Keep digital margin if any | Stop outward yaw; show limit status |

DECIDE Q9 default: Return to Wide cannot promise the original whole-stage composition after the head has yawed.

## Sunday pill additions (only when a link is connected)

- Persistent **Arm STOP** — immediate, no confirm, keeps the current digital shot.
- Link health chip (disarmed / armed / estop / digital-only).
- Do not add jog +/− to the pill.

## Controller sketch (normative, tune on the rig)

```
e = desired_x - subject_x_in_wide     // normalized, + = subject right of anchor
if |e| < e_phys_deadband: yaw_cmd = 0
else: yaw_cmd = clamp(Kp * e, -v_max, v_max)
send velocity lease; never queue old v
```

Start `e_phys_deadband` clearly wider than Steady Follow (e.g. 0.12–0.18 of frame width). `v_max` at the S6 “show” PWM, not bench-crawl.

During physical motion, keep updating the digital crop from the current source so small residuals are absorbed digitally and the two do not fight.

## Implementation order inside this session

1. Wire Return to Wide / Stop session / Manual → hardware stop+disarm. Arm STOP on the pill.
2. Tracking: visual P-yaw + existing digital follow/zoom. Rehearse on a still lock first.
3. Only then: physical auto-pan on a calibrated yaw range (optional if the church still wants digital pan). Default: leave Auto Pan digital unless a flag is on.

## Acceptance

Rehearse and record (comment on the Trello card):

- Target walks slowly off center → arm yaws, digital stays tight, no oscillation fight
- Target lost → arm stops within a lease; digital HOLD/last shot still works
- USB yank → arm halts; UI digital-only; no auto-home
- E-stop → arm dead, digital continues
- End switch → no outward drive; digital can still crop
- Return to Wide → arm stop+disarm + full current view
- Manual → no autonomous yaw

## Out of scope

- Multi-axis, IK, replacing the tripod
- Optical zoom protocol
- Auto home search
- Voice → yaw
- Third camera as a “safety wide” (that is DECIDE Q9-B, a different project)

## Files

- Channel controller (new small type) sitting above CropEngine + HardwareLink
- `OperatorCommand` — `emergencyStop`, maybe `setHybridPan`
- `OperatorPill.swift` — Arm STOP + health
- Tests: stale vision stops physical; ReturnToWide emits estop/disarm; digital phase is never sent as `u`
