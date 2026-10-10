# Director shadow record schema and privacy note

Status: **D-02 implementation specification for A-09; AWAITING OWNER review.** This document specifies a passive, Codable metadata record, not authority to run a show, collect media, or change an open product decision. It changes no Swift behaviour.

## Sources and decision boundary

Contract sources were checked at `origin/main` **59f3acc9930676db71d3f3de926f52a7babf39eb** (10 Oct 2026): [tickets D-02/A-09/B-04/C-05 and shared rules](../handoff/stage3-4/STAGE3-TICKETS.md), [design plan](../handoff/stage3-4/STAGE3-DESIGN-PLAN.md), [use case](../handoff/stage3-4/STAGE3-USE-CASE.md), [AI options](../handoff/stage3-4/STAGE3-AI-OPTIONS.md), [product contract](product-contract.md), and [DECISIONS](../handoff/stage3-4/DECISIONS.md). Recorded decisions prevail over older “recommended” wording in those documents.

Runtime type mappings below were inspected on the open A-07 stack at `origin/s3/a/A-07-evidence-adapter` **ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42**, in `CinematicCoreMacOS/CinematicCoreMacOS/Director/{DirectorProposal,DirectorShotPolicy,DirectorJudge,DirectorPreferences,DirectorEvidenceAdapter,DirectorAuthority}.swift`, plus `OperatorCommand.swift`, `ShotComposer.swift` and `RecoveryState.swift`. A-09 must use the integrated equivalents; it must not restore the old main-branch shot or authority vocabulary.

Binding requirements: C3/AI-4 allow bounded local metadata with **30-day retention and explicit dataset export**; E2 prohibits audio; AI-2 prohibits network use during the show. UC-1 requires the operator, UC-2 means one shot per input, N3 uses app presets, and P1 distinguishes preparation from cut readiness. AI-1 leaves authority and staleness deterministic. No media collection is authorized by this schema: E3 and AI-3 remain OPEN. A record, a `true` readiness bar, or a judge probability is never a qualification record or Take permit.

Options considered: (a) arbitrary diagnostic strings, (b) the typed metadata projection below, (c) serialized runtime objects or media. **Recommendation: (b), AWAITING OWNER review.** It supports timing/choice comparisons and replay while preventing free text and image leakage. The tradeoff is an explicit adapter and schema migration when runtime enums grow; it cannot reconstruct pictures or prove subject identity from logs. Evidence here is source inspection and **synthetic** serialization examples only; no recorded or live evaluation, calibration, performance claim, or per-level sign-off is supplied.

## 1. Encoding and clocks

`DirectorShadowRecord` is a value type conforming to `Codable`, `Equatable` and `Sendable`. The transport is UTF-8 JSON Lines: one complete record per line. Log storage/export belongs to B-04, analysis to C-05; A-09 implements the types, validated construction/decoding and tests. Explicit coding keys and string discriminators below are the wire contract; do not rely on Swift's synthesized associated-enum layout or `String(describing:)`.

- Schema version is the integer **1**. Any changed field meaning, unit, required shape or new enum case requires a new version and explicit reader support. Reject unsupported versions and unknown keys/discriminators; never silently coerce them into a known event or allow a free-form extension dictionary.
- A `?` field is optional: writers omit it when unavailable; readers accept omission or JSON `null`. Empty arrays mean “evaluated, none”; omission means “not measured/not evaluated” only where optional. `false`, zero and `[]` must not substitute for missing evidence.
- UUIDs are canonical UUID strings. Session and correlation UUIDs are newly generated local tokens, never device IDs or hashes of names. Channel references are opaque, session-scoped aliases matching `input-[1-9][0-9]*`, such as `input-1`, with a stable in-memory mapping from `ChannelID` for that session; no hardware unique ID is written. No cross-session or cross-camera person mapping is retained.
- Revision/epoch/counter values are Swift `UInt64`, encoded as **base-10 strings** matching `0|[1-9][0-9]*`, within `UInt64` range, so Python/JavaScript readers cannot lose integer precision. `schemaVersion`, preference version, person counts and ranks are JSON integers as specified below.
- All durations and host-clock readings are finite, nonnegative JSON numbers in **seconds**. Event, sample, proposal and judgement times use the same injected monotonic clock domain for a session. Preserve the source value (`computedAt`, `sampledAt`), including a finite, nonnegative future or out-of-order value needed to diagnose rejection; do not rewrite it to the log time. Such values are passive rejection evidence only and never authorize an effect. Never compare host times across sessions or subtract them from UTC time.
- `recordedAtUTC` is a UTC ISO 8601 string with millisecond precision (`YYYY-MM-DDTHH:mm:ss.SSSZ`) captured when the event is recorded. It is for expiry and human chronology, not proposal age. Export must retain it, not replace it with export time.
- NaN, infinities and out-of-domain measurements cannot be JSON numbers in a valid record. Omit the offending optional scalar and name its exact schema path in `invalidFields`; each entry must resolve to an optional numeric field in this record. Distinguish this from a genuinely unavailable scalar, which has no marker. Never log the raw invalid token or turn it into a plausible zero. An invalid required structural value rejects the record. Logging failure must not change authority, delay manual actions or block Take.

