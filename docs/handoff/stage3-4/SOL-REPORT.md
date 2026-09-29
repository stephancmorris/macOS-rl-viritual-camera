# GPT-6 Sol Stage 3/4 foundation report

Branch `s34/sol`, based on `origin/r2/engine` at `33a3faf`. All modules are new files and are unreferenced by the running app. No existing app file, project file, entitlement, or build script was edited.

## Verification

`xcodebuild build` with `CODE_SIGNING_ALLOWED=NO`: succeeded. Full `CinematicCoreMacOSTests` unit target: **432 passed, 0 failed, 1 skipped**. Baseline was 418 passed, 1 skipped; this branch adds 14 tests. The full scheme including `CinematicCoreMacOSUITests` returned failure because its UI runner was killed before bootstrap; its unit tests still recorded 432 passed and 1 skipped. The clean unit-target rerun is the authoritative count here. Tests were run on macOS arm64 with `/tmp/alfie-dd-sol34`.

## Tasks

| Task / commit | New files | Main types | Tests added | Unit total after task |
| --- | --- | --- | ---: | --- |
| 1 Authority `b68b985` | `Director/DirectorAuthority.swift`; `DirectorAuthorityTests.swift` | `DirectorAuthority`, event, transition, epoch token, `NextShotStatus.DirectorSection` mapping | 4 | 422 pass / 0 fail / 1 skip |
| 2 Proposal `9999241` | `Director/DirectorProposal.swift`; `DirectorProposalTests.swift` | `DirectorShot`, `DirectorProposal`, `DirectorWorld`, `ShowDirectorWorld`, validator, readiness | 1 | 423 / 0 / 1 |
| 3 Policy and preferences `ac612fd` | `Director/DirectorShotPolicy.swift`, `DirectorPreferences.swift`; `DirectorShotPolicyTests.swift` | Parameterized candidate selection, versioned Codable preferences | 2 | 425 / 0 / 1 |
| 4 Replay `d9184ba` | `Director/Replay/DirectorReplay.swift`, `DirectorReplayFixtures.swift`; `DirectorReplayTests.swift` | Deterministic event replay and metrics report, five synthetic fixtures | 1 | 426 / 0 / 1 |
| 5 Hardware `a11968f` | `Hardware/HardwareLink.swift`, `HardwareWireCodec.swift`, `SimulatedHardwareDevice.swift`; `HardwareLinkTests.swift` | Link/transport contracts, lifecycle simulator, bounded NDJSON codec | 3 | 429 / 0 / 1 |
| 6 Speech `ec03713` | `Speech/SpeechCommandGrammar.swift`, `VoiceCommandAdapter.swift`; `SpeechCommandTests.swift` | Complete utterance grammar, final transcript source, voice adapter | 3 | 432 / 0 / 1 |

Per-task totals are baseline plus new tests; the final total was measured by the full unit-target run. Individual task test classes also passed after each task.

## Pending decisions and parameter boundaries

- **A1/A2/A3/A4** (`authority-and-override.md`): the epoch always revokes old work. Manual input currently revokes without selecting a lasting pause policy; pin holds a channel identifier rather than a final shot-intent model. Auto Direct is representable and gated off by `autoTakeQualified = false`; no countdown runs. A global pause, pin semantics, and countdown require Stephan's decision and integration tests.
- **P1/P2/P3** (`prepare-and-readiness.md`): identity threshold, settling interval, motion limit and proposal lifetime are caller parameters. The adapter reads R2 revisions and route generation. It does not claim a calibrated identity probability. Post-prepare revision acknowledgement needs an integration hook.
- **T1/T2/T3** (`shot-style.md`): every policy timing/movement value is a parameter. The included `proposed` values predate Astra's different proposed table and are neither approved nor measured. Wide cadence is a preference in candidate ranking, never a forced cut. R2 manual Take rules are untouched.
- **F1/F2/F3** (`preferences.md`): only a small structured preferences schema is present. Mid-show edit policy, cues, roles, and richer validation are pending; imported preferences cannot grant authority. Conflict resolution is deterministic for the fields present.
- **E1/E2/E3** (`subject-evidence.md`): replay's `intended` label supplies a wrong-subject numerator and denominator. No audio, retained media, real identity verification, or calibrated confidence is present. Synthetic tests establish only harness arithmetic.
- **H1/H2/H3/H4** (`control-target-decision.md`): the link is transport-agnostic and motion is rejected. No hardware target, firmware, physical stop, serial transport, entitlement, or bench qualification is claimed.
- **Voice stack decision**: no `docs/voice/speech-stack-decision.md` was on `origin/s34/astra` at final fetch. Grammar and adapter consume final text only. Confidence floor and Stage/Webcam mapping are injected. No recognition, audio ingestion, or privacy decision is implemented.

## What remains

The running app never creates these types. Wiring requires the exact hooks in `integration-requests.md`, Stage 2 two-camera validation, Stephan's decisions, and qualification of any Auto Direct or physical motion path. The replay fixtures are synthetic and cannot establish editorial quality, real source freshness, subject identity accuracy, physical safety, or voice recognition accuracy.
# Follow-up: AD-VALIDATION — 2026-09-30

Card: https://trello.com/c/nPoIqkTe. Changed `DirectorProposal.swift`, `DirectorShotPolicy.swift`, `DirectorPreferences.swift`, `DirectorProposalTests.swift`, and `DirectorShotPolicyTests.swift`. The validator now rejects malformed clocks and expiry; readiness rejects nonfinite or out-of-range evidence and parameters; policy abstains on invalid timing and gives equal-evidence candidates a total ordering; preference resolution throws when hard duration intervals do not intersect. The policy numbers remain unapproved caller parameters (P1/T1/T2). Targeted tests: 16 passed, 0 failed, 0 skipped (8 distinct test methods executed twice by Xcode). Full `CinematicCoreMacOSTests` target with `CODE_SIGNING_ALLOWED=NO`: 437 passed, 0 failed, 1 skipped (log case count). No running-app integration was changed.

# Follow-up: AD-REPLAY-TRUTH — 2026-09-30

Card: https://trello.com/c/X0OTOpra. Changed `DirectorReplay.swift`, `DirectorReplayFixtures.swift`, and `DirectorReplayTests.swift`. Ordinary render freshness no longer increments `shotRevision`; explicit shot changes do. Events at the same timestamp use fixture sequence order. Shadow attempts capture proposals and schedule delayed effects; Stop, fault, manual input, expired permits, duplicate callbacks, failed effects, and bad clocks are exercised. The report exposes distinct proposal, director attempt, operator Take, and cut counts; wrong-subject denominators are separate for proposals and attempts. Manual override latency is `nil` (N/A) because this headless harness cannot measure the UI path. Evidence is marked `.synthetic`; these five fixtures are not real qualification evidence. Auto Direct still causes zero cuts. Targeted tests: 8 passed, 0 failed, 0 skipped (4 distinct methods run twice). Full `CinematicCoreMacOSTests` with `CODE_SIGNING_ALLOWED=NO`: 440 passed, 0 failed, 1 skipped (log case count). The harness remains an in-process model and does not demonstrate real camera timing, actual subject identity accuracy, or qualified Auto Direct safety (P3/T1/T2 remain open).
