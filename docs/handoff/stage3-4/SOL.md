# GPT-6 Sol — Stage 3 and Stage 4 foundations (code)

You are GPT-6 Sol. Build the parts of Alfie's Stage 3 (Auto Director) and Stage 4 (hardware control and voice) that stay valid whatever Stephan decides on the open questions. Every module is pure or simulated, fully tested, and **not referenced by the running app**. A parallel agent (Astra) is writing the decision memos; Claude is finishing Stage 2 on `r2/engine`. Leave anything a decision would change as a parameter or protocol, not a guess.

## Setup

```bash
cd /Users/stephanmorris/Documents/macOS-rl-viritual-camera
git fetch origin
git worktree add ../alfie-sol-s34 -b s34/sol origin/r2/engine
cd ../alfie-sol-s34/CinematicCoreMacOS
xcodebuild build -project CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/alfie-dd-sol34 -quiet
xcodebuild test  -project CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS -destination 'platform=macOS' -derivedDataPath /tmp/alfie-dd-sol34 -only-testing:CinematicCoreMacOSTests
```

Baseline on `r2/engine`: 418 tests pass, 1 skipped (opt-in real-camera test). Keep it that way. Commit after each task (message ends `Co-Authored-By: GPT-6 Sol`) and `git push -u origin s34/sol`. No PRs, merges or Trello writes.

Read first: `docs/handoff/stage3-4/README.md` (shared rules — binding), `docs/handoff/stage3-4/CARDS.md`, and the Stage 2 engine files it lists. Before each task, `git fetch origin` and check `origin/s34/astra` for the matching memo (`git show origin/s34/astra:docs/auto-director/<file>.md`). Follow its recommendations only where they don't depend on a pending decision; otherwise keep the behaviour parameterized and note the difference in your report.

## Where you may write

New files only, in:
- `CinematicCoreMacOS/CinematicCoreMacOS/Director/` (and `Director/Replay/`)
- `CinematicCoreMacOS/CinematicCoreMacOS/Hardware/`
- `CinematicCoreMacOS/CinematicCoreMacOS/Speech/`
- `CinematicCoreMacOS/CinematicCoreMacOSTests/` — new test files only; name them `Director*Tests.swift`, `HardwareLink*Tests.swift`, `Speech*Tests.swift`
- `docs/handoff/stage3-4/SOL-REPORT.md` and `docs/handoff/stage3-4/integration-requests.md`

**Never edit an existing file** — not `ShowCoordinator`, `CameraManager`, `OperatorCommand`, `OperatorPill`, anything in `Console/`, `ContentView`, `DeveloperFlags`, entitlements, `Info.plist`, `project.pbxproj`, or build scripts. Nothing in the existing app may reference your new types. If a real integration needs a hook (for example a new `OperatorCommand.Origin` such as `.director` or `.voice`), write the exact proposed change in `integration-requests.md`.

## Project gotchas (from previous rounds)

- **Isolation:** default actor isolation is MainActor, with `NonisolatedNonsendingByDefault` and Swift 5 mode. Mark pure value types and functions `nonisolated` so tests and background use are easy. Default argument values are evaluated nonisolated, so use optional parameters and create inside `init`.
- **Imports:** `MemberImportVisibility` is on — import every module you use (Foundation, CoreGraphics, QuartzCore for `CACurrentMediaTime`, Combine…).
- **Project file:** never edit `project.pbxproj`. Folders are synchronized, so new `.swift` files in these folders are picked up automatically.
- **Tests:**
  - Use Swift Testing: `import Testing`, `@testable import Alfie`, `@Test`, `#expect`.
  - Use `@MainActor struct …Tests` when touching MainActor types.
  - Build test fixtures as Swift literals or generate them in code, rather than bundled JSON.
- **Deterministic time:** inject a clock (`() -> TimeInterval`) everywhere. No `sleep` in tests, no real timers in logic.
- **ShowCoordinator in a test:** `ShowCoordinator(programOutput: ProgramOutputManager(sinks: []), admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "…-\(UUID())")!))`. DEBUG seams on `CameraManager`: `setRunningForTesting`, `setLatestRenderedFrameForTesting`, `setSourceMissingForTesting`, `setSourceIdentityForTesting`. See `ProgramTakeTests.swift` for a full Take rig.

