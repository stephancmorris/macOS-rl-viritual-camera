# Decisions for Stephan

| ID / question | Options | Recommendation / why | Blocks | Reversible? |
|---|---|---|---|---|
| E1 Authority to change person? | Operator nomination; visual salience; audio/visual fusion | Operator nomination per camera; existing evidence preserves identity, does not establish who should speak | AD-SUBJECT | Yes, separate qualification |
| E2 Audio policy? | No audio; local ephemeral analysis; consented retained recordings | No audio in first director release; later opt-in local ephemeral analysis, never ordinary-service recording | AD-SUBJECT/COMPUTE, S4 | Collection cannot be undone; settings reversible |
| E3 Evaluation media retention? | No media; consented private fixtures with expiry; indefinite archive | Consented private fixtures, proposed 30-day expiry and explicit renewal; sanitized metrics only in repo | AD-QA | Deletion irreversible; consent precedes collection |

Status: proposed, 2026-09-30. Code is evidence of mechanisms, not proof of identification accuracy.

## What exists today

| Source/type | Provides | Does not provide |
|---|---|---|
| `PersonDetector.swift` / `PersonDetector.DetectedPerson`, `DetectionRequestPlan`, `resolveLockedAssignment` | Body rectangles, pose, optional face box/landmarks, track UUIDs; locked geometry matching and probation | Speaker identity, pastor role, lip-sync active-speaker score, cross-camera person identity |
| `FaceSignatureExtractor.swift` / `FaceSignatureExtractor`, `LandmarkRatios` | Vision feature-print distance on exact face crop and landmark comparisons | Calibrated identity probability or biometric recognition guarantee; comments about vector size/stability are not vendor guarantees |
| `ShotComposer.swift` / `LockState`, `FaceSignatureGallery`, `ReacquisitionEvidence` | Operator-selected lock, gallery, HOLD/wideWaiting and identity-vetoed reacquisition | Autonomous editorial subject selection; `stagePriorityScore` is not selection authority |
| `DetectionFrame.swift` / `DetectionFrameStore` | Observation with matching pixels and freshness bound | Sensor exposure age or audio evidence |

Current code parameters include gallery readiness at 3 samples, max 8, refresh spacing 0.4 s; reacquisition distances 0.62 (multiple candidates)/0.55 (solo), landmark veto 0.10, margin 1.25 and 3 fresh observations. These are implementation constants, **not validated director confidence thresholds**. Preserve existing vetoes and qualify outcomes; do not map 0.62 to “62% confident.”

## Evidence permission matrix

| Evidence | Continue same nominated subject? | Switch physical person? | Failure response |
|---|---|---|---|
| Operator nomination / retarget | Yes after acquisition readiness | Yes, as explicit manual action; pauses director | Missed tap retains prior lock; ask again |
| Visual continuity + gallery match | Yes within current lock and fresh generations | No | Ambiguity/occlusion/look-alike → abstain; no largest-box substitution |
| Rundown “sermon / speaker alias” | Constrains eligibility and expected role | No, cue alone cannot identify a body | Ask operator to nominate in each view |
| Mixer channel activity / isolated mic (future) | Corroboration only | Only future qualified fusion + explicit mapping | Open mic, cough, music, audience questions and multiple hot mics must abstain |
| Room audio/VAD/diarization (future) | Indicates sound/speech, not visual identity | No standalone authority | Reverberation/offscreen voice/overlap → abstain |
| Lip movement / visual salience (future) | Experimental corroboration | Not first release | Small faces, singing, occlusion and silent gestures invalidate |

Alternatives for audio: no ingest is lowest workload/privacy cost; local ephemeral channel-energy features avoid transcripts but require truthful mixer mapping; local speech/diarization plus visual association adds substantial validation and sensitive content; retained training audio is a separate consented study, not a hidden diagnostic mode. No remote/cloud fallback proposed.

## Replay study (proposed starting design)

| Item | Protocol |
|---|---|
| Corpus | 12 consented sessions × 10 min initially, from at least 4 speakers; separate session/person split, proposed 6 training / 6 held-out. Rationale: diversity before tuning; expand if strata lack opportunities |
| Strata | Frontal/profile/back, small subject source-pixel bands, lighting/exposure changes, podium occlusion, similar clothing, crossing, exit/reentry, empty stage, visible non-speaker, multiple speaking people; no staged stand-ins labelled as real-service evidence |
| Labels | Pseudonymous physical-person ID, intended subject interval, visibility/occlusion, ambiguity, camera ID, source generation, nominated point, acceptable action; optional separately consented active-speaker labels |
| Review | Two independent reviewers; disagreements adjudicated before scoring; unresolved intervals are uncertain and require abstention, not removed from denominators |
| Existing harness | `origin/r2/sol:ReadinessEvaluationTests.swift` via documented readiness env vars. Nearest target points/tallest-body fallback and UUID switches are proxies. Run only annotated clips for identity claims |
| Missing replay | Proposed full composer acquisition/hold/recovery trace plus injected frame/observation delays; compare actual selected physical person with labels, not UUID alone |
| Frozen artifacts | Source/harness/policy hashes, split manifest, clip hashes, annotation version, consent/expiry references, event trace and reviewed error IDs |

| Metric | Numerator / denominator |
|---|---|
| Wrong-person reacquisition | Wrong physical-person bindings / all labelled reacquisition opportunities; also / completed bindings |
| Wrong-person proposal | Wrong physical-person proposals / all person-specific proposals; report ready subset separately |
| Wrong-subject cut | Committed cuts to unintended person / all person-specific committed cuts; also per service hour; policy-shadow recommendations reported separately, never called actual cuts |
| Identity continuity | Correctly bound visible-subject duration / labelled visible-subject duration |
| Abstention sensitivity | Abstentions on inadequate-evidence opportunities / all inadequate-evidence opportunities |
| Over-abstention | Abstentions on acceptable opportunities / all acceptable opportunities |
| Switching UUID proxy | UUID changes / consecutive selected pairs; retain as diagnostic only |

Count a continuous loss-to-resolution interval as one reacquisition opportunity; a new independent loss opens the next. Report counts, zero denominators as N/A, strata and uncertainty. Zero observed errors is not a zero-risk claim. Study acceptance follows qualification protocol; freeze targets before held-out evaluation.

## Privacy inventory and unresolved evidence

`origin/r2/sol:docs/privacy/privacy-audit.md` found live image buffers and galleries in memory, no feature-print file writer, local diagnostics and optional consented training observations. It explicitly leaves runtime cleanup and release disclosure checks open. CSV pruning covers CSVs, not manifests or text logs; do not call everything “30-day retention.” Program can leave the Mac via its selected downstream consumer.

Proposed audio handling if approved: opt-in mic source, persistent mute/listening indicator, bounded memory only, discard audio/transcripts on completion/cancel/mute/Stop; never persist through diagnostics, crash attachments or exports by design. Verify actual retained files and network behavior at runtime. Proposed evaluation fixture expiry is 30 days from acquisition, with manual review/deletion required even if app never runs again. Keep consent register/private originals outside Git; repo records opaque IDs, counts and policy hashes. Study audio recording needs separate approval even if runtime ephemeral analysis is approved.

No audio or new dataset was collected in discovery. Camera-specific identity reliability, speech-to-person association and cleanup behavior remain **UNVERIFIED** until the described runs.
