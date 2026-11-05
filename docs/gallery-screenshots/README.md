# Multiview UI gallery captures

The input, setup and pill files below are **synthetic**. They are 1280-point offscreen SwiftUI renders of the gallery's fake models, not photographs of a live show, a camera, or a receiver. `MultiviewGallerySnapshotTests` draws each named state on its own (the on-screen demos show every state at once) and writes these names when `ALFIE_GALLERY_SNAPSHOTS=1`. Input rows use `FakeConsoleModel`. Setup rows use `ShowSetupModel.gallery`. Pill rows use `PillDemo` with that fake console. Tiles have no camera pictures.

## Input strip

| Scenario | Capture |
| --- | --- |
| Ready | [input-ready.png](input-ready.png) |
| Preparing | [input-preparing.png](input-preparing.png) |
| Unsupported | [input-unsupported.png](input-unsupported.png) |
| Preview missing | [input-missing.png](input-missing.png) |
| Program hold | [input-programHold.png](input-programHold.png) |
| Program standby | [input-programStandby.png](input-programStandby.png) |
| Edit Live | [input-editLive.png](input-editLive.png) |
| One input | [input-oneInput.png](input-oneInput.png) |
| Two inputs after Take | [input-twoInputs.png](input-twoInputs.png) |
| Four-input layout preview | [input-fourInputs.png](input-fourInputs.png) |

## Show setup

| Pair check | Capture |
| --- | --- |
| Not run | [setup-not-run.png](setup-not-run.png) |
| Checking | [setup-checking.png](setup-checking.png) |
| Pass · trial | [setup-pass.png](setup-pass.png) |
| Unsupported | [setup-unsupported.png](setup-unsupported.png) |

## Control states

`StateGallerySnapshotTests` draws the controls whose states carry meaning in both appearances, from the `AlfieColor` roles: mode picker (all available, Multi Cam disabled), TAKE (eligible, refused with its reason, Edit Live on), the pill's lock states and Stop, tracking and tally chips on footage, and the text roles. `AlfieColorContrastTests` holds each pair to contrast.

| Appearance | Capture |
| --- | --- |
| Light | [states-light.png](states-light.png) |
| Dark | [states-dark.png](states-dark.png) |

### Button family

Every member of `AlfieButtonStyle` (UX F3) appears in five states: rest, hover, pressed, focus and disabled. They're drawn on the window chrome and on the pill's glass, and the sheet ends with the hold-to-stop phases. Hover, pressed and focus are forced with `alfieForcedControlState`.

| Appearance | Capture |
| --- | --- |
| Mist | [buttons-light.png](buttons-light.png) |
| Navy night | [buttons-dark.png](buttons-dark.png) |

### Display settings

There is one capture per macOS display setting (UX F4), forced with `alfieDisplayOverride`. Each shows the same elements: the text roles, an outline, a focused button, hold-to-stop at 60%, and the pill's lock dot and the drawer over a bright stripe. Increase Contrast's token values (stronger tertiary text and borders) switch only with the real system setting. `AlfieColorContrastTests` checks them; this capture shows the 2 pt outline and 3 pt focus ring.

| Setting | Mist | Navy night |
| --- | --- | --- |
| Standard | [light](a11y-standard-light.png) | [dark](a11y-standard-dark.png) |
| Increase Contrast | [light](a11y-increase-contrast-light.png) | [dark](a11y-increase-contrast-dark.png) |
| Reduce Transparency | [light](a11y-reduce-transparency-light.png) | [dark](a11y-reduce-transparency-dark.png) |
| Reduce Motion | [light](a11y-reduce-motion-light.png) | [dark](a11y-reduce-motion-dark.png) |
| Differentiate Without Colour | [light](a11y-differentiate-without-colour-light.png) | [dark](a11y-differentiate-without-colour-dark.png) |

## Operator pill

| Target | Capture |
| --- | --- |
| Current single camera | [pill-single.png](pill-single.png) |
| Camera B Preview | [pill-preview.png](pill-preview.png) |
| Camera A editing live | [pill-editing-live.png](pill-editing-live.png) |

## Director

C-01 gallery cards for every director state, using `NextShotStatus.DirectorSection` sentences. A level without a qualification record is greyed out and reads "not qualified". Every launch card is `atLaunch`. The Auto notice uses a 2 second fixture; that length is not a product default. The run sheet strip is the recommended layout; its format is still open. Controls are shown, not wired. Two contract lines have no typed reason yet and are not shown: "Program lost: Take Cam A?" and "Both inputs stale".

| State | Capture |
| --- | --- |
| Launch · Manual | [director-launch-manual.png](director-launch-manual.png) |
| Qualified rig · still Manual | [director-qualified-still-manual.png](director-qualified-still-manual.png) |
| Assist · preparing | [director-assist-preparing.png](director-assist-preparing.png) |
| Assist · nothing to prepare | [director-assist-safe-wide.png](director-assist-safe-wide.png) |
| Paused · you took over | [director-paused-takeover.png](director-paused-takeover.png) |
| Inhibited · adjusting the shot | [director-inhibited-adjusting.png](director-inhibited-adjusting.png) |
| Abstaining · nothing better ready | [director-abstaining.png](director-abstaining.png) |
| Auto · next cut notice | [director-auto-notice.png](director-auto-notice.png) |
| Auto · holding your cut | [director-nudge.png](director-nudge.png) |
| Backup · next cut, no countdown | [director-backup-next.png](director-backup-next.png) |
| Backup · paused after fallback | [director-backup-fallback.png](director-backup-fallback.png) |
| Paused · camera lost | [director-source-lost.png](director-source-lost.png) |
| Paused · editing Program live | [director-edit-live.png](director-edit-live.png) |
| Run sheet · panel | [director-run-sheet.png](director-run-sheet.png) |
