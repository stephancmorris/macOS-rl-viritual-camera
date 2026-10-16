# Proposed qualification record format for B-06

Status: **D-04 integration proposal, AWAITING OWNER (Q1–Q3), 2026-10-10.** This specifies a reviewable storage/lookup contract, not an existing Swift API or a signed qualification. Companion: [qualification protocol and scoring](../../reports/auto-director/qualification-protocol.md). Authority: [recorded decisions](../handoff/stage3-4/DECISIONS.md), [B-06/C16 ticket](../handoff/stage3-4/STAGE3-TICKETS.md) and [design plan](../handoff/stage3-4/STAGE3-DESIGN-PLAN.md). Recorded choices override older proposed text.

Evidence inspected at main `42191c71ec303e3f7d388c7cdafb5d5ef93d89db`: [MultiInputAdmission.swift](../../CinematicCoreMacOS/CinematicCoreMacOS/MultiInputAdmission.swift), [ShowCoordinator.swift](../../CinematicCoreMacOS/CinematicCoreMacOS/ShowCoordinator.swift), [CameraManager.swift](../../CinematicCoreMacOS/CinematicCoreMacOS/CameraManager.swift) and [ProgramOutputManager.swift](../../CinematicCoreMacOS/CinematicCoreMacOS/ProgramOutputManager.swift). The inspected main has no `QualificationLookup` or Director per-level record store. B-06 names that future seam; method signatures and fields below are integration requests. This memo does not edit or approve code.

## 1. Options and recommendation — AWAITING OWNER

| Choice | Options | Recommendation / tradeoff | Evidence required |
|---|---|---|---|
| Binding | Admission key only; typed admission snapshot plus Director scope; one broad machine approval | Typed admission snapshot plus explicit Director scope/build/parameters. More records to maintain, but avoids silently extending an R2 pair result to a different Director workload | Exact producer mapping below and mismatch tests |
| Availability | A persisted Boolean; per-level reviewed records; trust Debug fixture records in Release | Reviewed per-level records, with Debug test storage excluded from Release. More verification work, but no accidental grant from test data | Persistence, tamper/incomplete-record and build-boundary tests |
| Evidence | CI pass alone; aggregate mixed evidence; separate classes and signed run package | Separate synthetic/recorded/live references and complete per-route package; more bookkeeping but exposes missing real evidence | Protocol worksheet, manifest integrity and live signatories |
| Approval retention | Ordinary metadata only; an explicitly exported approval package; indefinite automatic persistence | Ordinary records obey C3's 30-day expiry; propose an explicitly exported and owner-reviewed approval package for longer audit availability. Export alone must never refresh or reactivate a lookup record | Owner resolution of authoritative approval lifetime/import rules, storage/cleanup tests and an auditable approval source |

No new production duration, exposure count, timeout, threshold or storage limit is set here. Proposed schema/version numbers identify an encoding, not authority or tuning defaults. Q1–Q3 and the approval-retention integration details require owner review before Release enablement.

## 2. Exact existing admission mapping

`AdmissionFingerprint` is `Codable`, `Hashable`, `Sendable`. Preserve this actual shape; do not rename or silently fill missing values when comparing qualification scope:

| Existing field | Type / actual producer |
|---|---|
| `policyVersion` | `Int`, initialized from `AdmissionPolicy.version` (currently 1) |
| `machineModel` | `String`; `DiagnosticsLog.currentBuildIdentity().machineModel` |
| `osVersion` | `String`; build identity uses `ProcessInfo.processInfo.operatingSystemVersionString` |
| `showStandard` | `String`; `ShowStandard.activeOrCurrent.title`, not a new enum or independent numeric FPS field |
| `route` | Optional `String`; `ShowCoordinator` uses current session output route title, falling back to preferred route title |
| `inputs` | Array of the actual `AdmissionFingerprint.Input` values from known channels |
| `inputs[].channel` | `String`; current `channelID.letter` (A/B), not shadow-log `input-N` aliases |
| `inputs[].deviceModelID` | Optional `String`; `selectedCamera?.modelID`, **not** a unique device ID or serial |
| `inputs[].deliveredWidth`, `deliveredHeight` | Optional `Int` pixels; source dimensions when positive, otherwise nil |
| `inputs[].captureFPS` | Optional `Double` frames/s; configured capture rate, nil before configuration or for a validation clip |
| `inputs[].captureProfile` | Optional `String`; producer currently supplies `stage` or `webcam` |
| `inputs[].mode` | `String`; `wide`, `track`, `manual`, `pan` from active camera mode |

