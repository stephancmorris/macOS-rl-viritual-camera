# Synthetic scorer cross-layer rehearsal

All evidence here is **synthetic**. The source bundle was emitted by the focused Swift capture/export harness, using actual `DirectorJudgeFeatures` vectors and B-04's bounded writer/export path. Labels are explicitly authored chosen ranks; no person, footage, camera, event trial or qualification is represented.

The three whole-session splits contain four comparison groups each. Identical vectors carry alternating authored choices, so both model and RuleJudge agree on 2/4 test choices. This establishes a truthful pipeline comparison, not a model win, calibrated probability or production result.

From the repository root, reproduce the portable model and report in a new directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 training/train_director_scorer.py \
  reports/auto-director/evaluation-tools-2026-10-21/evidence/scorer-synthetic/bundle \
  --labels reports/auto-director/evaluation-tools-2026-10-21/evidence/scorer-synthetic/labels.json \
  --splits reports/auto-director/evaluation-tools-2026-10-21/evidence/scorer-synthetic/splits.json \
  --output-dir /tmp/director-scorer-swift-synthetic-reproduction \
  --hidden-units 4 --epochs 160 --learning-rate 0.3 --seed 42 \
  --reliability-bins 5 --coreml
```

`model.json` is the reviewable raw-weight artifact. `parity.json` provides every unique captured Float32 input and the expected Python probability; its model token must equal the artifact/CoreML metadata. The uncompiled binary `.mlmodel` is generated only in the chosen local output directory and is deliberately absent from this evidence folder. The Swift/CoreML runtime test compiles that generated model explicitly; no model is bundled or promoted.

Original export/record IDs, clocks, class and input hashes are preserved. Hashes establish local linkage, not real-world provenance or complete capture. See [the pipeline contract](../../../../../docs/auto-director/director-scorer-training.md) for input schemas and evidence limits.
