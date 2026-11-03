#!/usr/bin/env python3
"""Synthetic acceptance of the metadata-only C-10 dataset contract."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import director_dataset as dataset

FIXTURE = Path(__file__).with_name('fixtures') / 'director-scorer-synthetic'


class DatasetTests(unittest.TestCase):
    def test_complete_parameter_rollback_cannot_enter_training(self):
        def complete(rows):
            for row in rows:
                row['parameters']['readiness'] = {
                    'minimumSettledTime': 0, 'maximumMotion': 0.2, 'cutOnMotionAllowed': False,
                    'minimumCutSettledTime': 0, 'maximumCutMotion': 0.1}
                row['parameters']['adapter'] = {'stillSpeed': 0.2, 'debounce': 0, 'maximumObservationAge': 2}
            rows[0]['parameters']['parametersVersion'] = '2'
        self.records(complete)
        rows, issues, source = dataset.shadow.load_input(self.root)
        self.assertFalse(dataset.shadow.blocking_input(issues))
        self.assertEqual(len(rows), 12)
        analysis = dataset.shadow.analyze(rows, 0, issues, source)
        self.assertGreater(analysis['issues']['parameter_version_rollback_records'], 0)
        self.assertFalse(any(analysis['issues'].get(key, 0) for key in dataset.INCOMPLETE_ISSUES))
        with self.assertRaises(dataset.DatasetError):
            self.load()
        self.records(lambda records: [r['parameters'].update(parametersVersion='1') for r in records])
        self.assertEqual(len(self.load().groups['train']), 4)

    def test_transient_export_replacement_cannot_bind_different_parsed_bytes(self):
        original_loader = dataset.shadow.load_input
        for member in ('records.jsonl', 'manifest.json'):
            path = self.root / member
            original = path.read_bytes()
            if member == 'records.jsonl':
                changed = original.replace(b'2026-10-18T00:00:00.000Z', b'2026-10-18T00:00:00.001Z')
            else:
                value = json.loads(original)
                value['exportID'] = '00000000-0000-0000-0000-000000000001'
                changed = json.dumps(value).encode()
            self.assertNotEqual(original, changed)

            def load_replacement(*args, **kwargs):
                path.write_bytes(changed)
                try:
                    return original_loader(*args, **kwargs)
                finally:
                    path.write_bytes(original)

            with self.subTest(member=member), mock.patch.object(dataset.shadow, 'load_input', side_effect=load_replacement):
                with self.assertRaises(dataset.DatasetError):
                    self.load()
            self.assertEqual(path.read_bytes(), original)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'bundle'
        shutil.copytree(FIXTURE, self.root)

    def tearDown(self):
        self.temp.cleanup()

    def load(self):
        return dataset.load_dataset(self.root, self.root / 'labels.json', self.root / 'splits.json')

    def update(self, name, mutate):
        path = self.root / name
        value = json.loads(path.read_text()); mutate(value)
        path.write_text(json.dumps(value))

    def records(self, mutate):
        path = self.root / 'records.jsonl'
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        mutate(rows)
        path.write_text(''.join(json.dumps(row) + '\n' for row in rows))

    def test_explicit_export_labels_and_whole_session_splits(self):
        data = self.load()
        self.assertEqual(data.evidence_class, 'synthetic')
        self.assertEqual([len(data.groups[name]) for name in dataset.SPLITS], [4, 4, 4])
        self.assertEqual([g.chosen_rank for g in data.groups['train']], [1] * 4)
        self.assertEqual(data.provenance['recordSchemaVersions'], [2])
        for member, field in [('manifest.json', 'manifestSHA256'), ('records.jsonl', 'recordsSHA256')]:
            self.assertEqual(data.provenance[field], hashlib.sha256((self.root / member).read_bytes()).hexdigest())
        self.assertEqual(data.projection()['featureNames'], list(dataset.FEATURE_NAMES))

    def test_labels_must_cover_every_comparison_without_duplicates_or_unknown_references(self):
        mutations = [lambda v: v['labels'].pop(),
                     lambda v: v['labels'].append(copy.deepcopy(v['labels'][0])),
                     lambda v: v['labels'][0].update(recordID='00000000-0000-0000-0000-000000000000'),
                     lambda v: v['labels'][0].update(chosenRank=2),
                     lambda v: v['labels'][0].update(chosenRank=True),
                     lambda v: v['labels'][0].update(judgementIndex=1),
                     lambda v: v.update(labelSchemaVersion=2),
                     lambda v: v['labels'][0].update(note='forbidden')]
        original = (self.root / 'labels.json').read_bytes()
        for mutate in mutations:
            (self.root / 'labels.json').write_bytes(original)
            self.update('labels.json', mutate)
            with self.assertRaises(dataset.DatasetError):
                self.load()

    def test_split_leakage_empty_duplicate_unassigned_and_mixed_evidence_refuse(self):
        mutations = [lambda v: v['test'].extend(v['train']),
                     lambda v: v['train'].append(v['train'][0]),
                     lambda v: v.update(validation=[]),
                     lambda v: v['test'].__setitem__(0, '00000000-0000-0000-0000-000000000000'),
                     lambda v: v.update(evidenceClass='live'),
                     lambda v: v.update(extra=True),
                     lambda v: v.update(splitSchemaVersion=True)]
        original = (self.root / 'splits.json').read_bytes()
        for mutate in mutations:
            (self.root / 'splits.json').write_bytes(original)
            self.update('splits.json', mutate)
            with self.assertRaises(dataset.DatasetError):
                self.load()

    def test_missing_materialized_features_are_never_imputed(self):
        self.records(lambda rows: rows[0].pop('scorerInputs'))
        with self.assertRaisesRegex(dataset.DatasetError, 'missing captured'):
            self.load()

    def test_loss_incomplete_action_pairs_or_backward_clocks_refuse(self):
        original = (self.root / 'records.jsonl').read_bytes()
        mutations = [lambda rows: rows[0].update(droppedRecordsBefore='1'),
                     lambda rows: rows[0].update(sequence='1'),
                     lambda rows: rows[1].update(sequence='2'),
                     lambda rows: rows[1].update(eventTime=1)]
        for mutate in mutations:
            (self.root / 'records.jsonl').write_bytes(original)
            self.records(mutate)
            with self.assertRaises(dataset.DatasetError):
                self.load()

    def test_no_unbundled_or_symlink_inputs(self):
        with self.assertRaises(dataset.DatasetError):
            dataset.load_dataset(self.root / 'records.jsonl', self.root / 'labels.json', self.root / 'splits.json')
        target = self.root / 'moved-records.jsonl'
        (self.root / 'records.jsonl').rename(target)
        (self.root / 'records.jsonl').symlink_to(target)
        with self.assertRaises(dataset.DatasetError):
            self.load()

    def test_duplicate_keys_nonfinite_metadata_and_manifest_mismatch_refuse(self):
        original = (self.root / 'labels.json').read_bytes()
        for value in (b'{"labelSchemaVersion":1,"labelSchemaVersion":1,"labels":[]}',
                      b'{"labelSchemaVersion":NaN,"labels":[]}'):
            (self.root / 'labels.json').write_bytes(value)
            with self.assertRaises(dataset.DatasetError):
                self.load()
        (self.root / 'labels.json').write_bytes(original)
        self.update('manifest.json', lambda v: v.update(recordCount=999))
        with self.assertRaises(dataset.DatasetError):
            self.load()


if __name__ == '__main__':
    unittest.main()
