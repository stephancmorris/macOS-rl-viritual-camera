# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| H1 First target? | Feedback actuator yaw; VISCA PTZ; Sony SDK lens control; Blackmagic/ONVIF route | One feedback actuator yaw bench using L12-100-210-12-P + local safety MCU; preserves existing camera and makes local deadlines testable | HW-CHOICE/S5–S7 | Software yes; procurement/mechanics cost sunk |
| H2 First motion scope? | Manual bounded jog; absolute goto; visual servo | Manual low-speed jog only after stop tests; goto only with validated measured position; servo deferred | S6/S7 | Yes |
| H3 Installation boundary? | Short USB bench; stage-side wired bridge; wireless | Short USB bench first; measure stage run before choosing bridge | S5 transport | Yes |
| H4 Safety acceptance? | Host stop; local watchdog only; local watchdog + independent physical stop/limits | Local watchdog plus independent stop and hard limits; no motion until demonstrated | S5/S6 | Cannot relax locked safety rule |

Status: discovery recommendation, no purchase, wiring, motor command or hardware qualification. Access date for every linked source: **2026-09-30**. The named actuator is a bounded **bench candidate**, not a claim that it can safely drive Stephan's tripod. Load/geometry suitability is UNVERIFIED and is a procurement gate.

## Current boundary

`ShowCoordinator.swift`/`ShowCoordinator` owns channel control and routing; `OperatorCommand.swift`/`CommandDispatcher` has no physical action origin or hardware safety authority. `ProgramRouter.swift` preserves one output. Historical `docs/astra-sessions/HARDWARE-OPTIONS.md` and S5–S7 are proposals, not installed hardware. Physical control must attach to a channel above existing digital composition, never turn crop center/phase into actuator stroke.

## Route comparison

