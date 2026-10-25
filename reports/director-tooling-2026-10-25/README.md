# Auto Director evidence and tooling

25 October 2026. Continued at the owner's request, prioritizing Auto Director evidence and tooling. Refreshed the Trello board (194 open cards across eight lists) and inspected the clean branch at `6c11f1b`. The previous verified application candidate and its installed-app distinction remain documented in [the preceding report](../next-ticket-batches-2026-10-24/README.md).

**18:01 AEDT refresh:** fetched `origin/main` at `952d05d`, which now includes PRs #78–#80 (Director style decisions, Settings sidebar/appearance, feel controls). The newly recorded F2/F3 and SU-1–SU-5 decisions supersede the earlier statement below that style defaults and mid-show policy were open. They remain provisional study parameters, not level qualification. This branch has not integrated those newer app/UI commits; its earlier app artifact is not a current-main build. Trello also shows SU-03/SU-06/SU-07/SU-08 actively assigned elsewhere. This follow-up remains in the separate offline reporting files and does not duplicate those tasks. No app integration, binary or native verification is claimed for the new main.

## Grouped work

**Current-main software check:** independently exported the unmodified `origin/main` commit `952d05d` into a new temporary directory without changing this checkout or integrating branches. Its full app test target passed **1,090 definitions / 1,683 expanded cases**, zero failures and three explicit investigation/consented-folder/real-camera skips. Existing synthetic CoreML CPU interoperability was configured and passed. The unsigned Release app and extension also build; the embedded source fingerprint matches `11ec9c50c05b64047296e2a681da364122a7c2f00ea39694eaf3e346be5a4329`. Exact sanitized provenance and binary hash are in [current-main-validation.json](current-main-validation.json). This verifies the newly merged Settings/feel source independently of the repairs on this branch. It does not verify their combined integration, native usability, receiver output, installation or Director level qualification. No installed app was changed. The earlier 18:01 note's lack of current-main binary verification is superseded by this check.

