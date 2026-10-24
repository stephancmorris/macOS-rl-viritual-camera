# Optional local learned judge — A-16

This is adapter infrastructure with synthetic software evidence. It supplies no trained model, calibrated probability claim, production threshold, live authorization or qualification. C-10 still needs real, provenance-preserving shadow data, a held-out comparison with `RuleJudge`, calibration evidence and a model that wins that comparison before bundling. The existing shadow record lacks the complete history needed to reconstruct these features for training; do not invent it from nearby events.

`LearnedJudge` only scores the candidates already allowed by `DirectorShotPolicy.rank`. It cannot generate a shot or alter identity, readiness, authority, staleness, a permit or a lease. `DirectorJudgeGate` and existing execution boundaries remain required. Every returned judgement preserves the supplied evidence revision and time.

## Explicit configuration and fallback

Construct the pure adapter with an optional immutable `DirectorScoringModel` and an explicit `minimumProbability`. Alternatively, `LearnedJudge.coreML(compiledModelURL:minimumProbability:)` loads an explicitly supplied local `.mlmodelc` file. There is no bundle search, model compilation, download, automatic installation or promotion. Ordinary app construction installs no scorer.

The CoreML wrapper owns its model exclusively, uses CPU compute, and serializes predictions with a private lock. Apple's [MLModel documentation](https://developer.apple.com/documentation/coreml/mlmodel) requires serialized use of each model instance. Loading occurs in the explicit factory; `judge` performs no filesystem access or asynchronous work. Synchronous inference still needs measured workload evidence before any live use.

An absent, unloadable, incompatible or failed model returns the exact `RuleJudge` judgement for the same context. A malformed score or failure on any candidate discards every learned score. No partial ranking survives. Valid scores below the requested threshold abstain with `lowConfidence`; they do not select a rules candidate. A score equal to the threshold is accepted. Ties preserve deterministic rules order. Invalid thresholds, clocks, history, inconsistent wide flags or numeric values that overflow Float32 abstain with `invalidJudgement`.

The adapter owns its probability threshold. When passing its result through the existing outer gate, use `minimumProbability: nil`: a rules fallback deliberately has no probability, and the gate refuses missing probabilities when an outer threshold is required. Never invent a probability for the fallback or weaken the other gate checks. Tests document both behaviors.

`evaluate(_:)` returns `judgement`, `rules`, `source`, optional `modelVersion` and optional `fallbackReason`. The source is `learned` only when the model produced a complete valid ranking or a valid low-confidence abstention. `rules` also covers a policy abstention where no model ran. `invalid` denotes invalid requested settings/input. The optional model token may identify a valid attempted model even when prediction failed; that does not make the effective source learned. Fallback reasons are typed diagnostics without paths, raw errors or user text.

## Feature schema 1

Only actual `DirectorJudgeContext` data is used. The input is `directorFeatures`, a required Float32 multiarray of exact shape `[1,16]`. The sole output is `probability`, a required Float32 multiarray of exact shape `[1,1]`, containing one finite value in `[0,1]`. Extra inputs/outputs, optional features, shape ranges, multiple allowed shapes, state and updatable models are refused. CoreML's singleton enumeration of the exact required shape is accepted as a fixed shape; it permits no alternate shape. Creator metadata must contain `alfie.director.featureSchema = "1"` and `alfie.director.modelVersion`, an opaque token matching `[A-Za-z0-9][A-Za-z0-9._-]*`.

The raw feature order is:

| Index | Feature | Meaning |
| --- | --- | --- |
| 0 | subjectConfidence | Rule candidate's existing confidence; not a calibrated learned probability |
| 1 | movement | Rule candidate's existing nonnegative movement |
| 2 | programDwellSeconds | Timeline now minus Program start |
| 3 | sinceWideSeconds | Timeline now minus last wide |
| 4 | historyCount | Number of supplied shot-history entries |
| 5 | sameShotHistoryCount | Entries whose shot equals this candidate's shot |
| 6–10 | candidate preset | One-hot Stage Wide, Full Body, Waist Up, Webcam Wide, Tight |
| 11–15 | Program preset | Same one-hot order for the current Program shot |

Time origins and history must be finite and nonnegative, ordered, and no later than timeline now. Context now must equal timeline now. Features are converted directly to Float32 and checked again for finiteness. The schema supplies no normalization, imputation, lock phase, settled time, observation speed, face visibility, media or inferred identity. The candidate's `isWide` must agree with its actual preset. A future model needing more evidence requires a new explicit contract.

## Shadow comparison and evidence limits

The existing schema-1 `judgements` array can carry both rules and effective learned results with their original bindings, producer-supplied categories and opaque model version. A projection must describe the effective source truthfully and preserve absent parameters/evidence as unavailable. A comparison is passive metadata; it cannot authorize or dispatch an effect. No synthetic judgement may be inserted into a live provenance record.

`DirectorLearnedJudgeTests` use authored backend scores. The actual CoreML fixture is an in-test protobuf encoder for `y = x·0 + 0.75`, with field labels and explicit synthetic metadata. It is generated in a temporary directory and compiled only by the test. No fitting, dataset, binary model asset or Python dependency is introduced. The encoder follows Apple's published [Model.proto](https://github.com/apple/coremltools/blob/main/mlmodel/format/Model.proto), [FeatureTypes.proto](https://github.com/apple/coremltools/blob/main/mlmodel/format/FeatureTypes.proto) and [NeuralNetwork.proto](https://github.com/apple/coremltools/blob/main/mlmodel/format/NeuralNetwork.proto). Fixed-model determinism here means repeatability of that exercised model/runtime; it is not a claim of bitwise equality across every model or device.

E3 media collection and the consent/fixture register remain separate open gates. AI-4 permits metadata-only training under C3 retention/export rules; it does not permit recording footage or off-machine transfer. The fixture uses no person, camera, media, network or qualification record. A-16's full training/model and real shadow A/B acceptance remains pending until the corresponding data and integration evidence exist.


Runtime comparison is an explicit `configureJudgeShadow` trial with an actual-context producer and maximum judgement age. The producer returns `DirectorJudgeShadow.Sample(context:provenance:)`; every contributing timeline/history/candidate input declares its evidence class. The bounded recorder combines those classes with current camera provenance and refuses mixtures. A context provider that changes route, source, policy, style, authority, nomination or evidence cannot stamp its old comparison with new bindings. Invalid trial settings or `.invalid` feature evaluations are not logged as rules output. Both baseline and effective judgements have `notEvaluated` gate status: comparison grants no permission to prepare or Take.
