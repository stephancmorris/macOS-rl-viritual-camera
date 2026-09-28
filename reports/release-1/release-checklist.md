# R1-GATE — single-camera release checklist

**Status: Open.** Card: https://trello.com/c/IDAjbyA9

A green unit suite does not establish live-show readiness. The release is a bounded, documented single-camera configuration; failures stay visible.

## Candidate

| Item | Value |
| --- | --- |
| Source commit | |
| Source fingerprint (app) | |
| Extension matched (Inspector → cmio status) | |
| Named rig: Mac, macOS, camera, capture device, converter, ATEM | |
| Camera mode (Stage / Webcam) and show standard | |

## Evidence

Every report must name this candidate's fingerprint.

| Card | Report | Fingerprint matches | Pass / fail | Limitations |
| --- | --- | --- | --- | --- |
| ZOOM-QA | [shot-move-test-plan.md](shot-move-test-plan.md) | | | |
| TRACK-QA | [tracking-replay.md](tracking-replay.md) | | | |
| SOAK | [soak.md](soak.md) | | | |
| LATENCY | [latency.md](latency.md) | | | |
| INSTALL | [install.md](install.md) | | | |
| DISPLAY-QA | [output-route.md](output-route.md) | | | |
| PAN-HITCH | [pan-hitch.md](pan-hitch.md) | | | |
| DOCS | README.md / operator guide walk-through at 1280 pt | | | |
| RECOVERY-UI | Rehearsal in shot-move-test-plan.md (Recovery controls) | | | |
| PAN-LIFE | Rehearsal in shot-move-test-plan.md (step 6) | | | |

## Release blockers (any one blocks)

- [ ] Wrong-subject switch in the release corpus
- [ ] Raw source pixels reaching the program output
- [ ] Operator ownership lost (automatic action overrides Manual / Pan / explicit Wide)
- [ ] Edge spill (black margins, clipped crop)
- [ ] Output instability (crash, progressive stutter, route stealing)

Optional optimisation and pan polish are not release requirements unless a report shows a blocker.

## Sign-off

| Role | Name | Date | Decision |
| --- | --- | --- | --- |
| Operator rehearsal | | | |
| Engineering | | | |
