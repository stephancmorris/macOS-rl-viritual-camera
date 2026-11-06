# Operator keyboard map

S1 assignment · 5 November 2026. Covers every `AlfieCommandCatalog.ID` at `3dd0d2d`. These are final spec assignments, not a claim that the six pending keys are already installed.

## Commands

Bare keys below mean **no modifier**. Show them in the menu as “Detect (key D)”, for example; the catalogue stores lowercase characters. Do not register bare characters as SwiftUI menu key equivalents: the existing `AlfiePlainKeyRouter` must dispatch them only when the responder is not typing.

| ID | Menu › command | Key | Availability / accessible result |
| --- | --- | --- | --- |
| `singleCam` | Session › Single Cam | ⌘1 | Stopped, available mode only. “Single Cam selected. {camera name} will start.” |
| `multiCam` | Session › Multi Cam | ⌘2 | Stopped, available mode only. “Multi Cam selected.” |
| `webcam` | Session › Webcam | ⌘3 | Stopped, available mode only. “Webcam selected. {camera name} will start.” |
| `detect` | Session › Detect | **D, bare** | Current editable camera when detection can start. “Detecting people.” |
| `cancel` | Session › Cancel Detect / Done Editing Live | Escape, bare | One published action for the current operation. “Detection cancelled.” / “Finished editing live.” |
| `stopSession` | Session › Stop Session | ⌘⌥⇧S | Running session. “Stopping session.” See [Stop](stop.md). |
| `wide` | Shot › Wide | **W, bare** | Current editable camera. “Wide selected for {target}.” |
| `fullBody` | Shot › Full Body | **F, bare** | Current editable camera. “Full Body selected for {target}.” |
| `waistUp` | Shot › Waist Up | **U, bare** | Current editable camera. “Waist Up selected for {target}.” |
| `pushIn` | Shot › Push In | **], bare** | One permitted push step. “Push In applied to {target}.” |
| `pullOut` | Shot › Pull Out | **[, bare** | One permitted pull step. “Pull Out applied to {target}.” |
| `cuePreview1` | Multi Cam › Cue Preview 1 | 1, bare | Available input 1. “Cam A cued in Preview.” |
| `cuePreview2` | Multi Cam › Cue Preview 2 | 2, bare | Available input 2. “Cam B cued in Preview.” |
| `cuePreview3` | Multi Cam › Cue Preview 3 | 3, bare | Available input 3. “Cam C cued in Preview.” |
| `cuePreview4` | Multi Cam › Cue Preview 4 | 4, bare | Available input 4. “Cam D cued in Preview.” |
| `take` | Multi Cam › TAKE | **None, deliberately** | Existing eligibility/refusal only. No auto-Take. On success “{camera} is on Program.” |
| `showInspector` | View › Show Inspector / Hide Inspector | ⌥⌘I | Main operator scene. “Inspector shown.” / “Inspector hidden.” |
| `directorHand` | Director › Hand to Alfie | ⌘⇧H | Debug only, existing authority and eligibility unchanged. Announce actual result/refusal; never claim a handover merely because the key was pressed. |
| `directorAdvance` | Director › Advance Run Sheet | ⌘⇧Return | Debug only, existing availability. “Run sheet advanced to {segment}.” No automatic TAKE. |

`{target}` is “Cam A, Program” or “Cam B, Preview”, as applicable; explicitly say “live Program” when editing live. Do not announce a successful shot change if the operation was refused. Keep the reason beside the relevant control and announce that reason once.

D means Detect; W/F/U name the three shots; left/right brackets make a paired Pull Out/Push In control. They avoid commandeering standard editing and application shortcuts. The key match is a character, not a hardware position: on layouts that require a modifier to produce brackets, use the menu or button. Layout-independent custom bindings would be separate work, not an unstated guarantee.

## Typing and focus contract

**No bare operator key fires while typing.** That includes D/W/F/U/[ /], digits 1–4 and Escape. `AlfiePlainKeyRouter` already protects bare characters for `NSText`, `NSTextField`, secure fields, `NSTextInputClient`, text-control descendants, wrong windows, modal/sheet windows, repeats and modified events. Its match is catalogue-driven and already supports letters/brackets once assigned; it is not limited to digits in code. Retain these guards and add coverage for all six assignments, SwiftUI TextField/TextEditor, search and run-sheet fields. With Caps Lock, behaviour must be explicit/tested; do not quietly add Shift aliases.

**Escape needs the same responder protection before publication.** M2 currently gives Escape a menu key equivalent; the plain-character router does not guard that path. The command owner must ensure Escape stays with text composition, text controls and modal/sheet cancellation, and never invokes Cancel Detect/Done Editing Live while typing. This is an implementation acceptance requirement, not a claim already proven by M2's digit tests.

Each screen publishes only its applicable independent focused values, and withdraws them when unavailable. Enter/Space on a focused button are normal control activation, not extra global shortcuts. Bare repeated key events do not repeatedly zoom or cue. Start, setup, restore-defaults and chooser actions remain keyboard reachable through normal focus; they are not additional catalogue IDs in S1.

Whoever publishes a command must set its key and clear `keysPending` in `AlfieCommandCatalog` **in the same PR**, with catalogue/router tests. Coordinate that small change with Sol, who owns those files; do not duplicate keys in view handlers. S1 itself is docs only.

## Collision check

Compared all 19 entries above as `(key, modifiers)` against the current catalogue's reservations. The six assignments are distinct and bare, so collide with none. Retained Stop, Director hand and Advance match only their allowed owners. ⌘1/2/3 differ from bare Preview 1/2/3. Inspector is ⌥⌘I, not ⌘I.

Catalogue reservations checked: ⌘Q/W/comma/H/M/N/O/S/P/F/G/A/C/V/X/Z/Space/Tab/Delete; ⌘⇧Z/G/P/S/N/slash/Tab; ⌘⌥H/W/M/Space; ⌘⌥Escape; ⌃⌘Q/F; plus the three Alfie-owned combinations above.

Also checked [Apple's Mac keyboard shortcuts](https://support.apple.com/en-us/102650) and [keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards): leave Spotlight, app/window switching, Dock, screenshots, Mission Control, accessibility controls, Force Quit, Lock Screen and text editing intact. Finder-only combinations are scoped to Finder; Alfie's bare characters remain scoped to its operator surface. User-assigned global shortcuts and non-US layouts need an attended check, not a universal no-conflicts claim. Neither new shortcuts nor a router should intercept Control–Option VoiceOver commands.

Acceptance evidence: catalogue coverage/uniqueness/reservations; real menu labels; unavailable focused values; typing/composition/secure fields; sheet/modal/window isolation; keyboard layouts; VoiceOver and Full Keyboard Access; explicit proof that 1–4 only cue and TAKE has no key. Check the retained Stop shortcut on the running app after Sol's publisher fix.

## Installed router policy (UX-KEYS, 6 November 2026)

The six assignments are installed before publication; all `keysPending` flags are clear. Letters appear uppercase in menu labels, while the catalogue stores lowercase. Bare keys, including Escape, have no native menu equivalent. The router checks the current responder for every event, including ancestor text clients, and leaves the original event untouched for typing/composition, sheets, alerts, modal windows, absent actions and repeats.

Caps Lock enables the same D/W/F/U actions from uppercase letter events. Shift (with or without Caps Lock) never invokes a bare command; brackets remain character matches with no modifier alias. No hardware-position aliases are added. Publishers withdraw `cancel` when Detect/Edit ends or another operator transient owns Escape, and recheck validity in the action.
