# SOAK — 60-minute single-camera release soak

**Status: Not run.** Card: https://trello.com/c/bYlNe6tu

Run after ZOOM-QA, TRACK-QA, DISPLAY-QA and PAN-HITCH, on the church rig, with the image-cache flush off (`DeveloperFlags.imageCacheFlushInterval = 0`, the current default).

## 1. Freeze budgets before the run

Take them from a 10-minute baseline on the same rig and write them here **before** starting the 60-minute run. Do not adjust them afterwards.

| Budget | Frozen value | Source (baseline session) |
| --- | --- | --- |
| Delivered fps floor (fraction of configured capture rate) | | |
| Handoff fps floor | | |
| Max gate-skipped frames per 5 s window | | |
| Render failures allowed | | |
| Refused handoffs allowed | | |
| Footprint growth ceiling (MB/min, least-squares over the run) | | |
| Hop / frame-wall last-third ÷ first-third ceiling | | |
| Thermal state ceiling | | |

## 2. Candidate and topology

| Item | Value |
| --- | --- |
| Source fingerprint / build | |
| Mac model, macOS, power | |
| Camera, capture device, profile, delivered size and rate | |
| Route and downstream (converter / ATEM input) | |
| Show standard | |
| Room temperature / enclosure | |

## 3. Script (60 minutes)

| Minute | Action |
| --- | --- |
| 0 | Start capture, Detect → lock subject, Crop |
| 0–10 | Normal movement; Push in / Pull out through every rung |
| 10 | Subject leaves frame for 20 s (HOLD → Searching), returns; confirm recovery or Resume |
| 15 | Manual: move the centre three times |
| 20–25 | Auto Pan, all three speeds |
| 25 | Crop again on the same subject |
| 30 | Unplug the Program Display for 10 s, reconnect |
| 35–55 | Normal movement; one Return to Wide and re-lock |
| 60 | Stop |

Record the downstream output externally for the full hour (for cadence spot-checks).

## 4. Results

Attach `scripts/diagnostics_report.py` output for the session, then fill in:

| Measure | Result | Within budget? |
| --- | --- | --- |
| Duration, crashes, restarts | | |
| Delivered fps (mean / worst window) | | |
| Handoff fps (mean / worst window) | | |
| Losses by stage (capture / gate / render / refused / no route) | | |
| Footprint start → end, trend MB/min | | |
| Heap blocks and external MB trends | | |
| Hop and frame-wall growth (last third ÷ first third) | | |
| Thermal timeline | | |
| Downstream cadence spot-checks (external recording, 3 × 20 s) | | |

Never infer 50 fps downstream from handoff counts alone.

## Outcome

- [ ] Hardware, topology, settings, build, duration, trends and downstream evidence recorded.
- [ ] No crash, restart or progressive stutter; any unexplained drop or growth investigated (LAG-DIAG).
