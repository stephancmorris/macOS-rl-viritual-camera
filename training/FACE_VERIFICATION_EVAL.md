# Face verification evaluation

This sets the face-identity thresholds on real footage, and decides whether a face-recognition model should replace the app's Vision feature print. It produces numbers only; it changes nothing in the app.

## What it measures

For each method, the scorer reports two things:

- the distance threshold that keeps false accepts at or below **0.1% per decision** (two different people judged the same)
- the **true-accept rate** at that threshold, overall and by face height

A pair falls in the face-height bin of the smaller of its two faces: under 48, 48–64, 64–96, or 96 px and over. Faces are measured in source pixels; the app grades faces under 64 px as "no evidence".

| Method | How it is scored |
| --- | --- |
| Vision feature print (today's app signature) | `scripts/face_verification/feature_print_distances.swift` runs the same pinned `VNGenerateImageFeaturePrintRequest` Revision2 on the same 15%-padded crop as `FaceSignatureExtractor` |
| SFace (OpenCV Zoo) | `face_verification_eval.py` computes 112×112 embeddings with OpenCV's DNN module and compares them by cosine distance. Faces are not aligned, the same as in the app |

## The labelled set

The owner supplies the footage, under their own consent and retention terms. Keep it under `training/face_eval/`, which git ignores. Nothing here downloads, uploads or commits media.

**Aim for at least:**

- 8 identities, across 8–10 clips
- every face-height bin
- look-alikes, matching outfits, profile views, a microphone across the face, and stage lighting

You need at least 1,000 impostor pairs for a 0.1% rate to be measurable; the report warns when there are fewer.

**Manifest** (`manifest.csv`, one row per face, paths relative to the manifest, no commas in paths):

```csv
image,identity,clip,face_x,face_y,face_w,face_h
frames/clip1_0001.png,speaker_a,clip1,0.41,0.55,0.04,0.07
```

The face box is normalised in Vision's convention, with the origin at the bottom left. An optional `face_height_px` column overrides the measured height.

## SFace model

Download `face_recognition_sface_2021dec.onnx` yourself from [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface) and keep it out of git (`*.onnx` is ignored).

The code is Apache-2.0. Like every open face model, it was trained on face images scraped from the web. The owner must sign off the licence before any model ships in the app.

## Run

```sh
swift scripts/face_verification/feature_print_distances.swift training/face_eval/manifest.csv training/face_eval/feature_print.json
```

```sh
cd training && python3 face_verification_eval.py face_eval/manifest.csv --feature-print-distances face_eval/feature_print.json --sface-model face_eval/face_recognition_sface_2021dec.onnx --json face_eval/results.json
```

Tests use synthetic vectors only:

```sh
cd training && python3 -m unittest test_face_verification_eval
```

## Reading the result

- **Feature-print threshold.** Its threshold at ≤0.1% false accepts replaces the provisional strong-match value (0.50) in `IdentityThresholds.featurePrintProvisional`. Its bins show where faces are too small to help.
- **Adopting SFace.** Swap it in behind `IdentityEmbedder` only if it beats the feature print clearly in the 48–96 px bins: about 20 percentage points more true accepts at the same false-accept rate.
- **Turning the live veto on** (`DeveloperFlags.identityVetoEnabled`) also needs the owner's rig checks and a settled legal position on processing faces.
