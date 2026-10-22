# Next group: attended rig validation

Prepared after the software group in PR #76. The next five executable Spec Ready cards share a rig and operator; their outcomes are still unmeasured. This is a test handoff, not completed acceptance. S3-PLAN is an overview, and INSTALL needs a separate clean Mac/distribution candidate.

| Order | Ticket | Concrete work | Evidence needed to close |
|---|---|---|---|
| 1 | [DISPLAY-QA](https://trello.com/c/HFyNhYO3) | Establish the actual source, show standard and receiver route before judging motion. Initial church target is the card's HDMI/converter/ATEM 1080p50. Check clean Program, destination selection and reconnect. | Named topology, candidate fingerprint, receiver observation/cadence and route recovery; host sends remain separate. |
| 2 | [MODE-QA](https://trello.com/c/bHd5ACBW) | Walk Single Cam, Multi Cam and Webcam on the same identified candidate. Check all Stage shots, A/B Takes, Edit Live, Stop/Start, live switch/refusal, persistence and the two specified legacy upgrade paths. | Per-step observations, receiver evidence, 1280×800 UI/VoiceOver results, migration provenance and the card's ten minutes per mode. |
| 3 | [ZOOM-QA](https://trello.com/c/rKHXzFgE) | Rehearse every rung and move using repeatable recorded motion plus real capture. Reverse at start/middle/end, test both pan dwells and zero travel, and cancel by the named controls. | Operator observations plus source/consumer evidence; reproduce clipping, margins, jumps or misleading active state before changing code. |
| 4 | [PAN-HITCH](https://trello.com/c/6vPWbhsg) | Run repeatable cold-start first sweeps with detection on/off at fixed source/settings. Compare capture/render/present traces. | A timestamped reproduction and controlled A/B hypothesis result, or an explicitly inconclusive result. Keep long-session drift separate. |
| 5 | [SOAK](https://trello.com/c/bYlNe6tu) | After prerequisite motion/output checks, run the card's sixty-minute single-camera release session with movement, loss/recovery, overrides, rungs, pan and reconnect. | Complete duration/trends, capture/render/drop/memory traces and attended receiver observations. Owner freezes budgets from baseline before pass/fail. |

## Setup before the run

1. Identify one candidate commit and record its app source fingerprint. The software changes are at `238f8d245732a54b5a2e77f031d006ebbff90985`, app fingerprint `a8ed233e30be8d4d3789e4105e8388ddd16b8a1edeeca2b02a6ab5fa9ffdfdc9`. The local validated Release at `/private/tmp/alfie-human-review-20261018/baseline-dd/Build/Products/Release/Alfie.app` is unsigned. MODE-QA calls for signed Debug and Release builds of the same commit; the unsigned build is software evidence only. Record any later code changes and rebuild/reidentify before using results.
2. Prepare the real stage camera, second input and below-show-rate webcam required by the cards; record selected formats, frozen show standard, display/converter/receiver and virtual-camera consumer. Confirm the actual attached inventory at run time. No present or available hardware is assumed by this plan.
3. Use synthetic or specifically consented source material and preserve the existing consent/retention procedure. Identify the attended operator and which machine/route is being observed. Keep identifying raw logs local; use the existing explicit export procedures for review copies.
4. Prepare isolated preference/upgrade fixtures for both legacy Stage and Webcam histories. Preserve the normal operator profile. Current-preference persistence from the stopped UI check does not satisfy legacy migration acceptance.
5. Record the applicable prerequisite results from each card. DISPLAY/MODE/motion checks can inform one another; reuse evidence only when candidate, source, standard, route and scenario actually match. Separate clean-Mac INSTALL and Director qualification are not prerequisites that this software report has completed.

## Execution sheet

For each scenario record: ticket/cell, candidate SHA/fingerprint, Debug or Release/signing state, source and selected format, show standard, route/consumer, initial state, action, expected result, actual result, evidence reference and outcome (`observed`, `failed`, `not run` or `inconclusive`). Preserve missing observations explicitly. The exact source/receiver environment belongs in the local run record; this template contains no claimed device measurement.

Start with a stopped-state baseline. Confirm selected mode and disabled Stop before Start. During a live B-only or pending-start scenario verify Session-menu Stop is available, then observe logical Stop and the receiver separately. The unit tests cover the availability calculation and source-bound metadata; they do not replace this attended observation. Do not equate `accepted` metadata with asynchronous capture shutdown or a final downstream picture.

Run one controlled scenario at a time. On a defect, preserve the trace and minimal reproduction, link a fix card, implement the causal change, then repeat affected cells on the newly identified candidate. Avoid changing curves, timers and renderer together for a hitch investigation. A failed or inconclusive cell stays visible; do not substitute synthetic test counts or reuse a prior candidate's receiver evidence.

For the long session, freeze the owner-approved quantitative baseline/budgets before rating it. Keep host capture/render/send counters, receiver cadence, visible motion and operator observations distinct. No numeric acceptance budget is chosen by this handoff. Do not turn a successful run into Assist/Auto/Backup permission: those levels still require their separate frozen plan, opportunities, real evidence and signatories.

## Separate hard follow-up

[INSTALL](https://trello.com/c/1BH2ecUh) needs a clean supported Mac plus the matched signed/notarized app and extension from the chosen candidate. Use the existing packaging procedure and retain OS approval checks; no signing credentials or approvals are available or inferred here. Verify the volunteer flow without Xcode, permission denial/retry, consumer selection, update and reconnect. A historical DMG or this unsigned local build cannot close it.

The Director [D-06](https://trello.com/c/865rDWWm) evaluation remains a separate assessment group after its owner inputs and real evidence exist. PR #76 supplies explicit phase tooling; it supplies no independent opportunity labels, live route exposure or qualification sign-off.