## Tasks, in order

### 1. Director authority — `Director/DirectorAuthority.swift` (AD-OVERRIDE)

A pure state machine:
- **Levels:** `off`, `suggest`, `autoPrepare`, `autoDirect`, plus `paused` and a shot `pin`.
- **Events:** operator enable/disable/pause/resume/pin/unpin, any manual operator command, Edit Live on/off, operator Take, source loss, Stop show.
- **Every transition returns** the new state and the cancellations it causes.
- **Authority token:** use an epoch the director must present with every proposal or Take. Any manual command bumps the epoch first, so a director action created before it can never take effect after it.
- **Auto Direct:** representable but **disabled by a constant** (`DirectorAuthority.autoTakeQualified = false`). The machine refuses to enter it while that is false.
- **Seam mapping:** a pure function mapping to `NextShotStatus.DirectorSection` (read it in `Console/NextShotStatus.swift`; do not edit it).
- **Tests:** every transition, the race invariants (manual vs pending prepare/Take, Take during prepare, Stop show mid-proposal), and that pause/resume never changes routing.

### 2. Proposals and staleness — `Director/DirectorProposal.swift` (AD-PREPARE core)

- **The proposal:** a value holding target channel, shot (preset / mode / zoom rung), reason, the authority epoch, and the Stage 2 stamps it was made under: channel `ChannelRevisions` (`sourceGeneration`, `controlEpoch`, `shotRevision`), `ProgramRouter.routeGeneration`, and time.
- **Validator:** `validate(proposal, against: live state, now:) -> .valid | .stale([reason])`. Reasons are typed: authority revoked, route changed, source restarted, shot changed by operator, target became Program, source missing, expired.
- **Preview only:** proposals may target only the current Preview channel, never Program. Assert it.
- **Live-state boundary:** read live state through a small protocol (`DirectorWorld`). Provide one adapter over `ShowCoordinator` built from its **public API only**, plus a fake for tests.
- **Readiness:** combine R2 `TakeAvailability` with extra director readiness inputs (identity confidence, framing settled for N ms, motion). Leave all of these as parameters; thresholds come later from Astra's memo and Stephan's decision.

### 3. Shot policy and preferences — `Director/DirectorShotPolicy.swift`, `Director/DirectorPreferences.swift` (AD-STYLE, AD-PREFS)

- **Shot policy:** a pure policy that, given a timeline state (current Program shot and how long it has been up, candidate shots, subject evidence), returns the next proposal or `nil` with a reason. Every number is a field of a `DirectorShotPolicy.Parameters` struct: minimum and maximum shot duration, wide cadence, repetition window, movement limits, cut-on-motion allowed. Mark default values in a comment as **PROPOSED — pending AD-STYLE decision**.
- **Preferences:** a `Codable`, versioned struct with validation, safe defaults, deterministic conflict resolution and a migration hook.
- **Tests:** minimum duration is honoured, no oscillation (A→B→A inside the window), repetition avoidance, invalid preferences are rejected, and preferences round-trip.

### 4. Replay harness — `Director/Replay/` (AD-QA, AD-SUBJECT groundwork)

A headless, deterministic simulator:
- **Input:** a timeline — per-channel events (subject present/absent, identity confidence, framing readiness, source loss/restore, fresh-render cadence) plus operator actions (manual command, Take, pause, Edit Live).
- **Run:** feed it through `DirectorAuthority` + `DirectorShotPolicy` + `DirectorProposal` validation with a simulated clock.
- **Output:** a `DirectorReplayReport` with cuts per minute, minimum-duration violations, oscillations, stale proposals rejected (by reason), manual overrides honoured and their latency, proposals made while paused (must be 0), and any Program change without authority (must be 0).
- **Wrong subject:** make "wrong-subject" computable from labelled ground truth in the timeline, with denominators.
- **Fixtures:** five or more synthetic timelines built in code — calm sermon, sermon with a walking pastor, panel of three, camera B dropping out, an operator fighting the director.
- **Tests:** assert the report numbers for each fixture.

The harness must not touch `AVFoundation`, the router or any UI.

