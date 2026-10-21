#!/usr/bin/env python3
"""C-10 offline tiny MLP fit/evaluation; no installation or model promotion."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import re
import struct
import sys

from director_dataset import DatasetError, FEATURE_NAMES, SPLITS, load_dataset, require
from director_dataset import shadow


def sigmoid(value):
    if value >= 0:
        return 1 / (1 + math.exp(-value))
    exponent = math.exp(value)
    return exponent / (1 + exponent)


def probability(model, features):
    """Raw schema-1 vectors; preprocessing is already folded into these weights."""
    require(len(features) == 16, 'invalid inference feature count')
    hidden = [sigmoid(bias + math.fsum(w * x for w, x in zip(weights, features)))
              for weights, bias in zip(model['hiddenWeights'], model['hiddenBias'])]
    value = sigmoid(model['outputBias'] + math.fsum(w * h for w, h in zip(model['outputWeights'], hidden)))
    require(math.isfinite(value) and 0 <= value <= 1, 'nonfinite model prediction')
    return value


def training_preprocessing(groups):
    rows = [row for group in groups for row in group.features]
    means = [math.fsum(row[index] / len(rows) for row in rows) for index in range(16)]
    scales = [math.sqrt(math.fsum(((row[index] - means[index]) / math.sqrt(len(rows))) ** 2
                                  for row in rows)) for index in range(16)]
    return means, [scale if scale > 0 else 1.0 for scale in scales]


def fit(dataset, *, hidden_units, epochs, learning_rate, seed):
    require(type(hidden_units) is int and 1 <= hidden_units <= 64, 'hidden units must be 1 through 64')
    require(type(epochs) is int and 1 <= epochs <= 10000, 'epochs must be 1 through 10000')
    require(type(learning_rate) in (int, float) and math.isfinite(learning_rate) and
            0 < learning_rate <= 1, 'learning rate must be finite and in (0, 1]')
    require(type(seed) is int and 0 <= seed <= 2**32 - 1, 'seed must be an unsigned 32-bit integer')
    groups = dataset.groups['train']
    means, scales = training_preprocessing(groups)
    rng = random.Random(seed)
    radius = math.sqrt(6 / (16 + hidden_units))
    weights = [[rng.uniform(-radius, radius) for _ in range(16)] for _ in range(hidden_units)]
    biases = [0.0] * hidden_units
    output = [rng.uniform(-radius, radius) for _ in range(hidden_units)]
    output_bias = 0.0
    prepared = [[([(x - mean) / scale for x, mean, scale in zip(row, means, scales)],
                  int(rank == group.chosen_rank)) for rank, row in enumerate(group.features)]
                for group in groups]
    # Every comparison group contributes equal total weight per epoch. One-hot
    # chosen/not-chosen labels describe supplied choices, never shot safety.
    order = list(range(len(prepared)))
    for _ in range(epochs):
        rng.shuffle(order)
        for group_index in order:
            candidates = list(prepared[group_index])
            rng.shuffle(candidates)
            step = learning_rate / len(candidates)
            for features, label in candidates:
                hidden = [sigmoid(b + math.fsum(w * x for w, x in zip(row, features)))
                          for row, b in zip(weights, biases)]
                predicted = sigmoid(output_bias + math.fsum(w * h for w, h in zip(output, hidden)))
                error = predicted - label
                hidden_errors = [error * w * h * (1 - h) for w, h in zip(output, hidden)]
                for index in range(hidden_units):
                    for feature in range(16):
                        weights[index][feature] -= step * hidden_errors[index] * features[feature]
                    biases[index] -= step * hidden_errors[index]
                    output[index] -= step * error * hidden[index]
                output_bias -= step * error
    # Export receives the raw vector and needs no hidden external preprocessing.
    raw_weights = [[shadow.float32(w / scale) for w, scale in zip(row, scales)] for row in weights]
    raw_bias = [shadow.float32(b - math.fsum(w * mean / scale for w, mean, scale in zip(row, means, scales)))
                for row, b in zip(weights, biases)]
    model = {'artifactSchemaVersion': 1, 'featureSchemaVersion': 1,
             'inputName': 'directorFeatures', 'inputShape': [1, 16],
             'outputName': 'probability', 'outputShape': [1, 1],
             'featureNames': list(FEATURE_NAMES), 'architecture': 'sigmoidMLP',
             'evidenceClass': dataset.evidence_class,
             'hiddenWeights': raw_weights, 'hiddenBias': raw_bias,
             'outputWeights': [shadow.float32(w) for w in output],
             'outputBias': shadow.float32(output_bias),
             'preprocessing': {'foldedIntoRawWeights': True, 'fitSplit': 'train',
                               'mean': means, 'scale': scales},
             'fit': {'hiddenUnits': hidden_units, 'epochs': epochs,
                     'learningRate': learning_rate, 'seed': seed,
                     'objective': 'groupBalancedCandidateBinaryCrossEntropy'},
             'provenance': dataset.provenance,
             'releaseStatus': 'offlineCandidateNoPromotion'}
    digest = hashlib.sha256(json.dumps(model, sort_keys=True, allow_nan=False).encode()).hexdigest()
    model['modelVersion'] = f'{dataset.evidence_class}-{digest[:16]}'
    for group in dataset.groups['train']:
        for row in group.features:
            probability(model, row)
    return model


def evaluate(model, groups, bins):
    require(type(bins) is int and 1 <= bins <= 100, 'reliability bins must be 1 through 100')
    exact = baseline_exact = 0
    scores, labels = [], []
    reliability = [[] for _ in range(bins)]
    for group in groups:
        predictions = [probability(model, row) for row in group.features]
        # Python max retains the original rules order on equal scores.
        chosen = max(range(len(predictions)), key=lambda rank: predictions[rank])
        exact += int(chosen == group.chosen_rank)
        baseline_exact += int(group.chosen_rank == 0)
        for rank, prediction in enumerate(predictions):
            label = int(rank == group.chosen_rank)
            scores.append(prediction); labels.append(label)
            reliability[min(int(prediction * bins), bins - 1)].append((prediction, label))
    require(bool(scores), 'no evaluation candidates')
    brier = math.fsum((prediction - label) ** 2 for prediction, label in zip(scores, labels)) / len(scores)
    # Clipping is exclusively for finite reporting at sigmoid saturation.
    log_loss = -math.fsum(label * math.log(max(prediction, 1e-15)) +
                         (1 - label) * math.log(max(1 - prediction, 1e-15))
                         for prediction, label in zip(scores, labels)) / len(scores)
    rows = []
    for index, entries in enumerate(reliability):
        rows.append({'lower': index / bins, 'upper': (index + 1) / bins,
                     'count': len(entries),
                     'meanProbability': math.fsum(value for value, _ in entries) / len(entries) if entries else None,
                     'selectedFraction': sum(label for _, label in entries) / len(entries) if entries else None})
    return {'comparisonGroups': len(groups), 'candidates': len(scores),
            'modelExactChoices': exact, 'rulesExactChoices': baseline_exact,
            'modelAgreement': exact / len(groups), 'rulesAgreement': baseline_exact / len(groups),
            'candidateBrier': brier, 'candidateLogLoss': log_loss,
            'rulesProbability': None, 'reliability': rows}


def make_report(model, dataset, bins):
    return {'reportSchemaVersion': 1, 'evidenceClass': dataset.evidence_class,
            'modelVersion': model['modelVersion'], 'provenance': dataset.provenance,
            'metrics': {name: evaluate(model, dataset.groups[name], bins) for name in SPLITS},
            'interpretation': 'descriptiveOfflineChoiceAgreement',
            'calibrationClaim': 'none', 'promotionDecision': 'notPerformed',
            'captureCompleteness': 'observedOnlyNotProvenComplete'}


def markdown(report):
    lines = ['# Offline Director scorer evaluation', '',
             f'Evidence class: **{report["evidenceClass"]}**. Model: `{report["modelVersion"]}`.', '',
             'Explicit supplied ranks are choice labels. Nonselection does not establish poor shot quality or safety. '
             'These results are descriptive; no qualification, calibrated probability claim, production threshold or promotion is supplied.', '',
             '| Split | Groups | Candidates | Model exact | RuleJudge exact | Model Brier | Model log loss |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for name, metric in report['metrics'].items():
        n = metric['comparisonGroups']
        lines.append(f'| {name} | {n} | {metric["candidates"]} | {metric["modelExactChoices"]}/{n} | '
                     f'{metric["rulesExactChoices"]}/{n} | {metric["candidateBrier"]:.6g} | {metric["candidateLogLoss"]:.6g} |')
    lines += ['', 'Validation and test are whole held-out sessions. Training uses only train-session features and labels. '
              'RuleJudge has no probability; its Brier, log loss and probability calibration are unavailable. '
              'Candidate probability metrics weight candidates equally; exact-choice agreement weights comparison groups equally.', '',
              'Reliability bins are descriptive candidate-level summaries, not fitted calibration or release criteria. '
              'Zero observed loss cannot establish complete capture, authentic labels or representative sessions.', '']
    for name in ('validation', 'test'):
        lines += [f'## {name.title()} reliability', '', '| Probability interval | Candidates | Mean probability | Selected fraction |',
                  '| --- | ---: | ---: | ---: |']
        for row in report['metrics'][name]['reliability']:
            mean = 'unavailable' if row['meanProbability'] is None else f'{row["meanProbability"]:.6g}'
            fraction = 'unavailable' if row['selectedFraction'] is None else f'{row["selectedFraction"]:.6g}'
            close = ']' if row['upper'] == 1 else ')'
            lines.append(f'| [{row["lower"]:g}, {row["upper"]:g}{close} | {row["count"]} | {mean} | {fraction} |')
        lines.append('')
    return '\n'.join(lines)


# Reviewable subset of Apple's Model.proto, FeatureTypes.proto and NeuralNetwork.proto.
# Exact fields and source links are documented in director-scorer-training.md.
def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128); value >>= 7
    result.append(value)
    return bytes(result)


def integer_field(field, value):
    return varint(field << 3) + varint(value)


def message(field, value):
    return varint((field << 3) | 2) + varint(len(value)) + value


def string_field(field, value):
    return message(field, value.encode('utf-8'))


def float_weights(values):
    return message(1, struct.pack('<' + 'f' * len(values), *values))


def coreml_bytes(model):
    """Uncompiled .mlmodel with raw Float32[1,16] -> Float32[1,1]."""
    def feature(name, shape):
        array = message(1, b''.join(varint(value) for value in shape)) + integer_field(2, 65568)
        return string_field(1, name) + message(3, message(5, array))

    def metadata(key, value):
        return message(100, string_field(1, key) + string_field(2, value))

    def layer(name, source, target, field, parameters):
        return string_field(1, name) + string_field(2, source) + string_field(3, target) + message(field, parameters)

    def matmul(name, source, target, weights, biases):
        # BatchedMatMul stores its [input, output] matrix in COLUMN-major order.
        parameters = (integer_field(5, len(weights[0])) + integer_field(6, len(weights)) +
                      integer_field(7, 1) + message(8, float_weights([w for row in weights for w in row])) +
                      message(9, float_weights(biases)))
        return layer(name, source, target, 1045, parameters)

    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', model['modelVersion']) is not None,
            'invalid model version')
    creator = (metadata('alfie.director.featureSchema', '1') +
               metadata('alfie.director.modelVersion', model['modelVersion']) +
               metadata('alfie.director.trainingEvidence', model['evidenceClass']))
    description = (message(1, feature('directorFeatures', [1, 16])) +
                   message(10, feature('probability', [1, 1])) + message(100, creator))
    layers = [matmul('raw-hidden', 'directorFeatures', 'hiddenLogits', model['hiddenWeights'], model['hiddenBias']),
              layer('hidden-sigmoid', 'hiddenLogits', 'hidden', 130, message(40, b'')),
              matmul('hidden-output', 'hidden', 'outputLogit', [model['outputWeights']], [model['outputBias']]),
              layer('output-sigmoid', 'outputLogit', 'probability', 130, message(40, b''))]
    network = b''.join(message(1, value) for value in layers) + integer_field(5, 1)
    return integer_field(1, 4) + message(2, description) + message(500, network)



def parity_projection(model, dataset):
    """All unique captured vectors, with expected raw JSON-model predictions."""
    cases, seen = [], set()
    for split in SPLITS:
        for group in dataset.groups[split]:
            for values in group.features:
                if values not in seen:
                    seen.add(values)
                    cases.append({'features': list(values), 'expectedProbability': probability(model, values)})
    return {'featureSchemaVersion': 1, 'evidenceClass': dataset.evidence_class,
            'modelVersion': model['modelVersion'], 'cases': cases}


def write_outputs(output, model, dataset, report, include_coreml=False):
    """Create one exclusive new directory; never replace an existing artifact."""
    output = Path(output)
    payloads = {'model.json': json.dumps(model, indent=2, sort_keys=True, allow_nan=False).encode() + b'\n',
                'dataset.json': json.dumps(dataset.projection(), indent=2, sort_keys=True, allow_nan=False).encode() + b'\n',
                'report.json': json.dumps(report, indent=2, sort_keys=True, allow_nan=False).encode() + b'\n',
                'report.md': markdown(report).encode()}
    if include_coreml:
        payloads['DirectorScorer.mlmodel'] = coreml_bytes(model)
        payloads['parity.json'] = json.dumps(parity_projection(model, dataset), indent=2, allow_nan=False).encode() + b'\n'
    output.mkdir(exist_ok=False)
    written = []
    try:
        for name, content in payloads.items():
            path = output / name
            with path.open('xb') as stream:
                written.append(path)
                stream.write(content)
    except BaseException:
        for path in written:
            path.unlink(missing_ok=True)
        try:
            output.rmdir()
        except OSError:
            pass
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description='Fit/evaluate a local metadata-only Director scorer candidate')
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--labels', required=True, type=Path)
    parser.add_argument('--splits', required=True, type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--hidden-units', required=True, type=int)
    parser.add_argument('--epochs', required=True, type=int)
    parser.add_argument('--learning-rate', required=True, type=float)
    parser.add_argument('--seed', required=True, type=int)
    parser.add_argument('--reliability-bins', required=True, type=int)
    parser.add_argument('--coreml', action='store_true', help='also write an uncompiled local .mlmodel; never install or bundle it')
    args = parser.parse_args(argv)
    try:
        require(not args.output_dir.exists() and not args.output_dir.is_symlink(), 'output directory already exists')
        require(1 <= args.reliability_bins <= 100, 'reliability bins must be 1 through 100')
        dataset = load_dataset(args.bundle, args.labels, args.splits)
        model = fit(dataset, hidden_units=args.hidden_units, epochs=args.epochs,
                    learning_rate=args.learning_rate, seed=args.seed)
        report = make_report(model, dataset, args.reliability_bins)
        write_outputs(args.output_dir, model, dataset, report, args.coreml)
    except DatasetError as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 2
    except (ValueError, OverflowError, TypeError, KeyError):
        print('ERROR: invalid numeric input or model fit', file=sys.stderr)
        return 2
    except OSError:
        print('ERROR: local input/output failed', file=sys.stderr)
        return 1
    print(f'Created offline {dataset.evidence_class} scorer candidate; no promotion performed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
