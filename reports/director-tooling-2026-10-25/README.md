# Auto Director evidence and tooling

25 October 2026. Continued at the owner's request, prioritizing Auto Director evidence and tooling. Refreshed the Trello board (194 open cards across eight lists) and inspected the clean branch at `6c11f1b`. The previous verified application candidate and its installed-app distinction remain documented in [the preceding report](../next-ticket-batches-2026-10-24/README.md).

## Grouped work

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

## Report completeness repair

Version-1 evaluation session summaries said `observed` despite dropped records, a missing prefix, an orphan action with no comparison rows, or an unscored completed Take. Two added test definitions reproduced five failing cases before the fix. The analyzer now exposes its authoritative capture-blocked session set independently of optional phase output. The evaluator uses that set and unscored-action status for each session summary. Legacy C-05 Markdown also labels unscored comparisons incomplete. Matching, parameter settings and qualification behavior are unchanged.

Regressions cover the four failures, Markdown, a separate complete session alongside a damaged session, and an unscored legacy Take. All **114 script Python test definitions pass**, zero failures. Baseline and final logs are local at `/private/tmp/alfie-evidence-status-baseline-20261025.log` and `/private/tmp/alfie-evidence-status-all-python-20261025.log`. This slice changes offline Python/report documentation only; the previously verified Swift app binary is unchanged. No new physical or editorial acceptance is claimed.
