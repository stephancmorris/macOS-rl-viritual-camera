# Director evaluation observations

**Synthetic software evidence. Qualification incomplete; no operating permission or parameter recommendation.**

Input SHA-256: `27f07553f1cc287888c5ca64e93cf7c6cc949f1608aa3280ebd9d35079585aad`.

Every scenario is kept in its own session, level, evidence, execution, route, configuration, parameter and judge/model partition. Rates are not pooled.

| Level | Synthetic scenarios | Assessment | Direct live output | Virtual Camera live output |
| --- | ---: | --- | --- | --- |
| assist | 5 | incomplete | notRun | notRun |
| auto | 0 | notRun | notRun | notRun |
| backup | 0 | notRun | notRun | notRun |

## Actual replay scenario measurements

Wrong proposals and attempts are separate from commits. The replay does not label committed subject correctness or independent useful opportunities.

| Scenario | Attempted / committed preparations | Wrong / labelled proposals | Wrong / labelled attempts | Stale commits / all commits | Operator cuts / attempts | Overrides honoured | UI latency | Software observation |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| calm-presenter | 1 / 1 | 0/1 | 0/1 | 0/1 | 0 / 0 | 0 | unavailable | observed |
| walking-presenter | 1 / 1 | 0/1 | 0/1 | 0/1 | 0 / 0 | 0 | unavailable | observed |
| panel-of-three | 1 / 1 | 1/1 | 1/1 | 0/1 | 0 / 0 | 0 | unavailable | observed; wrongSubjectProposalObserved, wrongSubjectAttemptObserved |
| camera-b-drops | 1 / 1 | 0/1 | 0/1 | 0/1 | 0 / 0 | 0 | unavailable | observed |
| operator-intervention | 1 / 1 | 0/1 | 0/1 | 0/1 | 1 / 1 | 1 | unavailable | observed |

- calm-presenter: `8DF5EB60-C30D-4E04-B93A-BF92D0BF50FF` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- walking-presenter: `E93664CF-A73D-4D5D-BF5A-0E0FFE4AAA74` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- panel-of-three: `FB8B8CAC-7646-46B5-A4C1-C6F5A1E1B8AF` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- camera-b-drops: `E3E189F2-A3E5-47F3-A3EB-E8D15F1B7AB5` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1, "sourceMissing": 1, "sourceRestarted": 1}`.
- operator-intervention: `19997F24-2BB4-47A0-8524-0F22F4E09A45` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1}`.

| Scenario | Unauthorized Program changes | Minimum-duration violations | Proposals while paused | Oscillations | Failed effects | Rejected attempts | Clock anomalies |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| calm-presenter | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| walking-presenter | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| panel-of-three | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| camera-b-drops | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| operator-intervention | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

DirectorReplay has no Take entry point. Its zero Director cuts is structural and does not demonstrate Auto or Backup cut safety. Synthetic timeline seconds are not live exposure.
Useful-preparation coverage, wrong committed-subject rate, visible override latency and downstream presentation are unavailable. Missing values are never replaced with zero.

## C-05 shadow observations

Accepted records: 6. Explicit export validated: true.

Agreement describes operator matching, not independent correctness. Bindings are declared evaluation scope, not verified physical-route observations.

| Session | Scope | Exact / compared | Predictions | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
No comparison opportunities observed; agreement is unavailable.

- Session `3456E9E2-5348-47C8-A44B-59186EFB78B5`: actual scopes `[["synthetic", "off", "shadow"]]`, judge/models `[["rules", null]]`; scope observed.

Version 2 phases cover accepted records once in their original inclusive sequence spans. Full-session capture and pair checks remain in force. Physical routes are unverified declared labels; route generations are observed metadata. No agreement or dwell crosses a phase boundary.

- Phase `capture-binding-1` / session `3456E9E2-5348-47C8-A44B-59186EFB78B5`: original sequences 0–2, 3 accepted records; route generations `["0"]`; scope observed.
- Phase `capture-binding-2` / session `3456E9E2-5348-47C8-A44B-59186EFB78B5`: original sequences 3–5, 3 accepted records; route generations `["0"]`; scope observed.
- Abstention reasons 3456E9E2-5348-47C8-A44B-59186EFB78B5 / synthetic / panel / 615D0875-6CC5-23EF-B488-E2C9F05061A7 / 11 / 2 / 1 / 0 / capture-binding-2 / observation / unclassified: 2. Reasons are not independent opportunities.
- Abstention reasons 3456E9E2-5348-47C8-A44B-59186EFB78B5 / synthetic / presenter / D0C95A18-4CC6-28ED-BE93-3FE2F28D4BAD / 10 / 2 / 0 / 0 / capture-binding-1 / observation / unclassified: 2. Reasons are not independent opportunities.
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