## 2. Record envelope

All fields are required except those marked `?`. Nested shapes are defined below; there are no implicit defaults.

| Field | Type / meaning |
|---|---|
| `schemaVersion` | Integer, exactly `1` |
| `recordID` | UUID, unique per emitted record |
| `sessionID` | UUID, fresh for each show/replay clock domain; never restored as authority |
| `sequence` | UInt64 string; strictly increasing within the session, assigned before queueing so gaps remain visible |
| `recordedAtUTC` | UTC timestamp described above |
| `eventTime` | Finite, nonnegative monotonic seconds at the decision/action observation |
| `evidenceClass` | `synthetic`, `recorded`, or `live`; class of the evidence used for this event, not the sink or test framework |
| `executionMode` | `shadow` or `observing`; `shadow` means no Director effects; `observing` logs alongside the actual authorized runtime. Neither grants authority |
| `context` | `Context` (§3), snapshot at the event |
| `parameters` | `ParameterContext` (§4), including explicit availability |
| `evidence` | Array of `EvidenceSummary` (§5), at most one per channel in `context.inputs`; empty if no samples exist |
| `judgements` | Array of `JudgementSummary` (§6); empty if no judge ran. Allows rules/model comparisons without implying either was acted on |
| `event` | Tagged `Event` (§7): exactly one event payload |
| `invalidFields` | Array of exact numeric field paths, e.g. `evidence[0].subjectSpeed`; unique, deterministic lexicographic order |
| `droppedRecordsBefore` | UInt64 string: records lost since the last successfully written record because of queue/encoding/storage failure; zero means none reported, not proof of complete capture |

Producer ordering is `sequence`; asynchronous file writes must preserve it. Use `recordID` for deduplication, not timestamps. A replay uses a new session ID and preserves the original evidence class: replaying recorded evidence is still `recorded`; manually authored fixtures are `synthetic`. The producer must supply verified provenance for the entire record, including input samples, timeline/history and judgement inputs; never infer it from `executionMode` or the environment. **Schema 1 prohibits mixed-provenance records.** If an event depends on more than one evidence class, omit that record, count it as dropped and report incomplete capture; never label a mixture `live`, split one decision into misleading homogeneous decisions, or silently discard a contributing input. Supporting mixtures needs an explicit per-source provenance contract in a later schema. Evidence class alone says nothing about permission to collect footage or qualification.

## 3. Context, roles and shot vocabulary

`Context` fields:

| Field | Type / meaning |
|---|---|
| `inputs` | Array of channel aliases, unique, stable order within session; only admitted/known channels |
| `program` / `preview?` | Channel alias / optional alias; members of `inputs`, distinct when Preview exists |
| `programShot?` | `Shot` at this event; omit if unknown |
| `programStartedAt?` / `lastWideAt?` | Monotonic seconds from `DirectorShotPolicy.Timeline`; unknown/invalid omitted as §1 |
| `level` | Actual `DirectorAuthority.Level`: `off`, `suggest`, `assist`, `auto`, `backup`. `off` is operator-facing Manual; `suggest` is internal shadow. Do not encode deprecated `autoPrepare`/`autoDirect` |
| `paused`, `editLive`, `running`, `healthy`, `evidenceAvailable`, `mayPropose`, `mayPrepare`, `mayTake` | Boolean snapshot of the actual authority properties; never inferred from a level name |
| `pinnedInput?` | Alias for `pinnedShot`, if present |
| `authorityEpoch`, `routeGeneration`, `policyRevision`, `nominationRevision`, `evidenceRevision` | UInt64 strings from their owners; separate counters, never substituted for one another |
| `segmentType` | `presenter`, `panel`, `performance`, `videoBreak`, `liveEvent`, matching `SegmentType`; no run sheet → `liveEvent` |
| `segmentToken?` | Fresh session-local UUID for segment correlation, no segment title or position text |

