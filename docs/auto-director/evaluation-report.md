# Director evaluation report tooling

D-06 software preparation and D-08 parameter evidence support. This is an offline reporter for actual **synthetic** `DirectorReplay.Report` exports and C-05 shadow observations. It never writes a qualification record, verifies signatories, chooses a parameter or authorizes a trial. The [qualification protocol](../../reports/auto-director/qualification-protocol.md), [D-05 runbooks](../../reports/auto-director/rehearsal-runbooks.md) and [consent/fixture procedure](fixture-consent-and-disclosure.md) govern the remaining real evaluations.

## Export actual synthetic replay measurements

The optional test `DirectorEvaluationExportTests/exportFiveActualSyntheticReplayReportsWhenExplicitlyRequested` runs all five existing `DirectorReplayFixtures` through `DirectorReplay.run`, using the explicitly supplied test study parameters. It projects the returned values and exact parameter inputs to JSON. It creates no app store, camera session or production setting.

Set `ALFIE_DIRECTOR_EVALUATION_EXPORT` on the test process to a **new absolute `.json` path in the system temporary directory**, for example `/private/tmp/alfie-director-evaluation-20261021.json`. With no variable the test performs no export. An existing destination is refused. When invoking `xcodebuild`, forward the variable with the `TEST_RUNNER_` prefix so it reaches the test process:

```sh
TEST_RUNNER_ALFIE_DIRECTOR_EVALUATION_EXPORT=/private/tmp/alfie-director-evaluation-20261021.json \
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests/DirectorEvaluationExportTests CODE_SIGNING_ALLOWED=NO
```

Retain the build/test provenance alongside the exported file. The test uses the unprefixed name inside the runner.

Each fixture gets a fresh opaque session ID. The wire format is described by [director_evaluation_schema.json](../../CinematicCoreMacOS/scripts/director_evaluation_schema.json) and its closed Python validator. It is a separate analysis format, not a new shadow-record or qualification schema. Root keys, scenario metrics and parameter groups are exact: unknown keys, duplicate JSON keys, nonfinite numbers, Boolean counts and unsupported versions refuse input. Committed preparations cannot exceed attempts, accepted acknowledgements cannot exceed committed preparations, and wide cadence must be positive as required by the Swift policy. Replay output cannot be relabelled recorded/live, Auto/Backup, learned-model or real-output evidence. All fields are required; there are no implicit metric defaults.

Current replay lacks independently labelled eligible opportunities, subject-correctness labels on committed preparations and visible UI latency. Their required placeholders remain null. A non-null opportunity count or UI latency is refused in version 1. Wrong-subject **proposals**, wrong-subject **attempts** and independently audited stale **commits** are separate columns. In particular, the panel fixture's expected wrong proposal remains a visible weakness even though the regression test passes.

`DirectorReplay` has no Take entry point and returns zero Director cuts structurally. The report labels this limitation explicitly; it supplies no Auto/Backup cut-safety evidence. Synthetic fixture duration is timeline length, never live exposure. Both real output routes and all per-level sign-offs stay missing.

## Generate the review artifacts

From the repository root, using new output paths:

```sh
python3 CinematicCoreMacOS/scripts/director_evaluation_report.py \
  /private/tmp/alfie-director-evaluation-20261021.json \
  --shadow-bundle CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic-export \
  --shadow-sidecar CinematicCoreMacOS/scripts/fixtures/director-evaluation-shadow-sidecar.json \
  --regression-fixture CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic-export \
  --match-window-seconds 2 \
  --output /private/tmp/alfie-evaluation.md \
  --json-output /private/tmp/alfie-evaluation-results.json \
  --parameter-memo /private/tmp/alfie-parameter-evidence.md
```

The two-second matching window belongs to the supplied authored fixture, not a recommended production setting. C-05 owns the shadow decoder, bundle checks, matching and censored dwell algorithm. The evaluator delegates matching and continuity checks to those APIs.

`--shadow-sidecar` is optional and has exactly `evaluationSchemaVersion` and `shadowBindings`. Version 1 retains one binding per session. Each binding supplies session, actual source class, level, execution mode, declared route/configuration, parameter version and judge/model identity. The example binds only the authored seven-row fixture. It cannot be reused with another session. Embedded bindings in the replay envelope and an external sidecar cannot both be supplied. Missing bindings are visible incomplete scope, not guessed configuration. Unknown parameter versions may be null for shadow evidence. A declared model must actually appear in the records; absent judgements require `unobserved` with a null model.

