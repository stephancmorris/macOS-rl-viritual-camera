# Fixture consent, retention and offline labelling

D-07 · 18 October 2026 · **E3 and AI-3 AWAITING OWNER. No footage admitted, collected, labelled or disclosed by this document.**

This is a procedure and decision packet for the owner, not permission to collect a dataset. It follows the [recorded decisions](../handoff/stage3-4/DECISIONS.md), [subject-evidence contract](subject-evidence.md), [shadow metadata allowlist](shadow-record-schema.md) and [qualification protocol](../../reports/auto-director/qualification-protocol.md). Source inspected: `origin/main` `434e26aba298e4fb1fc7f32e028bad2f03fffae8`.

The [blank fixture register](../../reports/auto-director/fixture-register-template.csv) and [blank label sheet](../../reports/auto-director/fixture-labels-template.csv) contain headers only. Copy them into the owner's controlled study storage before adding real records. Do not commit participant, consent, media or real fixture-location records to this repository, Trello or a PR. Ordinary Director shadow logs remain metadata-only and are not a fixture register.

## 1. Owner decisions to record

E3 (what media may be retained) and AI-3 (what may leave the Mac for offline work) are independent. Approving one does not approve the other. Existing camera permission, Training Data consent, event participation, access to a broadcast or possession of a public clip does not by itself supply the missing study/disclosure permission.

| Decision | Options | Recommendation for owner review | Tradeoff and evidence needed |
|---|---|---|---|
| E3 media | No study media; explicitly consented expiring fixtures; indefinite corpus | **Proposed:** keep no study media until a bounded, purpose-specific fixture protocol is approved; then admit only the smallest silent excerpts needed for a named study, with a mandatory expiry for each item | Enables independent visual labels at the cost of controlled storage, consent and deletion work. Indefinite retention is not recommended. The owner must set the actual window, permitted participants/context and review responsibilities. |
| E3 derived data | Delete all derivatives with source; retain a defined allowlist under a separate expiry | **Proposed:** treat crops, labels, hashes, dataset manifests and model derivatives as explicitly governed artifacts, not automatically anonymous exceptions | Reproducibility may need provenance after source deletion, but any retained fields/purpose/expiry must be recorded separately. A hash or numerical label is not a consent waiver. |
| AI-3 offline transfer | Nothing leaves; reviewed derived numbers only; named consented media to a named local/offline-labelling recipient or processor | **Proposed first scope:** local human labelling; no off-machine media. If a report must leave, approve a specific reviewed numerical-field export and recipients first | Keeps the first study local. External media labelling would need separate scope, recipient/tool terms, copy/retention controls and consent coverage; this packet supplies no vendor approval. |
| Renewal / withdrawal | Automatic extension; explicit renewed permission; deletion on expiry/withdrawal | **Proposed:** no automatic renewal, no new use after withdrawal, and no export while scope or deletion status is unresolved | Requires an owner/custodian response process and honest accounting of copies already disclosed. Do not promise deletion of copies outside your control without evidence. |

The C3/AI-4 **30-day ordinary metadata policy is recorded**; it is not an approved E3 media duration. The older E3 memo's 30-day fixture example remains a candidate, not an implemented or approved cleanup guarantee. Set a concrete UTC expiry and trigger for each approved media/derivative scope. No numerical duration is selected here.

Owner recording worksheet (leave blank until an actual decision):

| Required field | E3 entry | AI-3 entry |
|---|---|---|
| Selected option and exact purpose | — | — |
| Approved evidence sources, participant/context scope | — | — |
| Allowed media/derived fields and prohibited content | — | — |
| Recipients/tools/processors and location boundaries | — | — |
| Capture/use/export conditions | — | — |
| Expiry trigger, duration or explicit UTC deadline | — | — |
| Cleanup, renewal, withdrawal and derivative handling | — | — |
| Custodian / approval references | — | — |
| Decision ID/version, date, approver | — | — |

Record the completed decision in `DECISIONS.md` using its existing recording procedure. An unanswered field that affects a proposed use blocks that use. This packet does not fill or change the decision register.

## 2. Separate the permissions

