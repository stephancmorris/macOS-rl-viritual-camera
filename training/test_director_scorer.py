#!/usr/bin/env python3
"""Authored synthetic fit/evaluation and portable CoreML encoding checks."""
from dataclasses import replace
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from director_dataset import DatasetError, Group, load_dataset
import train_director_scorer as trainer

FIXTURE = Path(__file__).with_name('fixtures') / 'director-scorer-synthetic'
OPTIONS = {'hidden_units': 4, 'epochs': 160, 'learning_rate': 0.3, 'seed': 42}


def fields(raw):
    """Independent protobuf wire reader for the small portable-model assertions."""
    def integer(offset):
        value, shift = 0, 0
        while True:
            byte = raw[offset]; offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value, offset
            shift += 7
    result, offset = {}, 0
    while offset < len(raw):
        key, offset = integer(offset)
        if key & 7 == 0:
            value, offset = integer(offset)
        elif key & 7 == 2:
            size, offset = integer(offset)
            value = raw[offset:offset + size]; offset += size
        else:
            raise AssertionError('unexpected protobuf wire type')
        result.setdefault(key >> 3, []).append(value)
    return result


class ScorerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dataset = load_dataset(FIXTURE, FIXTURE / 'labels.json', FIXTURE / 'splits.json')
        cls.model = trainer.fit(cls.dataset, **OPTIONS)

    def test_deterministic_fit_learns_explicit_synthetic_choice(self):
        self.assertEqual(self.model, trainer.fit(self.dataset, **OPTIONS))
        result = trainer.make_report(self.model, self.dataset, 5)
        for name in ('train', 'validation', 'test'):
            self.assertEqual(result['metrics'][name]['modelExactChoices'], 4)
            self.assertEqual(result['metrics'][name]['rulesExactChoices'], 0)
            self.assertLess(result['metrics'][name]['candidateLogLoss'], math.log(2))
        self.assertTrue(self.model['modelVersion'].startswith('synthetic-'))
        self.assertEqual(result['promotionDecision'], 'notPerformed')
        self.assertIsNone(result['metrics']['test']['rulesProbability'])
        self.assertIn('**synthetic**', trainer.markdown(result))

    def test_heldout_values_and_labels_cannot_affect_fitting_or_preprocessing(self):
        groups = dict(self.dataset.groups)
        changed = []
        for group in groups['test']:
            features = [list(row) for row in group.features]
            for row in features:
                row[2] = 1000000
            changed.append(replace(group, features=tuple(tuple(row) for row in features), chosen_rank=0))
        groups['test'] = tuple(changed)
        altered = replace(self.dataset, groups=groups)
        self.assertEqual(self.model, trainer.fit(altered, **OPTIONS))
        means, scales = trainer.training_preprocessing(self.dataset.groups['train'])
        self.assertEqual(means, self.model['preprocessing']['mean'])
        self.assertEqual(scales, self.model['preprocessing']['scale'])

    def test_raw_weight_fold_matches_standardized_network(self):
        # An authored network establishes the transform algebra independently of fit.
        means, scales = trainer.training_preprocessing(self.dataset.groups['train'])
        hidden_weights = [[0.03 * (i + 1) for i in range(16)], [-0.01 * (i + 1) for i in range(16)]]
        biases, output, output_bias = [0.1, -0.2], [0.5, -0.4], 0.07
        raw = {'hiddenWeights': [[w / scale for w, scale in zip(row, scales)] for row in hidden_weights],
               'hiddenBias': [b - sum(w * mean / scale for w, mean, scale in zip(row, means, scales))
                              for row, b in zip(hidden_weights, biases)],
               'outputWeights': output, 'outputBias': output_bias}
        for group in self.dataset.groups['test']:
            for values in group.features:
                normalized = [(x - mean) / scale for x, mean, scale in zip(values, means, scales)]
                hidden = [trainer.sigmoid(b + sum(w * x for w, x in zip(row, normalized)))
                          for row, b in zip(hidden_weights, biases)]
                expected = trainer.sigmoid(output_bias + sum(w * h for w, h in zip(output, hidden)))
                self.assertAlmostEqual(trainer.probability(raw, values), expected, places=13)

    def test_metrics_known_values_bins_and_rules_tie_order(self):
        constant = {'hiddenWeights': [[0] * 16], 'hiddenBias': [0], 'outputWeights': [0], 'outputBias': 0}
        group = Group('record', 'session', 0, ((0,) * 16, (0,) * 16), 1)
        result = trainer.evaluate(constant, (group,), 2)
        self.assertEqual(result['modelExactChoices'], 0)
        self.assertEqual(result['rulesExactChoices'], 0)
        self.assertEqual(result['candidateBrier'], 0.25)
        self.assertAlmostEqual(result['candidateLogLoss'], math.log(2))
        self.assertEqual(result['reliability'][0]['count'], 0)
        self.assertEqual(result['reliability'][1]['count'], 2)
        self.assertEqual(result['reliability'][1]['selectedFraction'], 0.5)
        self.assertIsNone(result['reliability'][0]['meanProbability'])

    def test_explicit_fit_parameters_reject_invalid_values(self):
        for field, invalid in [('hidden_units', 0), ('hidden_units', True), ('epochs', 0),
                               ('learning_rate', float('nan')), ('learning_rate', 0),
                               ('seed', -1)]:
            options = dict(OPTIONS); options[field] = invalid
            with self.assertRaises(DatasetError):
                trainer.fit(self.dataset, **options)
        for value in (0, 101, True):
            with self.assertRaises(DatasetError):
                trainer.evaluate(self.model, self.dataset.groups['test'], value)

    def test_portable_coreml_shapes_metadata_weights_and_sigmoid_graph(self):
        import struct
        encoded = trainer.coreml_bytes(self.model)
        top = fields(encoded)
        self.assertEqual(top[1], [4])
        description = fields(top[2][0])
        for field, name, shape in ((1, b'directorFeatures', [1, 16]), (10, b'probability', [1, 1])):
            feature = fields(description[field][0])
            self.assertEqual(feature[1], [name])
            array = fields(fields(feature[3][0])[5][0])
            self.assertEqual(list(array[1][0]), shape)
            self.assertEqual(array[2], [65568])
        metadata = fields(description[100][0])
        values = {fields(value)[1][0].decode(): fields(value)[2][0].decode() for value in metadata[100]}
        self.assertEqual(values['alfie.director.featureSchema'], '1')
        self.assertEqual(values['alfie.director.trainingEvidence'], 'synthetic')
        network = fields(top[500][0])
        self.assertEqual(network[5], [1])
        layers = [fields(value) for value in network[1]]
        self.assertEqual(len(layers), 4)
        for index in (1, 3):
            self.assertIn(40, fields(layers[index][130][0]))
        multiply = fields(layers[0][1045][0])
        self.assertEqual((multiply[5], multiply[6]), ([16], [4]))
        weights = fields(multiply[8][0])[1][0]
        self.assertEqual(list(struct.unpack('<64f', weights)), [w for row in self.model['hiddenWeights'] for w in row])
        # Decode both matrix layers and execute their stored weights; catches a
        # transposition or a failure to fold preprocessing into portable weights.
        def predict(features):
            values = list(features)
            for layer in layers:
                if 1045 in layer:
                    parameters = fields(layer[1045][0]); inputs = parameters[5][0]; outputs = parameters[6][0]
                    weights = struct.unpack('<' + 'f' * (inputs * outputs), fields(parameters[8][0])[1][0])
                    biases = struct.unpack('<' + 'f' * outputs, fields(parameters[9][0])[1][0])
                    values = [biases[j] + math.fsum(values[i] * weights[j * inputs + i] for i in range(inputs)) for j in range(outputs)]
                else:
                    values = [trainer.sigmoid(value) for value in values]
            return values[0]
        for group in self.dataset.groups['test']:
            for row in group.features:
                self.assertEqual(predict(row), trainer.probability(self.model, row))

    def test_cli_outputs_strict_json_and_never_overwrites_or_installs(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'new-candidate'
            command = [sys.executable, str(Path(trainer.__file__)), str(FIXTURE),
                       '--labels', str(FIXTURE / 'labels.json'), '--splits', str(FIXTURE / 'splits.json'),
                       '--output-dir', str(output), '--hidden-units', '4', '--epochs', '10',
                       '--learning-rate', '0.3', '--seed', '42', '--reliability-bins', '5', '--coreml']
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual({path.name for path in output.iterdir()},
                             {'model.json', 'dataset.json', 'report.json', 'report.md', 'DirectorScorer.mlmodel', 'parity.json'})
            self.assertEqual(json.loads((output / 'model.json').read_text())['evidenceClass'], 'synthetic')
            parity = json.loads((output / 'parity.json').read_text())
            self.assertEqual(parity['evidenceClass'], 'synthetic')
            self.assertGreater(len(parity['cases']), 0)
            before = {path.name: path.read_bytes() for path in output.iterdir()}
            again = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(again.returncode, 2)
            self.assertEqual(before, {path.name: path.read_bytes() for path in output.iterdir()})
            self.assertNotIn(str(FIXTURE), again.stderr)


if __name__ == '__main__':
    unittest.main()
