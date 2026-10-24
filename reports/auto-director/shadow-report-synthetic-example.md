# Director shadow report

Metadata observations only; no qualification or tuning recommendation.

Input: explicit-export bundle. Manifest summaries and source age at export are validated.
Export ID: 3C38781E-8078-4D22-912E-0FB9A9C50154. Exported at UTC: 2026-10-19T00:00:00.000Z.
Retention: explicitExport. The exported copy is not aged out by the analysis clock.
Manifest validation does not prove complete capture. Session loss checks still apply.

Accepted records: 7. Matching window: 2 seconds (supplied).

Matching: latest unused preceding prediction of the same kind, within the supplied window,
matched to a paired completed operator action at its attempt time. Target and preset must both agree.
Partitions: session, source class, segment/token, parameter/preference versions, policy and route revision.
Agreement = exact / compared; coverage = compared / predictions. Unmatched and unscored counts remain visible.
Malformed input or export metadata suppresses all scoring; sequence loss, backward clocks or incomplete action pairs suppress their session.

| Session | Evidence | Segment | Decision | Parameter version | Predictions | Completed actions | Compared | Exact | Agreement | Unmatched predictions | Unmatched actions | Unscored actions | Status |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- |
| 73CA8376-001F-5EB7-B23C-AD2FA2F82A33 | synthetic | presenter/none; policy 1; route 1; prefs 2 | wouldCut | 1 | 2 | 2 | 2 | 2 | 2/2 | 0 | 0 | 0 | observed |

## Abstentions

Reason totals count reasons, not independent opportunities.

- synthetic / presenter / policy / minimumDuration: 1

## Interior Program dwell

Seconds between consecutive completed Takes with continuous roles and no observed disruption.
First/last censored holds and missing intervals are excluded; this is not downstream presentation.

- 73CA8376-001F-5EB7-B23C-AD2FA2F82A33 / synthetic / presenter / parameters 1: n=1, min=10, median=10, max=10 s

## Completeness

Zero reported loss does not prove complete capture. No source frames or raw rejected content are included.
