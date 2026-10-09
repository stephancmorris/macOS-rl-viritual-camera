# Alfie status audit — 10 October 2026

Alfie has an implemented operator-controlled framing workflow and app-wired manual two-camera Program/Preview operation. The quality sprint has repaired concrete consent, lifecycle, command, numerical and measurement defects. It is **not yet evidenced as ready for a live production release**: the current installation, physical-output, operator and sustained-load reports remain unrun, and release sign-off is open.

## What was audited

Audited implementation: `cacedcc2cc4a1816edfab691490b201fb2e55728`, pushed on `codex/alfie-quality-sprint-2026-10-04`. A fresh fetch confirms `origin/main` remains `a89644b865e31d179ab9bee5f41fe25b760d2f34`; the implementation is **24 commits ahead, zero behind, and unmerged**. This audit is a subsequent documentation-only commit, with the same tested implementation.

Repository build-input fingerprint: `99acd79a34675766421c00dfe5b3e292ee021628556520356abc633c188139c7`. The fingerprint comes from the existing [source fingerprint script](../CinematicCoreMacOS/scripts/source_fingerprint.py); the commit also identifies tests and standalone tooling. It is not a fingerprint of a newly signed or installed package.

The audit reconciles current source, branch history, committed test reports, release runbooks, historical packaging and the complete Trello board. Three independent read-only reviews covered capture/app integration, release/privacy evidence, and Director/voice/hardware boundaries. Root completed the two already-prepared lifecycle repairs alongside the audit. No further feature implementation or physical qualification was started. The primary `r2/engine` checkout and its existing build artifacts/documents were preserved; work used the managed quality worktree.

## What exists today

| Area | Delivered implementation | What remains unproved or incomplete |
|---|---|---|
| Single-camera operation | Detect/select subject, Track and recovery, Manual/Pan/Wide ownership, shot presets and one-rung Push/Pull, Return to Wide, crop/render pipeline. | Physical-person identity accuracy, distant-subject recovery, matched footage and one-handed rehearsal. |
| Independent A/B inputs | Separate camera controllers/session work, exclusive device leases, bounded render/perception scheduler, explicit reconnect. | Actual simultaneous device compatibility, supported delivered formats, sustained capacity and fault behavior on named rigs. |
| Setup and admission | Saved device proposals, show standard/output selection, A-only or pair Start. A uses existing app preflight and B joins afterward. Historical compatible records are distinguished from the current full fingerprint. Unknown pairs can start an explicitly unmeasured trial. | Short pair checks are provisional; they do not certify sustained operation or a different configuration. |
| Manual Program/Preview | One Program router/output, fresh legal Preview gating, route/source/shot checks and sink-accepted manual Take, role swap, revision-bound Preview commands and explicit Edit Live. | Real operator/receiver evidence during motion, failure and recovery. No automatic Take. |
| Stage Multiview | Current `useMultiviewConsole` flag is **true**. Stage uses live Multiview and stopped setup; Webcam retains single-camera presentation. Live pictures/thumbnails, Take, Stop, reconnect and pair measurement are wired. The new aggregate lifecycle fix keeps Multiview visible and setup locked while Program B continues after Preview A stops. | Installed 1280-point/VoiceOver/one-handed walkthrough and screenshots. Settings does not enforce the separate multi-camera format-switch helper. |
| Program delivery | Program Display or Virtual Camera carries the chosen Program feed with frozen show rate/route, source-loss hold then standby and explicit reconnect. | Actual receiving-client/display/converter/ATEM cadence, latency, installation and reconnect. Debug below-rate/rehearsal routes do not establish Release capability. |
| Diagnostics and consent | Pipeline measurements, build/configuration identity, distinct UUID session files and closing records. CLI arguments are validated before report writes. Optional training observations require consent; revocation stops new admission and drains accepted writes. | Runtime permission/export/storage acceptance and approved retention/disclosure rules across all file families. |
| Overload degradation | Pure `DegradePolicy` foundation and synthetic validation. | **Unwired in the running app**; calibration, runtime integration and sustained overload/recovery evidence remain open. |
| Three/four inputs | C/D identifiers and future layout/cue concepts. | Current operator setup adds B only. Three/four live inputs, cueing and workload qualification remain future work. |
| Director | Isolated authority, preferences, proposals/preparation, readiness and independent replay/effect auditing. | No running-app bridge/UI integration; Director refuses Take. Subject/editorial policy, intervention hooks and qualification remain open. |
| Voice | Text grammar, opaque utterance identities, stale/duplicate validation and final bound Track-lock checks. | Fake transcript source only; no microphone recognition, listening UI or app dispatch integration. Acoustic/timing/privacy gates remain open. |
| Physical motion | Protocol, bounded wire codec and deterministic motion-disabled simulator. | No concrete transport/app integration. Device choice, firmware/watchdog/limits, local physical stop and bench qualification remain open; simulator arm returns motion-disabled. |

