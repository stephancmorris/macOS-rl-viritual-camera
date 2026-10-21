# Director evaluation observations

**Synthetic software evidence. Qualification incomplete; no operating permission or parameter recommendation.**

Input SHA-256: `fb44cde90b269fefeb32a0289d3e2f87af3e5d8f019d2dc541f4b6c7fca13067`.

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

- calm-presenter: `C273948F-74FF-4FB5-A108-7B329B3C131F` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- walking-presenter: `EBD631B0-3151-429D-8565-7FAEB2502945` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- panel-of-three: `E7D7AE2B-6EB7-4DED-8733-E0E71CA6751A` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- camera-b-drops: `4F3C6E40-706A-4EC2-8C45-A6593FB9E833` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1, "sourceMissing": 1, "sourceRestarted": 1}`.
- operator-intervention: `449F9694-6D0E-448D-827F-6A06953F2245` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1}`.

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

Accepted records: 10. Explicit export validated: true.

Agreement describes operator matching, not independent correctness. Bindings are declared evaluation scope, not verified physical-route observations.

| Session | Scope | Exact / compared | Predictions | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 953ECAC0-B8CE-44CB-8DC5-CB4DECE5F394 | unbound | unavailable | 1 | 1 | 0 | 0 | incomplete |
| 953ECAC0-B8CE-44CB-8DC5-CB4DECE5F394 | unbound | unavailable | 1 | 0 | 0 | 1 | incomplete |

- Session `953ECAC0-B8CE-44CB-8DC5-CB4DECE5F394`: actual scopes `[["synthetic", "assist", "observing"], ["synthetic", "auto", "observing"], ["synthetic", "off", "shadow"]]`, judge/models `[]`; scope incomplete.
- Abstention reasons synthetic / liveEvent / observation / cutPolicyUnavailable: 2. Reasons are not independent opportunities.
Interior dwell unavailable.
Completeness issues: `{"operator_accepted": 2}`. Scope gaps: `[{"reason": "missingShadowBinding", "sessionID": "953ECAC0-B8CE-44CB-8DC5-CB4DECE5F394"}, {"reason": "mixedLevelModeOrModel", "sessionID": "953ECAC0-B8CE-44CB-8DC5-CB4DECE5F394"}]`. Zero reported loss does not prove full capture.

## Missing assessment evidence

- ownerFrozenPlanAndBudgets
- independentEligibleOpportunityLabels
- labelledCommittedPreparationOutcomes
- recordedValidation
- r2RigEvidence
- bothObservedLiveOutputRoutes
- perLevelSignatories

Assist, Auto and Backup remain incomplete without their required real evidence and explicit owner, event-operator and independent-reviewer sign-off. This tool never creates a qualification record.
