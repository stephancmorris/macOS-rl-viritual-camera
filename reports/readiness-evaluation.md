# READINESS-STUDY — distant subject and identity evidence

**Status: No real dataset evaluated.** This is the evaluation protocol and empty result sheet for https://trello.com/c/arj1CKTN. The offline harness has a synthetic no-person clip check; that validates decoding/CSV plumbing only. It cannot establish detection distance or recovery quality.

## Replay

Put only consented `.mov`, `.mp4` or `.m4v` clips in a local folder. Optionally place `<clip-basename>.json` beside each clip:

```json
{"points":[{"timeS":0.0,"x":0.5,"y":0.5},{"timeS":5.0,"x":0.55,"y":0.48}]}
```

Points mark the intended subject in normalized Vision coordinates (origin bottom left). The harness uses the nearest annotated point at each decoded frame and selects a body containing it. Without an annotation file it chooses the tallest detected body and labels the CSV row `annotated=no`; those clips cannot support a target-specific identity claim. A supplied annotation must contain at least one point, with finite nonnegative timestamps, no duplicate timestamps, and finite x/y within [0, 1]. Empty or invalid supplied annotations fail the run rather than falling back. Points are sorted by timestamp; equal-distance selection uses the earlier timestamp. An annotated point outside all detected bodies yields no selected subject, never the tallest fallback. Run the Swift Testing `ReadinessEvaluationTests` target with `ALFIE_READINESS_CLIPS=/absolute/consented-folder` and `ALFIE_READINESS_OUT=/absolute/readiness.csv`. The harness calls the existing `PersonDetector` in `.reacquiring` mode (full-frame body/pose/face) and `FaceSignatureExtractor` where a face exists. It writes one CSV row per clip, no frames or feature prints. Keep source clips and annotations private; the CSV still contains clip file names.

With neither environment variable set, the consented-folder test is explicitly skipped. Supplying only one variable, a non-absolute path, or a folder without supported clips fails the configured run. The synthetic decoder test remains independent and never counts as a consented dataset run. No annotation coverage threshold or identity-loss threshold is introduced.

The current replay is **offline**: `fresh_frames` counts detector completions within `DetectionFrameStore.maximumAge` of their processing start. It is a processing-age proxy, not live capture-to-composer freshness. `identity_switches_proxy` counts changes of selected Vision track UUID between consecutive selected frames; it is not a ground-truth wrong-person recovery count. Acquisition ROI, locked ROI, camera capture and complete `ShotComposer` recovery must be evaluated separately before using these results for thresholds.

## Dataset register (fill before analysis)

| Split | Consent/retention record | Source size/rate | Lighting/blur/exposure | Subject pixel-height bands | Occlusion/crossings | Clips / frames / subjects |
| --- | --- | --- | --- | --- | --- | --- |
| Training | | | | | | |
| Held-out small subject | | | | | | |
| Held-out crossing | | | | | | |
| Other held-out | | | | | | |

Freeze split and clip IDs before tuning. Do not report a universal distance threshold from one camera or the synthetic fixture. Record the capture source and any 4K-to-1080p detector proxy size; normalized boxes still yield source-pixel height when multiplied by source height.

## Denominators and outcomes

| Measure | Numerator | Denominator | Training | Held-out small | Held-out crossing |
| --- | --- | --- | --- | --- | --- |
| Body observation availability | Selected subject frames | Decoded annotated frames | | | |
| Face availability | Selected frames with matched face box | Selected subject frames | | | |
| Feature-print availability | Successful prints | Selected frames with face box | | | |
| Pose coverage | Selected frames with fresh pose keypoints | Selected subject frames | | | |
| Offline observation freshness | Selected frames processed within 0.5 s | Selected subject frames | | | |
| Track-ID continuity | Consecutive selected frame pairs without UUID change | Consecutive selected frame pairs | | | |
| Wrong-person reacquisition | Reviewer-confirmed wrong physical person recoveries | Annotated reacquisition opportunities | | | |
| Correct reacquisition | Reviewer-confirmed same-person recoveries | Annotated reacquisition opportunities | | | |
| Abstention | No authority granted when identity evidence inadequate | Annotated inadequate-evidence opportunities | | | |

Also report median and distribution of subject height in **source pixels** by band, acquisition latency and failures, follow loss duration, and reacquisition latency separately. Log the actual pixel/face/pose conditions at each error. Detection confidence alone never establishes identity readiness. Wrong-person, correct-recovery and abstention rows require human physical-person annotations and a separate composer replay or on-rig review; leave them blank until that evidence exists.

## Threshold/tradeoff decision

| Candidate threshold/category | Training sensitivity / abstention | Held-out sensitivity / abstention | Wrong-person count / opportunities | Decision and limitation |
| --- | --- | --- | --- | --- |
| Tracking-ready | | | | |
| Identity-recovery-ready | | | | |
| Inadequate evidence / abstain | | | | |

## Evidence and sign-off

| Item | Value |
| --- | --- |
| Build/source fingerprint, macOS, Mac | |
| Harness CSV and annotation version/hash | |
| Synthetic decoder/CSV check | |
| Reviewer and date | |
| Known camera/lighting/subject limitations | |

- [ ] Constructed consented dataset and frozen train/held-out split.
- [ ] Counts and denominators reported for small subjects and crossings.
- [ ] Physical-person recovery and abstention independently reviewed.
- [ ] Thresholds checked on held-out clips; no unsupported distance guarantee.
