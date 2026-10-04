# Hardware effect-clock repair — 4 October 2026

Card: https://trello.com/c/jXVfx5xG. Managed worktree `/Users/stephanmorris/.codex/worktrees/alfie-quality-sprint/macOS-rl-viritual-camera`, branch `codex/alfie-quality-sprint-2026-10-04`. Started after voice identity commit `237d66cc87772d1b0c74c2302d8c12b5c40b498d` with a clean worktree. Changes are confined to `SimulatedHardwareDevice.swift`, `HardwareLinkTests.swift` and this report. Primary checkout and other work were preserved. The commit and Trello delivery record are included in the overall quality sprint report.

## Source finding and reproduced failure

The initial finding was a static source trace, not test evidence: `apply` checked the watchdog before observing its later effect time, then could refresh a heartbeat at that later time without reevaluating the watchdog. The priority-estop branch captured negotiation before a later batch-time observation and could likewise treat an expired session as current.

Regression tests were added before any production change. The unchanged simulator then reproduced both defects in `/private/tmp/alfie-followup-hardware-baseline.xcresult`; xcodebuild exited 65 and reported TEST FAILED. At device time zero a fresh negotiation connected disarmed and accepted a heartbeat. Current-session records were prepared before arming the raw-clock schedule, with expiry 0.4 and the next valid sequence.

- Wire and direct heartbeat admission sampled `[0.29, 0.29, 0.29, effectTime]`, then held the final time. At both `effectTime=0.3` (the exact heartbeat deadline) and 0.31, the baseline renewed health instead of faulting. The wire log explicitly records an accepted sequence-2 ACK.
- A coalesced heartbeat / estop / reset batch sampled `[0.29, effectTime]`. At 0.3 and 0.31 the baseline prioritized and latched the estop from the expired session, with an out-of-order negative ACK, instead of rejecting the retired context as late data.
- A heartbeat effect at 0.299 remained accepted and healthy at 0.3. A priority estop at batch time 0.299 still outranked its heartbeat/reset peers and latched. All 29 existing definitions passed on the baseline.

Three new boundary definitions failed in six parameter runs. The fourth new definition and the timely priority parameter passed. This expected-failing bundle is preserved separately and is not final pass evidence.

## Repair and preserved behavior

The existing watchdog predicate now has a private `checkLink(at:)` entry point for an already validated clock observation. The public polling API retains its original time observation. `apply` checks the watchdog against its existing effect-time sample and confirms that its admitted negotiation remains current before any effect. `receiveWire` checks its existing batch-time sample before capturing the negotiation used by priority-estop admission. Neither path adds another clock read.

A heartbeat at or beyond the deadline faults with `heartbeatLost`, revokes the session and refuses old-context traffic as `.late`; it cannot grant health. Correlated sequence admission remains before expiry/effect refusal, and watchdog revocation still resets the retired session sequence. Existing duplicate/gap consumption, handshake/connect, reboot/reconnect, version mismatch, invalid-clock, framing and e-stop regressions pass unchanged. Timely current-session estop retains batch priority and its negative sequence ACK behavior. Direct local `emergencyStop()` remains unconditional, including after stream-session expiry.

The simulator continues to negotiate `motion=false`, has no armed transition, and reports `driveEnabled=false`. This repair changes only isolated simulated protocol admission. No running-app integration, transport, firmware, entitlement, target selection, physical motion or stopping qualification is implemented or established.

## Verification

All runs used Xcode 26.2 (17C52), arm64 macOS 26.6.2 (25G83), one host, `-parallel-testing-enabled NO` and `CODE_SIGNING_ALLOWED=NO`. Exact counts come from `xcresulttool get test-results summary` and `tests`, extracted with `/private/tmp/alfie-xcresult-counts.py`. A parameterized definition is counted once; its Arguments children replace that parent when counting case runs. Summary/tests/counts JSON sidecars are saved beside each bundle. Do not sum the targeted and full runs.

| Run | Definition passed / failed / skipped | Case runs passed / failed / skipped | Result bundle |
|---|---:|---:|---|
| Unchanged production, tests-only baseline | 30 / 3 / 0 | 31 / 6 / 0 | `/private/tmp/alfie-followup-hardware-baseline.xcresult` |
| Fixed HardwareLinkTests | 33 / 0 / 0 | 37 / 0 / 0 | `/private/tmp/alfie-followup-hardware-targeted.xcresult` |
| Fixed full CinematicCoreMacOSTests | 477 / 0 / 5 | 616 / 0 / 5 | `/private/tmp/alfie-followup-hardware-full.xcresult` |

The targeted and full commands exited 0 and reported TEST SUCCEEDED. The four added definitions produce eight runs: two wire deadline cases, two direct deadline cases, one control definition looping both heartbeat paths, and three priority-estop batch-time cases. The full bundle includes the current voice and Director repairs; HardwareLinkTests reports the same 33 passing definitions / 37 runs within it.

Five full-target skips are unchanged study/rig gates: `acceleratedInstrumentationStressKeepsOriginalBound`, `cadenceRealisticInstrumentationBenchmark`, `compareAcceleratedWallClockAndSourceClockWindows`, `replayConsentedFolderWhenConfigured` (missing consented dataset configuration), and `twoWebcamsRenderPicturesAndBJoinsWithoutCrashing` (real-rig opt-in). They do not represent qualification passes.

Baseline command, run from the managed worktree:

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -parallel-testing-enabled NO -only-testing:CinematicCoreMacOSTests/HardwareLinkTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd \
  -resultBundlePath /private/tmp/alfie-followup-hardware-baseline.xcresult
```

The fixed targeted run used the same suite selector and flags with `/private/tmp/alfie-followup-hardware-targeted.xcresult`. The full run used `-only-testing:CinematicCoreMacOSTests` and `/private/tmp/alfie-followup-hardware-full.xcresult`, retaining all other flags. Each command's combined output is preserved at the matching `/private/tmp/alfie-followup-hardware-{baseline,targeted,full}.log`. No bare method selector or zero-test success is used. `git diff --check` passed after the final changes.