The authority snapshot describes the state **before** an operator event is applied. Its later result is a separate correlated operator-action record (§7). At the inspected A-07 head, `mayTake` is always false and Auto/Backup operator Takes still pause pending A-11; record the actual state, never manufacture the proposed future nudge behaviour. Qualified cut capability must come from its separately reviewed implementation and per-level sign-off.

`Shot` is `{ "format": "stage", "preset": "waistUp" }` or its allowed alternatives. Exact pairs are `stage` + `wide|fullBody|waistUp`, `webcam` + `wide|tight`. Map directly to `DirectorShot(preset: OperatorCommand.Preset)`; reject cross-format pairs. This is a preset, not a virtual input. Do not introduce `mode`, `zoomRung`, `medium`, `closeUp`, or `custom`.

`DirectorShot.isWide`, `.order`, and `.title` are derived: the two Wide pairs are wide; order is Stage Wide / Full Body / Waist Up then Webcam Wide / Tight (runtime orders 0, 1, 2, 100, 101); titles are Wide / Full Body / Waist Up / Tight. Do not serialize display titles or use them as identity. A wide preset does **not** prove a verified safe-wide role. In contrast, `DirectorShotPolicy.Candidate.isWide` is an independent current runtime input and must be preserved in `CandidateSummary.isWide` (§6), even if it differs from the shot's derived flag; do not silently repair source evidence.

## 4. Parameters: version is not a threshold

`ParameterContext` contains required `status` (`available`, `unavailable`, `invalid`), `parametersVersion?` (UInt64 string), `preferencesVersion?` (integer), `resolvedStyle?` (`DirectorStyle` projection), `readiness?` (`ReadinessParameters`), `adapter?` (`AdapterParameters`), `judgeMaximumAge?` (seconds), and `minimumProbability?` (number in [0,1]).

`parametersVersion` identifies an immutable, session-local snapshot of **all supplied parameters**, and changes whenever any supplied parameter changes; it is assigned by the producer, not fabricated by A-09. `preferencesVersion` is the actual `DirectorPreferences.version`, currently **2**, and denotes its encoding, not a particular set of values. `context.policyRevision` remains the runtime invalidation counter. These three values are not interchangeable.

`available` requires both versions and a validated `resolvedStyle`. Optional readiness/adapter/judge groups are included only if used by this event's evaluation; when used they must be present. `unavailable` or `invalid` omits `resolvedStyle` and other invalid parameter groups; retain known versions, and emit an appropriate abstention instead of inventing defaults. A missing/invalid parameter snapshot may still accompany an operator action. `minimumProbability` omitted means no probability threshold was supplied, not zero.

The resolved style is precisely the value returned by `preferences.style(for: segmentType)` (including `liveEvent` fallback); include every field:

| `resolvedStyle` fields | Units / validation |
|---|---|
| `minimumShotDuration`, `preferredShotDuration`, `softMaximumShotDuration` | Seconds, finite, nonnegative; minimum ≤ preferred ≤ soft maximum |
| `wideCadence`, `repetitionWindow`, `settleTime` | Seconds; cadence > 0, others ≥ 0 |
| `maximumMovement` | Normalized frame units/second, ≥ 0 |
| `onAirMoveRate` | Shot-ladder steps/second, > 0; recording it does not approve N2 |
| `cutOnMotionAllowed` | Boolean; preparation policy input, never permission to bypass the stricter cut bar |

`ReadinessParameters` mirrors `DirectorReadiness.Parameters`: `minimumSettledTime` and `minimumCutSettledTime` in seconds (cut ≥ prepare ≥ 0), `maximumMotion` and `maximumCutMotion` in normalized frame units/second (0 ≤ cut ≤ prepare), and `cutOnMotionAllowed` Boolean. `AdapterParameters` mirrors `DirectorEvidenceAdapter.Parameters`: `maximumObservationAge`, `debounce` in seconds and `stillSpeed` in normalized frame units/second, all finite and ≥ 0. `judgeMaximumAge` is finite seconds ≥ 0.

