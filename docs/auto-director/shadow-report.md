# Director shadow report CLI

C-05 is an offline, metadata-only analysis tool. It reads A-09 schema-1 JSONL and produces Markdown. It does not open cameras, upload data, choose directing parameters or write qualification records.

From the repository root:

```sh
python3 CinematicCoreMacOS/scripts/director_shadow_report.py \
  CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic.jsonl \
  --match-window-seconds 2 --output /tmp/director-shadow-example.md
python3 -m unittest discover -s CinematicCoreMacOS/scripts -p test_director_shadow_report.py -v
```

The two-second window is a supplied synthetic fixture value, not a production recommendation. A matching window is always required. Output defaults to stdout; --output creates a new file and refuses to overwrite one. Exit status is 0 for an analyzed file (which may still have incomplete sessions), 2 for malformed/unsupported/limited input or invalid arguments, and 1 for an I/O failure. Check the Completeness section even after exit 0.

The [fixture](../../CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic.jsonl) contains seven generated records, two matched operator cuts, one abstention and one ten-second interior Program interval. The [example report](../../reports/auto-director/shadow-report-synthetic-example.md) is deterministic and includes its synthetic provenance. Swift's actual DirectorShadowRecord decoder also checks this fixture in DirectorReviewRegressionTests.

## Comparison rules

Prepare and cut decisions have separate rows, partitioned by session, evidence class, segment/token, parameter/preference versions, policy and route revision. No synthetic/recorded/live denominator is pooled. Within a partition, each paired completed operator action uses the latest unused preceding prediction of that kind inside the supplied window. Selection occurs before checking agreement, so a more agreeable older prediction cannot replace a recent mismatch. A match requires both target and preset.

An operator Take counts only after a correlated attempt and completed result name the observed Program/Preview swap. An accepted/refused/unobserved action is not a completed cut. A preparation comparison requires a completed off-air selectPreset with its shot. Missing post-Take shot or parameter information is unscored. Agreement is exact/compared; compared and total prediction counts expose coverage. Unmatched predictions/actions and unscored actions remain visible.

Only consecutive completed Takes with continuous role/parameter scope and no observed intervening disruption support interior dwell. The tool reports count/minimum/median/maximum in seconds. First/last censored holds are excluded. Routing metadata is not proof of downstream presentation or useful subject coverage.

## Invalid and incomplete evidence

The companion director_shadow_schema.json mirrors schema-1 typed fields/enums from DirectorShadowRecord.swift. Unknown fields, duplicate JSON keys, unsupported schemas, malformed tokens/counters/clocks, invalid event payloads and media-like additions refuse the record. Cross-field checks protect the analysis; this reader does not replace the app's authoritative serializer or validate human consent/ground truth. Schema changes require an explicit reader/table review.

Malformed/unattributable input suppresses all scoring. Identified sequence gaps, a missing prefix, reported drops, backward clocks, inconsistent parameter versions or incomplete/duplicate/inconsistent action pairs suppress their session's agreement and dwell. Observed abstention reasons remain descriptive counts, not independent opportunities. Sequence gaps and reported drops are separate, potentially overlapping indicators; do not add them into an invented missing-record denominator. Zero reported loss cannot prove full capture.

Input is bounded to 100,000 records by default (--max-records can lower/raise that record bound), one MiB per line and 64 MiB total bytes. These are local analysis resource bounds, not Director settings or qualification thresholds. Hitting a bound reports input_limit and suppresses scoring; files are never silently truncated into a passing result. Rejected raw content, source paths, arbitrary error strings and media are not copied into Markdown.

Real sessions still require controlled provenance, the appropriate recorded decisions and complete exported evidence. Current B-04 export UI/manifest integration and live parameter/decision producers remain separate work. This script's synthetic acceptance does not qualify a level, establish live agreement or propose T1–T3 values. See the [schema](shadow-record-schema.md), [qualification protocol](../../reports/auto-director/qualification-protocol.md) and [consent procedure](subject-evidence.md).
