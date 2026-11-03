# Eased auto-pan: constant vs eased sweep (PAN-EASE-MODEL, 4 Nov 2026)

`AutoPanMotion.eased` reshapes the sweep with a trapezoidal speed profile: speed ramps up over the first 15% of travel and down over the last 15% (an unapproved starting value). Phase still advances at constant speed and holds for 1.5 s at each end, so the timing is unchanged:

| Speed | Constant transit | Eased transit | Target |
|---|---|---|---|
| Slow | 33.3 s | 33.3 s | 25–35 s |
| Normal | 16.7 s | 16.6 s | 15–20 s |
| Fast | 11.1 s | 11.1 s | 8–12 s |

The CSVs here give the crop centre over 150 s at 50 Hz, with travel 0.5 (centre between 0.25 and 0.75), for each speed and curve. They come from `AutoPanMotionSweepTests` with `ALFIE_AUTOPAN_CSV=1`. Plot `center` against `seconds` to compare the turnarounds.

The flag `DeveloperFlags.easedAutoPan` is **off**. Per [PAN-EASE](https://trello.com/c/hVgfF7Xd), the curve needs the owner's approval from a replay on the rig before it replaces constant speed. That is a human judgement; these tests prove timing only, not feel.
