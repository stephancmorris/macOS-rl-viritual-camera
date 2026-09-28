# Release 1 evidence

Everything R1-GATE needs, one file per card. Files marked **Not run** are runbooks with empty result tables: nothing in them is a measured result until someone runs the procedure on the named rig and fills the table in. Never copy numbers between candidates; every report pins its own source fingerprint.

| Card | Report | Status | Needs |
| --- | --- | --- | --- |
| [ZOOM-QA](https://trello.com/c/rKHXzFgE) | [shot-move-test-plan.md](shot-move-test-plan.md) (procedure + results table) | Not run | Operator, camera, output route |
| [PAN-HITCH](https://trello.com/c/6vPWbhsg) | [pan-hitch.md](pan-hitch.md) | Not run | Camera, output route |
| [DISPLAY-QA](https://trello.com/c/HFyNhYO3) | [output-route.md](output-route.md) | Not run | Program Display → converter → ATEM |
| [INSTALL](https://trello.com/c/1BH2ecUh) | [install.md](install.md) | Not run | Clean supported Mac, notarized build |
| [TRACK-QA](https://trello.com/c/lxmF5I9Q) | [tracking-replay.md](tracking-replay.md) | Not run | Consented replay footage |
| [LATENCY](https://trello.com/c/TkyfhrsJ) | [latency.md](latency.md) | Not run | Camera, output route, a second camera or phone at 120/240 fps |
| [SOAK](https://trello.com/c/bYlNe6tu) | [soak.md](soak.md) | Not run | Church rig, 60 minutes, after the above |
| [R1-GATE](https://trello.com/c/IDAjbyA9) | [release-checklist.md](release-checklist.md) | Open | All of the above |

## Collecting diagnostics

Every capture writes three files to Alfie's sandbox, reachable from **Settings → Output → Diagnostics → Session Log → Open in Finder**:

```
~/Library/Containers/Morris.CinematicCoreMacOS/Data/Documents/CinematicCore/Diagnostics/
  alfie_session_<stamp>.json   build, source, route, column definitions, what is not observable
  alfie_soak_<stamp>.csv       one row per ~5 s window, every frame stage counted separately
  alfie_memory_<stamp>.csv     memory breakdown for the same windows
```

Recording starts on the first processed frame (detection on or off) and the last partial window is flushed when you press Stop. A session that has no closing record in its manifest did not end with Stop.

Summarise a session into Markdown and paste or attach it to the card's report:

```
python3 CinematicCoreMacOS/scripts/diagnostics_report.py <diagnostics folder or session file> --out summary.md
```

The summary lists observations (cadence shortfalls, losses by stage, growth over the run, stalls, thermal changes) and the numbers behind them. It does not pass or fail a run: each report freezes its own budgets first.

**Handoff is not presentation.** Alfie counts frames its output route accepted. When a display or virtual-camera client actually shows them, and what the ATEM does with them, is not observable from inside Alfie. Downstream cadence and latency need an external recording (see output-route.md and latency.md).

## Quick in-app checks

- **Inspector → Pipeline stages**: per-stage rates for the last ~5 s window and totals since Start.
- **Inspector → Setup check**: a ~30 s provisional check of the running source and route (supported / limited / unverified with reasons). It is a smoke test before a run, not evidence for a card.
