# Director shadow report

Metadata observations only; no qualification or tuning recommendation.

Input: explicit-export bundle. Manifest summaries and source age at export are validated.
Export ID: 10782666-258C-439D-9FC9-44ED4E22963C. Exported at UTC: 2026-10-18T00:00:00.000Z.
Retention: explicitExport. The exported copy is not aged out by the analysis clock.
Manifest validation does not prove complete capture. Session loss checks still apply.

Accepted records: 16. Matching window: 2 seconds (supplied).

Matching: latest unused preceding prediction of the same kind, within the supplied window,
matched to a paired completed operator action at its attempt time. Target and preset must both agree.
Partitions: session, source class, segment/token, parameter/preference versions, policy and route revision.
Agreement = exact / compared; coverage = compared / predictions. Unmatched and unscored counts remain visible.
Malformed input or export metadata suppresses all scoring; sequence loss, backward clocks or incomplete action pairs suppress their session.

| Session | Evidence | Segment | Decision | Parameter version | Predictions | Completed actions | Compared | Exact | Agreement | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- |
| 14EB93DE-C807-42A8-AEB5-53F5B601EFCC | synthetic | panel/BF175B8B-8758-474E-B02B-98863C5E8910; policy 2; route 0; prefs unknown | wouldCut | unknown | 0 | 1 | 0 | 0 | unavailable | 0 | 0 | 1 | observed |

## Abstentions

Reason totals count reasons, not independent opportunities.

No observed abstentions.

## Interior Program dwell

Seconds between consecutive completed Takes with continuous roles and no observed disruption.
First/last censored holds and missing intervals are excluded; this is not downstream presentation.

Unavailable: no complete continuous interior dwell intervals.

## Completeness

- operator_accepted: 4
- operator_refused: 2
- operator_unobserved: 1
Zero reported loss does not prove complete capture. No source frames or raw rejected content are included.
