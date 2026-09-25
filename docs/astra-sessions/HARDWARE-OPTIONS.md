# Hardware options — cheap tripod yaw for Alfie

**Astra role:** design reader. Do **not** write firmware, order parts, or change the Mac app from this file. S5–S7 implement after Stephan picks a row in the BOM.

**Use case:** Alfie already pans digitally. This hardware yaws the *existing* tripod a little so the speaker stays in the sensor, while digital zoom / fine pan finish the shot.

```
        [fixed clevis]────[linear actuator]────[clamp on pan arm]
              │                                      │
           floor / wall / table              yaw axis of tripod
```

- Extend → tripod turns **left** (confirm polarity on the bench; persist per device).
- Retract → tripod turns **right**.
- Camera still provides the picture. Image error is the framing truth. The actuator is a 1-DoF muscle.

## What we will not buy

| Avoid | Why |
| --- | --- |
| Commercial PTZ head ($500–2000+) | Replaces the tripod Alfie is supposed to *help*. Wrong product. |
| Multi-axis robot arm / IK | S7 explicitly out of scope. |
| ODrive / hobby servo stack as v1 | Excellent later; more setup than a Sunday MVP needs. |
| BLE / Wi-Fi motion | Church RF, pairing, reconnect mid-service. |
| GPIO “from the Mac” | The Mac has no motor drivers. Control stays on an MCU. |
| Pull-only rope without a return | Retracting slack cannot push the arm. Needs a spring/return or a bidirectional actuator. |

Stephan’s original pole that only pulls is **Option B** in DECIDE Q8. Preferred baseline is **Option A**: a rigid bidirectional actuator.

## Recommended path (v1): buy a cheap actuator, print the interfaces

Do **not** 3D-print the actuator. Printed lead-nuts wear, bind, and have no trustworthy position. Print the **clamps, clevises, and box**. Buy the muscle.

### Bill of materials (indicative USD, 2026 street prices)

| Part | Role | Approx. |
| --- | --- | --- |
| Generic **12 V, 100 mm** mini linear actuator with **built-in end-of-stroke switches** | Push/pull the pan arm | $25–35 |
| **Raspberry Pi Pico** (RP2040) | USB CDC device Alfie talks to; owns the motor watchdog | $5 |
| **DRV8871** or **TB6612FNG** breakout (prefer over L298N) | H-bridge, PWM speed, less heat than L298 | $6–10 |
| 12 V / 2 A wall supply, isolated from the Mac | Motor power. Never power the actuator from USB. | $10–15 |
| Mushroom **e-stop**, NC, in series with motor enable | Local halt even if the Mac or firmware wedges | $8–12 |
| Optional: cheap **current-sense** module or driver with I-sense | Jam detection | $5 |
| PETG/ABS printed parts + M3 hardware, rod ends | Mechanical interface | $10–20 filament/fasteners |
| **Total v1** | Bench-capable yaw | **~$70–110** |

Step up later, not for S5:

| Upgrade | When | Approx. |
| --- | --- | --- |
| Actuonix L12/T16 **with potentiometer** | Need `goto` without guessing stroke | $70–90 |
| USB–RS-485 or a second Pico at the tripod | Booth-to-stage cable > ~3 m | $20–40 |
| NEMA17 + T8 300 mm lead screw + printed carriage | Need ~30°+ yaw or more force | $40–60 extra |

### Why this stack

- **Pico** enumerates as USB serial (CDC) with no FTDI dongle. macOS sandbox can talk to it once `com.apple.security.device.serial` is granted and proven.
- **End-of-stroke switches** on the cheap actuator give S5/S6 a fail-safe without a $70 pot. `goto` in S6 can be timed/calibrated; pot comes when we care about repeatability.
- **Separate 12 V** means a USB disconnect cannot leave a powered H-bridge in an undefined state if firmware drops enable on link-loss (required).
- **Print the fixtures** so the same actuator fits *this* tripod without custom metal.

### 3D-printed parts (v1)

Print in PETG or ABS, not PLA (booth heat, creep).

