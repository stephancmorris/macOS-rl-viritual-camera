# Setup and Take boundary repairs — 24 October 2026

Started from current `origin/main` at `12a2bc5`, after finding that the initial local branch (`r2/modes/spec-and-model`) predated the merged follow-ups through PR #77. Working branch: `codex/next-ticket-batches-2026-10-24`. Trello work is grouped in [the verification/setup batch](https://trello.com/c/7lJuEA8O) and [TAKE-CLOCK](https://trello.com/c/AzTxvqP6).

## Changes

- **Verification:** `DirectorCutExecutionTests.Scheduler.fire` invoked a MainActor closure from an unisolated method under Xcode 26.3. Explicit MainActor isolation on the synthetic scheduler restores compilation. No runtime scheduler changed.
- **SHOW-SETUP / MODE-SWITCH:** an old Start-pair task could finish after Stop and a newer A-only start, then add B to that newer session. The regression reproduced both the unexpected B channel and B capture request. Every show Stop now rotates an intent token. Setup snapshots it before queuing A-only/pair work and checks it before effects and after suspension. Stop retires queued starts even before capture becomes live; a delayed old pair cannot attach to a newer A. The newer A remains running. Existing mode-change cancellation remains active.
- **TAKE:** the previous freshness subtraction accepted future/infinite host times and reversed processing/render order; infinite output dimensions also passed geometry validation. Synthetic frames committed at the actual Take/sink boundary before repair. Eligibility now requires finite, ordered host times, a valid finite positive freshness period/budget and finite positive output dimensions. UI and execution share that validation and report Preparing. Invalid evidence preserves Program, route generation and sink contents. Source media PTS remains independent of host time; numerical freshness budgets are unchanged.

These are software boundary repairs, not a claimed real-camera failure reproduction or completed rig qualification. No capture fallback, output standard, consent policy, Director authority, project setting, entitlement or Info.plist changed.

## Verification

Exact xcresult counts are in [validation.json](validation.json). Focused setup/capture/Director tests passed **59 definitions / 88 expanded cases**. Focused Take/permit/router tests passed **42 definitions / 81 expanded cases**. The final complete Swift suite passed **1,069 definitions / 1,674 expanded cases**, zero failures and four opt-in skips. A separately configured synthetic Python-export/CoreML CPU interoperability test then passed; the other three opt-in fixture/hardware tests remain unrun. Python script tests passed **111**, with **14** additional Director dataset/scorer tests. The Release app and extension built with signing disabled.

Before-fix evidence is retained: `setup-before.xcresult` reproduces the delayed pair race; `take-before.xcresult` fails three definitions/four expanded cases for invalid frame timing/geometry. An initial overly narrow individual selector ran zero tests and is excluded. The first baseline failed compilation on scheduler isolation. The subsequent Documents-based test host stalled in a synchronous fixture `open`; its process sample and log are preserved locally. The same tracked sources and edits were mirrored under `/private/tmp/alfie-batches-20261024/source` for successful verification, with matching app source fingerprints. No file-access permission was expanded.

Local commands and result bundles are under `/private/tmp/alfie-batches-20261024/`. Tests used scheme `CinematicCoreMacOS`, destination `platform=macOS`, `-only-testing:CinematicCoreMacOSTests`, `-parallel-testing-enabled NO` and `CODE_SIGNING_ALLOWED=NO`. Focused runs selected the named suites. Release used `-configuration Release -destination generic/platform=macOS`. The CoreML-only run used `TEST_RUNNER_ALFIE_DIRECTOR_SCORER_INTEROP` with a locally generated synthetic model, not an installed production scorer.

## Application inspection limits

Source, actual test-host behavior and builds were checked. Native computer-control attempts to select the candidate, installed Alfie and Finder timed out, so no manual stopped-window walkthrough is claimed. A copied Debug preview was signed ad hoc locally after the test-host bundle failed standalone signature verification; selecting that preview also timed out. Neither this copy nor the unsigned Release establishes signed installation. Camera capture and downstream routes were not opened for this batch. No screenshots or camera images were committed.

The next existing tickets and their remaining dependencies are grouped in [next-groups.md](next-groups.md). Owner decisions and attended acceptance remain explicit.

## Additional operator batch: recording Stop

[RECORD-STOP](https://trello.com/c/UUrJrSXP) reproduced a second admission-boundary gap through the actual Settings recording binding. Its setter scheduled async Stop in a new Task, so the next synthetic observation was accepted after the setter returned and persisted as an unwanted second row. Camera Stop used the same delayed pattern.

Both controls now synchronously request recording shutdown. Camera Stop closes admission before capture teardown publishes any notifications. Accepted writes still drain through the existing shared shutdown task; consent remains granted unless explicitly revoked. A plain admission guard prevents repeated/reentrant Stop notifications from entering shutdown twice. An optional recorder constructor parameter isolates CameraManager integration tests without changing its production default.

The tests exercise the real binding and `CameraManager.stopCapture`, reject post-action and teardown-notification observations, preserve an 801-row terminal tail behind eight blocked batches, reject restart while draining and verify exactly one writer close. The complete suite at this stage passed **1,071 definitions / 1,678 expanded cases**, zero failures and three fixture/hardware skips, with actual synthetic CoreML CPU interoperability configured in the run. The updated app and extension also build in unsigned Release. Exact earlier reproductions, intermediate runs and final `full-4` counts are retained in validation.json. The privacy inventory now distinguishes the recorder's own gate from its formerly delayed UI/camera callers. No real camera or operator observations were used.
