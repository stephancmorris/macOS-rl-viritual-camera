#!/usr/bin/env python3
"""C-10: strict, local metadata dataset. No label or history inference."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import sys

# Share C-05's closed wire reader rather than accepting a second interpretation.
SCRIPTS = Path(__file__).resolve().parents[1] / 'CinematicCoreMacOS' / 'scripts'
sys.path.insert(0, str(SCRIPTS))
import director_shadow_report as shadow

SPLITS = ('train', 'validation', 'test')
FEATURE_NAMES = shadow.DIRECTOR_FEATURE_NAMES
MAX_METADATA_BYTES = shadow.MAX_INPUT_BYTES
INCOMPLETE_ISSUES = (
    'leading_sequence_offset', 'sequence_gaps', 'reported_drops', 'backward_clocks',
    'inconsistent_parameters', 'incomplete_or_duplicate_action_pairs',
    'inconsistent_action_pairs', 'inconsistent_take_roles', 'invalid_measurements',
)


class DatasetError(ValueError):
    """Fixed diagnostics deliberately contain no source paths or rejected payload."""


def require(condition, message):
    if not condition:
        raise DatasetError(message)


def read_metadata(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_METADATA_BYTES + 1)
    require(len(raw) <= MAX_METADATA_BYTES, 'metadata input limit exceeded')
    try:
        return shadow.strict_json(raw), hashlib.sha256(raw).hexdigest()
    except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError):
        raise DatasetError('invalid metadata JSON') from None


def closed(value, keys):
    require(type(value) is dict and set(value) == set(keys), 'unknown or missing metadata field')


def integer(value):
    require(type(value) is int and 0 <= value <= 2**63 - 1, 'invalid metadata integer')


def token(value):
    try:
        return shadow.canonical_token(value)
    except (ValueError, TypeError, AttributeError):
        raise DatasetError('invalid metadata token') from None


@dataclass(frozen=True)
class Group:
    record_id: str
    session_id: str
    judgement_index: int
    features: tuple[tuple[float, ...], ...]
    chosen_rank: int

    def projection(self):
        return {'recordID': self.record_id, 'sessionID': self.session_id,
                'judgementIndex': self.judgement_index, 'chosenRank': self.chosen_rank,
                'features': [list(row) for row in self.features]}


@dataclass(frozen=True)
class Dataset:
    evidence_class: str
    groups: dict[str, tuple[Group, ...]]
    sessions: dict[str, tuple[str, ...]]
    provenance: dict

    def projection(self):
        return {'datasetSchemaVersion': 1, 'featureSchemaVersion': 1,
                'featureNames': list(FEATURE_NAMES), 'evidenceClass': self.evidence_class,
                'provenance': self.provenance,
                'splits': {name: {'sessionIDs': list(self.sessions[name]),
                                 'groups': [g.projection() for g in self.groups[name]]}
                           for name in SPLITS}}


def load_dataset(bundle_path, labels_path, splits_path):
    """Require a complete explicit export, explicit chosen ranks, whole sessions.

    Label coverage is exact for captured comparison groups. Schema-1 records
    remain readable, but a ranked comparison without captured vectors refuses
    training; operator events need no manufactured feature vector or label.
    """
    bundle = Path(bundle_path)
    require(bundle.is_dir() and not bundle.is_symlink(), 'an explicit export bundle is required')
    for name in ('manifest.json', 'records.jsonl'):
        member = bundle / name
        require(member.is_file() and not member.is_symlink(), 'invalid export bundle member')
    def member_digest(name):
        with (bundle / name).open('rb') as stream:
            raw = stream.read(shadow.MAX_INPUT_BYTES + 1)
        require(len(raw) <= shadow.MAX_INPUT_BYTES, 'export input limit exceeded')
        return hashlib.sha256(raw).hexdigest()
    digests = {name: member_digest(name) for name in ('manifest.json', 'records.jsonl')}
    try:
        records, issues, source = shadow.load_input(bundle)
        require(not shadow.blocking_input(issues) and source.get('manifest') is not None,
                'invalid explicit export bundle')
        # Existing C-05 checks include loss, action pairs, clocks and immutable parameters.
        analysis = shadow.analyze(records, 0, issues, source)
        require(not any(analysis['issues'].get(key, 0) for key in INCOMPLETE_ISSUES),
                'incomplete or inconsistent source sessions')
    except (ValueError, TypeError, KeyError, OverflowError, RecursionError, UnicodeError):
        raise DatasetError('invalid or incomplete explicit export bundle') from None
    require(digests == {name: member_digest(name) for name in digests}, 'export changed during validation')
    labels, labels_digest = read_metadata(labels_path)
    split_spec, splits_digest = read_metadata(splits_path)
    closed(labels, ('labelSchemaVersion', 'labels'))
    integer(labels['labelSchemaVersion'])
    require(labels['labelSchemaVersion'] == 1 and type(labels['labels']) is list,
            'unsupported label schema')
    choices = {}
    for label in labels['labels']:
        closed(label, ('recordID', 'judgementIndex', 'chosenRank'))
        record_id = token(label['recordID'])
        integer(label['judgementIndex']); integer(label['chosenRank'])
        key = (record_id, label['judgementIndex'])
        require(key not in choices, 'duplicate comparison label')
        choices[key] = label['chosenRank']
    closed(split_spec, ('splitSchemaVersion', 'evidenceClass', *SPLITS))
    integer(split_spec['splitSchemaVersion'])
    require(split_spec['splitSchemaVersion'] == 1, 'unsupported split schema')
    evidence_class = split_spec['evidenceClass']
    require(type(evidence_class) is str and evidence_class in ('synthetic', 'recorded', 'live'),
            'invalid dataset evidence class')
    require({row['evidenceClass'] for row in records} == {evidence_class},
            'dataset must contain one explicit evidence class')
    assigned, sessions = {}, {}
    for name in SPLITS:
        values = split_spec[name]
        require(type(values) is list and bool(values), 'each session split must be nonempty')
        for value in values:
            session = token(value)
            require(session not in assigned, 'duplicate session or split leakage')
            assigned[session] = name
        sessions[name] = tuple(sorted(values))
    require(set(assigned) == {row['sessionID'] for row in records},
            'session assignment must exactly cover the export')
    groups = {name: [] for name in SPLITS}
    observed = set()
    for row in records:
        captured = row.get('scorerInputs')
        has_ranking = any(j['judgeKind'] == 'rules' and j['outcome']['kind'] == 'ranked' and
                          j['outcome'].get('ranked') for j in row['judgements'])
        require(not has_ranking or captured, 'comparison is missing captured scorer inputs')
        if not captured:
            continue
        indices = sorted({item['judgementIndex'] for item in captured})
        for index in indices:
            key = (row['recordID'], index)
            require(key in choices, 'comparison is missing an explicit label')
            vectors = tuple(tuple(float(value) for value in item['features'])
                            for item in captured if item['judgementIndex'] == index)
            chosen = choices[key]
            require(chosen < len(vectors), 'label rank is outside the captured candidate set')
            observed.add(key)
            group = Group(row['recordID'], row['sessionID'], index, vectors, chosen)
            groups[assigned[row['sessionID']]].append(group)
    require(observed == set(choices), 'label does not reference a captured comparison')
    require(all(groups.values()), 'each split must contain labelled comparisons')
    # Candidate-level binary training requires positive and negative examples.
    require(any(len(g.features) > 1 for g in groups['train']),
            'training requires at least one nonselected candidate')
    manifest = source['manifest']
    provenance = {'exportID': manifest['exportID'], 'exportedAtUTC': manifest['exportedAtUTC'],
                  'sourceRecordCount': len(records), 'recordSchemaVersions': manifest['recordSchemaVersions'],
                  'manifestSHA256': digests['manifest.json'],
                  'recordsSHA256': digests['records.jsonl'],
                  'labelsSHA256': labels_digest, 'splitsSHA256': splits_digest,
                  'captureCompleteness': 'noObservedLoss', 'labelSource': 'explicitSuppliedRanks'}
    return Dataset(evidence_class, {name: tuple(values) for name, values in groups.items()}, sessions, provenance)