1. **Floor / table clevis** — locked to a sandbag, pew rail, or lighting stand, not “hope the table doesn’t walk.”
2. **Tripod-arm clamp** — two-shell clamp around the pan arm, rubber pad, no metal-on-carbon scratches. Attachment hole at a known radius `r` from the yaw axis.
3. **Actuator end adapters** — match the cheap actuator’s hole pattern (usually 3–6 mm). Use **ball joints / rose joints** if you can ($3–8 pair) so the linkage does not bind as the arm arcs.
4. **Pico + driver enclosure** — strain relief for USB and 12 V, e-stop on the lid, no exposed 12 V on the operator desk.
5. **Optional cable spine** — printed clips along a stand so the USB/12 V run cannot snag a volunteer.

CAD can be OpenSCAD or Fusion. Dimensions wait on the **actual** actuator and tripod. S6 does not start until those measurements exist.

### Printed lead-screw alternative (only if the cheap actuator is too short)

A T8 rod + NEMA17 + printed nut/carriage can make 200–300 mm stroke for more yaw. Costs about the same as a better commercial actuator, with more mechanical risk (binding, backlash, no IP rating). Treat as a **second** mechanism after the $30 actuator has proven the protocol and the clamp design.

## Geometry (enough to buy a stroke)

For a roughly parallel linkage, small-angle yaw:

```
Δθ (radians) ≈ ΔL / r
```

`r` = distance from tripod yaw axis to the moving clamp.

| Stroke | r = 200 mm | r = 300 mm | r = 400 mm |
| --- | --- | --- | --- |
| 50 mm | ~14° | ~10° | ~7° |
| 100 mm | ~29° | ~19° | ~14° |
| 200 mm | ~57° | ~38° | ~29° |

v1 target: **about 15–30° of physical yaw**. Digital crop already covers the rest of a church stage. A 100 mm actuator at r ≈ 250–300 mm is the default buy.

Do not mount through a dead-center (actuator in line with the axis) — mechanical advantage collapses and direction becomes ambiguous.

Uniform actuator speed ≠ uniform yaw. S6 calibrates stroke → yaw on the real rig. Do not code the cosine law as if it were measured.

## Transports

| Transport | When |
| --- | --- |
| **USB CDC, short cable** | S5/S6 bench. Default. |
| USB–RS-485 or Pico-at-tripod + long twisted pair | Booth-to-stage after measuring the run (DECIDE Q7). Same JSON protocol. |
| Wired Ethernet | Only if the run wants it; more pairing/permissions. Same `HardwareLink`. |
| BLE / Wi-Fi | Not for motion. |

Do not assume a 10 m passive USB cable is legal or reliable. Measure, then pick the long-run option **without changing the records**.

## Electrical safety (non-negotiable)

- Motor supply isolated from Mac USB.
- E-stop cuts **motor enable / 12 V to the bridge**, not just a software flag.
- Firmware watchdog: if no motion lease in ≤200 ms, **coast/brake per a tested stop**, do not leave last PWM.
- Link-loss, app quit, Mac sleep → disarmed, PWM 0.
- End-of-stroke switches are wired so firmware cannot drive through them.
- First motion is low PWM, on a bench, away from the camera’s glass.

## Software split (so S5 can start without the arm)

```
Alfie (sandboxed)  --USB CDC-->  Pico firmware
                         JSON, versioned
Pico owns: PWM, limits, lease, e-stop latch, telemetry
Alfie owns: when to ask for motion, image error (S7), UI
```

S5 implements the USB/JSON/e-stop/simulator with **motion electrically disabled**.  
S6 enables jog/goto.  
S7 closes the visual loop.

## Decision Stephan still owes (DECIDE Q7–Q9)

7. Controller at the Mac (short USB) vs at the tripod (long run)? Distance?
8. Rigid bidirectional actuator (recommended) vs pull-only + return spring?
9. After yaw, Return to Wide = current full sensor view (recommended) vs a second fixed safety camera?

Until Q8 is A, do not design a winch.

## Buying order

1. Pico + USB cable + e-stop + dummy load (LED / tiny DC motor) — enough for **S5**.
2. H-bridge + 12 V PSU + cheap 100 mm actuator — **S6**.
3. Print clamps after measuring the tripod tube and actuator eyes.
4. Potentiometer actuator or lead-screw only if jog proves the stroke is too short or `goto` is sloppy.
