# Director evaluation observations

**Evaluation observations. Qualification incomplete; no operating permission or parameter recommendation.**

Input SHA-256: `fbbe869ba9ad3014afcda1413a7800892dc7a08fea59745021bbe4456711139d`.

Shadow sidecar SHA-256: `7a0a129d291d77a5b40185eb69499c23a0e3e264b1ca42c5c3077340f95b954f`.

Every scenario is kept in its own session, level, evidence, execution, route, configuration, parameter and judge/model partition. Rates are not pooled.

| Level | Synthetic scenarios | Assessment | Direct live output | Virtual Camera live output |
| --- | ---: | --- | --- | --- |
| assist | 5 | incomplete | notRun | notRun |
| auto | 0 | notRun | notRun | notRun |
| backup | 0 | notRun | notRun | notRun |

## Supplied evidence inventory

| Input unit | Declared evidence class | Accepted count |
| --- | --- | ---: |
| Replay scenarios | synthetic | 5 |
| Shadow records | synthetic | 6 |

Counts retain their input units and declared classes. They do not authenticate collection, establish exposure or prove complete capture.

## Actual replay scenario measurements

Wrong proposals and attempts are separate from commits. The replay does not label committed subject correctness or independent useful opportunities.

| Scenario | Attempted / committed preparations | Wrong / labelled proposals | Wrong / labelled attempts | Stale commits / all commits | Operator cuts / attempts | Overrides honoured | UI latency | Software observation |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| calm-presenter | 1 / 1 | 0/1 | 0/1 | 0/1 | 0 / 0 | 0 | unavailable | observed |
| walking-presenter | 1 / 1 | 0/1 | 0/1 | 0/1 | 0 / 0 | 0 | unavailable | observed |
| panel-of-three | 1 / 1 | 1/1 | 1/1 | 0/1 | 0 / 0 | 0 | unavailable | observed; wrongSubjectProposalObserved, wrongSubjectAttemptObserved |
| camera-b-drops | 1 / 1 | 0/1 | 0/1 | 0/1 | 0 / 0 | 0 | unavailable | observed |
| operator-intervention | 1 / 1 | 0/1 | 0/1 | 0/1 | 1 / 1 | 1 | unavailable | observed |

- calm-presenter: `39C7C556-F73D-4BE9-A67E-B3C0525EFA6C` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- walking-presenter: `1C7D27D8-CB53-451A-9262-406F1A915F53` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- panel-of-three: `F2E5A883-7FB3-499C-B47F-66F771B1EFE7` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- camera-b-drops: `E4D72660-6D31-46A8-BBFD-B1E878FD99B4` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1, "sourceMissing": 1, "sourceRestarted": 1}`.
- operator-intervention: `12F023DF-CC43-4DD2-82A8-5BAFD7889619` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1}`.

| Scenario | Unauthorized Program changes | Minimum-duration violations | Proposals while paused | Oscillations | Failed effects | Rejected attempts | Clock anomalies |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| calm-presenter | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| walking-presenter | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| panel-of-three | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| camera-b-drops | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| operator-intervention | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

DirectorReplay has no Take entry point. Its zero Director cuts is structural and does not demonstrate Auto or Backup cut safety. Synthetic timeline seconds are not live exposure.
Useful-preparation coverage, wrong committed-subject rate, visible override latency and downstream presentation are unavailable. Missing values are never replaced with zero.


Records SHA-256: `c6a9a80707e404428924f290e12c202078e1799271a8f27136f28d7cdbd4cda5`.
Manifest SHA-256: `fb395d017164a387d437f5b6bc166662deeb4a47b36290ad3513cd3c43a71828`.
Fingerprints identify consumed bytes, not consent, complete capture or qualification. Partial bounded reads have no full-file fingerprint.

## C-05 shadow observations

Accepted records: 6. Explicit export validated: true.

Matching window: 2 seconds (supplied). This is an analysis setting, not a directing recommendation.

Agreement describes operator matching, not independent correctness. Bindings are declared evaluation scope, not verified physical-route observations.

| Session | Scope | Exact / compared | Predictions | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
No comparison opportunities observed; agreement is unavailable.

- Session `C9F2A03B-869C-42F8-A3F0-07D5460025EC`: actual scopes `[["synthetic", "off", "shadow"]]`, judge/models `[["rules", null]]`; scope observed.

Version 2 phases cover accepted records once in their original inclusive sequence spans. Full-session capture and pair checks remain in force. Physical routes are unverified declared labels; route generations are observed metadata. No agreement or dwell crosses a phase boundary.

- Phase `capture-binding-1` / session `C9F2A03B-869C-42F8-A3F0-07D5460025EC`: original sequences 0–2, 3 accepted records; route generations `["0"]`; scope observed.
- Phase `capture-binding-2` / session `C9F2A03B-869C-42F8-A3F0-07D5460025EC`: original sequences 3–5, 3 accepted records; route generations `["0"]`; scope observed.
- Abstention reasons C9F2A03B-869C-42F8-A3F0-07D5460025EC / synthetic / panel / 85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D / 11 / 2 / 1 / 0 / capture-binding-2 / observation / unclassified: 2. Reasons are not independent opportunities.
- Abstention reasons C9F2A03B-869C-42F8-A3F0-07D5460025EC / synthetic / presenter / 0CA82695-0370-0AFC-BB85-CE893773676C / 10 / 2 / 0 / 0 / capture-binding-1 / observation / unclassified: 2. Reasons are not independent opportunities.
Interior dwell unavailable.
Completeness issues: `{"operator_accepted": 1}`. Scope gaps: `[]`. Zero reported loss does not prove full capture.

## Missing assessment evidence

- ownerFrozenPlanAndBudgets
- independentEligibleOpportunityLabels
- labelledCommittedPreparationOutcomes
- recordedValidation
- r2RigEvidence
- bothObservedLiveOutputRoutes
- perLevelSignatories

Assist, Auto and Backup remain incomplete without their required real evidence and explicit owner, event-operator and independent-reviewer sign-off. This tool never creates a qualification record.
