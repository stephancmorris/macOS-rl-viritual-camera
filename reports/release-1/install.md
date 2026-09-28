# INSTALL — volunteer installation and virtual-camera activation

**Status: Not run.** Card: https://trello.com/c/1BH2ecUh

Goal: a volunteer installs Alfie and selects it as a camera without Xcode or a developer. A historical DMG is not proof of the current source: build a fresh candidate.

## Candidate

1. Build with the existing script (`CinematicCoreMacOS/build_release.sh`, Developer ID + notarization; see the distribution notes). Record the printed source fingerprint (`build_out/source-fingerprint.txt`) and the DMG checksum:

   ```
   shasum -a 256 CinematicCoreMacOS/build_out/Alfie.dmg
   ```

| Item | Value |
| --- | --- |
| Source fingerprint | |
| DMG SHA-256 | |
| Notarization ticket stapled (`xcrun stapler validate`) | |
| Clean Mac model and macOS version | |

## Procedure (clean supported Mac, never had Alfie)

| Step | Expected | Result |
| --- | --- | --- |
| Open DMG, drag Alfie to /Applications, launch | Gatekeeper accepts; no "damaged" warning | |
| Camera permission prompt → **Don't Allow**, then relaunch | Alfie explains the missing permission and how to fix it | |
| Grant camera permission in System Settings, relaunch | Camera list populates | |
| Activate the virtual camera (extension approval in System Settings → General → Login Items & Extensions) | Status moves to loaded; wording matches what the OS shows | |
| Deny extension approval once, then approve | Truthful status both times; no silent failure | |
| Select "Alfie" in a client (QuickTime / Zoom / OBS) | Client shows Alfie's program | |
| Quit Alfie with the client open | Client shows standby, not a frozen frame or crash | |
| Install the same build again over the top | Extension stays matched (Inspector → cmio status) | |
| Reboot, launch, select in client | Works without re-approval | |

## Outcome

- [ ] Fresh candidate fingerprint and matched extension recorded.
- [ ] Every permission path gives truthful feedback.
- [ ] Only confirmed paths documented in README.md.
