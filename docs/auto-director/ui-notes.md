# Director console notes

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Recorded operator contract

U2's visible levels are **Manual · Assist · Auto · Backup**. Every launch is Manual, not handed to Alfie. A level without its own current rig qualification is greyed out with **not qualified**; selecting it is refused, not silently changed to another level. Internal shadow/Suggest is not a fifth operator level or a qualified automation claim.

A1 requires immediate takeover and one **Hand to Alfie** action to give control back. Keep manual camera controls and Return to Wide understandable and reachable. N1 means Assist operator Take starts fresh on the new Preview without pausing; Auto/Backup operator Take is a nudge, while the Manual toggle stops preparing and cutting. Do not label every Take a takeover.

Alfie uses the operator's app preset names (N3), shows which subject it selected (E1), and allows one-tap nomination override. Uncertainty should read as a practical next step or wider-shot choice, not a probability, revision number or claim to know a person's name. P2 never blocks a legal manual Take.

## Actual A-07 console seam

`NextShotStatus.DirectorSection` is a plain value. `Level` is `manual`, `assist`, `auto`, `backup`; `Activity` is `active`, `paused`, `inhibited`, or `abstaining` with typed reasons and plain-language text. Examples include “Paused: you took over”, “Waiting: a camera is not ready”, and “More than one person on Cam B · staying wide”. Diagnostic ages/revisions belong in the inspector.

`PreparedShot` supplies input/shot; `NextCut` supplies input, optional countdown in seconds and `cancellable`. A missing countdown can represent the proposed Backup display, not a hidden next destination. The model includes `alfieSetShot` badges, per-level `Qualification`, `handedToAlfie`, and an optional `RunSheetLine`. `atLaunch` clears preparation, next cut and badges even if qualification is present.

`DirectorConsoleControlling` exposes `directorSection`, `setLevel`, `handToAlfie`, `takeOver`, `cancelNextCut`, `advanceSegment`, and `overrideSubject(on:at:)`. Views must send those intents through the owner; they do not dispatch camera commands or call the router. A fake gallery can demonstrate layout, never qualification or successful live wiring. A-07's optional Director section and value API do not implement the engine/UI connection.

A-07 has a review finding in countdown formatting for huge finite values overflowing `Int`; display formatting must fail safely before it is relied on in a show. No countdown duration is prescribed here.

## UI choices — AWAITING OWNER

| Decision | Options | Recommendation and tradeoff | Evidence |
|---|---|---|---|
| U1 placement | Next-shot panel; pill; inspector | Next-shot status plus always-visible Manual / Hand to Alfie as proposed; keeps the next action visible but consumes console space | Full-window operator walkthrough and accessibility checks |
| A4 notice | Countdown; confirm each cut; no countdown | Auto visible cancellable notice; Backup always names the next cut with notice details to be decided | Real cancellation/readability trials; parameter candidates derived from data |
| A2 pin | Program intent; person; pixels | Resolve pin meaning before adding an ambiguous pin control | Operator explanation of what keeps moving and how control returns |

Do not replace these open choices with fixed geometry, a countdown default, a timed usability budget or a screenshot advertised as release evidence. Check launch, each unqualified level, paused/inhibited/abstaining states, subject override, takeover, cancellation, current/next segment and truthful Program/Preview. N2 on-air motion and R2 fallback need separate approved behavior and qualification before their UI can claim active operation.

Mark synthetic gallery states, recorded evidence and live tests distinctly. No live level is qualified by screenshots or replay. UI/logging must preserve no audio, no show network, metadata-only 30-day retention and explicit export; no media collection without E3.
