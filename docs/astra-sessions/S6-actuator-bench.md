# [S6] Linear actuator jog/goto — physical yaw bench

**Astra role:** coding agent + firmware.  
**Trello:** https://trello.com/c/wFzqHXgD  
**Depends on:** S5 green. Parts from `HARDWARE-OPTIONS.md` on the bench. DECIDE Q8 = bidirectional actuator (default).  
**Unblocks:** S7 visual loop.

## Prompt (paste this file as the whole prompt)

You are implementing Alfie Session 6: low-speed jog and goto on **one** linear actuator, with watchdog, limits, and a measured stop.

S5’s HardwareLink is a prerequisite. If ping/telemetry/estop do not exist, stop.

This session enables **motion electrically**. It does **not** close a visual servo. It does **not** send digital auto-pan phase as stroke. It does **not** home during a fake “service.”

Read `docs/astra-sessions/HARDWARE-OPTIONS.md` before choosing PWM or units.

## Mechanical reminder

- Extend = tripod left; retract = right. **Verify polarity at low PWM** and persist `sign` per device / channel.
- Commands: Extend, Retract, Stop, Go to **normalized actuator stroke** `u ∈ [0,1]`. `u` is not image x.
- 100 mm class actuator, printed clevis + pan-arm clamp. Ball joints if the arm arcs.
- Built-in end-of-stroke switches are the hard limits. Firmware must honor them.
- Cheap actuators often have **no pot**. `goto` is then: timed/open-loop with calibration, or “run toward a limit.” Do not invent a fake encoder. `position_valid: false` is honest.
- If Stephan later fits an Actuonix-P or a pot, `position_valid: true` and `goto` become closed-loop. Same records.

## Firmware additions (S6)

New records (still versioned JSON):

```json
{"v":1,"session":"s7","seq":40,"type":"arm"}
{"v":1,"session":"s7","seq":41,"type":"velocity","v":0.15,"expire_ms":180}
{"v":1,"session":"s7","seq":42,"type":"goto","u":0.40,"expire_ms":180}
{"v":1,"session":"s7","seq":43,"type":"stop"}
{"v":1,"session":"s7","seq":44,"type":"clear_estop"}
```

Rules:

- `arm` only from `connected/disarmed` after a healthy hello. Never auto-arm on connect.
- Every `velocity` / `goto` needs a fresh lease. Heartbeat alone does not move the arm.
- `|v|` and `u` bounded. Reject out of range.
- MCU stops within the local deadline even if USB is still attached and the Mac stalls.
- “Stop” is a **measured** brake/coast behavior, not “cut 12 V and hope it doesn’t slam.”
- End switches: stop outward, allow reverse.
- Optional current threshold → fault + stop.
- `clear_estop` does not arm. Operator must arm again.
- No blind home on boot. Homing, if any, is a setup wizard at low speed toward a limit, once, with a button — never mid-session.

## Mac UI (developer / inspector is enough)

- Arm / Disarm
- Jog + / Jog − (low speed)
- Stop
- E-stop (already latched in S5; now it also drops PWM)
- Optional: `u` slider for goto, disabled when `position_valid == false`

Do **not** put jog on the Sunday operator pill yet. S7 adds `Arm STOP` when hybrid is live.

## Calibration (setup, not Sunday)

Persist per device:

- Polarity sign
- Usable `u` min/max (inside the switches)
- Neutral `u` (tripod “stage center”)
- Optional: a few (stroke, observed yaw) points if a phone angle app or marked card is used
- Max PWM for bench vs show

Do not encode `L² = d² + r² − 2dr cos(θ−θ₀)` as if `d` and `r` were measured. That formula is a design sketch only.

## Acceptance

- Bench: low-speed extend/retract, stop, e-stop, unplug-while-moving → halt, no free-run.
- Stop distance measured and written in the card comment or `firmware/README` (seconds and mm, even if rough).
- Limits halt outward motion; reverse still works.
- Reconnect stays disarmed.
- `goto` either works with a pot **or** is clearly marked unsupported when `position_valid` is false.
- No image-based motion.

## Out of scope

- S7 visual P controller
- Physical auto-pan
- Multi-axis
- Speech → jog
- Printing CAD (Stephan’s workshop). Firmware may include a `docs` photo of pinout.

## Safety rehearsal (human)

Target loss is S7. For S6: hand over the e-stop, yank USB, jam the rod with a block (not fingers), confirm halt.
