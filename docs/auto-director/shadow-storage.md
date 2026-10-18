# Director shadow storage

B-04 candidate · 18 October 2026. Metadata infrastructure and synthetic tests only; no live study or qualification. This engine stack follows [the schema](shadow-record-schema.md) and recorded C3/AI-4 decisions in [the register](../handoff/stage3-4/DECISIONS.md).

`DirectorShadowLog` is separate from `DiagnosticsLog.swift`, which also compiles into the camera extension. Its app-only factory places `director_shadow_<session UUID>.jsonl` files beside the existing diagnostics files. It never serializes a camera, pixel buffer, point, filename, source URL, person UUID, face gallery, transcript or raw error string. The A-09 schema validates each record before encoding and again when decoding an export.

## Configure explicitly

The owner supplies positive `maximumRecordBytes`, `maximumQueuedBytes`, `maximumFileBytes` and `maximumStoreBytes`. A record must fit the queue and session file, and a session file must fit the total Director store. No queue/storage budget is silently chosen by the app. Tests supply synthetic limits; they are not production recommendations.

Create `DirectorShadowLog.besideDiagnostics(limits:)`, then pass it to `ShowCoordinator(directorShadowLog:)`. The optional argument defaults to nil, so an unconfigured show performs no new disk logging. This PR supplies the storage/export API and event hooks; selecting approved limits and wiring a Settings destination picker remain integration work. No qualification or operating level is restored from a log.

One producer submits typed records in sequence order. `append(_:provenance:)` returns queue admission, not a successful filesystem write. Callers may inspect `metrics`, or await `flush()` for a FIFO barrier. Flush is not a power-failure durability guarantee. Encoding is bounded metadata work at a Director tick or operator event; all filesystem reads, writes, pruning and export occur on a shared serial utility queue. There is no frame-path I/O or per-frame published state.

## What is actually recorded

The configured controller emits typed operator camera attempts/results, level/handback/takeover actions, and correlated Take attempts/results. A completed Take is logged only after the router committed the new Program; refusal is distinct. A synchronous camera command returning accepted stays `accepted`, never a fabricated completed downstream picture. Safety-origin commands and an automatic preparation-failure pause are not labelled human actions.

The current tick emits `cutPolicyUnavailable` abstention while B-08 scheduling is absent. It does not invent would-cut decisions, preset scores, complete parameter snapshots or face-visibility measurements. Known preferences can identify their schema version; without a complete versioned parameter snapshot the record says parameters are unavailable. Unknown Program timeline/shot fields are omitted, not guessed. A-09's writer API accepts all schema-supported event kinds when their real producer supplies valid facts.

Source provenance comes from every actual running input's active source and source identity. A validation clip remains recorded evidence; it is never classified from the output route or shadow mode. Unknown or mixed provenance is omitted and counted as lost under schema 1. Debug-only tests may inject synthetic provenance. Aliases are session-local `input-N`; source device names and IDs are not logged. A new show renews the session UUID and sequence rather than merging clock domains.

## Capacity and loss

Queue reservations bound pending records before encoding. Oversized/invalid records, mixed provenance, stale sequences, duplicate record IDs and failed writes are dropped. Producer losses and prior queued-write failures are carried separately so a later missing sequence is never attributed to an earlier queued record. The next successful record reports the additional loss in `droppedRecordsBefore`; metrics also report total drops, write successes, pruning and storage errors.

A full session file stops accepting further writes rather than growing or silently rewriting old lines. To keep the total Director store bounded, the writer may evict the oldest other managed sessions. Quota eviction can therefore remove unexpired logs: thirty days is a maximum retention policy, not a minimum preservation promise. Only strict UUID-named Director JSONL files are managed. Unrelated diagnostics, user notes, directories and symlinks are not followed or deleted.

Do not infer complete capture from a successfully exported file. Preserve planned run/session references, sequence gaps, drop metrics and evidence exclusions in the [qualification assessment](../../reports/auto-director/qualification-protocol.md). Missing sessions or intervals remain unverified; deleting a log cannot create a passing denominator.

## Expiry and explicit export

C3's recorded thirty-day metadata retention uses the original `recordedAtUTC`, not file modification time or export time. Writes require nondecreasing UTC and sequence within a session; future/expired timestamps are refused. Managed-file expiry is based on its first original record; corrupt or future managed headers are removed conservatively. No raw invalid token is converted into a plausible timestamp.

Pruning runs at initialization, append, explicit maintenance and export. When the app is closed or idle, physical cleanup waits for the next such operation; this is not an installed background deletion service. Expired data is never eligible for export. The writer manages only its Director namespace, not every existing diagnostics/training file or external copy. E3 media retention is a separate open decision.

After the user deliberately chooses a local destination outside the managed log directory, call `show.director.exportShadowLog(to:)`. The exporter waits behind queued writes, validates every retained JSONL record, checks session/sequence/identity/expiry, preserves source class and original timestamps, and refuses an existing destination. No upload or implicit export occurs. `finish()` prevents new writes while retained data can still be exported within policy. Exported copies need their own controlled dataset retention; exporting does not renew the ordinary source log.

## Validation boundary

Synthetic tests exercise typed round-trip/export, overwrite refusal, corrupt files, strict size/queue/store limits, sequence-correct loss accounting, duplicate sequence rejection, refreshed file modification times, symlink/unrelated-file protection, session renewal and actual controller Take correlation. App and camera-extension builds verify isolation of the app-only writer. No camera, person, microphone, live route, consent or sign-off is exercised by these tests. Runtime workload and approved storage budgets still require the named-rig study.