| Route | Pan/tilt/optical zoom and feedback | Transport / Mac sandbox | Local safety / latency | Cost, availability / simulator |
|---|---|---|---|---|
| Historical generic actuator | Yaw via linkage only; no tilt/optical zoom. Sensorless stroke is not measured position | USB CDC to MCU; serial entitlement [Apple sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html); signed-device test needed | Proposed MCU lease and hardwired stop, not existing. Ack/stop distance unmeasured | Old $70–110 BOM is **UNVERIFIED**, not current quote; generic load/switch specs unresolved. Excellent protocol simulator, poor substitute for mechanics |
| **Feedback actuator candidate** | Same yaw-only mechanism, measured potentiometer stroke; yaw still needs calibration. L12 P is feedback variant, S is switch variant; do not assume P has S limits [datasheet](https://www.actuonix.com/assets/images/datasheets/ActuonixL12Datasheet.pdf) | Same CDC; external limit interlocks, motor driver and safety controller proposed | Local controller can enforce leases independently of Mac; physical NC stop removes drive enable. All timing/braking evidence must be measured | [L12-100-210-12-P](https://www.actuonix.com/l12-100-210-12-p) catalogued. Vendor listing for another L12-P 100 mm variant shows $80 and stock; exact selected SKU/Australian landed price and stock **UNVERIFIED** ([catalog](https://www.actuonix.com/L12_c_138-2.html)). Simulator supports honest absent telemetry |
| VISCA / VISCA-over-IP PTZ | Integrated PTZ cameras provide pan/tilt/lens zoom; standalone heads need compatible lens control. Model-specific position inquiries/presets; do not infer encoder precision from ACK | Serial RS-232/422 via adapter or IP; SRG-X120 is documented with optical zoom and VISCA-over-IP ([Sony product](https://pro.sony/en_EE/products/ptz-network-cameras/srg-x120), [manual index](https://www.sony.com/electronics/support/ptz-and-remote-cameras-ptz-cameras/srg-x120/manuals)). Network client, and UDP receive may need server entitlement | Camera executes motor command. Stop packet is not a local expiry guarantee; loss timeout/e-stop and feedback specifics **UNVERIFIED** for selected firmware. Ack/completion not exposure latency | Camera/head/controller and local safety cost **UNVERIFIED**, obtain AU dealer quote and loan rig. Byte-level simulator feasible; vendor timing not simulated proof |
| Sony Camera Remote SDK, PXW-Z200 | Z200 is a supported device and macOS is supported. Z200 has no motorized pan/tilt body; exact zoom command/readback matrix must be checked. SDK pan/tilt additions name BRC-AM7/FR7, not Z200 | SDK family lists USB/wired/wireless LAN, **per-device** interface matrix required. USB/network entitlements depend on actual transport; SDK signing/sandbox integration untested | Lens-local motion, but stop-on-disconnect/deadline semantics **UNVERIFIED**. No assumption that API return means settled | SDK free per vendor; camera purchase/availability/firmware and distribution terms need confirmation. Mock API feasible; no verified vendor simulator. [Sony SDK](https://support.d-imaging.sony.co.jp/app/sdk/en/index.html) |
| Blackmagic camera control | Lens controls depend on active lens; pan/tilt requires external motorized head. Vendor describes legacy Micro Studio Camera 4K converting SDI PTZ to VISCA; not every modern camera has that connector | SDI return/ATEM remote RS-422 or supported camera-control interface. Mac ATEM/network or capture hardware integration separately assessed; not Alfie's existing video-only output API | Safety at external head/controller; SDI command path alone is no watchdog. End-to-end control and readback latency **UNVERIFIED** | Existing ATEM does not establish compatible ports/head/lens; cost/stock **UNVERIFIED**. Simulate commands, not presumed acknowledgements. [Blackmagic PTZ developer PDF](https://documents.blackmagicdesign.com/DeveloperManuals/BlackmagicPTZControl.pdf?_v=1703059210000) |
| ONVIF PTZ (additional route) | Capabilities queried per node: absolute/relative/continuous motion and position/status support vary; optical zoom only if device provides it | SOAP over wired IP; client entitlement; discovery may require additional receive permissions | Standard ContinuousMove timeout specifies local motion duration and GetConfigurationOptions advertises timeout range; strongest documented protocol lease candidate, still requires real-device proof | No named qualified camera chosen, price/availability **UNVERIFIED**. WSDL-driven simulator feasible. [ONVIF PTZ WSDL](https://www.onvif.org/ver20/ptz/wsdl/), [PTZ spec](https://www.onvif.org/specs/srv/ptz/ONVIF-PTZ-Service-Spec-v221.pdf) |

Sony verification is narrower than “full Z200 control works on this Mac”: support listing is verified; exact Z200 transport, zoom absolute-position support, readback units, firmware, packaged SDK/sandbox behavior and safe loss remain unverified. The SDK announcement's absolute-zoom footnote names other models; do not attach it to Z200 merely because it appears in the same release. No SDK application/account action was submitted.

Apple documents that UDP applications usually need both network client and server entitlements ([network client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)); test selected socket behavior in a signed sandbox. USB raw-device access and serial access are different paths. Local-network privacy/Bonjour requirements, vendor libraries and signed entitlements require exact-build testing; no broad exception/helper is proposed.

## Why this one bounded recommendation

Choose the feedback actuator bench if preserving the existing camera/tripod and yaw is the goal: local watchdog, drive enable and actual stroke can be specified and fault-injected. Replace the historical sensorless timed-goto assumption. This incurs mechanical engineering and is not inherently safer than a commercial head. If load/mounting cannot pass, return H1 to Stephan; do not silently buy a bigger actuator or implement a second route. Sony SDK is attractive for lens control if that is the real need, but cannot solve Z200 yaw. ONVIF merits a later device study for its documented timeout; VISCA familiarity alone cannot satisfy local-loss safety.

## S5 wire contract survives, with corrections

Keep bounded newline-delimited JSON **between Alfie and its own safety MCU/simulator**. Vendor VISCA, SDK and ONVIF routes would use adapters, not pretend to speak this wire format.

| Contract item | Proposed requirement |
|---|---|
| Envelope | `v` protocol version, `session`, monotonic `seq`, `type`; boot ID required in negotiation and every state-changing lease context |
| Duplicate key defect | Historical S6 velocity example uses `v` twice (version and velocity). Rename motion field `velocity`; reject duplicate JSON keys, nonfinite/range-invalid values |
| Expiry | Explicit `expiresDeviceMs`, bounded to negotiated device-clock lease window; bind to boot/session. `expire_ms:180` must not ambiguously mean duration or absolute time |
| Deadlines | Proposed starting heartbeat 10 Hz, telemetry 20 Hz, motion lease ≤200 ms, link-loss latch ≤300 ms, record cap 1 KiB; rationale: bounded bench feedback. Measure actual jitter/braking; no runtime loop has been validated |
| Heartbeat | Health only, never extends a motion lease; duplicates/late ACKs never renew authority |
| E-stop | Wire estop latches logical state, separate physical stop interrupts drive. Clearing latch does not arm; reboot/reconnect stays disarmed |
| Telemetry | Separate requested velocity from measured position/velocity; unsupported or invalid values null, never command echoes. ACK = accepted, not arrived/stopped |
| S5 scope | Negotiate motion=false, reject all motion commands, test electrical drive enable inactive; simulator success cannot prove this |

## Calibration and stop plan before motion authority

First inspect real tripod friction/payload, radius, linkage monotonic range, side loads, cable sweep, stability, pinch points, driver ratings and power isolation. Confirm datasheet load/duty limits for selected gearing; fit external hard limits and independent drive-disable circuit. No glass/payload or person in motion envelope during initial dummy-load test. No blind homing; invalid sensor means no goto. Calibration records device/boot/firmware, polarity, measured stroke→yaw samples, neutral, safe limits, speed/current limits and date.

| Stage | Evidence required before next stage |
|---|---|
| No-motion electrical | Power-on/reset/app kill/sleep/unplug/malformed/oversize/replay tests keep drive disabled; physical stop works without Mac or firmware cooperation |
| Human-controlled crawl | Qualified hardware reviewer approves current/force/speed bounds from actual assembly; first movement short, low-speed manual jog with reachable physical stop |
| Stop matrix | Each direction at each approved speed/load: command Stop, lease expiry while heartbeat continues, cable yank, host stall, MCU reset, stuck sensor, limit activation and physical e-stop. Log request/drive-disable/mechanical-stop times and stroke/angular travel; no hand-jam test |
| Calibration | Proposed 5 stroke→yaw sample positions in each direction and 10 stop repeats per condition, to expose hysteresis and worst-case distance; expand if variability is high |
| Accept | Worst measured stop travel plus documented margin stays within physical clearance; every loss ends disarmed, no last-velocity replay, no auto-home. Numerical stop-distance limit must be frozen from measured rig clearance before enabling higher speed |
| Later S7 | Separate qualification of wide-image visual error, one physical/digital controller, immediate stop on stale vision; never inherit digital 10 s HOLD as physical motion permission |

All timing/count values are proposed starting study parameters. No local physical safety deadline may be implemented solely by a Mac timer. Return to Wide must stop/disarm hardware and show current full sensor view; it cannot promise original stage coverage after yaw. Stage 4 remains deferred until Stage 3 qualification.
