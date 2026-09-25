# [S5] HardwareLink — USB/simulator, telemetry, e-stop

**Astra role:** coding agent (Mac) + firmware/simulator in-repo.  
**Trello:** https://trello.com/c/zY3O7OLb  
**Depends on:** S2 channel ownership (hardware binds to a channel, not to a global singleton). Read `HARDWARE-OPTIONS.md` first.  
**Unblocks:** S6 motion. Speech is not a prerequisite.

## Prompt (paste this file as the whole prompt)

You are implementing Alfie Session 5: a HardwareLink that can discover a device, ping it, negotiate, receive telemetry, and latch an emergency stop — **with motor motion disabled**.

This is IMPLEMENTATION of the connection contract. Do not drive an actuator. Do not map pixels to PWM. Do not add BLE. Do not unsandbox the Mac app.

If Channel / ShowCoordinator are missing, attach HardwareLink to a `ChannelID.cameraA` stub so S2 can drop in later. Do not put serial I/O inside `CropEngine` or `ProgramOutputManager`.

Read `docs/astra-sessions/HARDWARE-OPTIONS.md` for the intended Pico + USB CDC device. Implement the **protocol and simulator** even if no Pico is on the desk.

## Why this session exists

Until now Alfie only moves pixels. The first hardware win is: Alfie sees a trusted device, the device sees Alfie, and either side can **stop and stay stopped**.

## Transport (v1)

USB CDC serial on a short cable. `HardwareLink` hides the port name.

Recommended firmware target: **Raspberry Pi Pico** USB CDC (see HARDWARE-OPTIONS). A loopback **simulator** in the Mac app or a CLI that speaks the same JSON is required for CI.

## Lifecycle

```
disconnected → discovered → negotiating → connected/disarmed
        → (S6) explicitly armed → stopped / faulted
```

- Discover by stable USB identity (VID/PID + serial string you set in firmware).
- After open, confirm an Alfie protocol identity record. **Never** enable an arbitrary USB-serial gadget.
- Negotiate: protocol major version, capabilities (`motion: false` in S5), device boot ID.
- Reconnect, device reboot, app launch/wake, version mismatch, heartbeat loss → **disarmed**.
- No replay of last velocity. No auto-home.

## Wire protocol (v1)

Bounded newline-delimited JSON. Max record size (propose 1 KiB and enforce). Validated numbers. Explicit error replies.

Every record: `v`, `session`, `seq` or `ack_seq`, `type`.

Motion records (S6) add device-clock expiry tied to the current **boot / lease**. Do not compare Mac timestamps to device clocks. Reject expired, duplicate, and old-session commands. Duplicate acks must not renew motion.

Starting test numbers (tune later):

- 10 Hz heartbeat
- 20–50 Hz telemetry
- ≤200 ms motion lease (S6; S5 still sends heartbeats)
- ≤300 ms link-loss → disconnect/disarm

A heartbeat must **not** perpetuate stale motion intent.

Example shapes (normative enough to implement):

```json
{"v":1,"session":"s7","seq":18,"type":"hello","role":"host","proto":1}
{"v":1,"session":"s7","seq":19,"type":"hello","role":"device","proto":1,"boot":"b3","caps":{"motion":false}}
{"v":1,"session":"s7","seq":20,"type":"ping"}
{"v":1,"session":"s7","type":"ack","ack_seq":20,"accepted":true,"state":"disarmed"}
{"v":1,"session":"s7","seq":21,"type":"enable","motion":false}
{"v":1,"session":"s7","seq":22,"type":"estop"}
{"v":1,"session":"s7","type":"telemetry","boot":"b3","device_ms":41200,"armed":false,"position_valid":false,"position":null,"velocity":0,"limits":[],"fault":null,"current":null}
```

Ack means **accepted**, not “the arm arrived.” Telemetry reports requested vs measured separately. Unsupported measurements are `null`, never an echo of the command.

`estop` latches. Clearing it is an explicit, separate command in S6 (`clear_estop` + arm), never implicit on reconnect.

## Mac architecture

```
ShowCoordinator
  └── Channel
        └── HardwareLink?     // optional capability
              ├── SimulatorTransport
              └── SerialTransport (USB CDC)
```

Typed operations: discover, connect, disconnect, ping, enable(comms), estop, subscribe(telemetry).  
Health is published to the inspector: disconnected / connected-disarmed / estopped / fault.

Firmware owns motor deadlines. A Mac `Timer` is not sufficient if the app crashes — that is why S5’s firmware tests include **app kill** and **cable yank**.

## Permissions

- Add `com.apple.security.device.serial`.
- Prove CDC open/read/write **inside the signed sandbox** on the deployment Mac.
- No Accessibility, no fake keyboard HID, no broad file-system exception, no unsandboxed helper.
- CMIO extension stays video-only.

## This slice’s firmware / simulator tests

- Unplug
- App termination
- Mac sleep/wake
- Malformed JSON, oversized line, duplicate seq, late seq
- MCU reset → new boot id, host must renegotiate, stays disarmed
- `estop` latch survives a host reconnect until explicitly cleared (clear is S6; in S5, reconnect may stay estopped)
- `enable` with `motion: true` is **rejected** in S5 firmware

## Acceptance

- Simulator CI passes the tests above.
- On a real Pico (if present): hello, ping, telemetry, estop. PWM pins stay low. Document how you verified with a meter or LED on enable.
- Sandbox serial proven, or a honest “blocked on entitlement / device approval” note — do not fake success.
- Inspector can show link health. No jog UI yet.

## Out of scope

- `velocity` / `goto` records that move a motor
- Image servo
- BLE, Ethernet
- 3D-printed clamps (physical; not this repo session)
- Pill “Arm STOP” (S7, when hardware is actually connected and able to move)

## Files

- New: `HardwareLink.swift`, transport protocols, JSON coder, simulator
- Optional in-repo: `firmware/alfie-pico/` (C or MicroPython CDC). Small and testable.
- Inspector module row: HardwareLink
- Unit tests on the codec + state machine (no hardware required)
