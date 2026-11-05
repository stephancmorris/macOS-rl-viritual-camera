# Claude Wave 1 results (UX F2, F3, F4)

6 November 2026. The owner reassigned Wave 1 from Sol 6.1 to Claude Opus 5.5 while Sol was out of usage. Tags and gates are unchanged:
- **Sol:** UX-KEYS and UX-M3, then Track B once UX-F4 is merged.
- **Astra:** Track C once UX-F4 is merged, then Track A. New-file prep could start once UX-F3 was merged.

This file is the trail for the final review.

| Tag | PR | Merge commit | Local suite (Xcode 27.1, serial) | Hosted CI (Xcode 26.2) |
| --- | --- | --- | --- | --- |
| UX-F2 | [#117](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/117) | `b6fc858` | 1,238 of 1,239. `ShowSetupTests.stayingInMultiCamStartsTheSelectedCameraBOnceAfterA` timed out once; it passed 3 of 3 on its own and F2 doesn't touch setup | Passed |
| UX-F3 | [#118](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/118) | `b4b7197` | 1,257 of 1,257 | Passed |
| UX-F4 | This PR | Its merge commit | 1,261 of 1,261 | On this PR |

## What Tracks A, B and C get

- **Palette** (`Settings/AlfieAppearance.swift`):
  - Mist and Navy night, with every value pinned by `paletteMatchesMistAndNavyNight`.
  - **Navy night danger is FF6961.** FF453A is only 3.8:1 on the control fill.
  - The accent is navy in Light and Mist in Navy night, with `onAccent` the opposite.
  - D2: `LiveConsoleAppearance` keeps the live Multiview console dark.
- **The button family** (`Settings/AlfieButtonStyle.swift`):
  - Apply it with `.alfieButtonStyle(role, surface:, isSelected:, cornerRadius:)`. Roles: `primary`, `secondary`, `quiet`, `destructive`, `refusing`, `tallyTile`, `segment` and `toggle(isOn:)`. Surfaces: `chrome` and `video`.
  - Use `alfieUnavailableReason(_:)` for a disabled control's reason.
  - Snapshots force a state with `alfieForcedControlState`.
- **Rules that came out of the contrast tests:**
  - Text inside a control uses `text` or `secondaryText`, never `tertiaryText`.
  - A control with its own ground applies that ground **outside** the style (`.alfieButtonStyle(…).background(…)`), so the hover and press washes sit behind its label.
- **Hold-to-stop** (`Settings/AlfieHoldToStopButton.swift`): build it with `AlfieHoldToStopButton(confirmationMessage:stopFailed:onStop:)`.
  - Pass the confirmation line from `stop.md`'s route table.
  - Set `stopFailed` when the lifecycle reports a failed stop.
  - The timing lives in `HoldToStop`.
  - Track A replaces the pill's Stop with it, and Track B the console header's.
- **Display settings** (`Settings/AlfieDisplayPreferences.swift`):
  - Store `private let display = AlfieDisplay()` in a view and read `reduceMotion`, `reduceTransparency`, `differentiateWithoutColor` or `increaseContrast`.
  - Snapshots set `alfieDisplayOverride`.
  - `PillLockIndicator`, `OperatorPillBackground` and `InspectorDrawerBackground` already honour them.
- **11 pt floor:** `TypeFloorLintTests` fails on any size below 11 pt, including `.caption`, `.caption2` and `.footnote`, outside `Console/Gallery/`, `*Demo.swift` and `Director/UI/`.
- **Gallery:**
  - `buttons-light.png` and `buttons-dark.png`: every member in every state, plus the hold-to-stop phases.
  - `a11y-<setting>-<look>.png`: one per display setting.
  - The existing captures, regenerated.

## Done ahead of the tracks

These came out of adopting the family, so the tracks needn't repeat them:
- **J7.3:** Edit Live is a navy outline at rest.
- **J4 (partly):** Crop, Manual and Auto Pan are toggles with an on/off indicator, and the active shot segment shows as selected.
- **J2.3:** an unavailable mode's reason stays at secondaryText.
- **J10.4:** the drawer is opaque under Reduce Transparency.
- **J11.1:** the Settings sidebar is tinted.
- **J7.4:** the TAKE refusal is a steady highlight under Reduce Motion.

## Left alone, and why

- **Debug-only Director views** (`DirectorModeControl`, `DirectorSubjectPickView` and the rest of `Director/UI/`) keep their look and sizes. Journey 13 is limited to the colour pass this round.
- **The Edit Live banner's white "Done" capsule** stays as it is. Track B's J8 reworks the banner.
- **System `.link`, `.borderless` and `.bordered` buttons and `Menu`s** keep their system styles.

## Not verified by software

These are attended checks on the running app:
- the pointer, real hover and Full Keyboard Access focus traversal;
- VoiceOver output for the hold-to-stop confirmation and toggles;
- each display setting with the **real** macOS switch on. macOS won't build the high-contrast appearance by name, so Increase Contrast's token values are checked through the resolver, not a render;
- system controls inside the forced-dark live console;
- the rig itself.

## Owner questions

None.
