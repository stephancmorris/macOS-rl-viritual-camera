# Alfie repair implementation — 6 September 2026

The source repairs are implemented and validated by the automated suite and Debug/Release builds. Matched raw-camera replay and live hardware certification remain pending the original camera footage and an available capture/ATEM setup. The supplied movies are recordings of different Alfie sessions, so they cannot provide a controlled before/after replay comparison.

This supersedes the original diagnosis’s “no fixes applied” status. The diagnosis remains an archival record of the inspected August source; its line-number references describe that version.

## Changes completed

| Area | Result |
|---|---|
| Locked subject matching | Ordinary matching cannot reuse the locked UUID after the locked policy rejects a candidate for distance, body size, or probation. Missing candidates reset consecutive probation. |
| Observation/frame pairing | Each detection owns its original pixel buffer, capture time, source presentation time and observation ID. Identity extraction uses those pixels. Repeat observations do not add evidence; observations expire after 500 ms. Older results cannot replace newer ones, including after expiry. |
| Reacquisition evidence | All visible faces are scored as one observation batch. Recovery requires three distinct, increasing observations, with distance, landmark and margin checks. Missing, ambiguous, stale and failed evidence resets confirmation. A landmark-rejected bystander cannot relax the single-candidate threshold. |
| HOLD recovery | Full-frame face recovery runs during HOLD, so a returning speaker with a new body UUID can recover before the ten-second wide fallback. The intentional ten-second crop hold remains. |
| Acquisition | Eight-second overall deadline; missing-subject grace uses the last actual observation capture time. Active gallery progress and retry feedback explain incomplete acquisition. |
| Lifecycle | Session/target generations invalidate stale detector and identity work. Capture admission uses leases, preventing an old frame from unlocking or entering a new capture session. Playback and render completions are guarded against replacement sessions. |
| Steady Follow | Band width is relative to the program crop, with matching yellow guides and explanatory settings text. Exit/settle confirmation uses fresh observation capture time (40/240 ms), not display frame counts. Spring gains remain unchanged. |
| Framing/UI | Wide ≥ Full Body ≥ Waist Up at the crop caps. Labels use the actual stage/webcam preset. Recovery shows the last known subject position, and operator controls distinguish HOLD/recovery from waiting wide. Subject boxes no longer imply an identity-confidence percentage. |
| Capture/output rates | Capture requests the selected duration within the supported range, including exact 60000/1001 timing. The extension advertises 50/59.94/60 support. Frames wait for a connection-scoped rate acknowledgement. Delayed replies/errors from retired XPC connections cannot alter a replacement connection. |
| Session standard | The show standard is frozen at session start and reused for capture, reconnect and display checks. Settings changes apply to the next session. |
| Replay clock | Validation clips use absolute presentation deadlines, avoiding the previous accumulation of processing time into every frame interval. |
| Diagnostics | Real completed detection duration, observation age, main-actor active work, whole-frame elapsed time, detector cadence, processed-input cadence and output handoff cadence are separate measurements. The final partial window is flushed on stop. Logs include build/source identity and capture settings. |
| Build provenance | Release builds embed a SHA-256 fingerprint of source/build inputs, including uncommitted edits, and save it beside release output. An ordinary build without that value reports “unrecorded.” |

The existing off-main rendering and memory-management changes were preserved. No spring-speed retuning or claim of sub-150-ms end-to-end tracking latency is made from the screen recordings.

## Verification completed

- **52 tests passed, zero failures or skips.** Two parameterized tests produce six runs, giving **56 executed cases**. Coverage includes actual locked-tracker assignment, identity batches, source-buffer retention and expiry, acquisition timers, preset ordering, Steady Follow settling/exit at 25/50/60 fps, replay deadlines, output acknowledgement and capture restart leases.
- Debug application/extension/test build passed, followed by the unit suite.
- Release application and embedded extension build passed with signing disabled and build output isolated under `/tmp/alfie-fixes-release`.
- Release Info.plist was read back and its fingerprint verified:
  `a809490d5d7a3ad948fafc3a63d6ddd612d274cd1eba836cf049454d6c6ab765`.
- Release script syntax passed `bash -n`; the script was not executed to package or publish.
- Source diff whitespace checks passed. Pre-existing modifications in `build_out` were preserved; their historical packaging-log whitespace is unrelated to these repairs.

Xcode’s structured result counts logical tests separately from parameterized executions. Evidence is in `implementation-evidence/unit-tests.log`, `implementation-evidence/test-summary.json`, and `implementation-evidence/release-build.log`.

Builds still report existing warnings about the system-extension embedding classification and, on a full compile, the retained CVPixelBuffer crossing the render queue and a redundant CIContext isolation annotation. Passing unsigned builds do not certify signed installation or downstream consumers. UI automation and a physical-device soak were not run.

## Remaining runtime validation

1. Use the **same original camera file**, identical settings and identical subject-selection time for the August baseline and repaired build. In Session Source choose Validation Clip, choose the file, enable Crop, then Start Session. Include a walking subject, a projected/background person, brief occlusion, loss/return after the old one-second UUID lifetime, and a face turned away. Compare subject identity, observation age, visible crop-center error and output cadence. The supplied interface recordings remain visual evidence, not suitable raw inputs for this comparison.
2. Test the actual card at 50, 59.94 and 60 fps. Check both Program Display/HDMI/ATEM and virtual-camera consumers. Change the saved standard mid-session and verify it takes effect only after restarting. Restart/reconnect the extension during each rate test.
3. Install the app and extension from the same signed build: the rate-setting XPC method now includes an acknowledgement, so an older extension is not a compatible test counterpart. Existing distributed app files were not replaced by this work.
4. Run a **60-minute soak** with detection active, repeated loss/recovery, and the normal output route. Inspect footprint trend, gate drops, detector rate, observation age and main-active versus frame-wall duration. Treat `processed_input_fps` as admitted frames, and `handoff_fps` as host sends, not proof of physical output/display cadence. `vision_*` records end-to-end detection request duration, including its queue/return wait; it is not isolated CPU execution time.

These runtime checks require footage/hardware that was not confirmed available. No live-output, long-session, or signed-release certification is implied by the automated results.

## Reproduce the build checks

From the repository root:

```sh
python3 CinematicCoreMacOS/scripts/source_fingerprint.py
xcodebuild -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/alfie-fixes-build CODE_SIGNING_ALLOWED=NO \
  test -only-testing:CinematicCoreMacOSTests
```

For a traceable build, also pass `ALFIE_SOURCE_FINGERPRINT=<the printed hash>`. The release script supplies that setting automatically.