1. **Report completeness:** [AD-EVIDENCE-STATUS](https://trello.com/c/FsPvuofO), related C-05/D-06. Repair contradictory session/row summaries first. Implemented below.
2. **Parameter evidence attribution:** inspect D-08's subject-speed summaries for segment, configuration and source attribution before using them to prepare any parameter memo. No owner values or numeric recommendations are authorized by synthetic fixtures.
3. **Reproducible study artifacts:** inspect report provenance and explicit input binding. Retain exact source identities and missing evidence rather than inferring successful collection.

The queued initial Program handoff repair remains separate. D-06 real per-level evaluations, D-08 real-data recommendations, frozen owner plans, independent labels, both attended output routes and signatories remain open. Newly proposed Director style defaults and mid-show policy remain owner decisions.

## Parameter evidence attribution

[AD-PARAMETER-ATTRIBUTION](https://trello.com/c/nB2el8ZI) reproduced five failing cases: legacy distributions mixed segment types, segment instances, parameter contexts and channels, while explicit phases also mixed channels. One shared summarizer now partitions those dimensions inside existing evidence/level/mode/model/phase boundaries. Each block retains the actual settings and input channel. Missing/invalid samples remain attributed; a settings-only row preserves a null channel without inventing a measurement. Channels are recorded labels, not proof of persistent physical source or subject identity.

All **117 script Python test definitions pass**, zero failures. Additional regressions preserve both channels' reported, unavailable and invalid counts in legacy and phase reports and check the generated memo. Baseline and final logs: `/private/tmp/alfie-parameter-attribution-baseline-20261025.log` and `/private/tmp/alfie-parameter-attribution-all-python-20261025.log`. This changes offline summaries only. No numeric recommendation, schema change, app policy or qualification follows.

## Exact input fingerprints

[AD-EVIDENCE-FINGERPRINT](https://trello.com/c/sB0AbpE0) adds exact-byte SHA-256 identities for shadow records and their export manifest, using the same bounded reads that feed analysis. Separate complete malformed inputs retain identities while scoring stays blocked. Missing or limited reads have unavailable full-file hashes. C-05 Markdown and D-06 JSON/Markdown/memos retain these identities. External sidecars are now identified in both version 1 and 2; embedded bindings remain covered by the evaluation input hash. Paths and rejected content are omitted.

All **120 script Python definitions and 14 Director training definitions pass**, zero failures. Regressions compare exact fixture bytes, whitespace variants, malformed and empty input, record/line/byte limits, valid bundle identities, bounded manifest reads, legacy and phase artifact propagation, and version-1 external sidecars. Logs: `/private/tmp/alfie-fingerprint-final-python-20261025.log` and `/private/tmp/alfie-fingerprint-training-20261025.log`. Hash identity is not source authentication or qualification. This remains offline tooling with no app-binary changes.

The current CLI was also run end to end against the retained **21 October historical Swift synthetic replay export**, the existing seven-record synthetic shadow fixture, its version-1 sidecar and authored negative-regression fixture, using the explicit fixture matching window of two seconds. The regenerated [analysis](evidence/historical-synthetic-analysis.md), [JSON](evidence/historical-synthetic-analysis.json) and [parameter evidence](evidence/historical-parameter-evidence.md) demonstrate the current output. This is reanalysis of existing synthetic bytes, not a new Swift execution, real rehearsal or parameter recommendation. All qualification remains incomplete.

## Continued work window

The renewed request was received around 17:41 AEDT on 25 October. A thread heartbeat named **ALFIE Director tooling work window** is active every 15 minutes through 22:41 AEDT today, with explicit instructions to avoid overlapping active work and to stop at the deadline. The older goal remains platform-marked usage-limited; a replacement goal was refused because it is unfinished. No goal was falsely marked complete and no reset credit was consumed. The latest usage snapshot allowed ordinary usage (5% of the primary window used); consumption is not an acceptance criterion.

## Legacy Python binding validation

[AD-BINDING-API](https://trello.com/c/v5e2dwnA) closes a mismatch between the version-1 direct Python API and the CLI/version-2 paths. Direct calls silently accepted duplicate conflicting session declarations, arbitrary configuration text, unsupported routes and unknown keys. The existing closed validator now runs before reading evidence. Missing valid bindings still produce explicit incomplete scope, and valid legacy/phase behavior is preserved.

One regression definition reproduced **four failing cases** before repair, plus a learned-model-without-version control already refused. All **121 script Python definitions pass**, zero failures. The regression also supplies a missing evidence path and verifies that invalid metadata is refused before file access. Baseline/final logs: `/private/tmp/alfie-binding-api-baseline-20261025.log` and `/private/tmp/alfie-binding-api-final-20261025.log`. No new schema or acceptance rule was introduced.

## Dataset consumed-byte integrity

[AD-DATASET-DIGEST](https://trello.com/c/8vf2UFYx) uses the new same-read fingerprints to close a C-10 dataset provenance gap. The loader previously hashed files before and after parsing, but a file replaced only during parsing could pass those checks while supplying different metadata. Deterministic temporary-file regressions replaced records and manifest separately, restored the original file before the post-read checks, and reproduced two failures. The loader now also compares the bounded parser's consumed-byte hashes to the initial digests. Existing post-read checks remain.

All **15 Director training and 121 script Python definitions pass**, zero failures. The ordinary synthetic corpus explicitly retains the exact manifest/records hashes. No labels, features, splits, model parameters, app code or qualification changed. Logs: `/private/tmp/alfie-dataset-digest-baseline-20261025.log`, `/private/tmp/alfie-dataset-digest-training-20261025.log`, `/private/tmp/alfie-dataset-digest-scripts-20261025.log`. Trello refresh still shows the Director style tasks active elsewhere; they were not duplicated.

## Matching-window provenance

[AD-MATCH-WINDOW](https://trello.com/c/PfUxs7j0) retains the actual caller-supplied matching window in legacy and phase evaluation JSON, Markdown and parameter memos, plus every authored negative-regression row. Previously exact file hashes could identify inputs while omitting the analysis setting that changes agreement counts. No default or recommended value was introduced.

The regression reproduced four missing-field errors before repair. All **122 script Python definitions pass**, zero failures. Zero, fractional and custom windows are retained; the historical synthetic fixture compares zero actions with 0/0.05 seconds and two actions with 2.75 seconds. A separate end-to-end CLI reanalysis of retained historical synthetic exports verified the JSON, report and memo at an explicitly supplied 2.75 seconds, with qualification still false. Logs/artifacts: `/private/tmp/alfie-match-window-baseline-20261025.log`, `/private/tmp/alfie-match-window-final-20261025.log`, `/private/tmp/alfie-matching-window-20261025.json`, `/private/tmp/alfie-matching-window-20261025.md`, `/private/tmp/alfie-matching-window-memo-20261025.md`. This is analysis reproducibility, not a new recording or operating parameter. Refreshed main remains `952d05d`; active style tasks remain separate.

## Judge participation within phases

[AD-PHASE-MODEL-SAMPLES](https://trello.com/c/2BkIe1XZ) extends parameter attribution to the actual judge/model observations on each row inside an explicit phase. Empty judgement rows were neutral for phase validation but their speed samples were pooled into the observed model's distribution. A synthetic phase with four learned-model rows at 0.1 and three unobserved rows at 0.9 reproduced one pooled block. The two distributions now remain separate, retaining their sample counts and phase. The phase declaration is named explicitly as `declaredJudgeKind` / `declaredModelVersion` beside actual `judgeModels`; full bindings remain unchanged.

All **123 script Python definitions pass**, zero failures. The existing legacy mixed-model, missingness, actual phase-fixture and matching tests remain green. Logs: `/private/tmp/alfie-phase-model-attribution-baseline-20261025.log` and `/private/tmp/alfie-phase-model-attribution-final-20261025.log`. No new model observations, matching, settings or qualification are inferred. Main and active UI task status were refreshed and remain separate.

## Declared evidence inventory

[AD-EVIDENCE-INVENTORY](https://trello.com/c/URMUc3OZ) replaces the evaluation's unconditional synthetic heading with an explicit inventory: replay scenarios and accepted shadow records remain separate units, each retaining its declared evidence class. JSON, Markdown and parameter memos show the same inventory. Declared recorded/live classes are not authentication or verified exposure, and capture failures continue to suppress scoring.

All **124 script Python definitions pass**, zero failures. Authored synthetic-fixture class mutations exercise all three labels without collecting real recorded/live data; explicit phase totals remain seven synthetic records. Baseline/final logs: `/private/tmp/alfie-evidence-inventory-baseline-20261025.log`, `/private/tmp/alfie-evidence-inventory-final-20261025.log`. No input/record schema, app behavior or qualification changed.

## Report completeness repair

Version-1 evaluation session summaries said `observed` despite dropped records, a missing prefix, an orphan action with no comparison rows, or an unscored completed Take. Two added test definitions reproduced five failing cases before the fix. The analyzer now exposes its authoritative capture-blocked session set independently of optional phase output. The evaluator uses that set and unscored-action status for each session summary. Legacy C-05 Markdown also labels unscored comparisons incomplete. Matching, parameter settings and qualification behavior are unchanged.

Regressions cover the four failures, Markdown, a separate complete session alongside a damaged session, and an unscored legacy Take. All **114 script Python test definitions pass**, zero failures. Baseline and final logs are local at `/private/tmp/alfie-evidence-status-baseline-20261025.log` and `/private/tmp/alfie-evidence-status-all-python-20261025.log`. This slice changes offline Python/report documentation only; the previously verified Swift app binary is unchanged. No new physical or editorial acceptance is claimed.