| Item | What it permits / does not permit |
|---|---|
| macOS camera access | App capture permission; does not grant recording, retaining, labelling, training or disclosure permission for study footage |
| Existing Training Data consent | The recorder's implemented observation-data workflow; does not admit raw video or create a consented fixture |
| Fixture consent under approved E3 | Only the named people/context, purpose, media, derivatives, expiry and permitted uses recorded in its scope |
| AI-3 approval plus matching consent | Only the named off-machine disclosure; local fixture availability never implies permission to upload |
| C3 / AI-4 metadata scope | Bounded local Director metadata and explicit dataset export; not media, transcripts, gallery prints or raw subject identifiers |
| Qualification/trial authorization | Permission for that operating scope on the exact rig; does not grant study-media consent |

E2 remains **no audio** for Stage 3: no microphone recording, transcription, speaker-ID labels or audio-based subject choice. Admit silent approved sources; an audio-bearing source is blocked rather than silently transcribed or treated as authorized by stripping. AI-2 still prohibits show-time network use. Offline disclosure, if later approved, is a separate deliberate operation outside the live app.

## 3. Intake and custody procedure

1. **Plan without media.** Create a study plan reference, purpose, evidence class, required label schema, fixture owner/custodian, intended local use, proposed recipients (if any), and planned expiry basis. The register entry is `planned`; no capture/import occurs yet.
2. **Check decisions and consent.** Confirm recorded E3 and, for any external disclosure, AI-3. The consent custodian records the participant/venue scope, permitted capture/use/labelling/training/disclosure, expiry and withdrawal route in controlled storage. The register stores opaque references and the consent-scope version, not names or signed forms. Missing/unclear permission leaves the entry blocked.
3. **Approve one fixture scope.** An actual owner authorization changes the entry to `approved`; link that approval and the decision versions. Freeze allowed uses, derivative handling and exact expiry before admission. No inferred targets involving children; no incidental person is silently added to the approved scope. If required scope cannot be established, use synthetic fixtures instead.
4. **Admit only the approved silent source.** The custodian imports or captures only within that scope. Store it in the approved controlled location, outside ordinary app logs and this repository. Record UTC capture/interval times, source class, opaque storage reference and a content digest. Do not copy source URLs, device serials, raw filenames or credentials into a public artifact.
5. **Verify provenance and limits.** Confirm the approved content/interval, lack of audio, actual consent coverage, readable source, expiry and allowed-use fields. Rejected material does not become a training/evaluation sample. An existing recording stays `recorded` when replayed; a generated test clip stays `synthetic`. A live-derived capture is not a live-rig qualification run merely because people were originally live.
6. **Make it available only for named uses.** Change the record to `available` only after those checks, with a custody/approval reference. Every analysis/export operator checks current status, consent version, expiry and permitted purpose before opening it. Do not treat `available` as a camera/Director grant.
7. **Track copies and derivatives.** Register each extraction, annotation batch, dataset manifest and model dependency with its own reference, purpose, recipients and expiry. A content revision gets a new immutable fixture revision/digest. Preserve lineage rather than relabelling changed bytes as the same evidence.
8. **Retire explicitly.** On expiry, withdrawal, permission mismatch or unexpected disclosure, block further use/export immediately and follow the approved closure procedure below. Never change capture time or reset expiry to make old data appear current.

Synthetic fixtures containing no real participants can support schema/replay tests; label them synthetic and retain provenance. They do not replace consent for real clips or independent live evaluation.

## 4. Register fields and states

The CSV templates are storage formats for a controlled workflow, not an automated consent/expiry service. Use UTC ISO-8601 timestamps with explicit `Z`. Empty required values mean unknown/blocking; do not put `0`, `false` or a guessed date in their place. Semicolon-separated opaque references may list multiple consents, participants, copies or derivatives; keep the referenced records in controlled storage.

| Fields | Meaning / handling |
|---|---|
| `fixture_id`, `revision`, `content_sha256` | Opaque item identity, immutable revision and actual content digest; compute only for an admitted source. Digests remain controlled metadata. |
| `status`, `blocked_reason` | `planned`, `approved`, `available`, `blocked`, `expired`, `revoked`, `retired`; only `available` with current permission/expiry can be used. Record actual reasons, never a pre-filled pass. |
| `study_ref`, `owner_ref`, `consent_refs`, `participant_refs`, `consent_scope_version` | Purpose and controlled authorization/participant references; no names, contact details or biometric identifiers. |
| `evidence_class`, `captured_at_utc`, `interval_start_utc`, `interval_end_utc` | Source provenance and actual interval. Preserve original provenance on replay/export; do not mix classes in a schema-1 shadow record. |
| `expires_at_utc`, `expiry_basis_ref`, `decision_refs`, `allowed_uses` | Current explicit expiry, its owner-approved basis, exact E3/AI-3 versions and permitted purposes. “Training” or “external labelling” must be explicit if intended. |
| `storage_ref`, `copy_refs`, `derivative_refs`, `disclosure_refs` | Controlled locations and lineage; no raw paths/URLs in shared reports. Maintain a separate approved disclosure manifest for each recipient/copy. |
| `label_schema_version`, `revocation_status`, `retired_at_utc`, `deletion_evidence_ref` | The approved labelling schema; current withdrawal state; actual closure time and cleanup evidence. A blank deletion reference is not proof of deletion. |

