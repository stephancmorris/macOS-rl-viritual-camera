# Director evaluation observations

**Synthetic software evidence. Qualification incomplete; no operating permission or parameter recommendation.**

Input SHA-256: `0789608de68a766193538a10bf270f0dc038d434a8676b271d3547395d4d58d7`.

Shadow sidecar SHA-256: `c07bfbc0f242c801179b6cf37b6434419154b26600d91c44aba7e22039989173`.

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

- calm-presenter: `B09BF636-2BD0-4451-A776-B0642F4FD9B2` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- walking-presenter: `63CA243D-FB3E-4152-A8E0-060249A9AC16` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- panel-of-three: `952C6A95-27A3-4530-B642-46F88CFBBCDE` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{}`.
- camera-b-drops: `CA27368C-A341-4714-A34E-8A48CEA636A5` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1, "sourceMissing": 1, "sourceRestarted": 1}`.
- operator-intervention: `97FF20D4-D882-4713-B520-92743C9E859B` / synthetic / assist / observing / route none / replay-study-1 / parameters 1 / rules:none. Synthetic timeline: 60 s. Rejection reasons: `{"authorityRevoked": 1, "shotChangedByOperator": 1}`.

| Scenario | Unauthorized Program changes | Minimum-duration violations | Proposals while paused | Oscillations | Failed effects | Rejected attempts | Clock anomalies |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| calm-presenter | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| walking-presenter | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| panel-of-three | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| camera-b-drops | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| operator-intervention | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

DirectorReplay has no Take entry point. Its zero Director cuts is structural and does not demonstrate Auto or Backup cut safety. Synthetic timeline seconds are not live exposure.
Useful-preparation coverage, wrong committed-subject rate, visible override latency and downstream presentation are unavailable. Missing values are never replaced with zero.


Records SHA-256: `d913c617a0986462502228fe7f4efee3c9471f489c168f0175f9859436df3ed2`.
Manifest SHA-256: `2cfe8be808bd39dbe4794a28bef4685dd8a33394c16e1a047fe9d502fef54958`.
Fingerprints identify consumed bytes, not consent, complete capture or qualification. Partial bounded reads have no full-file fingerprint.

## C-05 shadow observations

Accepted records: 7. Explicit export validated: true.

Agreement describes operator matching, not independent correctness. Bindings are declared evaluation scope, not verified physical-route observations.

| Session | Scope | Exact / compared | Predictions | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 73CA8376-001F-5EB7-B23C-AD2FA2F82A33 | synthetic / suggest / shadow / none / authored-shadow-fixture-1 / 1 / unobserved / None | 1/1 | 1 | 0 | 0 | 0 | observed |
| 73CA8376-001F-5EB7-B23C-AD2FA2F82A33 | synthetic / suggest / shadow / none / authored-shadow-fixture-1 / 1 / unobserved / None | 1/1 | 1 | 0 | 0 | 0 | observed |

- Session `73CA8376-001F-5EB7-B23C-AD2FA2F82A33`: actual scopes `[["synthetic", "suggest", "shadow"]]`, judge/models `[]`; scope observed.
- Abstention reasons synthetic / presenter / policy / minimumDuration: 1. Reasons are not independent opportunities.
- Interior dwell `["73CA8376-001F-5EB7-B23C-AD2FA2F82A33", "synthetic", "presenter", null, "1", 2, "1", "2"]`: n=1, min=10, median=10, max=10 s. Censored first/last holds excluded.
Completeness issues: `{}`. Scope gaps: `[]`. Zero reported loss does not prove full capture.

## Authored synthetic C-05 regression matrix

These in-memory fixture mutations exercise analysis behavior; they are not camera or sink observations.

| Case | Predictions | Completed operator actions | Compared | Exact | Unscored actions | Interior dwell seconds | Capture status |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 2 | 2 | 2 | 2 | 0 | 10 | observed |
| wrongPredictedPreset | 2 | 2 | 2 | 1 | 0 | 10 | observed |
| reportedDrop | 2 | 2 | 0 | 0 | 2 | unavailable | incomplete |
| sequenceGap | 2 | 2 | 0 | 0 | 2 | unavailable | incomplete |
| orphanAttempt | 1 | 0 | 0 | 0 | 0 | unavailable | incomplete |
| unknownPostTakeShot | 2 | 2 | 1 | 1 | 1 | 10 | incomplete |
| empty | 0 | 0 | 0 | 0 | 0 | unavailable | incomplete |

## Missing assessment evidence

- ownerFrozenPlanAndBudgets
- independentEligibleOpportunityLabels
- labelledCommittedPreparationOutcomes
- recordedValidation
- r2RigEvidence
- bothObservedLiveOutputRoutes
- perLevelSignatories

Assist, Auto and Backup remain incomplete without their required real evidence and explicit owner, event-operator and independent-reviewer sign-off. This tool never creates a qualification record.
