# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| U1 Director controls location? | Next-shot panel; pill; separate inspector | Next-shot panel under Preview, state always visible | AD-UI | Yes |
| U2 Mode presentation? | Generic Auto; explicit four levels; progressive hidden levels | Explicit levels; Auto Direct shows qualification requirement until approved | AD-UI/TAKE | Yes |

Status: proposed text wireframes, not a rendered/usability-tested UI. 2026-09-30. Existing `ConsoleSnapshot.swift` describes roles/health/control target and `NextShotStatus.swift` reserves the director section but leaves it nil. `TakeAvailability.swift` remains authority for manual Take refusal copy.

## Fit at 1280×800

Retain R2 pane geometry: Preview x24 y64 w600 h338, Program x656 y64 w600 h338; next-shot x24 y414 w600 h70. Use compact two-line layout within that panel, not an overlay on Program. Proposed internal controls are 28 pt high with keyboard/VoiceOver equivalents; accessibility hit-target and truncation verification remains required. Do not shrink video or move Stop/Wide to gain room.

```text
HEADER: Show / standard                                    [Stop show]
PREVIEW · B                             PROGRAM · A · Routed
[actual rendered Preview]               [actual routed frame]

NEXT · B Waist Up          [Auto Prepare ▾] [Pause] [Pin]
Ready · Nominated speaker · Take is manual          [Details]

(existing R2 Take bar, input slots and target-bound operator pill)
```

Proposed next-shot panel layout budget: first-row text 250 pt, mode 130, Pause 64, Pin 48 plus padding/gaps inside 600; second row reason 480 plus Details. Longer content truncates editorial description only, with full accessibility text; never truncate mode, camera identity, fault status or control labels into ambiguity. If localization cannot fit, reduce optional description rather than hide pause.

| State | Panel text / controls |
|---|---|
| Off | `Director Off · Take is manual` + mode selector; no proposal |
| Suggest | `Suggest: B Waist Up · Nominated speaker` + `Prepare` action; no countdown; operator acceptance remains bounded |
| Auto Prepare / preparing | `Preparing B · Waiting for framing to settle` + Pause / Pin |
| Paused by manual Take | `Auto Prepare · Paused by you` + Resume / Pin; prior proposal cleared |
| Pinned | `Pinned Program A · Tracking may continue` + Unpin; unpin leaves paused with Resume |
| Fault pause | `Paused · B source missing` + Details; Resume disabled with explicit reason; manual controls remain usable |
| Edit Live | Persistent Program `EDITING LIVE A` banner; director paused, no resume until Done |
| Later Auto Direct | `AUTO DIRECT · B Waist Up in 3 s` + Cancel / Pin; reason on second row; cancellable countdown only after qualification |
| Cancelled countdown | `Auto Direct · Paused by you` + Resume; never restarts automatically |

Mode dropdown is deliberate configuration, not an emergency override. Pause/Cancel, Pin/Unpin and context-appropriate Resume are inline, always operable without Details. Return to Wide stays the existing single action on the **current control target**; it does not silently widen Program when controls target Preview. Edit Live remains explicit. Stop show stays in the header. A director pause must never block either control.

Director-ready and manual Take-ready are distinct: show `Take ready · Director waiting for identity` when appropriate; do not reuse R2's disabled reason to impose a new manual policy. Program means Alfie's routed output, not ATEM on-air tally. Proposed `DirectorSection` changes are listed in the authority memo; publish them with route revisions in one snapshot.

## Acceptance rehearsal

Proposed starting study: 6 volunteer operators, each completes normal and fault walkthroughs on a 1280×800 window with one hand; repeat with keyboard and VoiceOver. Target zero mistaken Program/Preview actions and all operators locate Pause/Wide/Stop without opening a menu. Proposed identification target ≤3 s for mode/next action, measured from scripted prompt; choose approved budget before running. Test long labels, missing source, denied resume, pending countdown, focus loss and display scaling. Record task success/errors/time, not preference ratings alone. No UI acceptance is claimed by these text wireframes.