`AdmissionFingerprint.key` is a delimiter-joined string, sorting inputs by channel. Its optional substitutions are `route ?? "none"`, model/profile `?? "?"`, dimensions/FPS `?? 0`. It is a store lookup key, **not a cryptographic digest or complete proof of a known measurement**. Nil and zero must remain distinct in the proposed typed snapshot. Recommend full structured comparison after validating complete live fields, not trusting only the flattened key or Swift's process-dependent `hashValue`.

Current route titles are `Direct output (HDMI / USB-C)`, `Virtual Camera`, and `Rehearsal · no output`. The active route and downstream observation must establish which physical output was tested; a preferred title alone is not proof that any frame reached it. A rehearsal sink cannot qualify either output route. Store separate records for exact route/configuration rows; do not put a wildcard in `route`.

`AdmissionRecordStore.Record` currently contains only `status`, `measuredAt: Date` and `policyVersion`, keyed by the fingerprint key in `admissionRecords.v1`. Status is `unknown`, `provisional`, `certified`, or `unsupported(reasons)`. `PairAdmission.evaluate` yields unknown/unsupported/provisional; `markCertified` is the separate MULTI-QA entry point. None means Director Assist/Auto/Backup is qualified. `ShowCoordinator` treats fewer than two channels as provisional; that shortcut is not the required two-input R2 certification.

## 3. Missing facts are integration requests

The actual fingerprint does **not** contain app/harness commit, Director policy/parameter/model version, qualified level, segment/capability scope, workload configuration, signatories, sign-off expiry, rig serial identity, physical connection topology, output endpoint identity, run evidence, or verified safe-wide coverage. Do not pretend those fields already exist or concatenate them into the current key without a reviewed migration.

Recommend separate `directorScope` and `setupAttestation` values in B-06's record. The latter is an opaque, owner-controlled setup-manifest reference/digest for the physical arrangement and observed downstream path; no device serial, source URL, filesystem path or person name belongs in the exported metadata. Model IDs alone cannot distinguish two units of the same model or prove identical cable/display topology. A physical substitution must therefore trigger explicit setup recheck even if the existing fingerprint happens to match. This additional binding is proposed integration, not behavior of `AdmissionFingerprint` today.

Reject incomplete live qualification bindings: unknown route/model/dimensions/rate/profile, duplicate channels, invalid/nonfinite/nonpositive dimensions/rates, unsupported profile/mode, wrong input count for the approved scope, or missing setup/admission evidence. Recorded clips with nil configured rate remain valid **recorded study evidence**, but cannot impersonate a complete live-rig fingerprint. All required mode/profile/format combinations must be listed and evaluated; normal mode changes alter the current fingerprint and cannot be covered by an implicit wildcard.

## 4. Proposed record envelope and semantics

Proposed name: `DirectorQualificationRecord`, schema **1**. This is a design for B-06, not a type found in the inspected sources. Recommend explicit coding keys/discriminators, reject unknown schema/keys and invalid required fields, and keep the decoded value passive. Do not introduce a free-text extensions dictionary. Identifiers below are fresh opaque tokens; digests use a specified canonicalization/algorithm version and bind content, not just a filename.

