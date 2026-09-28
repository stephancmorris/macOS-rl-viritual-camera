# MULTI-QA — two-input Program / Preview qualification

**Status: Not run.** Card: https://trello.com/c/uO1HAlYm. The first R2 release qualifies exactly two running inputs, not C/D. Do not certify a pair from a short Setup check.

## 1. Freeze budgets before the run

Use a 10-minute A-only and a 10-minute measured pair baseline on the **same** rig, standard and route. Enter all values and source session IDs before the 60-minute trial. No post-run budget edits.

| Budget | Frozen value | Baseline evidence / rationale |
| --- | --- | --- |
| A and B delivered fps floor versus each configured source rate | | |
| Program accepted handoff fps floor | | |
| External downstream cadence floor and allowed repeats | | |
| Maximum Preview render/source age eligible for Take | | |
| Take request-to-commit ceiling; stale revision refusal | | |
| Maximum gate skips, mailbox replacement, render failures and route refusals per 5 s | | |
| MainActor, Vision, compose/render latency and observation-age ceilings by channel | | |
| IOSurface/high-water count and footprint growth ceiling | | |
| Thermal state and sustained CPU ceilings | | |
| Clock discontinuities and Program interruption allowed | | |

## 2. Candidate and topology

| Item | Value / evidence |
| --- | --- |
| `alfie_session_<stamp>.json` path(s), app version/build/source fingerprint | |
| Mac model/architecture, macOS build, power, room temperature | |
| A camera/capture card/port/hub, delivered size/rate/profile | |
| B camera/capture card/port/hub, delivered size/rate/profile | |
| Initial Program, Preview; show standard | |
| Output route, display/virtual-camera client, converter, ATEM input | |
| External recorder and timestamp synchronization method | |
| R1 single-camera baseline session/report | |
| Pair admission fingerprint/status/policy version before run | |

Read the build/source identity from the manifest rather than typing a Git hash from memory. Save a copy of each session's soak CSV, memory CSV and manifest. A manifest that names only A is insufficient to establish B's delivered format or rate; add B's capture evidence explicitly and mark that diagnostics gap.

## 3. Matrix and fault script

Repeat the matrix on each proposed supported Mac/OS/camera-card/hub combination. Record source clock/rate mismatch cases, including two devices at different actual cadences. Start with A-only equivalence, then admit B; a failed B start must leave A available.

| Configuration | A role/mode | B role/mode | Run ID | Result/evidence |
| --- | --- | --- | --- | --- |
| Baseline | Program Track | Off | | |
| Pair | Program Track | Preview Track | | |
| Pair | Program Track | Preview Pan | | |
| Roles exchanged | Preview Track | Program Track or Pan | | |
| Different source clocks/rates | Program Track | Preview Track | | |

For each Track+Track and Track+Pan run:

1. Confirm independent subject lock, recovery, pan/zoom and shot revision. Inspect Program and Preview panes and the actual output; only Program reaches the output.
2. Prepare Preview and Take under normal load, then under controlled CPU/GPU/thermal pressure. Record request, refusal/commit reason, route generation, output timestamp continuity, and externally observed frame sequence. A stale candidate, stale shot revision, or failed render must refuse Take without role change.
3. Try two rapid Takes, preset change during a pending Take, and a Preview stop/rebind. Record whether old work was rejected and whether the current Program continues.
4. Hot-unplug **B** while A is Program. Confirm Preview shows loss and Program stays A. Reconnect/restart B; no auto-cut.
5. After a deliberate Take, hot-unplug **A** while B is Program. Confirm only A/Preview fails. Then hot-unplug the current Program **B**: verify HOLD then generated standby, no automatic switch to A, and deliberate recovery.
6. Disconnect/reconnect the external output route; verify status and no silent route stealing. Check unsupported source format/admission refusal without changing the show standard.
7. Run two inputs continuously for at least **60 minutes** in each required mode. Include movement, recovery, Take and fault periods. Track capture, Vision, render, memory/IOSurface high water, thermal, handoff and externally observed cadence. Stop normally to flush the partial diagnostics window.

## 4. Results per named rig

| Check | Result | Measured evidence / file | Within frozen budget? |
| --- | --- | --- | --- |
| A-only invariant retained | | | |
| Track+Track 60-minute duration and restarts | | | |
| Track+Pan 60-minute duration and restarts | | | |
| A/B delivered and admitted cadence | | | |
| Program handoff vs external presentation cadence | | | |
| Preview freshness and valid Take latency | | | |
| Stale Take/revision and rapid-Take refusal | | | |
| B unplug; A unplug; current Program unplug | | | |
| HOLD/standby and no silent source switch | | | |
| Output loss/reconnect | | | |
| Memory/IOSurface plateau and thermal timeline | | | |
| Source clock mismatch and unsupported pair behavior | | | |

List every unverified condition and unsupported combination with its exact fingerprint. Summarize each diagnostics session with `python3 CinematicCoreMacOS/scripts/diagnostics_report.py <session>` and attach external cadence evidence. A host handoff rate cannot fill the downstream presentation column.

## 5. Certification gate

`AdmissionRecordStore.markCertified(_:)` in `MultiInputAdmission.swift` records certification for the exact `AdmissionFingerprint` (machine, OS, device/profile/**mode**, standard, route and policy version). Track+Track and Track+Pan have different keys; certify each only after its required run passes. Call it **only after** every required matrix/soak/fault result above passes the frozen budgets, with the report reviewed and the fingerprint checked against the tested pair. The code has no automatic certification path; a short admission probe yields provisional status. If any result is missing, failed, or the fingerprint changes, leave the record unknown/provisional/unsupported and do not call `markCertified`.

- [ ] Candidate and budgets frozen before run.
- [ ] Both required 60-minute modes and fault matrix completed on named hardware.
- [ ] External output cadence separated from app handoff evidence.
- [ ] Review approved exact fingerprint for `markCertified`.