Source references: [ContentView](../CinematicCoreMacOS/CinematicCoreMacOS/ContentView.swift), [DeveloperFlags](../CinematicCoreMacOS/CinematicCoreMacOS/DeveloperFlags.swift), [LiveShowSetup](../CinematicCoreMacOS/CinematicCoreMacOS/LiveShowSetup.swift), [ShowCoordinator](../CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift), [LiveConsole](../CinematicCoreMacOS/CinematicCoreMacOS/Console/LiveConsole.swift), [ProgramOutputManager](../CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift). Director, Speech and Hardware have no production references outside their own module folders in this source audit.

## Completed quality work

The [4 October sprint](quality-sprint-2026-10-04.md) delivered the original consent-revocation boundary, historical/current setup truth and exact latency FIFO window/benchmark separation. Follow-ups repaired independent replay evidence, nonreusable voice identity, the simulator's effect-clock watchdog and bound Track dispatch. These are narrow source/test proofs; future features remain unwired.

The [5 October batch](quality-followups-2026-10-05.md) delivered separate diagnostics session files, originating-pane command binding, stopped-profile synchronization, pair measurement/save provenance and truthful capture-rate handling for clips/unknown Preview expectations.

Seven additional units were completed and separately pushed on 10 October. Each has an expected-failing behavioral baseline, focused repair, passing regression evidence and an open Human Review child card. Counts below are **passed definitions / passed case runs**; full Swift rows have zero failures and five skips.

