# Director shadow report CLI

C-05 is an offline, metadata-only analysis tool. It reads A-09 schema-1 and schema-2 JSONL, validates B-04 export bundles and produces Markdown. It does not open cameras, upload data, choose directing parameters or write qualification records.

From the repository root:

```sh
python3 CinematicCoreMacOS/scripts/director_shadow_report.py \
  CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic-export \
  --match-window-seconds 2 --output /tmp/director-shadow-example.md
python3 -m unittest discover -s CinematicCoreMacOS/scripts -p test_director_shadow_report.py -v
```

The two-second window is a supplied synthetic fixture value, not a production recommendation. A matching window is always required. Output defaults to stdout; `--output` creates a new file and refuses to overwrite one. Exit status is 0 for analyzed input (which may still have incomplete sessions), 2 for malformed/unsupported/limited input or invalid arguments, and 1 for an I/O failure. Check the Completeness section even after exit 0.

The displayed matching window preserves the supplied numeric value on a text round trip. It is not rounded to a short descriptive precision, since reusing a rounded setting can change comparisons at a boundary. The evaluation report and standalone parameter memo use the same representation.

The shared synthetic bundle contains [seven generated records](../../CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic-export/records.jsonl) and a [companion manifest](../../CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic-export/manifest.json): two matched operator cuts, one abstention and one ten-second interior Program interval. The [example report](../../reports/auto-director/shadow-report-synthetic-example.md) is deterministic and includes its synthetic provenance. Swift export tests check the same fixture against the actual record decoder and generated manifest.

## Bundles and unbundled input

A directory argument selects exactly `records.jsonl` and `manifest.json` inside that directory. The reader does not search recursively, choose the newest dataset or guess a companion filename for a file argument. Missing bundle files, malformed export metadata or a summary mismatch suppress all agreement/dwell scoring and return exit 2. Other input/output failures return exit 1. Rejected content and filesystem paths are omitted from reports and fixed I/O diagnostics.

Manifest schema 1 has exactly eight required fields. Unknown keys, duplicate JSON keys, null values, Boolean numbers and noncanonical tokens/timestamps are rejected.

| Field | Validation |
|---|---|
| `exportSchemaVersion` | Integer, exactly `1` |
| `exportID` | Canonical uppercase UUID |
| `exportedAtUTC` | Valid UTC calendar timestamp, exactly `YYYY-MM-DDTHH:mm:ss.SSSZ` |
| `sessionIDs` | Sorted, unique canonical UUIDs; exactly the sessions in the records |
| `recordCount` | Nonnegative JSON integer; exactly the number of validated records |
| `evidenceClasses` | Sorted, unique `live` / `recorded` / `synthetic` values; exactly the classes in the records |
| `recordSchemaVersions` | Sorted, unique supported integers; exactly the record versions, currently `1` and `2` |
| `retention` | Exactly `explicitExport` |

An empty bundle has count zero and empty summary arrays. Each record's original `recordedAtUTC` must be at or before `exportedAtUTC` and less than 30 × 24 hours old at export. The exact 30-day expiry is rejected. This implements the source-retention rule in [D-02 §8](shadow-record-schema.md#8-privacy-retention-and-explicit-export); it introduces no study threshold. The analysis clock does not expire explicit exported copies, so a valid archival export remains readable later. Ordinary source-log retention remains the writer's responsibility.

A matching manifest does not establish complete capture or qualification. Original sequence numbers and action pairs remain unchanged. Time-limited exports may deliberately lack a prefix or a correlated result; those sessions still show incomplete and suppress agreement/dwell.

New reports include separate SHA-256 fingerprints for the exact records and manifest bytes read by the bounded parser. Whitespace changes therefore change the fingerprint. A complete malformed input can still be identified, while its scoring remains suppressed. Missing files or reads stopped by a resource bound have an unavailable full-file fingerprint; a consumed prefix is never labelled as the complete file. Hashes establish byte identity only, not capture completeness, consent or qualification. No source path is copied into the report.

A file argument still accepts unbundled JSONL, including the [original fixture](../../CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic.jsonl):

```sh
python3 CinematicCoreMacOS/scripts/director_shadow_report.py \
  CinematicCoreMacOS/scripts/fixtures/director-shadow-synthetic.jsonl \
  --match-window-seconds 2
```

Its report explicitly says that export metadata is unavailable and explicit-export retention is not established. A nearby manifest does not change that label. Valid record-only observations may still be analyzed; they are not presented as a validated B-04 export.

## Comparison rules

Prepare and cut decisions have separate rows, partitioned by session, evidence class, segment/token, parameter/preference versions, policy and route revision. No synthetic/recorded/live denominator is pooled. Within a partition, each paired completed operator action uses the latest unused preceding prediction of that kind inside the supplied window. Selection occurs before checking agreement, so a more agreeable older prediction cannot replace a recent mismatch. A match requires both target and preset.

