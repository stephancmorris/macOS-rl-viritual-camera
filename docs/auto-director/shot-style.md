# Shot style for live events

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Recorded scope and implementation

S1 covers static-camera live events with qualified steps and a present operator, not a sermon-only fixed timer. UC-2 has one shot per input. N3 uses app presets: Stage Wide / Full Body / Waist Up and Webcam Wide / Tight. `DirectorShot(preset:)` wraps `OperatorCommand.Preset`; `isWide`, `title` and deterministic `order` derive from that preset. There is no independent Director mode/zoom-rung mapping to maintain.

The A-07 `SegmentType` cases are `presenter`, `panel`, `performance`, `videoBreak`, `liveEvent`. A style affects ranking and pacing; a segment never grants authority. The no-run-sheet profile is `liveEvent`. The run-sheet authoring/advancement policy remains F3 open.

## Explicit style parameters

| `DirectorStyle` field | Unit / validation |
|---|---|
| `minimumShotDuration`, `preferredShotDuration`, `softMaximumShotDuration` | Finite nonnegative seconds; minimum ≤ preferred ≤ soft maximum |
| `wideCadence` | Finite positive seconds |
| `repetitionWindow`, `settleTime` | Finite nonnegative seconds |
| `maximumMovement` | Finite nonnegative normalized frame units/s |
| `onAirMoveRate` | Finite positive shot-ladder steps/s; storing it does not implement or approve N2 |
| `cutOnMotionAllowed` | Boolean; does not relax the stricter cut-ready bar |

## Feel table v1 (SU-1, SU-2, recorded 2026-10-25)

Operators set each segment with three choices instead of these nine numbers ([options summary](director-style-options.md)). `DirectorFeelTable.v1` (`Director/DirectorFeel.swift`) maps each feel to a style; the feel is derived by matching, so the stored schema is unchanged. Values are provisional study parameters, frozen as version 1; a new set of values is a new version.

| Choice | Option | Values |
|---|---|---|
| Pace | Calm / Balanced / Lively | minimum · preferred · soft maximum shot 12·30·60 / 8·20·40 / 5·12·25 s; repetition window = 2 × preferred; on-air move rate 0.25 / 0.35 / 0.5 steps/s |
| Wide shots | Rarely / Sometimes / Often | wide cadence 120 / 75 / 40 s |
| When someone moves | Wait until they settle / Cut while moving | maximum movement 0.05 / 0.15 frame/s; settle time 1.0 / 0.5 s; `cutOnMotionAllowed` false / true |

With nothing saved, the Live event style is Balanced · wide sometimes · wait until settled (SU-1); other segments follow Live event until given their own feel. The movement values are placeholders until checked against shadow evidence. Hand-edited exact values read as "Custom".

The style tightens the cut-ready bar (SU-4, `DirectorReadiness.Parameters.tightened(by:)`): settle time raises the required settled time, and when cutting while moving isn't allowed, maximum movement lowers the cut motion limit. A style never loosens the injected study parameters, and the prepare bar is unchanged, so preparation may still move.

Settings › Director previews three minutes of cuts for the selected style (`DirectorRhythmPreview`, SU-06) by running a fixed synthetic presenter timeline through `DirectorShotPolicy` ranking and the same `CutPolicy.timingReason` the live cut uses.

`DirectorShotPolicy` ranks eligible Preview candidates using explicit parameters. It may recommend preparing Preview before the current Program shot's minimum duration has elapsed. `recommendationDue`, soft maximum and wide cadence are advisory, never a forced cut, readiness waiver or permit. Abstentions are `invalidInput`, `minimumDuration`, `noEligibleCandidate`, `repetition`, `movement`, `noPreview`.

AI-1 restricts judges to rule-allowed candidates; optional probabilities are calibrated model outputs, not fabricated identity confidence. Low-confidence handling must preserve eligibility and authority even when preferring a wider shot. The current rule judge supplies no probability.

## Style choices — AWAITING OWNER

| Decision | Options | Recommendation and tradeoff | Evidence |
|---|---|---|---|
| T1 pace | Fixed timer; bounded suggestions; event-only | Per-segment style with soft suggestions, preserving a useful stable shot instead of cutting on a timer; may feel less predictable | Operator cuts and would-cut timing, rejected/accepted preparation opportunities |
| T2 movement | Allow cuts into motion; require settlement; limited exceptions | Keep P1's stricter cut bar and prefer a wide during movement; trades dramatic timing for clarity | Motion/landing annotations and wrong-time cuts, separate from synthetic gate tests |
| T3 wide frequency | Mandatory timer; soft reminder; none | Soft profile-based cadence; avoids a bad cut but can leave a long hold | Useful-wide opportunities, repeated-shot and missed-wide counts |

P2's ambiguity rule and N1's operator nudge override aesthetic pressure. Assist starts fresh after an operator Take; Auto/Backup respect the configured minimum hold after a nudge. N2 on-air motion and N4 once-per-Preview-tenure preparation are still open details, not granted by these style fields.

Evidence classes stay synthetic, recorded and live. No audio or show network; Director study logs contain metadata only, expire after 30 days unless explicitly exported, and contain no media without a separate E3 decision. No profile or synthetic score qualifies a level without its sign-off.