No values are proposed here for timing, speed, probability, debounce, cadence, log rate, queue size or storage size. Tests supply their own synthetic values. Study-derived production values and open T1–T3/P3/A4/N2/N4 choices belong in owner-reviewed parameter memos; an encoding requirement of schema 1, preference version 2 or C3's 30 days is not a behavioural default.

## 5. Evidence summary: an allowlist, not a serialized sample

Each `EvidenceSummary` has required `channel` (alias), `sampledAt?`, `lockPhase`, `trackingOwnsControl`, `galleryReady`, `hasLockedTarget`, `observationAge?`, `subjectSpeed?`, `holdingSteady`, `cropConverged`, `operatorGestureInProgress`, `observedPersonCount?`, `identity`, `identitySource`, `adapterEvidenceAvailable?`, `settledSince?`, `framingSettledFor?`, `prepareReadiness?`, `cutReadiness?`, and `revisions?`.

| Source / fields | Wire meaning |
|---|---|
| `ChannelEvidenceSample.channel`, `.sampledAt` | Alias and host seconds; only emit a summary when an actual sample exists |
| `.lockPhase` | Exact `RecoveryState.Phase`: `inactive`, `acquiring`, `tracking`, `hold`, `wideWaiting` |
| `.trackingOwnsControl`, `.galleryReady`, `.holdingSteady`, `.cropConverged`, `.operatorGestureInProgress` | Boolean observations, not inferred confidences |
| `.lockedTargetID` | **Never serialize the UUID.** `hasLockedTarget` is its presence only; nomination changes are correlated with the context revision |
| `.observationAge` | Seconds since newest detection, finite ≥ 0; absent when no observation; not a wall timestamp |
| `.subjectSpeed` | Normalized frame units/second, finite ≥ 0; no pixel or camera-space coordinates |
| `.observedPersonCount` | Integer ≥ 0; count in the freshest observation's subject ROI while locked, **not** a whole-frame census or a list of people |
| `identity` | Published `DirectorEvidenceAdapter.ChannelState.identity` when present, otherwise `IdentityEvidence.classify` with supplied parameters. Exact cases: `confirmed`, `acquiring`, `holding`, `lost`, `ambiguous`, **`unavailable`** |
| `adapterEvidenceAvailable?` | Actual adapter Boolean, omitted if no adapter state; may differ from raw sample during debounce |
| `settledSince?`, `framingSettledFor?` | Adapter's monotonic start time and nonnegative settled duration at `eventTime`; do not recompute from UTC |
| `prepareReadiness?`, `cutReadiness?` | Each `{ "isReady": Boolean, "reasons": [ReadinessReason] }`; only when that bar was evaluated, using that bar's actual result |
| `revisions?` | `{ "sourceGeneration": UInt64 string, "controlEpoch": UInt64 string, "shotRevision": UInt64 string }` sampled alongside the evidence; never fabricated from a previous source binding |

The required `identitySource` is `adapter` or `sampleClassifier` so readers can distinguish the two identity sources. When no valid classification parameters exist, use `sampleClassifier` with `identity: unavailable` and `parameters.status: invalid|unavailable`; do not assert confirmed identity.

`ReadinessReason` is one of the actual `DirectorReadiness.Reason` cases: `compositionUnavailable`, `evidenceUnavailable`, `takeUnavailable`, `invalidParameters`, `invalidEvidence`, `identityUncertain`, `framingUnsettled`, `moving`, `cropMoving`. Preserve reason-array order; `isReady` must equal `reasons.isEmpty`. A missing bar is not false and not ready. A cut bar must never be generated by copying a prepare bar.

There is **no `faceVisible` measurement** in the inspected `ChannelEvidenceSample` or `DirectorReadiness.Inputs`. Do not fabricate it from `galleryReady` or a `confirmed` identity. Logging the current cut result documents the implementation; it is not independent proof of the product P1 face-visible requirement. Future measurement changes require a reviewed type/schema change. There is no numeric `identityConfidence`; the legacy candidate `subjectConfidence` below is a different ranking input, not a biometric identity probability.

## 6. Judgements and reason namespaces

`CandidateSummary` contains required `channel` (alias), `shot` (`Shot`), `isWide` (the candidate field), and optional `subjectConfidence` ([0,1]), `movement` (normalized frame units/second ≥ 0). These map exactly to `DirectorShotPolicy.Candidate`. Invalid numbers are omitted and marked as in §1; they remain invalid, never eligible training examples by default.

