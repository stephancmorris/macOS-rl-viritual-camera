# HW-SIM-SAFETY — no-motion foundation contract

Implemented on `s34/astra-hardware` from Sol **605df3f**; reviewed against Astra **b4b447f**, findings 25–31. Card: https://trello.com/c/AkZj4BJB. This is an isolated simulator repair, **not firmware, physical stop qualification, a chosen target, or permission to move**. The app has no references to these foundations. Director, Speech, app code, project settings and entitlements are unchanged.

## Decisions for Stephan

| Question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| H1 physical route | Existing supported camera/head; external PTZ; custom linkage | Inventory the actual camera, lens, head, interfaces/firmware, required axes, load, travel geometry, duty, noise, cable run and local-loss behavior **before choosing one route**. No SKU selected. | Procurement, transport, mechanics, motion | Before purchase yes |
| H4 evidence for eventual motion | Host timeout; local safety + measured bench | Require verified local deadlines/stop behavior plus appropriate independent protection. Simulator timings are study inputs, not physical limits. | Any motion enablement | Cannot substitute simulation for bench evidence |

All 37 product decisions remain open. The authorized repair implements fail-closed no-motion behavior without choosing H1–H4.

## Implemented contract

`HardwareLink.swift` preserves the `HardwareLink` and `HardwareTransport` interfaces. `SimulatedHardwareDevice` has **no transition to armed**, negotiates `motion=false` and reports `driveEnabled=false`. Direct typed commands and decoded wire commands share the effect gate. There is no actuator output, velocity replay, homing, transport implementation or background app connection.

| Concern | Implemented semantics |
|---|---|
| Bootstrap | After explicit discover/open, decoded `hello` carries positive protocol version and UUID nonce. Device negotiates and connects disarmed, returning typed capabilities with the echoed nonce, fresh UUID `boot` and `session`, current device time and bounds. Communications health is initially false; it is not sensor/mechanical safety health. A replayed hello on an established session is refused. The existing in-process negotiate/connect API remains usable. |
| Identity | Both IDs rotate on every negotiation; reboot rotates boot immediately as well. Here `boot` is a **logical device/negotiation epoch**, not a hardware serial number, literal power-cycle counter, authentication credential or proof of physical identity. Reboot/reconnect cannot reuse an old context. A future adapter should separately retain a native firmware boot counter if one exists. |
| Framing | UTF-8 flat NDJSON, LF terminator, bounded partial buffer, coalesced records, strict exact keys and typed fields. Default record limit **1,024 bytes including LF**, permitted configuration 128–4,096. Each feed accepts at most 65,536 bytes / 64 LF records. Oversized partial lines are discarded through their next LF; excessive chunks are rejected and require a delimiter to resynchronize. Session invalidation flushes partial state. |
| Syntax | Reject malformed JSON, duplicate keys (including escaped aliases), nested/extra/missing fields, unknown command types, inbound ACK/telemetry, invalid UUIDs, zero/invalid sequence, nonfinite/invalid numeric values. No arbitrary string payload. Structural errors return typed rejection without fabricating an ACK correlation. |
| Command context | Every established command has `v`, `boot`, `session`, positive `seq`, typed `type`, and finite `expiresDeviceTime` in **device seconds**. Supported types: ping, heartbeat, disarm, stop, estop, resetEstop, arm, motion, quit. Motion additionally requires finite normalized velocity [-1,1] and positive bounded lease; it is always refused. Normalized units are reserved simulator syntax, not vendor motor units. |
| Sequence | Start at 1; contiguous increasing sequence, no wrap. Same as last = duplicate; earlier/gap = outOfOrder. Invalid sequence does not advance. Once a correctly correlated expected sequence reaches admission, it is consumed even if expiry or effect is refused; resending cannot later gain authority. Reconnect starts at 1 with new IDs. |
| ACK | Typed versioned `ack` includes boot/session, `ack_seq`, accepted and optional typed rejection. Accepted means logical operation accepted, **not physical arrival or mechanical rest**. Parsing/identity failures return typed errors rather than ACKs for untrusted context. ACKs are responses only and cannot refresh heartbeat or authority. |
| Deadlines | `expiresDeviceTime > now` and at most `now + maximumMotionLease`; expired records reject. Heartbeat refreshes health only. There is no active motion lease to extend in this build. Every operation checks current clock/link before effects. Invalid/backwards raw time faults and revokes the session. |
| E-stop priority | A well-formed, current-version/current-session, unexpired estop is processed before all peers in the same bounded receive batch. It latches and revokes the session. A duplicate/out-of-order **current-context** estop still latches but receives a negative ACK; peers cannot clear it. Foreign/expired/malformed estop is rejected as data. Direct local `emergencyStop()` bypasses the stream and always latches. This is not a hardwired physical stop. |
| Reset | Latch survives reboot/reconnect. After e-stop, reconnect/discover/fresh negotiation **and a current accepted ping/heartbeat** are required before reset. Clear then destroys that recovery session and leaves disconnected/disarmed; another negotiation and health check are needed for normal communication. Reset never arms, restores an old session or clears via reboot. |
| Loss | Unplug, app quit, reboot and explicit stop revoke context. Version mismatch or heartbeat deadline faults and revokes. Reconnect restores neither health nor commands. Faulted/stopped/disconnected are all drive-disabled outcomes; health recovery never auto-arms. |
| Telemetry | Version/type/epoch/session, nullable device time, phase, health and latch state. Position, measured velocity, current and limit states are explicitly JSON `null`, not zeros or command echoes. Invalid clock gives null time. No simulated measurement is claimed. |
| Diagnostics | Typed rejection reasons only, no raw payloads; default ring limit 64, configuration 1–256, invalid configurations fail closed. No disk logging. |
| Device scheduler | `SimulatedDeviceClock.advance` immediately invokes registered watchdogs without a host command or `checkLink` call. Exact heartbeat deadline faults. Negative/nonfinite advances reject. Raw clock injection is retained for compatibility/fault tests and requires explicit polling; it is **not** an autonomous watchdog. Calls are serialized; no concurrent transport/executor is implemented. |

