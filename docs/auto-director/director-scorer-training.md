# Offline Director scorer pipeline — C-10 infrastructure

This pipeline prepares metadata, fits a small local sigmoid MLP, and reports descriptive held-out choice agreement. C-10 acceptance remains open until real, provenance-preserving shadow sessions, credible explicit labels and a held-out comparison support a model. The supplied three-session corpus is authored **synthetic** software evidence. Its fit, metrics and exported model establish no live accuracy, calibrated probability, qualification, production threshold or permission to bundle a model.

There is no dependency installation, network access, camera access, app installation, runtime configuration or automatic promotion. The optional export is an uncompiled local `.mlmodel`. The app continues to require explicit scorer configuration and its existing deterministic policy and authority gates.

## Inputs and capture

`training/director_dataset.py` uses the existing closed C-05 reader and requires a validated B-04 explicit-export bundle containing `manifest.json` and `records.jsonl`. The eight-field export manifest stays unchanged; `recordSchemaVersions` now explicitly supports 1 and 2. Original UTC, evidence class, IDs, sequence and reported loss survive analysis. C3's thirty-day rule is checked at original export time; processing an explicit exported copy does not refresh or expire that copy.

Shadow schema 1 remains readable and rejects `scorerInputs`, including a null-valued key. Schema 2 may omit that field when no actual comparison input was captured. When supplied, it contains complete, ordered groups of:

```json
{"featureSchemaVersion":1,"judgementIndex":0,"candidateRank":0,"features":[0.75,0,10,10,1,0,0,1,0,0,0,1,0,0,0,0]}
```

Each group references an actual rules judgement. It must include every candidate rank exactly once, in `(judgementIndex, candidateRank)` order. The sixteen values are the actual `DirectorJudgeFeatures` Float32 values widened to JSON numbers. The reader validates finiteness, exact Float32 representation, domains, candidate confidence/movement, timeline differences at the judgement's `computedAt`, history-count integer relations, candidate/Program one-hots, current evidence revision, Preview binding and preset/wide consistency. Counts must agree across candidates; distinct candidate shots cannot collectively account for more than the supplied history count.

A comparison without materialized inputs refuses training. The loader never reconstructs history from adjacent records, substitutes missing values or turns a recorded judgement into a ground-truth label. Other operator/abstention records need no invented feature vector. The pipeline rejects observed gaps, missing prefixes, drops, backward clocks, inconsistent parameters, invalid measurements and incomplete or inconsistent operator-action pairs. An absence of observed loss still cannot prove complete capture or authenticity.

The dataset loader also refuses any source session that C-05 marks capture-blocked, including complete parameter-version rollbacks. This uses the analyzer's authoritative session result rather than relying only on a copied list of issue names. Existing stricter dataset checks for invalid measurements and inconsistent evidence remain. A clean monotonic version history still passes; this introduces no new directing threshold.

## Explicit labels and session splits

Labels use this exact closed JSON shape:

```json
{
  "labelSchemaVersion": 1,
  "labels": [
    {"recordID":"00000000-0000-0000-0000-000000000001","judgementIndex":0,"chosenRank":1}
  ]
}
```

Every captured comparison group must have exactly one explicit chosen rank. Unknown references, extra fields, duplicate labels and ranks outside the original candidate set refuse the dataset. There is no automatic Take-to-label matcher. The caller is responsible for establishing and documenting why an explicit rank is a credible operator-choice label. A nonselected candidate is only a negative *choice* signal; it is not labelled unsafe or visually poor. Supplied labels do not themselves prove human review or consent.

Splits use this exact closed shape:

```json
{
  "splitSchemaVersion": 1,
  "evidenceClass": "synthetic",
  "train": ["00000000-0000-0000-0000-000000000001"],
  "validation": ["00000000-0000-0000-0000-000000000002"],
  "test": ["00000000-0000-0000-0000-000000000003"]
}
```

All exported sessions must be assigned exactly once. Train, validation and test must each contain labelled comparisons, and training needs a nonselected candidate. Candidates from one decision and all decisions from one session remain together. One dataset contains exactly one explicitly selected evidence class (`synthetic`, `recorded` or `live`); they are never pooled. Repeated sessions from the same underlying event need a separately justified study split: session isolation alone cannot establish event independence or prevent an operator from choosing a biased corpus.

## Fit, report and export