| Proposed field | Shape / meaning |
|---|---|
| `schemaVersion`, `recordID`, `revision`, `supersedes?` | Encoding integer 1, UUID, lossless revision counter and optional prior record UUID; revisions do not overwrite the old assessment |
| `level` | Exactly `assist`, `auto` or `backup`; no “all levels”. Manual requires no record; internal shadow is not a release qualification |
| `disposition` | `draft`, `incomplete`, `failed`, `approved`, `revoked`; only a complete, current, verified approved record can contribute to availability |
| `recordClass` | `realAssessment` or `debugFixture`; separate production/test storage. A synthetic test fixture is never a real assessment just because its signatures are populated |
| `createdAtUTC`, `assessedAtUTC?`, `validFromUTC?`, `validUntilUTC?` | UTC instants; required validity interval for an approval, chosen by owner before activation, no default duration. Future/invalid/rollback-ambiguous clock evidence cannot extend validity |
| `admissionFingerprint` | Full actual typed snapshot from §2, with field names, units and nil values preserved |
| `admissionKey` | Exact existing key at assessment, as a compatibility cross-check, never the sole equality or integrity check |
| `admissionEvidence` | Reference/digest to the exact real R2 certification and its measured time/policy version; not a copy of a provisional UI label |
| `setupAttestation` | Proposed manifest token/digest, approved configuration revision and observed route proof reference; facts absent from current fingerprint remain separately attested |
| `directorScope` | Build/engine commit, supported build configuration, capabilities/segment types/input count, policy and complete immutable parameter snapshot references, optional controlled model token/digest, workload configuration reference; no automatic widening of scope |
| `protocol` | Approved protocol/decision baseline and frozen run-plan/metric-budget references/digests; includes recorded resolutions needed for this scope |
| `runs` | Nonempty references to immutable run summaries below, with evidence class, route/fingerprint binding and data integrity digest; no pooled mixed-class “pass” |
| `results` | Required metric/scenario cells, actual counts/exposure, thresholds and `pass`, `fail`, `incomplete`, `notRun` statuses; no fabricated zero for unavailable measurements |
| `exclusions` | Typed capability/segment/route exclusions approved before scoring, not free-text waivers for failed mandatory cells. Required both-route protocol cannot be satisfied by excluding a missing route |
| `approvals` | Owner, event operator and independent technical reviewer attestations over the same immutable content digest; details below |
| `revocation?` | Typed reason, observed UTC time, authorized source reference and affected record revision. Revocation dominates an older approval and cannot be cleared by selecting a level |
| `retention` | Ordinary capture time/expiry and optional explicit-export reference; record validity and retention are separate checks, neither silently renews the other |

Serialization details proposed for consistency with shadow schema: canonical UUID strings; revision counters as base-10 UInt64 strings; counts/versions as integers; finite nonnegative durations in seconds and measurement units explicitly named; UTC milliseconds; no free-form error strings. Retain actual zero and missing distinctly. B-06 must specify canonical signing/digest bytes before implementation, including sorted object keys/input order, exact optional/null handling and algorithm identifier; do not use unstable `Hasher` output or sign a mutable dictionary. The approval verifier/trust mechanism is an integration request for owner review, not supplied by Codable.

## 5. Run summaries, metrics and approvals

Each run summary should bind `runID`, `planID`, `appCommit`, `harnessCommit`, parameter/model references, `evidenceClass`, `executionMode`, exact fingerprint/route row, setup revision, UTC interval, monotonic session token, actual observed duration, exposure counts, result digest and completeness status. Recorded evidence needs its approved fixture/consent reference; synthetic fixtures need a manifest/version; live runs need an operator observation reference. No source frames, audio, identity UUIDs, subject names or input URLs are embedded.

Each metric result contains a controlled metric ID, level/route/stratum, numerator, denominator, unit, observation/distribution summary, frozen threshold reference, status and evidence reference. Count dropped records, unmatched action pairs and unverified labels separately. An absent denominator is N/A with incomplete coverage where required. Signature or runtime grant fields never come from these counters.

Recommend each approval carry `role` (`owner`, `eventOperator`, `independentTechnicalReviewer`), opaque `signerRef`, explicit decision, UTC time, content digest and verifiable approval-artifact reference. The owner identity must resolve to the actual project owner; operator/reviewer roles must resolve to real participating people, not generated placeholders. Recommend independent reviewer identity differ from the implementation author and operator; record any proposed role overlap for owner resolution before a run. Do not infer independence from having three string fields. No person names are inferred from video; names on human approval documents, if required, are explicit approval metadata outside shadow logs.

No signatures are pre-populated here. A PR approval or CI success alone does not supply Q3 attestations. If a reviewer refuses, evidence is incomplete, a required route is missing or a critical event occurred, the record stays failed/incomplete until a new reviewed assessment; editing the existing outcome or signatures in place must invalidate its digest.

## 6. QualificationLookup and runtime handoff — proposed

