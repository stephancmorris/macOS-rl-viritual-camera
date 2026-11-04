# Next group: attended rig validation

> **Updated 4 November 2026 ([RIG-RUNBOOK-UPDATE](https://trello.com/c/SS7mZhnQ)).** The procedure below still applies. Read the section *What changed since 22 October* first: it says what each step should now show, adds the MODE-QA checklist and the PAN-EASE replay step, and replaces the old candidate in *Setup before the run*. This remains a procedure; it records no results.

Prepared after the software group in PR #76. The next five executable Spec Ready cards share a rig and operator; their outcomes are still unmeasured. This is a test handoff, not completed acceptance. S3-PLAN is an overview, and INSTALL needs a separate clean Mac/distribution candidate.

| Order | Ticket | Concrete work | Evidence needed to close |
|---|---|---|---|
| 1 | [DISPLAY-QA](https://trello.com/c/HFyNhYO3) | Establish the actual source, show standard and receiver route before judging motion. Initial church target is the card's HDMI/converter/ATEM 1080p50. Check clean Program, destination selection and reconnect. | Named topology, candidate fingerprint, receiver observation/cadence and route recovery; host sends remain separate. |
| 2 | [MODE-QA](https://trello.com/c/bHd5ACBW) | Walk Single Cam, Multi Cam and Webcam on the same identified candidate, using the *MODE-QA checklist* below. Check all Stage shots, A/B Takes, Edit Live, Stop/Start, live switch/refusal, the first-frame wait before Cam B, persistence and the two specified legacy upgrade paths. | Per-step observations, receiver evidence, 1280×800 UI/VoiceOver results, migration provenance and the card's ten minutes per mode. |
| 3 | [ZOOM-QA](https://trello.com/c/rKHXzFgE) | Rehearse every rung and move using repeatable recorded motion plus real capture. Reverse at start/middle/end, test both pan dwells and zero travel, and cancel by the named controls. | Operator observations plus source/consumer evidence; reproduce clipping, margins, jumps or misleading active state before changing code. |
| 4 | [PAN-HITCH](https://trello.com/c/6vPWbhsg) | Run repeatable cold-start first sweeps with detection on/off at fixed source/settings. Compare capture/render/present traces. | A timestamped reproduction and controlled A/B hypothesis result, or an explicitly inconclusive result. Keep long-session drift separate. |
| 5 | [SOAK](https://trello.com/c/bYlNe6tu) | After prerequisite motion/output checks, run the card's sixty-minute single-camera release session with movement, loss/recovery, overrides, rungs, pan and reconnect. | Complete duration/trends, capture/render/drop/memory traces and attended receiver observations. Owner freezes budgets from baseline before pass/fail. |

## Setup before the run

1. Identify one candidate commit and record its app source fingerprint. *(4 Nov: the 22 October candidate `238f8d2` predates the three-mode picker, the first-frame wait, the run-sheet fixes and the review fix, so don't use it.)* Build the candidate from a single `main` commit with `build_release.sh`. A plain `xcodebuild` Release leaves `AlfieSourceFingerprint` empty in Info.plist, so the diagnostics wouldn't name the source; see `reports/release-check-2026-11/README.md`. MODE-QA calls for signed Debug and Release builds of the same commit; an unsigned build is software evidence only. Record any later code changes and rebuild/reidentify before using results.
2. Prepare the real stage camera, second input and below-show-rate webcam required by the cards; record selected formats, frozen show standard, display/converter/receiver and virtual-camera consumer. Confirm the actual attached inventory at run time. No present or available hardware is assumed by this plan.
3. Use synthetic or specifically consented source material and preserve the existing consent/retention procedure. Identify the attended operator and which machine/route is being observed. Keep identifying raw logs local; use the existing explicit export procedures for review copies.
4. Prepare isolated preference/upgrade fixtures for both legacy Stage and Webcam histories. Preserve the normal operator profile. Current-preference persistence from the stopped UI check does not satisfy legacy migration acceptance.
5. Record the applicable prerequisite results from each card. DISPLAY/MODE/motion checks can inform one another; reuse evidence only when candidate, source, standard, route and scenario actually match. Separate clean-Mac INSTALL and Director qualification are not prerequisites that this software report has completed.

## Execution sheet

For each scenario record: ticket/cell, candidate SHA/fingerprint, Debug or Release/signing state, source and selected format, show standard, route/consumer, initial state, action, expected result, actual result, evidence reference and outcome (`observed`, `failed`, `not run` or `inconclusive`). Preserve missing observations explicitly. The exact source/receiver environment belongs in the local run record; this template contains no claimed device measurement.

Start with a stopped-state baseline. Confirm selected mode and disabled Stop before Start. During a live B-only or pending-start scenario verify Session-menu Stop is available, then observe logical Stop and the receiver separately. The unit tests cover the availability calculation and source-bound metadata; they do not replace this attended observation. Do not equate `accepted` metadata with asynchronous capture shutdown or a final downstream picture.

Run one controlled scenario at a time. On a defect, preserve the trace and minimal reproduction, link a fix card, implement the causal change, then repeat affected cells on the newly identified candidate. Avoid changing curves, timers and renderer together for a hitch investigation. A failed or inconclusive cell stays visible; do not substitute synthetic test counts or reuse a prior candidate's receiver evidence.

For the long session, freeze the owner-approved quantitative baseline/budgets before rating it. Keep host capture/render/send counters, receiver cadence, visible motion and operator observations distinct. No numeric acceptance budget is chosen by this handoff. Do not turn a successful run into Assist/Auto/Backup permission: those levels still require their separate frozen plan, opportunities, real evidence and signatories.

## What changed since 22 October (4 November 2026)

These merged to `main` after this runbook was written. For each one, here's what an attended step should now show. Nothing here is a result.

| Change | PR | Where it shows up | What to look for |
|---|---|---|---|
| Three operator modes: **Single Cam · Multi Cam · Webcam**, in that order | #77 | The Mode picker on the single-camera stopped screen (above Start), in the Show setup header, and in Settings › Show & cameras | Single Cam is always available ("Default"). Multi Cam is enabled when discovery sees 2+ cameras, apart from Alfie's own virtual camera (it says "N cameras found"). With fewer it shows "Connect a 2nd camera" and stays disabled, unless Multi Cam is already the current mode, in which case the segment stays enabled. When a second camera unlocks it, Multi Cam gets a brief outline. Webcam appears only on a Mac with a built-in camera ("Built-in camera found"), or if it is already the current mode |
| Leaving Multi Cam while live is refused | #77 | The picker, with the reason shown inline (never an alert) | With Cam B present, the reason is "Remove Cam B or stop the show to leave Multi Cam." With B as Program, it is "Cam B is Program. Stop the show to leave Multi Cam." Mode, Program and capture are unchanged. Single Cam → Multi Cam while live keeps capture running with A as Program |
| Cam B waits for Cam A's first accepted frame | #86 | Multi Cam, **Start show · A Program, B Preview** | B is added only after the selected output has accepted a new A frame. Until then the console note reads "Waiting for Cam A to reach the output before starting Cam B". If the output never accepts (no route, refused), A keeps running and B never starts; Stop retires the wait. This is host acceptance, so still observe the receiver separately |
| Run-sheet Current marker follows Advance | #89 | **Run sheet…** (Show setup, standby screen, or **Edit…** in the live console header); Advance is ⌘⇧↩ | After Advance, opening the run sheet shows the Director's current segment as Current, and "Unsaved changes" does not appear. The panel is opaque in Dark. Debug builds only (`runDirectorShadow`) |
| Console refresh under load | #92, #98 | Multi Cam console | Only with `runtimeWorkloadPolicy` on (see below): the periodic refresh halves at the `optionalUI` level and above, but every operator action still refreshes at once |
| Inspector Workload row | #97 | Inspector › Show | Only with `runtimeWorkloadPolicy` on. It shows the level and the last change's reasons |

### MODE-QA checklist

Run each line on the identified candidate and record the result using the execution sheet above. Follow the card's ten minutes per mode.

1. **Fresh install:** launch with clean preferences. Single Cam is selected, and the stopped screen reads "SINGLE CAM · SESSION STOPPED".
2. **Legacy upgrade, Stage:** with an isolated preference fixture that holds `cinematicFormat = stage` and no `operatorMode`, launch. Multi Cam is selected and `operatorMode` is written once.
3. **Legacy upgrade, Webcam:** the same with `cinematicFormat = webcam`. Webcam is selected.
4. **Single Cam:** Start → Detect → lock. Walk Wide → Full Body → Waist Up and back with push/pull. Try Manual, Auto Pan and Return to Wide. The pill shows Stop session, and Program reaches the route and the receiver.
5. **Single Cam → Multi Cam while live with A only:** the switch is allowed, the console swaps, A stays Program, and Preview reads "No Preview camera".
6. **Multi Cam pair start:** after A is running, and until the selected output accepts a new A frame, the console note reads "Waiting for Cam A to reach the output before starting Cam B". That note does not appear during A's startup. B starts once the frame is accepted. Record the receiver picture before and after.
7. **Take both ways, and Edit Live on and off:** the console updates immediately after each action.
8. **Leaving Multi Cam with B live:** refused with the exact copy above; nothing changes.
9. **Stop show, then switch to Single Cam:** no Cam B remains, and A is Program on the next Start.
10. **Webcam:** a 1080p30 webcam runs below the show rate with the capture status line explaining why. Wide and Tight only; no Manual or Auto Pan.
11. **Persistence:** quit and relaunch in each mode; the same mode returns.
12. **Accessibility:** at 1280×800, VoiceOver reads the Mode picker ("Mode", each segment's note) and the refusal reason.

### PAN-EASE replay step (owner verdict)

Run this as part of ZOOM-QA or PAN-HITCH, on a **Debug** build of the same candidate.

1. **Constant first:** with `DeveloperFlags.easedAutoPan = false` (the default), record one Auto Pan sweep at each speed (Slow, Normal, Fast) on repeatable recorded motion or a static wide. Capture the receiver picture and the session diagnostics.
2. **Then eased:** set `nonisolated static let easedAutoPan = true` in `CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift`, rebuild Debug, and repeat the three sweeps on the same source.
3. **Compare** the turnarounds against `reports/pan-ease-2026-11/autopan-0.0{1,2,3}-{constant,eased}.csv`. These are the synthetic expected centre paths: transit Slow 33.3 s, Normal 16.7 s, Fast 11.1 s, with a 1.5 s dwell for both curves.
4. **Record** the owner's verdict (adopt eased, keep constant, or adjust the 15% ramp) on [PAN-EASE](https://trello.com/c/hVgfF7Xd). Revert the flag edit; never commit it as `true` without that verdict.

### Workload policy (only when investigating overload)

`DeveloperFlags.runtimeWorkloadPolicy` is **off**. To observe it, set it to `true` in `DeveloperFlags.swift` and rebuild Debug. Level changes then appear in the session diagnostics notes (`workload <from> -> <to>: <reasons>`) and in the Inspector's Workload row. Thresholds are provisional until MULTI-QA calibrates them, so record what you observe and don't tune anything during a validation run. Revert the flag edit afterwards.

## Separate hard follow-up

[INSTALL](https://trello.com/c/1BH2ecUh) needs a clean supported Mac plus the matched signed/notarized app and extension from the chosen candidate. Use the existing packaging procedure and retain OS approval checks; no signing credentials or approvals are available or inferred here. Verify the volunteer flow without Xcode, permission denial/retry, consumer selection, update and reconnect. A historical DMG or this unsigned local build cannot close it.

The Director [D-06](https://trello.com/c/865rDWWm) evaluation remains a separate assessment group after its owner inputs and real evidence exist. PR #76 supplies explicit phase tooling; it supplies no independent opportunity labels, live route exposure or qualification sign-off.