`JudgementSummary` fields:

| Field | Shape |
|---|---|
| `judgeKind` | `rules`, `recorded`, `learned` (producer-supplied implementation category) |
| `modelVersion?` | Producer-controlled opaque build/dataset token matching `[A-Za-z0-9][A-Za-z0-9._-]*`, never a filesystem path or user text; required for `learned` |
| `evidenceRevision` | Original `DirectorJudgement.evidenceRevision` as UInt64 string |
| `computedAt?` | Original `DirectorJudgement.computedAt`, host seconds; invalid omitted and marked |
| `outcome` | Either `{ "kind": "ranked", "ranked": [RankedSummary] }` or `{ "kind": "abstain", "reason": Reason }` |
| `gateResult` | `notEvaluated`, `accepted`, `abstained`, `stale`; actual `DirectorJudgeGate` outcome |
| `gateReason?` | `Reason`, required only for `abstained` |

`RankedSummary` has `candidate` (`CandidateSummary`), `probability?` (finite [0,1]), and `reason` (`Reason`). Array order is the original rank; no extra rank number. Rules emit **no probability**, not 1.0 and not their `subjectConfidence`. Preserve the entire bounded original ranking, including a candidate a gate refused. `acceptedRank?` (zero-based JSON integer) is required when `gateResult` is `accepted`, prohibited otherwise, and refers to the actual admitted item after the gate's allowed-candidate filter; the first raw item need not be admitted. An empty ranked result can be represented for rejected/unevaluated diagnostics but cannot have `acceptedRank`.

`Reason` is `{ "domain": <enum>, "code": <enum> }`. Exact namespaces/codes:

| `domain` | Allowed `code` values / source |
|---|---|
| `proposalStale` | `authorityRevoked`, `routeChanged`, `sourceRestarted`, `shotChangedByOperator`, `targetBecameProgram`, `sourceMissing`, `expired`, `requestReplaced`, `policyChanged`, `nominationChanged`, `evidenceUnavailable` — `DirectorProposalValidator.StaleReason` (11 cases) |
| `policy` | `invalidInput`, `minimumDuration`, `noEligibleCandidate`, `repetition`, `movement`, `noPreview` — `DirectorShotPolicy.Abstention` (6 cases) |
| `judge` | `lowConfidence`, `notRecorded`, `nothingAllowed`, `invalidJudgement` — `DirectorJudgement.Abstention`; its `.policy(x)` becomes `{domain: policy, code: x}`, preserving the nested meaning |
| `readiness` | The nine `ReadinessReason` codes in §5 |
| `selection` | `advisoryWideReminder`, `advisoryMaximumDwell`, `subjectEvidence`, `unclassified` |
| `observation` | `parametersUnavailable`, `parametersInvalid`, `judgementStale`, `cutPolicyUnavailable`, `unclassified` |
| `authorityRefusal` | `notQualified`, `prerequisites`, `paused`, `exhausted` — `DirectorAuthority.Refusal` |

The existing free strings `advisory wide reminder`, `advisory maximum dwell`, `subject evidence` map explicitly to the respective `selection` codes. All other proposal/judge explanation text maps to `selection.unclassified`; discard the text. Unknown operator rejection text similarly becomes `observation.unclassified`. `judgementStale` is an observation of `DirectorJudgeGate.stale`, **not** an invented proposal stale enum case. Do not collapse `noPreview`, `noEligibleCandidate`, and `nothingAllowed`, or log arbitrary `localizedDescription`/error text. Later cut-policy reason codes require an explicit schema revision rather than guessed enums here.

## 7. Events and correlation

Every `event` has `kind` and exactly the corresponding payload fields below. An event never causes the action it describes. Arrays of reasons retain source order and may contain multiple different namespaces.

| `kind` | Required payload | Optional payload / constraints |
|---|---|---|
| `wouldPrepare` | `decisionID` UUID, `target` alias, `shot` Shot, `reason` Reason | `proposalID?` UUID, `requestID?` UUID, `proposalCreatedAt?` host seconds, `judgementIndex?` integer into envelope `judgements`. Target is captured Preview and differs from Program; no implied dispatch/receipt |
| `wouldCut` | `decisionID` UUID, `target` alias, `shot` Shot, `reason` Reason | `judgementIndex?`. Target is captured Preview; this is a cut-policy recommendation only, **not** a committed cut, notice, permit or qualification |
| `abstention` | `decisionID` UUID, `stage` (`prepare`, `cut`, `judge`, `validation`), nonempty `reasons` array of Reason | `target?` alias, `proposalID?`, `requestID?`, `judgementIndex?`; preserve every validator stale reason rather than only the first |
| `operatorAction` | `actionID` UUID, `action` code below, `phase` (`attempt`, `result`), `targetScope` (`session`, `channel`) | `target?` required exactly when scope is channel; `shot?` required exactly for `selectPreset`; `outcome?` required exactly on result; `reasons?`; `programAfter?`, `previewAfter?` aliases only on result |

