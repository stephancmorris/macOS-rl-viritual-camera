# PAN-HITCH — first-sweep hitch vs long-session degradation

**Status: Not run.** Card: https://trello.com/c/6vPWbhsg

Goal: separate an immediate stall on the first Auto Pan sweep from progressive slowdown. Long-run behaviour belongs to [soak.md](soak.md). Change nothing (curve, timers, renderer) until a hitch is reproduced; then test one hypothesis at a time.

## Candidate

| Item | Value |
| --- | --- |
| Source fingerprint / build | from `alfie_session_*.json` |
| Mac model, macOS, power (battery / mains) | |
| Source device, profile, delivered size and rate | |
| Output route and receiver | |
| Show standard | |
| Pan speed setting | |

## Procedure

Run each condition from a **cold start** (quit Alfie, relaunch, Start capture) so the first sweep is always the first:

| Run | Condition | How |
| --- | --- | --- |
| A1–A3 | Detection off | Start → Return to Wide → Auto Pan. Do not press Detect. |
| B1–B3 | Detection on, then Pan | Start → Detect → tap subject → wait for Locked → Auto Pan. |
| C1–C3 | Warm start | After a completed run, Stop → Start → Auto Pan (not relaunched). |

For each run:

1. Film the output receiver (phone at 60 fps or more) through the first two full sweeps.
2. Watch **Inspector → Pipeline stages** during the first sweep; note any gate skips, render failures or refused handoffs.
3. Stop after two sweeps. Keep the session files and run `scripts/diagnostics_report.py` on each.
4. Mark the timecode of any visible hitch in the recording and find the matching window (elapsed_s) in the CSV.

## Results

| Run | Hitch seen (timecode) | Matching window | delivered / admitted / handoff fps | gate skips | hop max ms | frame wall max ms | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | | | | | | | |
| A2 | | | | | | | |
| A3 | | | | | | | |
| B1 | | | | | | | |
| B2 | | | | | | | |
| B3 | | | | | | | |
| C1 | | | | | | | |
| C2 | | | | | | | |
| C3 | | | | | | | |

## Reading the evidence

- Hitch with delivered fps steady but handoff dips or gate skips rise → pipeline/MainActor stall (compare hop and frame-wall max).
- Hitch with handoff steady in the CSV but visible on the receiver → downstream/presentation side (not observable in-app; see output-route.md).
- Hitch only on cold starts (A/B, not C) → first-use cost (shader compile, cache warm-up); a candidate for the conditional PRESENTER/PRESENT-POSE cards.
- No hitch reproduced in 9 runs → record "not reproduced" with the conditions; do not change code.

## Outcome

- [ ] Timestamped reproduction with an A/B hypothesis test, **or** explicit "inconclusive / not reproduced".
- [ ] Linked fix card (if reproduced).