Proposed starting timings: heartbeat interval 100 ms; telemetry interval 50 ms; maximum command/motion lease 200 ms; heartbeat loss 300 ms. Timing fields must be finite, positive and ≤60 seconds, heartbeat interval strictly less than loss interval, and lease ≤loss interval. The 60-second cap and framing/history caps are simulator configuration bounds, not certified safety limits. Telemetry/heartbeat intervals are negotiated study metadata, not claims of a running real transport cadence. Real deadlines need a target-local monotonic clock and measured worst-case stop travel.

Example bootstrap: `{"v":1,"type":"hello","nonce":"<UUID>"}` followed by LF. The typed hello response supplies the two IDs and device time. A heartbeat then uses `{"v":1,"boot":"<returned UUID>","session":"<returned UUID>","seq":1,"type":"heartbeat","expiresDeviceTime":0.1}` at device time zero. Do not send a Mac timestamp. This deliberately tightens the historical S5 illustrative protocol; it is not byte-compatible vendor VISCA/ONVIF/SDK traffic.

## Fault matrix / acceptance evidence

| Stimulus | Required and tested outcome |
|---|---|
| Partial / bytewise / coalesced records | No effect before LF; complete typed records reach device effects and correlated responses |
| Huge line/chunk, malformed, escaped duplicate key, unknown type, numeric overflow | Bounded buffering, explicit rejection, no health grant; recover only at framing boundary |
| Duplicate/gap/old sequence, expired record, old boot/session | No renewed authority or heartbeat; expired admitted attempt consumed, old-session replay rejected after reconnect/reboot |
| Wire hello / mismatched version | New capability epoch with motion=false and no health, or faulted/disarmed |
| E-stop alongside heartbeat/reset, replayed current-context stop | Priority latch; no peer reset; explicit sequence rejection when necessary |
| Reset without connection or health | Refused; valid clear still revokes recovery context and leaves disconnected |
| Unplug, quit, stop, reboot | Session retired, drive disabled, no motion replay/home; e-stop retained |
| Host silent / heartbeat duplicated / heartbeat late | Device-clock advance faults at deadline without host polling; late traffic cannot revive it |
| NaN/infinite/negative time, lease or velocity; impossible configuration | Reject/fault closed; no armed state |
| Repeated bad traffic, unsupported sensors | Bounded history, null measurements; ACK never reports mechanical stopping |

The completed run totals are recorded below. Simulator tests establish these software transitions only. No serial/IOKit, firmware deployment, real commands, entitlement change, procurement, PR, merge or Trello status change is part of this task.

## Primary-source checks and remaining bench

Accessed **2026-09-30**:

