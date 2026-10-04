# Alfie quality follow-ups — 5 October 2026

Five additional narrow tickets were implemented, reviewed, committed and pushed separately on `codex/alfie-quality-sprint-2026-10-04`. Continued from `3e85fb7` in the attached managed worktree. Fresh fetches confirm main remains `a89644b865e31d179ab9bee5f41fe25b760d2f34`. The primary `r2/engine` checkout's thirteen modified build artifacts and four untracked artifact/document paths were preserved. No PR or merge to main.

## Completed source/test units

Counts are passed test definitions / argument case runs. Every final run has zero failures; every full run retains five skips. Do not sum targeted/full snapshots or successive source snapshots.

| Ticket | Source commit | Targeted pass | Targeted skips | Full pass | Evidence |
| --- | --- | ---: | ---: | ---: | --- |
| [Distinct diagnostics sessions](https://trello.com/c/zpf1GOxX) | `d720042` | 11 / 12 | 2 | 480 / 627 | [Report](diagnostics-session-identity-2026-10-05.md) |
| [Originating pane callback binding](https://trello.com/c/LQLaXBUY) | `9e07683` | 52 / 68 | 0 | 489 / 652 | [Report](pane-callback-binding-2026-10-05.md) |
| [Stopped setup profile synchronization](https://trello.com/c/IEivZspd) | `4c1b68b` | 59 / 66 | 0 | 490 / 654 | [Report](setup-profile-sync-2026-10-05.md) |
| [Pair measurement and save provenance](https://trello.com/c/cuiuPM9U) | `dc3eb17` | 117 / 151 | 0 | 501 / 676 | [Report](pair-check-provenance-2026-10-05.md) |
| [Clip and Preview capture-rate truth](https://trello.com/c/1tBSRlMq) | `2c43636` | 62 / 80 | 1 | 506 / 688 | [Report](capture-rate-truth-2026-10-05.md) |

Diagnostics now use dated UUID stems shared by soak/memory/manifest; rapid sessions cannot merge CSV rows or overwrite each other's manifests. Actual temporary-file regressions and all eight Python reader tests pass; historical timestamp-only files remain readable.

Source-pane callbacks retain originating channel epoch/control revision and reject delayed target changes, ABA, Stop/restart and superseding actions. Tests call actual production closures and retain fresh Preview/Edit Live/single-input controls. A deduplicated Settings format observer also keeps stopped setup profile/VoiceOver model text current without starting capture/output or changing stored evidence.

Pair checks freeze starting fingerprint/context, roles/route and exact channel lifecycle for every window and one-shot save. Stale/canceled evidence cannot be relabelled with another configuration; reset/oversized counters cancel. Separate lifecycle truth plus pending notifications preserves reentrant cancellation/new checks. Review caught and fixed the intermediate NaN equality loop before final verification.

Clip startup clears inherited device FPS; unknown/invalid Preview expectations stay Unknown. Public generated-clip startup and decoder-failure tests prove channel/fingerprint/coordinator agreement. Checked rate formatting avoids integer conversion traps. Valid thresholds, historical compatibility/certification, Start trial, Take/routing and the two-input limit are preserved.

## Verification and board state

Latest tested source commit: `2c4363692f6d38af3abbc11bb2972da8c5b7b74b`. Complete target `/private/tmp/alfie-oct5-rate-full.xcresult`: **506 passed definitions / 688 passed runs, zero failures, five skipped definitions/runs** (511 total definitions / 693 total runs including skips). Latest targeted rate bundle `/private/tmp/alfie-oct5-rate-targeted.xcresult`: 62/80 passed, zero failures, one skipped consented-clips study. Expected-failing baselines, initial compile/selector attempts and authoritative final bundles are distinguished in each unit report.

The five full skips are opt-in instrumentation stress, cadence and investigation; absent consented readiness clips; and the opt-in real two-webcam rig. Timing studies were exercised in the prior 4 October sprint, not newly qualified here. No bound/assertion was weakened. All builds use CODE_SIGNING_ALLOWED=NO, serial macOS tests and `/private/tmp/alfie-quality-sprint-dd`; Xcode 26.2 (17C52), arm64 macOS 26.6.2 (25G83). Exact xcresult summary/tests/count JSON exports are retained. Argument children replace their definition for run counts.

All five children were re-read: Human Review, open, complete=false. Unchecked evidence items were appended to METRICS, CHANNEL-CMD, SHOW-SETUP, ADMISSION and CAPTURE parents, preserving their original acceptance. Source patches received peer/root review; pair publication and rate formatter amendments were reviewed again. No broad parent acceptance was closed.

## Remaining gates and scope

The five Spec Ready cards remain real evidence: [60-minute named-rig soak](https://trello.com/c/bYlNe6tu), [clean-Mac matched app/extension installation](https://trello.com/c/1BH2ecUh), [physical display/ATEM cadence](https://trello.com/c/HFyNhYO3), [cold-start pan-hitch reproduction](https://trello.com/c/6vPWbhsg), and [one-handed zoom rehearsal](https://trello.com/c/rKHXzFgE). Optional optimization/pan polish still needs measured cause or human curve choice.

Synthetic filesystem/model/command/clip evidence is not real-camera, physical safety, glass-to-glass latency, privacy/Store compliance or release qualification. No Director app integration, automatic Take, three/four live-input feature, hardware motion or microphone recognition was added. Permissions, entitlements, retention/deletion policy and PrivacyInfo decisions were preserved. The broader nonfinite-metric evaluator policy was inspected without a normal live NaN producer established and was not changed. A universal lossless count cap for arbitrary same-time latency bursts still requires a drop/aggregation choice.

## Complete batch file manifest

These repository-relative paths cover the 5 October batch since `3e85fb7`; [the previous report](quality-sprint-2026-10-04.md) has the earlier sprint manifest.

- `CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/CapabilityReport.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveConsole.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/DiagnosticsLog.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/LiveShowSetup.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/MultiInputAdmission.swift`
- `CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift`
- `CinematicCoreMacOS/CinematicCoreMacOSTests/DiagnosticsLogTests.swift`
- `CinematicCoreMacOS/CinematicCoreMacOSTests/LiveConsoleTests.swift`
- `CinematicCoreMacOS/CinematicCoreMacOSTests/MultiInputAdmissionTests.swift`
- `CinematicCoreMacOS/CinematicCoreMacOSTests/ReadinessEvaluationTests.swift`
- `CinematicCoreMacOS/CinematicCoreMacOSTests/ShowSetupTests.swift`
- `CinematicCoreMacOS/scripts/diagnostics_report.py`
- `CinematicCoreMacOS/scripts/test_diagnostics_report.py`
- `reports/capture-rate-truth-2026-10-05.md`
- `reports/diagnostics-session-identity-2026-10-05.md`
- `reports/pair-check-provenance-2026-10-05.md`
- `reports/pane-callback-binding-2026-10-05.md`
- `reports/quality-followups-2026-10-05.md`
- `reports/setup-profile-sync-2026-10-05.md`
