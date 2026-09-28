# Alfie privacy and diagnostic data audit

Status: source review on `r2/sol`, 28 September 2026. Runtime permission, export, and fresh-install checks remain open. This is an engineering inventory, not a store disclosure approval.

## Data flow in the current build

| Data | Source and use | Persistence | Destination |
| --- | --- | --- | --- |
| Live camera frames | `CameraManager` captures; `PersonDetector`, `FaceSignatureExtractor`, `ShotComposer`, and crop/output code process locally. | Live buffers and recent rendered frames are retained in memory while needed. Ordinary capture does not write raw frames to a file. | The selected Program output is intentionally sent to a local virtual-camera consumer or Program Display. A connected display/switcher can carry the picture beyond the Mac; Alfie does not control downstream recording. |
| Subject identity evidence | `FaceSignatureExtractor` makes Vision feature prints and landmarks for lock/reacquisition. | The gallery is held in process memory for the lock. No feature-print file writer was found. | Used within the app; no network transfer was found. |
| Camera/device names and format | Capture selection and setup; the source identity includes device name/model, profile, requested and delivered size/rate. | Per-session `alfie_session_*.json` manifest; training-data `metadata.json` when recording is consented. | Local app-container Documents until the user exports or shares the files. |
| Session diagnostics | `DiagnosticsLog` writes build/source fingerprint, OS/machine, route, stage counters, timing, thermal/memory samples, and bounded text notes. `ProgramOutputManager` also writes a text log with error/diagnostic messages. | `CinematicCore/Diagnostics/alfie_soak_*.csv`, `alfie_memory_*.csv`, `alfie_session_*.json` under the sandboxed Documents directory; `Library/Logs/Alfie/alfie-diagnostics.log`. | Local files. Notes and error descriptions may contain device names, session IDs, or file paths; inspect any export before sharing. |
| Optional training observations | `TrainingDataRecorder` requires its explicit consent flag before starting. It writes frame time/index, subject box/position/confidence, keypoints, current and ideal crop, and configuration. It does not write camera pixels in this code path. | `CinematicCore/TrainingData/session_*/frames.jsonl` and `metadata.json` in sandboxed Documents. | Local until user shares. These observations can still describe identifiable people and deserve the same care as image data. |
| Preferences and admission records | `UserDefaults` stores consent, show/display and camera choices, extension state, framing headroom, and pair-admission records. | App defaults/container. | Local; no app network transport found in the reviewed Swift sources. |

The app has no `URLSession`/Network framework upload path in the reviewed application Swift sources. This supports **no automatic app upload**; it does not mean the Program video cannot leave the Mac through a virtual-camera consumer, external display, or switcher, nor that an operator cannot share a diagnostic file.

## Retention and cleanup

- `DiagnosticsLog.beginSession` requests a 30-day prune of **CSV files** in the Diagnostics directory. It does not prune `alfie_session_*.json` manifests or the separate `Library/Logs/Alfie/alfie-diagnostics.log`. The prune runs when a new diagnostics session begins, not continuously.
- `TrainingDataRecorder` defaults to 30 days and deletes expired `session_*` directories when a new consented recording begins. Existing recordings can remain longer if recording is not restarted. A manual delete-all method exists.
- In-memory identity evidence is not written by the face extractor, but the retention/clear path on every Stop, Wide, crash and relaunch needs a runtime check.
- A diagnostic export can include device names, host/build identity, timestamps, notes and errors. Check the actual file set before it is attached to support correspondence.

## Consent and declarations

- The app target's generated Info.plist sets `NSCameraUsageDescription` to “Alfie needs camera access to capture and process video frames for the virtual camera system.” This explains capture but should be reviewed with an operator for Stage/Program Display terminology and the downstream destination. The sandbox entitlement includes camera access. Permission refusal and later revocation still need a fresh-install test.
- Training-data recording has a separate stored consent flag and start guard. Verify the UI copy, its reset path, and that revocation stops active recording during a manual exercise.
- `PrivacyInfo.xcprivacy` declares the source-observed required-reason categories: `UserDefaults` (`CA92.1`, app preferences), `contentModificationDateKey` (`C617.1`, cleanup of files in the app container), and `ProcessInfo.systemUptime` (`35F9.1`, elapsed-time/expiry calculations). No disk-space or active-keyboard access was found. The manifest marks tracking false and collected-data types empty because no app-initiated off-device collection path was found; validate this against the release binary and all bundled components before submission.
- Source references: [Apple privacy manifest overview](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [Apple required-reason API categories and reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Open release checks

1. Exercise camera permission denied and revoked, then inspect logs and retained files from a fresh install.
2. Verify the app bundle contains `PrivacyInfo.xcprivacy` and generate Xcode's privacy report for the complete archive, including the CMIO extension and dependencies.
3. Decide and implement retention for manifests and the text log; the present 30-day CSV prune does **not** cover them.
4. Export a real session and confirm that it contains no unintended imagery or identity vectors, and that names/paths/notes are suitable for explicit sharing.
5. Recheck App Store Connect disclosures and Apple's current rules at submission time. No store approval or on-rig consent result is claimed here.
