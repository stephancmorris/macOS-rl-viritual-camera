# Multiview UI gallery captures

These are 1280-point offscreen SwiftUI captures of the INPUT-STRIP, SHOW-SETUP and PILL-TARGET gallery states. Input scenarios use `FakeConsoleModel`; setup results use the fake `ShowSetupModel.PairCheckResult` sequence. Tiles intentionally have no rendered camera pictures until the channel image provider is integrated.

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