- [ONVIF PTZ Service Specification 2.2.1, §§5.3.3–5.3.5](https://www.onvif.org/specs/srv/ptz/ONVIF-PTZ-Service-Spec-v221.pdf): continuous motion has timeout semantics and PTZ status/Stop operations. Capability spaces and supported operations vary. This supports investigating a device-local timeout; it does not prove an unidentified camera's loss response or braking distance.
- [Blackmagic PTZ Control developer document](https://documents.blackmagicdesign.com/DeveloperManuals/BlackmagicPTZControl.pdf?_v=1703059210000): describes ATEM remote-port VISCA/RS-422 and the legacy Micro Studio Camera 4K SDI-to-head route. It does not establish that Stephan's equipment has these paths or implements Alfie's proposed lease/latch semantics.
- [Sony Camera Remote SDK](https://support.d-imaging.sony.co.jp/app/sdk/en/index.html): lists macOS and PXW-Z200 support. The listing alone does not establish required axes, exact transport/control coverage or safe local loss behavior. No SKU or adapter selected.

These are distinct vendor protocols; retain route-specific adapters behind `HardwareLink`/`HardwareTransport`, not a presumption that cameras speak this JSON. UUID freshness prevents accidental stale-context reuse; it is not network authentication. Authentication, scheduling, backpressure and failure handling for any real transport remain future adapter work.

Before selecting a route: inventory exact installed camera/head/lens/firmware, supported control/status/stop interfaces, geometry/clearances/pinch points, payload, balance, cable sweep, speed/force needs, service duty and acoustic limits. Confirm documented and observed behavior on host stall, link loss, local reboot and power loss.

Before any intended-rig motion: inspect independent stop/protective limits, validate no-motion electrical drive-disable behavior, then separately authorize low-energy dummy-load trials. Measure command receipt, drive removal, mechanical stop time and travel in each direction/load/speed under stop, local lease expiry while heartbeat continues, unplug, host stall, reboot, sensor/limit faults and physical e-stop. Set acceptance margins from measured clearance. Power removal and packet ACK alone are not proof of rest. Firmware, signed sandbox transport, sensor calibration, physical limits, braking, noise/duty and actual hardware loss behavior remain **UNVERIFIED**.

## Completed verification

Run on 30 September 2026, Xcode 26.2 (17C52), arm64 macOS 26.6.2 (25G83), with **CODE_SIGNING_ALLOWED=NO**. Both final commands exited 0 and reported TEST SUCCEEDED.

| Run | Passed | Failed | Skipped | Result bundle |
|---|---:|---:|---:|---|
| HardwareLinkTests, final | **29** | **0** | **0** | `/tmp/alfie-astra-hardware-targeted-final.xcresult` |
| Full CinematicCoreMacOSTests | **458** | **0** | **1** | `/tmp/alfie-astra-hardware-full.xcresult` |

Totals above are Xcode's device/configuration **test-case runs**, consistent with the previous 432/0/1 baseline. The full summary also aggregates parameterized cases into **390 passed test definitions, 0 failed, 1 skipped** (391 definitions; 14 parameterized definitions produced 82 runs). Do not add the targeted run to the full run. The skip is `RealCameraTests/twoWebcamsRenderPicturesAndBJoinsWithoutCrashing`, which requires explicit real-camera opt-in; no camera permission or hardware study was run. The three former HardwareLink tests were replaced by 29, accounting for the 26-case increase.

Commands (run from the isolated worktree):

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -derivedDataPath /tmp/alfie-dd-astra-hardware \
  -resultBundlePath /tmp/alfie-astra-hardware-targeted-final.xcresult \
  -only-testing:CinematicCoreMacOSTests/HardwareLinkTests CODE_SIGNING_ALLOWED=NO

xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -derivedDataPath /tmp/alfie-dd-astra-hardware \
  -resultBundlePath /tmp/alfie-astra-hardware-full.xcresult \
  -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO
```

Authoritative counts were read with `xcrun xcresulttool get test-results summary --path <bundle> --format json`. Local logs are `/tmp/alfie-astra-hardware-targeted-final.log` and `/tmp/alfie-astra-hardware-full.log`. Intermediate runs exposed an overflow rejection-label expectation and a nested test-macro compile error; both were repaired before these clean final runs. `git diff --check` passed. No physical stopping, camera/output qualification, UI automation, firmware, real transport or speech recognition is established by these results.

The branch remains based on **605df3f**. Sol's remote branch advanced independently during this work; its later Director/Speech changes were not merged, rewritten or tested here. The separate `docs/auto-director/event-authority-contract.md` deliberately scopes its baseline inconsistencies to 605df3f and leaves product approvals open.