### 5. HardwareLink contract and simulator — `Hardware/` (S5 redesign, target-agnostic)

- **Protocol:** `HardwareLink` covering discover, negotiate (protocol version), connect, arm/disarm, priority e-stop, command/ack, telemetry, heartbeat.
- **Lifecycle:** `disconnected → discovered → negotiating → connectedDisarmed → armed → stopped/faulted`. Reconnect, reboot, version mismatch and heartbeat loss **always** end disarmed. No last-velocity replay. No auto-home.
- **Wire codec:** bounded newline-delimited JSON. Every record carries `v`, `session`, `seq`, `type`. Handle malformed, oversize, duplicate, out-of-order and late records explicitly, with a typed rejection for each.
- **Timing:** starting values as parameters — 10 Hz heartbeat, 20–50 Hz telemetry, motion lease ≤ 200 ms, link-loss ≤ 300 ms. Use an injected clock.
- **E-stop:** latches until an explicit operator reset, and outranks everything.
- **Motion:** motion commands exist in the protocol but are **rejected** (`motionEnabled = false` constant). This round is connection, not motion.
- **Simulator:** `SimulatedHardwareDevice` implements the device side in-process, including faults — drop link, reboot, send garbage, stall heartbeat, version mismatch.
- **Tests:** unplug, app quit (link drop), MCU reset, malformed/duplicate/late records, heartbeat loss, reconnect lands disarmed, e-stop latch and reset.
- **Out of scope:** no real serial/IOKit transport and no entitlement change (the control target is undecided — Astra's `docs/hardware/control-target-decision.md`). Leave a `HardwareTransport` protocol for it.

### 6. Speech command grammar, text only — `Speech/` (S4 redesign)

- **Grammar:** `SpeechCommandGrammar` maps a **final transcript** to a `VoiceIntent` or a typed rejection:
  - wake prefix "Alfie" required; the complete utterance must match; no substring matches; case and punctuation tolerant
  - "Alfie, detect" → `.detect`
  - "Alfie, track" → `.setMode(.autoTracking)`, allowed only when a subject is locked; otherwise reject with "Pick a subject."
  - "Alfie, manual" → `.setMode(.manualCrop)`
  - "Alfie, pan" → `.setMode(.autoPan)`
  - "Alfie, back to wide" → `.returnToWide` (bare "wide" does not map)
  - "Alfie, waist up" → `.selectPreset(.stage(.waistUp))`, or the Webcam equivalent in Webcam format
  - "Alfie, push in" / "Alfie, pull out" → `.beginZoom(.pushIn / .pullOut)`
  - optional channel prefix: "Alfie, camera two, pan"
  - never Stop
- **Adapter:** `VoiceCommandAdapter` takes final transcripts with utterance IDs:
  - dedupes and applies a confidence floor
  - binds the intent to a channel the way the pill does: the control target at the moment of the utterance, or the named camera
  - produces a dispatchable command value
  - a manual command after the utterance cancels a pending voice command
  - voice can never undo Return to Wide
- **Dispatch:** go through `ShowCoordinator.makeCommand` / `dispatch` where the public API allows. Otherwise produce the value and put the needed hook in `integration-requests.md`.
- **Transcripts:** a `SpeechTranscriptSource` protocol plus a fake. **No recognizer, no microphone, no audio, no entitlement** — the stack is a pending decision (Astra's `docs/voice/speech-stack-decision.md`).
- **Tests:**
  - every command and its rejections
  - a false-action corpus of 50+ sermon, music and conversation transcripts that must produce zero actions
  - one action per utterance
  - cancellation by a manual command

### 7. Report — `docs/handoff/stage3-4/SOL-REPORT.md` and `integration-requests.md`

- **SOL-REPORT.md:**
  - per task: files, public types, tests added, exact test totals (pass / fail / skip)
  - every assumption a pending decision could overturn (cross-reference Astra's `DECISIONS.md` IDs if present)
  - what you could not do
- **integration-requests.md:** every change needed in existing files to wire this in later — exact file, the proposed code, and why.

Stop after task 7. If you run out of budget, stop at a task boundary with everything committed, pushed and green, and put the remaining tasks in `SOL-REPORT.md`.
