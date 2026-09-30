# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| S1 First directing scope? | Sermon Auto Prepare + nominated subject; sermon Suggest; whole-service Auto Direct | Sermon Auto Prepare: removes preparation work without delegating editorial cuts | AD-SCOPE, all director wiring | Yes, expand only after evidence |
| S2 What remains manual? | All cuts/subject changes; cuts only; autonomous speaker choice | All cuts, subject changes and service transitions; person detection cannot infer intent | AD-SUBJECT/TAKE | Yes, requalify |

Status: proposed contract, 2026-09-30. Authority rules: [authority-and-override](authority-and-override.md). No decision is recorded as approved.

## Existing foundation

`ShowCoordinator.swift` owns two-channel roles and explicitly routes `TakeRequest` via `take`; `CameraChannel.swift` supplies `ChannelOutputPort`; `ProgramRouter.swift` owns one downstream Program output. `OperatorCommand.swift`/`CommandDispatcher` provides channel-scoped intent, and `ShotComposer.swift`/`ShotComposer` provides existing framing/lock modes. Director is proposed orchestration above these, not a new crop mode or output. R2 two-camera real-rig qualification is still required; code and unit tests are not release evidence.

| Candidate | Volunteer benefit | Main risk / evidence required |
|---|---|---|
| Sermon Suggest | Least authority; explain desired next shot | Operator still performs every framing step; measure proposal usefulness and extra attention |
| **Sermon Auto Prepare + nomination** | Prepares alternate shot while volunteer watches Program and chooses Take | Unexpected Preview edits; measure override and subject continuity; explicit resume after any intervention |
| Worship/panel Auto Prepare | More dynamic subject coverage | Unresolved singer/speaker identity, instruments and overlap; needs separately labelled multi-person evidence |
| Whole-service Auto Direct | Lowest routine operator load | Audio/editorial inference, service transitions and autonomous cuts compound risks; cannot qualify from sermon results |

## Proposed bounded contract

- Two admitted Stage inputs, one output, one sermon speaker explicitly nominated **in each channel** where a close shot is required. Cross-camera identity transfer is not implemented; a name/alias is operator metadata, not face recognition across views.
- Initial setup Off. Operator enables Auto Prepare after verifying role assignments and candidate subject. Suggest is available as a lower level. Auto Direct remains unavailable until its separate gate and decision.
- Director may prepare current Preview using approved existing presets/modes; cannot touch Program, turn on Edit Live, change sources, change output, reconnect hardware or widen Program. Current Program tracking may continue under its existing lock grant.
- Volunteer chooses every Take, nomination/retarget, service cue, pause/pin/resume, fault recovery and show start/stop. A Take pauses director; deliberate Resume creates fresh proposals for the new Preview.
- On insufficient evidence: explain and abstain. Manual Take remains governed by R2 technical eligibility, independent of director editorial readiness.
- Unsupported: autonomous preacher naming, active-speaker selection, worship/panel/whole-service direction, audience/reaction close-ups, children as inferred targets, third/fourth running inputs, physical motion, spoken execution, ATEM tally/control, extra outputs, unattended operation. A service containing these sections is supported only by turning director Off and using qualified manual R2 operation.

## Minute-by-minute walkthroughs

Times below are proposed rehearsal scripts, not timing requirements or forced shot changes. A legal stable shot may remain indefinitely; maximum-duration suggestions never force a bad cut.

| Minute | Normal sermon: operator | Director / Program outcome |
|---|---|---|
| 00 | Start two-camera show manually; A stage-wide, B speaker camera | Off; confirm actual downstream Program A |
| 01 | Nominate speaker on B, verify lock; enable Auto Prepare | Prepare B Waist Up; show nomination and reason |
| 02 | Inspect B; press Take | R2 validates/commits B; director pauses, no hidden next action |
| 03 | Resume Auto Prepare; A assigned safe-wide | Fresh proposal A Wide, Program B tracks under existing lock |
| 04 | Keep B live; pin shot | Pin prohibits director work; B tracking remains live, not a freeze |
| 05 | Unpin, then Resume | Re-evaluate A; no replay of minute 03 work |
| 06 | Deliberately Take A for contextual view | A Program; pauses. B remains its own channel state |
| 07 | Resume; inspect B's new prepared shot | B preparation has no effect on A output |
| 08 | Take B when editorially appropriate | Commit if R2 ready; rejected click never becomes a future cut |
| 09 | Speaker ends; set service cue / turn Off | No automatic transition to worship; manual operation continues |

| Minute | Disturbance rehearsal: operator | Director / Program outcome |
|---|---|---|
| 00 | A wide Program, B nominated; enable Auto Prepare | Preparing B only |
| 01 | Second person crosses B | Ambiguous identity → no director-ready proposal |
| 02 | Try manual Take only after visually judging Preview | Uses R2 readiness; director pauses before attempt, even if refused |
| 03 | Speaker leaves field; remain on A | Ask for nomination; no largest-person substitution |
| 04 | Unplug B | Cancel proposal; A remains Program |
| 05 | Explicit reconnect B | Fresh source generation; still paused |
| 06 | Nominate restored speaker and Resume | New evidence and fresh preparation; no inherited countdown |
| 07 | Enter Edit Live to adjust A | Global pause before live editing; prominent live-control banner |
| 08 | Exit Edit Live, choose whether to Resume | No automatic re-enable |
| 09 | Stop show | Off, all grants retired; next launch starts Off |

Acceptance evidence: volunteer can explain what will happen next, correctly distinguish Preview from Program, take/pause/Wide without searching, and recover each fault without a silent source switch. Run the two scripts on both downstream routes and report counts of incorrect expectations, unintended Preview changes and interventions. Risks: extra Resume work may outweigh preparation savings; measure completed framing actions and attention shifts against manual R2 and Suggest before broadening authority.
