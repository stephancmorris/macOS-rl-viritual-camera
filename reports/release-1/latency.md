# LATENCY — capture-to-consumer delay

**Status: Not run.** Card: https://trello.com/c/TkyfhrsJ

Target: ≤ 150 ms from a visible event in front of the camera to the same event on the downstream output. This is a target, not an assumed result. Depends on [output-route.md](output-route.md) being qualified first.

## Method

Pipeline delay must be separated from tracking response, dwell and zoom duration, so measure with the shot **static** (Return to Wide, or Manual with no movement).

1. Put a millisecond timer (a phone stopwatch or a web ms clock on a laptop) in view of Alfie's camera.
2. Place the downstream monitor (ATEM multiview / program monitor, or the virtual-camera client window) next to the timer.
3. With a second camera or phone recording at **120 or 240 fps**, film the timer and the downstream monitor in one shot.
4. For each sample, frame-step the recording and read: time on the real timer (T_real) and time shown on the downstream monitor (T_out). Latency = T_real − T_out.
5. Take at least **30 samples** spread over 2 minutes. Repeat for each route you claim (Program Display → ATEM; virtual camera → client).

Resolution: limited by the recording frame period (8.3 ms at 120 fps) plus the timer's display refresh and the downstream display refresh. State it.

## Rig

| Item | Value |
| --- | --- |
| Source fingerprint / build | |
| Camera, capture device, delivered size and rate | |
| Route and consumer | |
| Show standard | |
| Recording device and frame rate | |
| Timer device and its refresh rate | |

## Results

| Route | Samples | p50 ms | p95 ms | max ms | Resolution ± ms |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

Raw samples (T_real, T_out, latency) go in a CSV next to this file.

## Outcome

- [ ] Sample count, p50/p95/max, method and resolution recorded per route.
- [ ] Above 150 ms at p95 blocks any latency claim and opens a fix card.
- [ ] ALFIE_SPEC.md measured table updated only from this report.