Transition guidance: `planned → approved → available`; any state may become `blocked`, `expired` or `revoked`. Only verified cleanup/closure under the approved rules reaches `retired`. Reinstatement requires fresh explicit approval and updated scope/expiry references, not an automatic status edit. Keep only the closure metadata allowed by the approved retention policy.

## 5. Offline labelling

Before a batch, freeze the study plan, label definitions, matching tolerances, held-out event split, reviewers, disagreement process and tool version. Check each fixture's current permission and expiry. A held-out event must not also train the evaluated model; frames from one correlated event cannot create independent evidence by duplication.

Use the blank label sheet with opaque fixture/interval/reviewer references and relative seconds. Example label **types**, not completed observations: intended subject present (`yes/no/unknown`), independently observed face visibility (`yes/no/unknown`), desired input alias, desired app preset and opportunity eligibility (`yes/no/unknown`). Define allowed values in the approved label schema before use. Never put names, transcripts, face embeddings, gallery prints, keypoints or free-text person descriptions in these labels. These are offline study labels, not new schema-1 shadow-log fields.

Label only what the approved source supports. App `confirmed`, gallery-ready or a candidate score cannot independently establish the visual ground truth being evaluated. Unknown/occluded/unreviewed intervals stay unknown and outside scored denominators, with their exclusion counts reported. Record initial reviewers and adjudication separately; do not silently overwrite disagreement to increase agreement rates.

The label template is one row per labelled interval/type. Reference actual fixture revision/digest and study plan. Preserve the evidence class on all derived tables. Labels and approved derived numerical summaries remain governed data; keeping them does not extend source permission or automatically authorize a model training use.

## 6. Disclosure, expiry and withdrawal

For any proposed off-machine artifact: stop if AI-3, matching consent, named recipients, allowed fields, purpose, retention or copy/deletion conditions are missing. Prepare a reviewed manifest listing opaque fixture/derivative IDs, exact fields/content, digests, decision/consent versions and recipient scope. The actual owner-authorized export is deliberate and recorded; no background upload or live-app network path is introduced.

Review the package for excluded media/audio, identifiers, names, paths, source links, coordinates and unapproved fields. A numerical summary is not automatically anonymous. Log the actual export time, recipient reference, package digest and copy/expiry obligations in controlled storage. Explicit export does not silently reset capture times or retain original ordinary logs past their policy.

Before each use and at the owner-defined cleanup trigger, check expiries and current consent. On expiry/withdrawal: block analysis, training and disclosure; identify all local, working, cached, backup, exported and derivative references; notify only through the owner's approved process; then remove/quarantine the artifacts as the approved policy requires and record what was actually verified. No messaging or deletion is performed by this document.

If a recipient, backup or derived model cannot be verified as handled, record the unresolved scope and keep closure blocked; do not claim every copy is deleted. Resolve whether derivatives must be deleted, excluded from new work, or rebuilt under the recorded decision. Renewal is a new explicit approval made before further use, with scope/version history preserved. Keep no closure audit metadata indefinitely without a recorded basis and expiry.

## 7. Handoff and current register

To approve E3/AI-3, the owner can complete §1 and the controlled templates, then record the actual selected options in `DECISIONS.md`. The custodian needs the completed decisions, consent references, storage/cleanup ownership and label plan before admitting any footage. Q1–Q3 sign-off and scored evaluation remain separate.

This packet's register templates: **zero fixture rows and zero label rows; no approved media-retention interval, recipient or collection authorization supplied by this packet**. D-06/D-08 cannot claim recorded/live results or data-driven parameter choices from these empty templates. This is documentation evidence only, not a privacy, legal or release certification.