A decision evaluation for preparation and one for cutting have different decision IDs. Do not write a `wouldCut` just because preparation was selected or `recommendationDue` is true. A-07 has no `CutPolicy`; until A-12 supplies one, evaluated cut logging is `abstention` with `stage: cut` and `observation.cutPolicyUnavailable`, or no cut evaluation. Do not infer cut timing from a Take that has already happened. The independent `wouldCut` shape exists now so A-09 and C-05 can round-trip synthetic future-policy fixtures.

Only explicit human/manual ingress is an `operatorAction`: `operatorUI` camera commands or the corresponding operator UI/Take hook. Never relabel safety recovery, automatic recovery, Director effects or fallback effects as human choices.

Operator `action` is one of: `take`, `detect`, `cancelDetect`, `selectSubject`, `unlock`, `resumeTracking`, `setMode`, `selectPreset`, `beginZoom`, `endZoom`, `moveManualCenter`, `returnToWide`, `startSession`, `stopSession`, `settingsChanged`, `formatChanged`, `editLive`, `setLevel`, `handToAlfie`, `takeOver`, `cancelNextCut`, `advanceSegment`, `overrideSubject`, `otherManualAction`. The first camera-command names map to `OperatorCommand.Action`; later names cover the explicitly planned ingress/UI hooks. Log action category only: no tap location, manual-centre coordinate, name, settings text, gesture path or run-sheet title. Operator `take`, session lifecycle, authority and segment actions have session scope; channel camera actions carry the captured alias. `otherManualAction` has no free-text subtype.

`outcome` is `accepted`, `completed`, `refused`, `unobserved`. `accepted` means admission only; `completed` means an observed committed effect. For Take, only `completed` plus `programAfter` is an actual cut label. A refused attempt is not a cut. Pair attempt/result with the same `actionID`; emit the attempt at ingress even if refused. Do not guess completion if a command merely reports acceptance. An incomplete pair stays an attempt; use `unobserved` if a terminal observer knows it cannot determine the result. Record actual roles afterward only when observed. No synthetic result should be emitted on logging loss.

Record reasons for refusal using the allowlist; never embed command rejection strings. Preserve the pre-event authority context on the attempt, and the current context on its result (each record has its own timestamp/sequence). Offline analysis joins by `sessionID` and `actionID`, reports missing pairs, and matches decisions to actions with a declared study matching rule. No agreement window or timing tolerance is set here. No operator identifier is needed for this comparison.

## 8. Privacy, retention and explicit export

**Never logged or exported through this schema:** frames, crops, thumbnails, screenshots, pixels, video, audio, microphone samples, transcripts, lip/speech activity, face images/templates/embeddings, gallery contents, body keypoints, tap/ROI coordinates, raw locked-target UUIDs, inferred names, inferred age/child labels, device serials, source URLs, file paths, credentials, unrestricted error strings or run-sheet text. Neither children nor audience/reaction subjects become inferred targets through logging. No cross-camera identity inference is introduced. `galleryReady` is only a Boolean; it is not permission to retain the gallery.

Version 1 writes **no names**, including operator-entered labels. C3 permits no names beyond operator-entered labels; those labels are unnecessary for the requested comparisons and are deliberately omitted from this minimal projection. If a later reviewed schema includes a label, it must be explicitly operator-entered and purpose-limited; never infer or scrape one. Data minimization also applies to model and parameter identifiers: controlled opaque tokens, no user strings.