| Unit | Commit / card | Targeted evidence | Full Swift evidence | Report |
|---|---|---|---|---|
| Retire ended/failed validation clips before Take | `0c3d573` · [child](https://trello.com/c/AGbc6NFC) | 40 / 45, one skip | 509 / 695 | [Clip retirement](clip-source-retirement-2026-10-10.md) |
| Stop/newer choice wins over delayed camera switching | `9019bce` · [child](https://trello.com/c/G9eMDFpv) | 56 / 63, one skip | 516 / 704 | [Camera switching](camera-switch-stop-2026-10-10.md) |
| Correct even-population readiness median | `f175a29` · [child](https://trello.com/c/WH5u0x7F) | 12 / 17, one skip | 519 / 707 | [Median evidence](readiness-median-2026-10-10.md) |
| Stabilize ordinary crop spring at supported ticks | `be838fd` · [child](https://trello.com/c/FKTpe5WA) | 51 / 74 | 522 / 724 | [Spring stability](crop-spring-stability-2026-10-10.md) |
| Reject invalid explicit cadence report arguments | `f972bee` · [child](https://trello.com/c/Boj6LxeY) | 14 Python tests | 522 / 724 | [Argument validation](diagnostics-argument-validation-2026-10-10.md) |
| Reject frames/drop counts from retired capture outputs | `f662620` · [child](https://trello.com/c/LDE5b8sA) | 40 / 50 | 524 / 734 | [Callback provenance](capture-callback-provenance-2026-10-10.md) |
| Use all-channel activity for live UI/setup/Stop | `cacedcc` · [child](https://trello.com/c/h6sgju5S) | 58 / 70 | **534 / 749** | [Show lifecycle truth](show-lifecycle-truth-2026-10-10.md) |

The final full-suite result at `cacedcc` is **534 passed Swift definitions, 749 passed case runs, zero failures, five skipped definitions/runs**. The diagnostics Python suite was rerun at that source: **14 passed, no errors or skips**. A parameterized definition can execute several cases; these totals are not interchangeable and successive runs are not additive.

Swift evidence: `/private/tmp/alfie-oct10-show-full.xcresult`, matching `.log`, exported summary/test tree and `-counts.json`; Python evidence: `/private/tmp/alfie-oct10-audit-python.log`. Temporary bundles are not durable release artifacts; exact outcomes and procedures are preserved in the committed reports. Swift used Xcode 26.2 (17C52), arm64 M4 Pro, macOS 26.6.2 (25G83), serial macOS testing and `CODE_SIGNING_ALLOWED=NO`.

The five skips remain opt-in accelerated instrumentation stress, cadence-realistic benchmark, accelerated clock-window comparison, an unconfigured consented replay folder, and two-real-webcam integration. None is a hardware/dataset pass. Even that webcam test uses no output sink and only short rendering, so a future pass would not prove downstream presentation or a soak. No actual capture authorization/start, microphone recognition, extension activation or physical motion was performed for these repairs.

## Current board state

Fresh complete [Alfie Coding Board](https://trello.com/b/FkxA6E36/alfie-coding-board) read after delivery: 107 cards, eight lists, no pagination remaining and no archived cards returned.

| List | Cards |
|---|---:|
| Spec Backlog | 45 |
| Spec Ready | 5 |
| Agent Queue | 0 |
| In Progress | 0 |
| Human Review | 48 |
| Blocked | 0 |
| Done | 3 |
| Deferred — physical control and voice | 6 |

All seven new child cards are in **Human Review**, open and incomplete. Their parent evidence was added as unchecked checklist items; broader acceptance remains open. A list position is not a release approval or completion percentage. The three pre-existing Done-list entries concern the crop mailbox, capture-duration pinning and autorelease drains, not overall Alfie release acceptance.

The five Spec Ready cards are [INSTALL](https://trello.com/c/1BH2ecUh), [DISPLAY-QA](https://trello.com/c/HFyNhYO3), [ZOOM-QA](https://trello.com/c/rKHXzFgE), [PAN-HITCH](https://trello.com/c/6vPWbhsg) and [SOAK](https://trello.com/c/bYlNe6tu). They require candidate/rig/operator evidence. [TRACK-QA](https://trello.com/c/lxmF5I9Q), [LATENCY](https://trello.com/c/TkyfhrsJ), [MULTI-QA](https://trello.com/c/uO1HAlYm), [PRIVACY](https://trello.com/c/ecKr4f2R) and [R1-GATE](https://trello.com/c/IDAjbyA9) also remain open in backlog.

## What is needed next, in priority order

1. **Review the delivered quality branch and choose a release scope/candidate.** Merge remains a human delivery step; nothing was merged by this sprint. Pin the exact commit/fingerprint, supported OS/Mac, cameras, formats, show standard and destination. The current project deployment floor is macOS **26.2**, which needs exact-floor launch/install evidence and a supported-platform decision. Older 14+ copy does not establish support.
2. **Resolve the manual-workflow integration gaps for the claimed scope.** `ConsolePresentation.canSwitchFormat` is tested but has no production caller; Settings still writes A's composer format directly. Decide/enforce the intended multi-input format rule and Settings authority. `DegradePolicy` is pure/unwired; calibrate and integrate any promised live load shedding, or explicitly bound the release capability. These are additional engineering/policy work, not already delivered safeguards. The aggregate lifecycle repair does not close either gap.
3. **Build a fresh matched app/extension and qualify installation.** Historical packaging worked: the repository archive is dated 5 September 2026, version 1.0/build 2, and [release logs](../CinematicCoreMacOS/build_out/release_build.log) record accepted notarization/stapling. Its exported plist lacks the current fingerprint and its historical output lacks `source-fingerprint.txt`. It does not contain proof of these latest repairs. For the final candidate retain signing/notarization/stapling, matched extension, fingerprint and DMG checksum, then run [INSTALL](release-1/install.md) on a clean supported Mac: denial/approval/relaunch, receiving client, quit, reinstall/upgrade and reboot.
4. **Qualify real output and the operator workflow.** [DISPLAY-QA](release-1/output-route.md) requires the actual display/converter/ATEM 1080p50 path where claimed, receiving picture, external cadence and reconnect. [ZOOM-QA](release-1/shot-move-test-plan.md) requires real one-handed moves, ownership/Stop/focus/recovery and intended Stage/Webcam delivery. Complete the installed 1280-point, VoiceOver and guide/screenshot walkthrough against that same candidate.
5. **Measure tracking, latency and the Pan symptom.** [TRACK-QA](release-1/tracking-replay.md) needs matched consented raw inputs/settings and reviewed physical-person/loss/recovery outcomes with denominators. [LATENCY](release-1/latency.md) needs external timer/event recordings, raw samples and measurement resolution for each claimed route. [PAN-HITCH](release-1/pan-hitch.md) needs cold/warm and detection-off/on runs correlated with receiver timecodes/diagnostics. The spring repair proves a numerical defect; it does not establish the cause of the original physical hitch or live beta lag.
6. **Freeze budgets, then run sustained-load acceptance.** Complete preceding checks and a baseline before the named church-rig [60-minute R1 soak](release-1/soak.md), retaining matching manifest/soak/memory files and receiving-output evidence. Then run [R2's machine/device matrix and two-input moving-subject soak](../docs/ALFIE_MULTICAMERA_SPEC.md), including actual delivered formats, full admission fingerprint, Take, source/output faults, reconnect, sleep/wake and thermal/memory behavior. Certify only tested configurations.
7. **Close privacy acceptance alongside qualification.** Verify camera refusal/revocation/recovery, buffer/gallery/export contents and storage behavior using disposable fixtures/accounts. Approve retention/deletion rules across training JSONL/metadata, diagnostics CSV/JSON and routing text. Review actual signed entitlements, declarations and disclosures for the chosen distribution. Source-schema tests do not establish privacy compliance.
8. **Provide consented readiness data before threshold/accuracy claims.** [The readiness study](readiness-evaluation.md) has no evaluated real dataset. Freeze annotations, held-out split and hashes; report source-pixel conditions, coverage/abstention and reviewed identity outcomes. Synthetic decoder/CSV tests establish harness behavior, not calibrated accuracy.

[R1-GATE](release-1/release-checklist.md) remains **Open** with blank candidate/rig/evidence/sign-off tables. [The R1 evidence index](release-1/README.md) marks all seven physical/operator reports **Not run**. These documents are procedures, not completed measurements. Optional optimization and Pan-polish backlog should proceed only when its measured trigger/product decision is satisfied; it is not automatically a release prerequisite.

## Privacy and future-feature boundaries

The old consent finding is superseded: [the privacy inventory's October 4 addendum](../docs/privacy/current-source-audit.md) records the editable consent binding and serialized final-write boundary. Revocation stops new admission while accepted observations drain; retained sessions are preserved.

Current retention has several distinct behaviors. Diagnostics prune CSV by modification age at a later session start; JSON manifests are excluded and routing text has no audited rotation. Training cleanup occurs on Start or explicit actions. This cannot support a blanket promise that every file disappears after 30 days. Manual Finder export has no approved sanitizing packager; identifiers, timing, configuration and notes can identify context, so these files should not be described as anonymous.

No tracked `PrivacyInfo.xcprivacy` exists in this branch. Determine required declarations from the chosen build/distribution and inspect built bundles. The checked-in entitlement plist omits microphone input while the project's audio-input resource flag is enabled; inspect effective signed entitlements instead of inferring runtime permissions from either alone. No permissions, entitlements, retention policy or disclosure text was changed by this audit.

All **37** entries in [DECISIONS.md](../docs/handoff/stage3-4/DECISIONS.md) remain **OPEN**. Most concern future Director/voice/hardware expansion; they do not collectively block a bounded R1/manual R2 release. That expansion separately requires approved subject/editorial/override/workload/recognizer/hardware policies, [integration hooks](../docs/handoff/stage3-4/integration-requests.md) and [qualification](auto-director/qualification-protocol.md). Proposed budgets and simulated replay/watchdog results are not approvals for autonomous cuts, speech actions or physical stopping.

## Documentation cleanup and audit conclusion

Some older implementation snapshots are stale: Multiview is currently enabled, setup/B/thumbnails are wired, grammar/simulator foundations exist, and consent/replay fixes supersede earlier findings. Preserve dated historical evidence but reconcile the current capability summaries before operator qualification. [The operator guide](../docs/user-guide/README.md) has static checks and corrected consent/history wording; installed visual/print/VoiceOver/screenshots remain pending.

**Delivered:** core framing and manual A/B app workflow, isolated future-feature foundations, the October quality repairs and passing automated evidence on the pushed work branch. **Still needed:** human review/integration, the two explicit manual-workflow integration gaps, one current signed candidate, named-rig/installer/operator/soak evidence, privacy decisions/runtime checks, and readiness data. Director/voice/physical motion/three-four-input work remains a separate expansion after its own decisions and gates.
