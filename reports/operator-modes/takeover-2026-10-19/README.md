# Operator modes takeover — 19 October 2026

Reviewed MODES-SPEC, MODE-MODEL, SINGLE-CAM and MODE-SWITCH on `r2/modes/spec-and-model`, inherited commits `21025af`, `83137a3`, `7d78324`, `05ecb92`, based on main `39e05d2`.

Review found a pair-start race: while setup awaited Camera A's start, changing to Single Cam or Webcam could allow the old task to create and start hidden Camera B afterward. Leaving Multi Cam now cancels the setup intent; stale actions and continuations recheck cancellation and mode. Returning to Multi Cam cannot revive that intent. The production start path remains unchanged when Multi Cam stays selected.

Four new regression definitions / seven executions cover suspended start, both single-input destinations, switching away and back, stale actions and a successful pair-start control. All use synthetic device proposals and an injected B-start callback; no camera opens even if a regression occurs. Discovery continues to consume the publisher's emitted camera list.

## Verification

| Check | Result |
| --- | --- |
| Inherited full unsigned Debug unit target | 699 passed definitions / 975 executions; 0 failures; 3 inherited opt-in skips |
| Full target after initial race repair | 702 passed definitions / 981 executions; 0 failures; 3 inherited opt-in skips |
| Final affected setup/mode suites, including positive pair-start control | 49 passed definitions / 55 executions; 0 failures or skips |
| Unsigned Release app and extension build, final source | Passed |
| Python diagnostics report tests | 5 passed |
| Diff whitespace check | Passed |

Xcode 26.2; arm64 macOS 27.0.1. Local logs/results are under `/private/tmp/alfie-takeover-20261019`: `modes-unit`, `modes-repaired-unit`, `modes-final-targeted` (`.xcresult` and `.log`), and `modes-release.log`. Final build-input fingerprint from `CinematicCoreMacOS/scripts/source_fingerprint.py`: `70dc713e03a477c537b956166c73fe89dd9374736034a67489e41c803a04120e`.

## UI observations and remaining acceptance

The running unsigned Debug candidate at inherited `05ecb92` showed Single Cam, Multi Cam and Webcam in the correct order on both stopped surfaces and Settings. Mouse selection changed screens and Settings reflected the same mode. The native accessibility tree exposed the Mode label, all three selected states and descriptive hints. The screenshots here are from that candidate, before the startup-only repair. The observed main window was 1280×832 logical points; inherited automated renders separately check 1280×800.

Tab/Right attempts on this host did not obtain keyboard focus in the segmented picker. Mode-picker keyboard acceptance and spoken VoiceOver remain pending; accessibility-tree presence alone does not establish them. Selection was restored to Single Cam, and the candidate was quit. No Start or camera/output command was requested during this UI walkthrough.

MODE-QA remains pending the real rig: signed Debug/Release at one commit, actual cameras and downstream routes, live-switch matrix, migration/relaunch, mode soak and attended accessibility checks. Synthetic unit results and unsigned stopped-screen observations do not complete that card.