Local storage must expire ordinary records **30 days after `recordedAtUTC`**, interpreted as 30 × 24 hours in UTC, not 30 local midnights. Expiry applies to logs, rotated files, queues persisted to disk, indexes and derived non-exported datasets that contain record-level data. A rotated file must be deleted no later than the earliest contained record's expiry, or rewritten without expired records; modification time must not extend retention. Perform cleanup at startup, before local reads/exports, and during active writing. An app that was closed cannot run deletion while closed; on reopening, expired records must be removed before they are accessible to analysis/export. Future/invalid wall timestamps or a detected clock rollback must not extend retention: quarantine from analysis and discard affected ordinary records rather than reset their capture time. DiagnosticsLog's existing 30-day file prune is useful but not, alone, evidence that all these stores comply.

Explicit export is an operator-initiated **local** dataset action with a visible time/session selection and destination. No background export, upload, cloud-sync integration or network entitlement is added; AI-2 remains binding. Export only valid, unexpired allowlisted records, preserve their original schema/times/evidence class, and write a manifest alongside the JSONL containing `exportSchemaVersion: 1`, fresh `exportID` UUID, `exportedAtUTC`, sorted `sessionIDs`, `recordCount` integer, `evidenceClasses`, `recordSchemaVersions`, and `retention: "explicitExport"`. Counts must reflect the exported records; report skipped invalid/expired records without their contents. Do not include a destination path, person's name or media in the manifest.

The explicit exported copy is exempt from automatic 30-day expiry under AI-4/C3 and remains under the operator's control; the original local log still expires on schedule. Export is not authorization to send it to a service, retain video or collect new data; AI-3/E3 stay OPEN. Exported datasets must not be silently reimported into an ordinary log to refresh its age. External sharing, media consent and fixture registers are separate owner decisions/D-07 work.

Bound collection by supplied writer limits for queue count, record bytes, file bytes and total storage; limits must be explicit in B-04's configuration with no guessed production defaults in A-09. Do not truncate an individual record or ranked list silently: reject an oversize record, account for the loss, and keep the camera path non-blocking. `droppedRecordsBefore` plus sequence gaps is analysis evidence, not a guarantee of complete capture after a crash. Coalescing identical abstentions, if B-04 adds it, must have a versioned count/time-range representation; do not quietly treat one record as many evaluations. Record admission/retention counters without copying rejected payloads to an unrestricted debug log.

## 9. Acceptance and handoff

A-09 should provide synthetic round-trip and rejection tests covering:

1. All four event kinds; attempted/refused/committed operator Takes; no-Preview abstention; every shot pair and authority level; no automatic effects from decode or encode.
2. All six identities, five lock phases, nine readiness reasons, eleven proposal stale reasons, six policy abstentions, and nested judge policy abstention; preserve prepare/cut bars independently.
3. Rules with omitted probability, learned probability at domain boundaries, ranked results with a filtered-out first item and a later `acceptedRank`, stale evidence revision/time, and explicit `cutPolicyUnavailable`.
4. Preferences v2 versus shadow schema v1 versus parameters version versus policy revision; resolved live-event fallback; unavailable/invalid parameters; no invented numeric values.
5. UInt64 maximum round-trip without precision loss; absent versus zero/false; marked invalid measurement versus unavailable measurement; negative host clocks and mixed provenance refused; nonnegative future/out-of-order clocks retained only as passive evidence; unknown schema/key/enum, cross-format shot, malformed UUID/counter, inconsistent readiness and event payload rejected.
6. A malicious explanation/name/path and media-like unknown key are never serialized. Construction adapters map only allowed values; round-trip encoding exposes no frame/pixel/audio/name field. Reason text cannot bypass the allowlist.

B-04 adds writer/clock/expiry/overflow/export tests separately, with injected clocks and limits, including the exact 30-day boundary, expired records in a recently modified file, restart cleanup, invalid/future capture time and clock rollback, explicit export preserving original age, and no auto-export. C-05 reports evidence class, observed coverage/loss, decision-to-action matching rules and parameters version before reporting agreement or dwell; it cannot call an attempt or shadow prediction an actual cut.

A-09 remains pure metadata; B-04 must not perform file I/O in the frame path or insert an `await` between validation and effect. Logging refusal must never inhibit an operator Take. No release enablement or default qualification is introduced. Synthetic tests, recorded replays and live shadow observations remain separately labelled; **none qualifies Assist, Auto or Backup without its explicit per-level sign-off**.

Implementation limitations visible at this source revision: no independent `faceVisible` scalar; no cut policy, notice or Take permit yet; no runtime log writer connected by this ticket. These are truthful absences, not schema-created capabilities. Other open decisions remain AWAITING OWNER; this document sets no numeric study recommendation.