B-06's ticket requires a lookup that survives relaunch and makes a level unavailable when the fingerprint changes. Recommend a read-only lookup over the current full fingerprint, Director scope, setup attestation, clock and verified record index. Return eligibility plus a typed unavailable reason/reference for the console; method signatures are not prescribed as existing APIs. Release reads verified real records only; Debug can inject fixtures in a visibly separate test path. A missing/corrupt/unknown-version store returns unavailable, never a permissive fallback.

An approved record qualifies exactly its named level and binding. Require all mandatory evidence/results/approvals, correct integrity/trust checks, current admission, current setup/scope, unexpired validity and retention, and no later revocation. A match for Assist cannot enable Auto/Backup. Both output-route rows must pass the proposed protocol; each lookup still matches only the active exact route. Never search for an older matching approval after a newer revision was revoked or failed; retain a bounded supersession/revocation index and expire the family together when necessary so pruning cannot resurrect authority.

Availability must be refreshed on fingerprint, policy/build/model/workload/scope/admission changes, at selection and handback, and before an authority-dependent effect. If it disappears while active, retire current grants/work; existing deterministic effect validation remains mandatory. Stored eligibility cannot bypass manual takeover, evidence freshness, cut-ready checks or one-shot Take permits. Health restoration, reconnect and relaunch never auto-enable the Director; launch remains Manual, then the operator explicitly selects/hands back an available level.

Critical defects or withdrawal by the owner invalidate the affected approval immediately through a local, persistent revocation path. No show-time network lookup is permitted (AI-2). The local authoritative record/verifier and operator's withdrawal path must work offline; proving that mechanism is B-06 integration work. Restoring a backup store or importing an old exported assessment must not erase a newer revocation. Unknown order, clock rollback or conflicting approvals fail closed pending review.

## 7. Retention, export and unresolved lifetime

C3/AI-4 require ordinary bounded metadata to expire after 30 days, with explicit local export. B-06 must not create indefinite ordinary qualification/evidence storage by renaming it configuration. It must also survive relaunch while the record remains valid and retained. Proposal: ordinary records and indexes expire no later than their capture-time retention boundary; a missing/expired authoritative record makes the level unavailable. No owner-approved long-lived qualification retention exception exists in the inspected register.

An explicit exported assessment/evidence copy may remain under owner control with original timestamps. **Export is not approval, requalification or automatic import.** How an exported signed approval may serve as a durable authoritative source is an unresolved owner/integration question; do not enable it by default or refresh the original record's age on read/import. If the owner wants a different operational approval lifetime, record that policy separately before implementing it. A bounded approval interval alone does not waive metadata expiry.

Use controlled metadata only. No audio, video, frames, screenshots, gallery/face/body vectors, raw subject UUIDs, inferred names, children as targets, source URLs, serials, arbitrary paths, credentials or free-text rejection logs. No show network or background export/upload. Separate media fixtures need E3; the protocol does not authorize collection. Proposed storage/queue limits are explicit implementation parameters, not numbers selected in this memo.

## 8. B-06 acceptance cases — proposed, no pass claimed

- Each real per-level record survives relaunch; app starts Manual. Empty/missing/failed/incomplete/revoked/expired/corrupt/unknown-schema records keep the level unavailable.
- Change each actual fingerprint field independently, including route, mode, optional nil/value and input membership; old approval no longer matches. Reordering a validated input set uses the documented canonical comparison. Same-model physical substitution still requires setup re-attestation.
- Provisional or single-input admission cannot masquerade as the required certified two-input rig. Preferred/rehearsal route cannot satisfy active downstream-route evidence.
- Missing operator/owner/reviewer attestation, mismatched digests, altered parameters/model/scope, absent live evidence, dropped critical intervals or missing route cells cannot approve a level. Fixture records remain unusable in Release.
- Revoke while active; pending effects retire and cannot resume after health restoration. A newer failed/revoked record, store restart, retention prune, clock rollback or old export/import cannot resurrect earlier approval.
- Run expiry cleanup and explicit export using injected clocks without blocking frame/Take paths. No forbidden payload or rejected record content is copied into unrestricted debug logs.

These are proposed tests and format constraints for B-06, not existing implementation results. The only evidence produced for D-04 is source inspection and documentation validation. All level approvals and policy choices remain **AWAITING OWNER**.