The evaluator keeps every session, source class, level, execution mode, judge/model, route/configuration and parameter scope separate. A binding that contradicts actual record metadata refuses analysis. Heterogeneous level/mode/model evidence inside one session is conservatively unscored; no cross-scope matching is inferred. Physical route/configuration declarations are not proof of downstream observation. C-05 sequence gaps, drops, action-pair faults and global input failures retain their original suppression behavior.

### Explicit study phases (version 2)

An opt-in version-2 sidecar permits multiple explicitly declared phases in one session. Each binding retains every version-1 scope field and adds a globally unique `phaseID`, inclusive original `firstSequence` / `lastSequence` Counter strings, canonical `parameterContext`, and sorted unique `routeGenerations` Counter strings. See the [decision fixture](../../CinematicCoreMacOS/scripts/fixtures/director-phase-decision-v2.json) and [binding fixture](../../CinematicCoreMacOS/scripts/fixtures/director-phase-binding-v2.json); their opaque session IDs bind only those specific historical exports. New exports require new explicit sidecars.

Every accepted input row must belong to exactly one nonoverlapping phase, both endpoints must exist, and actual evidence class, level, execution mode, complete canonical parameter context, observed judge/model union and route-generation set must match. Missing optional parameter fields remain null. An empty judgement row is neutral within a phase; a phase with no judgements requires `unobserved`. Reusing one configuration ID with different contexts is refused. The declared physical route remains unverified because route generations do not identify downstream devices.

The reporter runs C-05 once on the complete original sessions. It never filters a phase into a new zero-based session: leading loss, gaps, drops, parameter-history conflicts and incomplete pairs still suppress the entire affected session. Prediction matching requires a strictly earlier sequence as well as an in-window clock, and stays inside a phase. A completed Take crossing a phase boundary is retained as an unscored action in its attempt phase. Interior dwell requires both Take pairs and every intervening row to remain in one phase. Accepted level/segment transition pairs still receive whole-session pair validation. Outputs retain separate phase IDs and original strata, and include the exact sidecar SHA-256. No rates are pooled and no qualification follows from an observed phase.

`--regression-fixture` accepts only synthetic, single-session fixture records. Its explicitly authored in-memory cases report baseline matching, a wrong preset, dropped records, a sequence gap, an orphan attempt, an unknown post-Take shot and empty input. They exercise the analysis pipeline, not actual Director effects. No mutated fixture is written back to the input.

Output defaults to stdout. Requested artifacts are created exclusively; existing files are never overwritten. Exit 0 means the analysis completed and may still be incomplete for qualification. Exit 1 means I/O failure, and exit 2 means invalid evaluation metadata or arguments. Read the completeness and missing-evidence sections in all cases. The evaluation input is bounded to 8 MiB and 1,000 replay runs/bindings; these are offline resource bounds, not study settings.

## Parameter evidence and remaining assessment work

The optional memo copies only actual exported replay settings and actual C-05 parameter snapshots. It labels configuration values separately from measured outcomes and summarizes recorded subject-speed scalars, preserving unavailable/invalid samples. Each speed distribution and memo block retains its actual source class, level, execution mode and judge/model scope within the session; unobserved models stay separate from known models. Multiple judge/model identities on the same record preserve reported sample counts but make distribution values unavailable. Shadow rates use normalized frame units/second for speed and shot-ladder steps/second for configured on-air moves. Repeated records are not independent opportunities. Notice length is unavailable in the supported records. A recorded move-rate setting does not establish achieved motion or approve N2.

The memo is **AWAITING OWNER** and makes no numeric recommendation. T1–T3, N4, P3, A4 and N2 still require suitable real observations, a manual baseline, independent opportunities and owner decisions. Existing exported evidence keeps its source class and original retention provenance. Export is not consent, disclosure permission or qualification.

The reporter can expose useful synthetic regressions now. Completing D-06 still needs the frozen per-level plan/budgets, consented recorded validation where required, current R2 rig evidence, actual attended downstream observations on both routes, complete fault/override cells and owner/operator/independent-reviewer sign-off. Do not mark a level qualified from these generated artifacts.

Verification:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s CinematicCoreMacOS/scripts -p test_director_evaluation_report.py -v
```
