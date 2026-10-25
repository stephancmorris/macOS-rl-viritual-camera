# Auto Director evidence and tooling

25 October 2026. Continued at the owner's request, prioritizing Auto Director evidence and tooling. Refreshed the Trello board (194 open cards across eight lists) and inspected the clean branch at `6c11f1b`. The previous verified application candidate and its installed-app distinction remain documented in [the preceding report](../next-ticket-batches-2026-10-24/README.md).

## Grouped work

1. **Report completeness:** [AD-EVIDENCE-STATUS](https://trello.com/c/FsPvuofO), related C-05/D-06. Repair contradictory session/row summaries first. Implemented below.
2. **Parameter evidence attribution:** inspect D-08's subject-speed summaries for segment, configuration and source attribution before using them to prepare any parameter memo. No owner values or numeric recommendations are authorized by synthetic fixtures.
3. **Reproducible study artifacts:** inspect report provenance and explicit input binding. Retain exact source identities and missing evidence rather than inferring successful collection.

The queued initial Program handoff repair remains separate. D-06 real per-level evaluations, D-08 real-data recommendations, frozen owner plans, independent labels, both attended output routes and signatories remain open. Newly proposed Director style defaults and mid-show policy remain owner decisions.

## Report completeness repair

Version-1 evaluation session summaries said `observed` despite dropped records, a missing prefix, an orphan action with no comparison rows, or an unscored completed Take. Two added test definitions reproduced five failing cases before the fix. The analyzer now exposes its authoritative capture-blocked session set independently of optional phase output. The evaluator uses that set and unscored-action status for each session summary. Legacy C-05 Markdown also labels unscored comparisons incomplete. Matching, parameter settings and qualification behavior are unchanged.

Regressions cover the four failures, Markdown, a separate complete session alongside a damaged session, and an unscored legacy Take. All **114 script Python test definitions pass**, zero failures. Baseline and final logs are local at `/private/tmp/alfie-evidence-status-baseline-20261025.log` and `/private/tmp/alfie-evidence-status-all-python-20261025.log`. This slice changes offline Python/report documentation only; the previously verified Swift app binary is unchanged. No new physical or editorial acceptance is claimed.
