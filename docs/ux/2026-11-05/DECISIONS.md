# UX decisions — 5 November 2026

Owner decisions are final for this programme. S1 is documentation only; specifications describe acceptance criteria, not implemented or rig-certified behaviour.

| ID | Decided | Rationale |
| --- | --- | --- |
| D1 | Deep navy `#0C2340`, Mist `#E4EAF1` as light secondary; dark appearance is **Navy night**. | A consistent palette gives controls and text a clear contrast hierarchy. |
| D2 | Multiview is forced dark while live. | Stable live-monitor surroundings avoid appearance changes during operation. |
| D3 | On-screen Stop requires about 0.8 s of holding with progress fill; VoiceOver uses a standard action plus confirmation; ⌘⌥⇧S stays. | Protects against stray clicks while keeping accessible and deliberate keyboard paths. |
| D4 | TAKE has no shortcut; bare 1–4 cue Preview. | Fast camera preparation remains separate from the deliberate on-air cut. |
| D5 | Get ready lives on the stopped screen. | Missing setup and its fixes appear at the point where Start needs them. |
| D6 | Pre-Start camera pictures require an explicit **Preview cameras** button, off by default. | Operators choose when physical camera lights turn on. |

## Delegated S1 choices

These are implementation specifications within the brief, not requests to reopen D1–D6: D/W/F/U/]/[ for Detect/Wide/Full Body/Waist Up/Push In/Pull Out; waiting counts as a blocker; at most one readiness fix with no redundant ready-row action; Show expanded and Engineering collapsed; a bounded current-session fault list. Details: [readiness](readiness.md), [faults](faults.md), [Inspector](inspector.md), [keys](keyboard-map.md), [Stop](stop.md), [Webcam](webcam.md).

No new owner decision is required to implement S1. Hardware validation remains outstanding evidence, not a decision that can be replaced by a software test. If a new product choice becomes necessary, record its exact question, options and recommendation here and in the results handoff before coding it.

## Wave 1 state acceptance contract

Review Sol's actual renders and state gallery against this table; post findings on the PR, without pushing to its branch. Existing Wave 0 captures are a baseline, not proof of Wave 1. Hex values below are visual targets only; code uses roles in Sol's `Settings/AlfieAppearance.swift` and the shared `AlfieButtonStyle` family.

| State | Required rendering and behaviour | Accessible state / action |
| --- | --- | --- |
| Resting | At least 11 pt live text; enabled text pairs at least 4.5:1 | Visible name is accessible name; standard button activation. |
| Hover | Navy 6% fill on Mist; primary `#1B3A63`; TAKE `#C40021`; arrow cursor | No state announcement for pointer hover. |
| Pressed | One step darker; no scale effect | Standard pressed interaction; no duplicate action. |
| Focus | 2 pt `accentText` ring, 2 pt outside control, following its radius | Full Keyboard Access focus remains visible and unobscured. |
| Selected | Navy fill/Mist text in light; Mist fill/navy text in Navy night | Selection announced as selected; toggles say on/off and differ in shape. |
| Disabled | `#6E7C91` on Mist; `#7B8796` on navy; no text opacity | Disabled state plus a persistent reason in `secondaryText`; do not hide the reason only in hover help. Existing disabled contrast floor is 3:1. |
| Increase Contrast | Double borders; tertiary text becomes secondary; focus ring 3 pt | Same names, actions and state, no information lost. |
| Reduce Transparency | Drawer and pill become opaque | Text remains readable over bright and dark footage. |
| Reduce Motion | No pulse, flash or slide | Persistent words/shape carry changes; timed Stop remains usable. |
| Differentiate Without Colour | Lock glyph added to lock dot | “Locked” remains spoken; no duplicate decorative-symbol announcement. |

Check light and Navy night, a forced-dark live Multiview, enabled/disabled/reason/hover/pressed/focus/selected combinations, long copy and narrow layouts. Render evidence must name the PR head and settings used. A static image cannot verify cursor, keyboard focus movement, announcements, motion reduction or an actual receiver; label those as interaction or rig checks still required. Never turn an unseen state into a pass.

## Programme boundaries

Wave 1 foundations (UX-F2 palette, UX-F3 shared buttons and hold-to-stop, UX-F4 accessibility) belong to Sol. Astra reviews Sol's UX-KEYS, UX-F2, UX-F3, UX-F4 and UX-M3 PRs. Track C belongs to Astra: first run, mode picker, Single Cam faults, Inspector and Settings. New-file Track C preparation may begin after UX-F3 merges; existing view integration waits for UX-F4 to merge. Track A also belongs to Astra after Track C, unless Sol has already claimed it through a UX-TA PR. Track B belongs to Sol. Each journey gets its own tagged PR; Sol reviews Astra's journeys and Astra reviews Sol's Track B. Claude performs the final review of main after both tracks finish. Settings already has an Advanced grouping in the baseline: preserve it at the foot, complete per-page confirmed Restore defaults and search coverage rather than adding a duplicate group. No automatic TAKE, authority/qualification/DeveloperFlags changes, rig certification or Trello Done transition is authorised by this programme.

Assignment updated by the owner on 6 November 2026. The original D1–D6 decisions and state acceptance criteria remain in force.