From the repository root, this supplied **synthetic** rehearsal uses explicit example fit parameters:

```sh
python3 training/train_director_scorer.py \
  training/fixtures/director-scorer-synthetic \
  --labels training/fixtures/director-scorer-synthetic/labels.json \
  --splits training/fixtures/director-scorer-synthetic/splits.json \
  --output-dir /tmp/director-scorer-synthetic-candidate \
  --hidden-units 4 --epochs 160 --learning-rate 0.3 --seed 42 \
  --reliability-bins 5 --coreml
```

The directory must be new; existing outputs and dangling destination symlinks are refused. No fit setting, abstention threshold or study recommendation is silently chosen. Integer bounds and numeric checks limit the local tool's parameter domains, not production directing settings. Exit 0 means outputs were written, 2 means invalid metadata/settings or an existing destination, and 1 means a local I/O failure. Errors omit source paths and rejected payloads.

The stdlib model has sixteen raw inputs, one sigmoid hidden layer and one sigmoid output. Seeded stochastic updates fit group-balanced candidate binary cross entropy. Mean/scale statistics use only training-session features; validation and test never participate in fitting. The selected final epoch is used without automatic validation selection or test-driven tuning. Training standardization is folded into the first layer's weights/biases, then parameters are rounded to Float32. Both JSON inference and CoreML export receive the original raw vector with no separate preprocessing step.

Outputs are:

- `dataset.json`: explicit candidate groups, labels, splits and feature schema, with original export ID/time, counts and SHA-256 digests of the input manifest, records, labels and split specification. Export digests must match both the bytes consumed by the bounded parser and the before/after file checks; temporarily replacing an export during parsing cannot bind different parsed metadata to the original digest. Hash consistency establishes local linkage, not source authenticity.
- `model.json`: reviewable Float32 weights, feature order/shapes, train-only preprocessing statistics, explicit fit parameters, evidence class and deterministic model token. This is data, not executable code or a pickled checkpoint.
- `report.json` and `report.md`: exact top-choice agreement against original rules rank zero on the same comparison groups, candidate Brier/log loss and descriptive reliability bins. Ties retain rules order. Baseline probability metrics are unavailable because `RuleJudge` provides no probability. Group agreement weights groups equally; probability metrics weight candidates equally. No calibrated-probability or release claim follows from these summaries.
- With `--coreml`, `DirectorScorer.mlmodel`: an uncompiled immutable model with exactly `directorFeatures: Float32[1,16]` and `probability: Float32[1,1]`, plus feature-schema/model-version and evidence-class metadata. A synthetic dataset produces a model token beginning `synthetic-` and synthetic training metadata. Companion `parity.json` contains every unique captured raw vector and its expected JSON-model probability for an actual CoreML runtime comparison. Export never copies a model into app resources, compiles/installs it or chooses an abstention threshold.

The small reviewable protobuf encoder follows Apple's published [Model.proto](https://github.com/apple/coremltools/blob/main/mlmodel/format/Model.proto), [FeatureTypes.proto](https://github.com/apple/coremltools/blob/main/mlmodel/format/FeatureTypes.proto) and [NeuralNetwork.proto](https://github.com/apple/coremltools/blob/main/mlmodel/format/NeuralNetwork.proto). It writes two BatchedMatMul layers with column-major weight storage, each followed by a sigmoid activation, using exact array mapping. CoreML runtime/device parity still requires the actual exported artifact to be compiled and predicted through the Swift adapter; Python structural checks alone do not establish runtime parity.

## Software validation and remaining evidence

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s CinematicCoreMacOS/scripts -p test_director_shadow_report.py -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s training -p 'test_director_*.py' -v
```

Synthetic tests cover strict versions/keys/types, full captured groups, Float32/domains/one-hots/bindings, history invariants, export validation, exact label coverage, incomplete sessions, split leakage, held-out isolation, deterministic fitting, preprocessing fold, known metric values, CoreML shapes/metadata/weight layout, and CLI nonoverwrite behavior. The synthetic fixture intentionally has a simple authored label pattern; learning it is a software check, not evidence about event directing.

Real-data collection under the recorded decisions, credible label review, session/event study design, useful held-out performance, probability calibration assessment, synchronous inference workload evidence and a separately reviewed bundle/promotion decision remain outstanding. All exported datasets and model artifacts remain local operator-controlled copies; this tool creates no separate background recorder or retention journal.
