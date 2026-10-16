# Subject evidence and selection

Status: reconciled 2026-10-10 for D-01. [Recorded decisions](../handoff/stage3-4/DECISIONS.md) take precedence over older proposed text. Implementation references describe the open A-07 stack at `ecbf8814b7c77c64edfd2cc4a92ff6c80d892e42`, not merged or qualified behavior. Unrecorded choices and recommendations remain **AWAITING OWNER**. See the [product contract](product-contract.md) and [event contract](event-authority-contract.md).

## Recorded contract

E1 gives an operator nomination priority. Without one, Alfie may select by visible rules such as a lectern/centre-stage presenter, a run-sheet position hint or a stable tracked person. Show the pick and allow a one-tap override. A run-sheet name is operator metadata, never inferred identity or cross-camera recognition. Do not infer children or audience members as targets.

E2 pauses audio: no microphone, microphone entitlement, audio evidence, active-speaker analysis or recorded audio for this work. Panels and crossings use a wide/group shot under P2 rather than guessed close-ups. E2 can change only by a new owner decision. Stage 4 voice-control proposals do not authorize Stage 3 audio.

N5 makes the composer's `wideWaiting` a declared subject loss. It must revoke affected work and pause; temporary acquisition/recovery gaps inhibit effects without guessing that a subject remains ready. A camera source fault and loss of a subject in a healthy camera are different events.

## Actual evidence boundary at A-07

`ChannelEvidenceSample` is a value snapshot, not an image or identity model:

| Field | Meaning / unit |
|---|---|
| `channel`, `sampledAt` | Input ID; sample host-clock time in seconds |
| `lockPhase` | `inactive`, `acquiring`, `tracking`, `hold`, `wideWaiting` |
| `trackingOwnsControl`, `galleryReady` | Existing tracking/gallery state |
| `lockedTargetID` | Optional local tracking UUID, not a person's name |
| `observationAge` | Optional seconds since newest detection observation |
| `subjectSpeed` | Smoothed normalized frame units per second |
| `holdingSteady`, `cropConverged` | Composer settlement and crop landing flags |
| `operatorGestureInProgress` | Temporary operator-adjustment inhibition |
| `observedPersonCount` | Count in the observation ROI while locked, not a full-stage census |

`IdentityEvidence` has six cases: `confirmed`, `acquiring`, `holding`, `lost`, `ambiguous`, `unavailable`. Confirmation requires the classifier's tracked target/control/gallery/freshness conditions; multiple observed people classify as ambiguous. These categories are not numerical confidence probabilities. A narrow ROI may miss another person elsewhere on stage. Gallery continuity is neither a person's identity nor proof of current face visibility.

`DirectorEvidenceAdapter` takes explicit observation-age, debounce and still-speed parameters. It publishes availability/loss/nomination events and readiness inputs; it does not select an autonomous subject or grant a cut. Review findings on stale-evidence debounce and negative observation counts remain implementation defects to resolve before relying on this boundary, not new allowed behavior. See [readiness](prepare-and-readiness.md) for the confirmed-as-face-visible question.

AI-1 allows local ranking within rule-allowed choices and low-confidence fallback toward an eligible safe wide. A judge's optional calibrated probability is distinct from identity categories and from the shot-policy candidate's `subjectConfidence`. None grants authority, extends freshness or makes an otherwise unsafe wide eligible.

## Evaluation and privacy — AWAITING OWNER for open choices

Options for E3 are no media, expiring consented fixtures, or retained fixtures; recommend only separately consented, bounded fixtures if metadata cannot answer the question. The tradeoff is reproducible visual review versus collecting identifiable media. Evidence required before collection: owner decision, consent scope, expiry/export rules and fixture provenance. This document authorizes no frames, crops, embeddings, video, audio or transcripts in Director logs.

Use synthetic sequences for exact transition tests, recorded evidence only with its real provenance and permissions, and live observations for rig/operator validation. Report these classes separately. Study opportunities should include stable presenters, acquisition, crossings, disappearance, motion, stale samples and nomination changes. Measure wrong-subject preparations, missed useful preparations, uncertainty, gap duration and false readiness without inventing a sample count or success threshold. Owner-approved per-level sign-off is still required.

AI-2 forbids network during a show. C3/AI-4 permit bounded metadata with 30-day expiry and explicit export; training permission is metadata-only. Export is an explicit operator action, not background upload. E3 and AI-3 remain open for any separate media/offline transfer proposal.
