# Director shadow report

Metadata observations only; no qualification or tuning recommendation.

Input: explicit-export bundle. Manifest summaries and source age at export are validated.
Export ID: A68D45AE-A30E-4354-9253-6F860A3D709F. Exported at UTC: 2026-10-22T00:00:00.000Z.
Retention: explicitExport. The exported copy is not aged out by the analysis clock.
Manifest validation does not prove complete capture. Session loss checks still apply.

Accepted records: 10. Matching window: 2 seconds (supplied).

Matching: latest unused preceding prediction of the same kind, within the supplied window,
matched to a paired completed operator action at its attempt time. Target and preset must both agree.
Partitions: session, source class, segment/token, parameter/preference versions, policy and route revision.
Agreement = exact / compared; coverage = compared / predictions. Unmatched and unscored counts remain visible.
Malformed input or export metadata suppresses all scoring; sequence loss, backward clocks or incomplete action pairs suppress their session.

| Session | Evidence | Segment | Decision | Parameter version | Predictions | Completed actions | Compared | Exact | Agreement | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- |
| 99CABC9F-E733-42F0-864D-E01088213F0E | synthetic | liveEvent/none; policy 0; route 0; prefs 2 | wouldPrepare | 10 | 1 | 0 | 0 | 0 | unavailable | 1 | 0 | 0 | observed |
| 99CABC9F-E733-42F0-864D-E01088213F0E | synthetic | liveEvent/none; policy 0; route 0; prefs 2 | wouldCut | 11 | 1 | 1 | 1 | 1 | 1/1 | 0 | 0 | 0 | observed |

## Abstentions

Reason totals count reasons, not independent opportunities.

- synthetic / liveEvent / observation / cutPolicyUnavailable: 2

## Interior Program dwell

Seconds between consecutive completed Takes with continuous roles and no observed disruption.
First/last censored holds and missing intervals are excluded; this is not downstream presentation.

Unavailable: no complete continuous interior dwell intervals.

## Completeness

- operator_accepted: 2
Zero reported loss does not prove complete capture. No source frames or raw rejected content are included.