An operator Take counts only after a correlated attempt and completed result name the observed Program/Preview swap. An accepted/refused/unobserved action is not a completed cut. A preparation comparison requires a completed off-air selectPreset with its shot. Missing post-Take shot or parameter information is unscored. Agreement is exact/compared; compared and total prediction counts expose coverage. Unmatched predictions/actions and unscored actions remain visible.

Action correlation preserves the attempt's prediction partition while validating the named action's terminal context. A completed Take must swap the exact roles and increase route generation by exactly one; its segment, policy, parameter, preference, nomination and model bindings stay current. An accepted explicit segment advance may change segment/token and resolved style while increasing policy revision exactly once; input roles, route, preference version, nomination and other readiness/adapter/judge settings must stay unchanged. Accepted explicit Show Stop uses the narrow logical reset exception described below; other pairs retain their original scope. Intervening control actions, unexplained scope changes and cross-source or model changes invalidate the pair. These exceptions never pool prediction partitions or authorize run-sheet wiring while F3 remains open.

The controller records a shared action ID on the pre-event attempt and current terminal result for level selection, handback, takeover and explicit segment advance. Settings notifications currently arrive before the published setting is committed, so their terminal result is `unobserved`; it closes the observed intent without claiming an applied setting or a completed camera effect. Ordinary admitted preset commands remain `accepted` until a separate observer establishes completion.

Only consecutive completed Takes with continuous role/parameter scope and no observed intervening disruption support interior dwell. The tool reports count/minimum/median/maximum in seconds. First/last censored holds are excluded. Routing metadata is not proof of downstream presentation or useful subject coverage.

The `dwell` field measures recorded **Program input-role tenure**, not a stable crop, composition or subject hold. Exact Take roles can establish that interval even when missing shot metadata makes an agreement comparison unscored. On-air composition changes and useful subject coverage require their own observations; do not use input tenure alone as measured shot-duration or directing-quality evidence. Earlier generated reports labelled this field “Interior Program dwell”; its calculation is unchanged.

## Invalid and incomplete evidence

The companion `director_shadow_schema.json` mirrors supported schema-1/2 typed fields/enums from `DirectorShadowRecord.swift` and the eight-field export projection. Input must be UTF-8. Unknown fields, duplicate JSON keys, unsupported schemas, malformed tokens/counters/clocks, invalid event payloads and media-like additions refuse the record. Cross-field checks protect the analysis; this reader does not replace the app's authoritative serializer or validate human consent/ground truth. Schema changes require an explicit reader/table review. Schema 2 may carry complete materialized `scorerInputs` for actual rules candidates; these are strictly validated against their candidate, timeline, revision and Float32 feature contract. Schema 1 rejects that key even when null. C-05 agreement/dwell behavior is unchanged; C-10 consumes those inputs only with separately supplied explicit labels and whole-session splits in the [offline scorer pipeline](director-scorer-training.md).

Malformed/unattributable input or invalid export metadata suppresses all scoring. Identified sequence gaps, a missing prefix, reported drops, backward clocks, inconsistent parameter versions or incomplete/duplicate/inconsistent action pairs suppress their session's agreement and dwell. Observed abstention reasons remain descriptive counts, not independent opportunities. Sequence gaps and reported drops are separate, potentially overlapping indicators; do not add them into an invented missing-record denominator. Zero reported loss cannot prove full capture.

Input is bounded to 100,000 records by default (`--max-records` can lower/raise that record bound), one MiB per JSONL line and 64 MiB total bytes. In bundled mode the manifest and JSONL share that total byte budget. These are local analysis resource bounds, not Director settings or qualification thresholds. Hitting a bound reports `input_limit` and suppresses scoring; files are never silently truncated into a passing result. Rejected raw content, source paths, arbitrary error strings and media are not copied into Markdown.

Real sessions still require controlled provenance, the appropriate recorded decisions and complete exported evidence. Runtime parameter/decision producers and per-level qualification remain separate work. This script's synthetic acceptance does not qualify a level, establish live agreement or propose T1–T3 values. See the [schema](shadow-record-schema.md), [qualification protocol](../../reports/auto-director/qualification-protocol.md) and [consent procedure](subject-evidence.md).

## Explicit evaluation phases

The optional Python API `analyze(..., phase_assignments=...)` restricts matching and dwell while retaining complete original-session validation. The D-06 version-2 sidecar validates those assignments against explicit sequence spans and actual scope; see [evaluation-report.md](evaluation-report.md#explicit-study-phases-version-2). Phase IDs do not repair missing input. Equal event clocks also require a prediction sequence strictly before the operator attempt, so a later row cannot receive earlier credit. Default unphased reports retain their existing scope and output format.

An accepted explicit Show Stop may reset Program to input-1, Preview to the first other attached input, and route generation by one only when Program changes. Its post-role marker distinguishes this logical all-input reset from legacy camera Stop. The reader requires matching membership/source class, parameter/segment/policy/nomination/model scope and a stopped, Off/shadow, unpinned, non-Edit-Live result. Other mismatches still block the session. This validates exported metadata consistency, not physical capture shutdown.
