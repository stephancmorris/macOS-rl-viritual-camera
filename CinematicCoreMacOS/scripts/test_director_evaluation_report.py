#!/usr/bin/env python3
"""Synthetic evaluation metadata and report regressions; no app or real evidence."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
import director_evaluation_report as report

FIXTURES = Path(__file__).with_name('fixtures')


def token(value):
    return str(uuid.uuid5(uuid.NAMESPACE_OID, value)).upper()


def run_fixture(name='scenario'):
    metrics = {key: 0 for key in report.SCHEMA['countMetrics']}
    metrics.update(cutsPerMinute=0, staleProposalsRejected={}, manualOverrideLatencies=[],
                   finalLevel='assist', finalPaused=False, proposalCount=1, labelledSubjectProposals=1,
                   directorAttemptCount=1, labelledSubjectAttempts=1, preparationsCommitted=1,
                   acknowledgementsAccepted=1)
    return {'scenarioID': name, 'sessionID': token(name), 'evidenceClass': 'synthetic',
            'level': 'assist', 'executionMode': 'observing', 'route': 'none',
            'configurationID': 'replay-study-1', 'parameterVersion': '1', 'judgeKind': 'rules', 'modelVersion': None,
            'durationSeconds': 60, 'opportunities': {'eligible': None, 'useful': None, 'unverified': None},
            'parameters': {
                'shotPolicy': {'minimumShotDuration': 8, 'maximumShotDuration': 35, 'wideCadence': 90,
                               'repetitionWindow': 20, 'maximumMovement': 0.1, 'cutOnMotionAllowed': False},
                'readiness': {'minimumSettledTime': 0.2, 'maximumMotion': 0.1, 'cutOnMotionAllowed': False,
                              'minimumCutSettledTime': 0.2, 'maximumCutMotion': 0.1},
                'replay': {'maximumProposalAge': 5, 'maximumEvidenceAge': 5}},
            'metrics': metrics}


def envelope(*runs):
    return {'evaluationSchemaVersion': 1, 'producer': 'DirectorReplay', 'runs': list(runs), 'shadowBindings': []}


def shadow_rows():
    return [json.loads(line) for line in (FIXTURES / 'director-shadow-synthetic-export' / 'records.jsonl').read_text().splitlines()]


def binding(rows, configuration='shadow-config-1', judge='unobserved', model=None):
    first = rows[0]
    return {'sessionID': first['sessionID'], 'evidenceClass': first['evidenceClass'],
            'level': first['context']['level'], 'executionMode': first['executionMode'], 'route': 'none',
            'configurationID': configuration, 'parameterVersion': first['parameters'].get('parametersVersion'),
            'judgeKind': judge, 'modelVersion': model}


def analyze_shadow(rows, bindings):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'records.jsonl'
        path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
        return report.summarize_shadow(path, 2, bindings)


def with_model(rows, model):
    for row in rows:
        row['judgements'] = [{'judgeKind': 'learned', 'modelVersion': model,
                              'evidenceRevision': '1', 'computedAt': row['eventTime'],
                              'outcome': {'kind': 'abstain', 'reason': {'domain': 'judge', 'code': 'lowConfidence'}},
                              'gateResult': 'notEvaluated'}]
    return rows


def with_speed(rows, speed):
    for row in rows:
        row['evidence'] = [{'channel': 'input-2', 'lockPhase': 'inactive', 'trackingOwnsControl': False,
                            'galleryReady': False, 'hasLockedTarget': False, 'subjectSpeed': speed,
                            'holdingSteady': False, 'cropConverged': False, 'operatorGestureInProgress': False,
                            'identity': 'unavailable', 'identitySource': 'sampleClassifier'}]
    return rows


def phase_binding(rows, first, last, phase_id):
    scoped = [r for r in rows if first <= int(r['sequence']) <= last]
    models = {(j['judgeKind'], j.get('modelVersion')) for r in scoped for j in r['judgements']}
    judge, model = next(iter(models)) if models else ('unobserved', None)
    value = binding(scoped, configuration=phase_id + '-config', judge=judge, model=model)
    return {**value, 'phaseID': phase_id, 'firstSequence': str(first), 'lastSequence': str(last),
            'parameterContext': copy.deepcopy(report.canonical_parameter_context(scoped[0]['parameters'])),
            'routeGenerations': sorted({r['context']['routeGeneration'] for r in scoped}, key=int)}


def analyze_phases(rows, bindings):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'records.jsonl'
        path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
        return report.summarize_shadow(path, 2, bindings, binding_schema_version=2)


class PhaseEvaluationTests(unittest.TestCase):
    def test_phase_speed_samples_retain_unobserved_judge_rows(self):
        rows = with_speed(with_model(shadow_rows(), 'model-A'), 0.1)
        for row in rows[4:]:
            row['judgements'] = []
            row['evidence'][0]['subjectSpeed'] = 0.9
        data = analyze_phases(rows, [phase_binding(rows, 0, 6, 'whole')])
        samples = data['parameterEvidence']
        self.assertEqual(len(samples), 2)
        actual = {json.dumps(p['scope']['judgeModels']): p['subjectSpeed'] for p in samples}
        self.assertEqual(actual['[]']['reportedSamples'], 3)
        self.assertEqual(actual['[]']['median'], 0.9)
        self.assertEqual(actual[json.dumps([['learned', 'model-A']])]['reportedSamples'], 4)
        self.assertEqual(actual[json.dumps([['learned', 'model-A']])]['median'], 0.1)
        self.assertTrue(all(p['phaseID'] == 'whole' for p in samples))
        self.assertTrue(all(p['scope']['declaredModelVersion'] == 'model-A' for p in samples))
        self.assertTrue(all('modelVersion' not in p['scope'] for p in samples))

    def test_explicit_phases_preserve_actual_counts_and_isolate_parameter_samples(self):
        rows = with_speed(shadow_rows(), 0.1)
        for row in rows[3:]:
            row['evidence'][0]['subjectSpeed'] = 0.9
        bindings = [phase_binding(rows, 0, 2, 'first'), phase_binding(rows, 3, 6, 'second')]
        data = analyze_phases(rows, bindings)
        self.assertEqual(data['records'], 7)
        self.assertEqual(data['recordEvidenceCounts'], {'synthetic': 7})
        self.assertEqual(data['bindingMode'], 'explicitPhases')
        self.assertEqual({row['phaseID'] for row in data['rows']}, {'first', 'second'})
        self.assertEqual(sum(row['counts']['compared'] for row in data['rows']), 2)
        self.assertFalse(data['dwell'])
        self.assertEqual([(p['phaseID'], p['subjectSpeed']['median']) for p in data['parameterEvidence']],
                         [('first', 0.1), ('second', 0.9)])
        value = envelope(); value['evaluationSchemaVersion'] = 2; value['shadowBindings'] = bindings
        result = report.evaluate(value, shadow_data=data)
        self.assertFalse(result['qualified'])
        self.assertEqual(result['evaluationSchemaVersion'], 2)
        self.assertEqual(result['qualificationStatus'], 'incomplete')
        text = report.markdown(result)
        self.assertIn('Physical routes are unverified declared labels', text)
        self.assertIn('original sequences 3–6', text)
        self.assertIn('/ phase second', report.parameter_memo(result))

    def test_v1_stays_strict_and_does_not_implicitly_accept_phase_bindings(self):
        rows = shadow_rows()
        value = envelope(); value['shadowBindings'] = [phase_binding(rows, 0, 6, 'one')]
        with self.assertRaises(ValueError):
            report.validate_evaluation(value)
        legacy = analyze_shadow(rows, [binding(rows)])
        self.assertNotIn('bindingMode', legacy)
        self.assertNotIn('phases', legacy)
        self.assertEqual(sum(r['counts']['compared'] for r in legacy['rows']), 2)

    def test_phase_metadata_rejects_overlap_duplicate_ids_unknown_fields_and_bad_counters(self):
        rows = shadow_rows()
        base = [phase_binding(rows, 0, 2, 'first'), phase_binding(rows, 3, 6, 'second')]
        mutations = [lambda b: b[0].update(firstSequence=True),
                     lambda b: b[0].update(firstSequence='00'),
                     lambda b: b[0].update(lastSequence=str(2**64)),
                     lambda b: b[0].update(firstSequence='3'),
                     lambda b: b[1].update(firstSequence='2'),
                     lambda b: b[1].update(phaseID='first'),
                     lambda b: b[0].update(opportunities=1),
                     lambda b: b[0].update(routeGenerations=['1', '1']),
                     lambda b: b[0].update(routeGenerations=['2', '1']),
                     lambda b: b[0].update(routeGenerations=[True]),
                     lambda b: b[0]['parameterContext'].update(private='PRIVATE')]
        for mutate in mutations:
            candidate = copy.deepcopy(base); mutate(candidate)
            value = envelope(); value.update(evaluationSchemaVersion=2, shadowBindings=candidate)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                report.validate_evaluation(value)

    def test_every_accepted_row_and_span_endpoint_must_be_covered_exactly(self):
        rows = shadow_rows()
        variants = [[], [phase_binding(rows, 0, 2, 'first')],
                    [phase_binding(rows, 0, 2, 'first'), phase_binding(rows, 4, 6, 'second')]]
        too_far = phase_binding(rows, 0, 6, 'first'); too_far['lastSequence'] = '7'; variants.append([too_far])
        nonexistent = phase_binding(rows, 0, 6, 'first'); nonexistent['sessionID'] = token('unknown-session'); variants.append([nonexistent])
        for bindings in variants:
            with self.subTest(bindings=bindings), self.assertRaises(ValueError):
                analyze_phases(rows, bindings)

    def test_each_phase_matches_actual_level_mode_class_model_parameters_and_routes(self):
        rows = with_model(shadow_rows(), 'model-A')
        mutations = [lambda b: b.update(level='auto'), lambda b: b.update(executionMode='observing'),
                     lambda b: b.update(evidenceClass='recorded'), lambda b: b.update(modelVersion='model-B'),
                     lambda b: b.update(routeGenerations=['99']),
                     lambda b: b['parameterContext']['resolvedStyle'].update(wideCadence=91)]
        for mutate in mutations:
            candidate = phase_binding(rows, 0, 6, 'one'); mutate(candidate)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                analyze_phases(rows, [candidate])
        mixed = copy.deepcopy(rows); mixed[-1]['judgements'][0]['modelVersion'] = 'model-B'
        with self.assertRaises(ValueError):
            analyze_phases(mixed, [phase_binding(rows, 0, 6, 'one')])
        first, second = phase_binding(rows, 0, 2, 'first'), phase_binding(rows, 3, 6, 'second')
        second['configurationID'] = first['configurationID']
        second['parameterContext']['resolvedStyle']['wideCadence'] = 91
        value = envelope(); value.update(evaluationSchemaVersion=2, shadowBindings=[first, second])
        with self.assertRaises(ValueError):
            report.validate_evaluation(value)

    def test_phase_boundaries_preserve_completed_actions_and_cannot_repair_source_loss(self):
        rows = shadow_rows()
        data = analyze_phases(rows, [phase_binding(rows, 0, 1, 'before'), phase_binding(rows, 2, 6, 'after')])
        self.assertEqual(sum(r['counts']['completed_actions'] for r in data['rows']), 2)
        self.assertEqual(sum(r['counts']['unscored_actions'] for r in data['rows']), 1)
        self.assertEqual(next(r for r in data['rows'] if r['phaseID'] == 'before')['status'], 'incomplete')
        rows = shadow_rows(); rows[0]['droppedRecordsBefore'] = '1'
        data = analyze_phases(rows, [phase_binding(rows, 0, 2, 'before'), phase_binding(rows, 3, 6, 'after')])
        self.assertEqual(sum(r['counts']['compared'] for r in data['rows']), 0)
        self.assertTrue(all(p['status'] == 'incomplete' for p in data['phases']))
        rows = shadow_rows()
        for row in rows:
            row['sequence'] = str(int(row['sequence']) + 10)
        data = analyze_phases(rows, [phase_binding(rows, 10, 12, 'before'), phase_binding(rows, 13, 16, 'after')])
        self.assertEqual(data['issues']['leading_sequence_offset'], 10)
        self.assertEqual(sum(r['counts']['compared'] for r in data['rows']), 0)
        self.assertEqual(data['phases'][1]['binding']['firstSequence'], '13')

    def test_actual_legacy_exports_accept_only_their_explicit_v2_scopes(self):
        root = Path(__file__).resolve().parents[2]
        for name, count, versions in [('binding', 6, {'10', '11'}), ('decision', 10, {None, '10', '11'})]:
            path = root / 'reports/capture-continuity-2026-10-22/evidence' / (name + '-export')
            if not path.exists():
                self.skipTest('historical integration export unavailable')
            sidecar = json.loads((FIXTURES / ('director-phase-' + name + '-v2.json')).read_text())
            data = report.summarize_shadow(path, 2, sidecar['shadowBindings'], binding_schema_version=2)
            self.assertTrue(data['exportValidated'])
            self.assertEqual(data['records'], count)
            self.assertEqual(sum(p['acceptedRecords'] for p in data['phases']), count)
            self.assertEqual({p['binding']['parameterVersion'] for p in data['phases']}, versions)
            self.assertEqual(data['issues'].get('incomplete_or_duplicate_action_pairs', 0), 0)
            self.assertEqual(data['issues'].get('inconsistent_action_pairs', 0), 0)
            if name == 'decision':
                self.assertEqual(sum(row['counts']['completed_actions'] for row in data['rows']), 1)
                self.assertEqual(sum(row['counts']['compared'] for row in data['rows']), 1)
                self.assertEqual({p['binding']['level'] for p in data['phases']}, {'off', 'assist', 'auto'})
                self.assertFalse(data['dwell'])

    def test_cli_v2_sidecar_is_explicit_and_reports_its_own_digest(self):
        rows = shadow_rows()
        with tempfile.TemporaryDirectory() as directory:
            src, sidecar, records, out = [Path(directory) / name for name in ('input.json', 'sidecar.json', 'records.jsonl', 'report.json')]
            src.write_text(json.dumps(envelope()))
            sidecar.write_text(json.dumps({'evaluationSchemaVersion': 2, 'shadowBindings': [phase_binding(rows, 0, 6, 'whole')]}))
            records.write_text(''.join(json.dumps(row) + '\n' for row in rows))
            command = [sys.executable, str(Path(report.__file__)), str(src), '--shadow-bundle', str(records),
                       '--shadow-sidecar', str(sidecar), '--match-window-seconds', '2', '--json-output', str(out)]
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(out.read_text())
            self.assertEqual(data['evaluationSchemaVersion'], 2)
            self.assertEqual(len(data['shadowBindingSHA256']), 64)
            expected = hashlib.sha256(records.read_bytes()).hexdigest()
            self.assertEqual(data['shadow']['inputFingerprints']['recordsSHA256'], expected)
            self.assertIn(expected, report.markdown(data))
            self.assertIn(expected, report.parameter_memo(data))
            self.assertFalse(data['qualified'])


class EvaluationTests(unittest.TestCase):
    def test_evidence_inventory_preserves_declared_shadow_classes_and_replay_counts(self):
        for declared_class in ('synthetic', 'recorded', 'live'):
            rows = shadow_rows()
            for row in rows:
                row['evidenceClass'] = declared_class
            # Authored class mutations exercise reporting only, not real collection.
            data = analyze_shadow(rows, [binding(rows)])
            result = report.evaluate(envelope(run_fixture()), shadow_data=data)
            with self.subTest(declared_class=declared_class):
                self.assertEqual(result['evidenceInventory']['replayScenarios'], {'synthetic': 1})
                self.assertEqual(result['evidenceInventory']['shadowRecords'], {declared_class: 7})
                for text in (report.markdown(result), report.parameter_memo(result)):
                    self.assertNotIn('**Synthetic software evidence.', text)
                    self.assertIn(f'| Shadow records | {declared_class} | 7 |', text)
                    self.assertIn('| Replay scenarios | synthetic | 1 |', text)
                self.assertFalse(result['qualified'])

    def test_reports_retain_the_supplied_matching_window(self):
        directory = FIXTURES / 'director-shadow-synthetic-export'
        bindings = [binding(shadow_rows())]
        for window in (0, 0.05, 2.75):
            with self.subTest(window=window):
                data = report.summarize_shadow(directory, window, bindings)
                self.assertEqual(data['matchingWindowSeconds'], window)
                self.assertEqual(sum(r['counts']['compared'] for r in data['rows']), 2 if window == 2.75 else 0)
                result = report.evaluate(envelope(), shadow_data=data)
                for text in (report.markdown(result), report.parameter_memo(result)):
                    self.assertIn(f'Matching window: {window:g} seconds (supplied)', text)
                regressions = report.negative_shadow_regressions(directory, window)
                self.assertTrue(all(r['matchingWindowSeconds'] == window for r in regressions))
        phased = report.summarize_shadow(directory, 1.25,
                                        [phase_binding(shadow_rows(), 0, 6, 'whole')], binding_schema_version=2)
        self.assertEqual(phased['matchingWindowSeconds'], 1.25)

    def test_legacy_python_api_validates_bindings_before_loading_evidence(self):
        rows = shadow_rows()
        cases = []
        original = binding(rows)
        cases.append([original, {**original, 'configurationID': 'conflicting'}])
        cases.append([{**original, 'configurationID': 'PRIVATE INVALID TEXT'}])
        cases.append([{**original, 'route': 'unrecognized'}])
        cases.append([{**original, 'unexpected': 'PRIVATE'}])
        cases.append([{**original, 'judgeKind': 'learned', 'modelVersion': None}])
        for bindings in cases:
            with self.subTest(bindings=bindings), self.assertRaises(ValueError):
                analyze_shadow(rows, bindings)
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    report.summarize_shadow(Path(directory) / 'missing.jsonl', 2, bindings)

    def test_legacy_external_sidecar_retains_exact_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            src, out = Path(directory) / 'input.json', Path(directory) / 'report.json'
            src.write_text(json.dumps(envelope()))
            sidecar = FIXTURES / 'director-evaluation-shadow-sidecar.json'
            command = [sys.executable, str(Path(report.__file__)), str(src),
                       '--shadow-bundle', str(FIXTURES / 'director-shadow-synthetic-export'),
                       '--shadow-sidecar', str(sidecar), '--match-window-seconds', '2', '--json-output', str(out)]
            completed = subprocess.run(command, capture_output=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(out.read_text())
            expected = hashlib.sha256(sidecar.read_bytes()).hexdigest()
            self.assertEqual(result['shadowBindingSHA256'], expected)
            self.assertIn(expected, report.markdown(result))
            self.assertIn(expected, report.parameter_memo(result))

    def test_legacy_report_preserves_bundle_fingerprints(self):
        directory = FIXTURES / 'director-shadow-synthetic-export'
        data = report.summarize_shadow(directory, 2, [binding(shadow_rows())])
        for name, field in [('records.jsonl', 'recordsSHA256'), ('manifest.json', 'manifestSHA256')]:
            expected = hashlib.sha256((directory / name).read_bytes()).hexdigest()
            self.assertEqual(data['inputFingerprints'][field], expected)
            result = report.evaluate(envelope(), shadow_data=data)
            self.assertIn(expected, report.markdown(result))
            self.assertIn(expected, report.parameter_memo(result))

    def test_parameter_distributions_keep_segments_contexts_and_channels_separate(self):
        for dimension in ('segmentType', 'segmentToken', 'parameters', 'channel'):
            rows = with_speed(shadow_rows(), 0.1)
            for row in rows[4:]:
                row['evidence'][0]['subjectSpeed'] = 0.9
                if dimension == 'segmentType':
                    row['context']['segmentType'] = 'panel'
                elif dimension == 'segmentToken':
                    row['context']['segmentToken'] = token('second-segment')
                elif dimension == 'parameters':
                    row['parameters']['parametersVersion'] = '2'
                    row['parameters']['resolvedStyle']['maximumMovement'] = 0.8
                else:
                    row['evidence'][0]['channel'] = 'input-1'
            with self.subTest(dimension=dimension):
                evidence = analyze_shadow(rows, [])['parameterEvidence']
                self.assertEqual(len(evidence), 2)
                self.assertEqual({p['subjectSpeed']['median'] for p in evidence}, {0.1, 0.9})
                self.assertEqual({p['subjectSpeed']['reportedSamples'] for p in evidence}, {3, 4})

    def test_phase_parameter_distributions_keep_two_channels_separate(self):
        rows = with_speed(shadow_rows(), 0.1)
        for row in rows:
            row['evidence'].append({**row['evidence'][0], 'channel': 'input-1', 'subjectSpeed': 0.9})
        data = analyze_phases(rows, [phase_binding(rows, 0, 6, 'whole')])
        evidence = data['parameterEvidence']
        self.assertEqual(len(evidence), 2)
        self.assertEqual({p['scope']['channel']: p['subjectSpeed']['median'] for p in evidence},
                         {'input-1': 0.9, 'input-2': 0.1})
        self.assertTrue(all(p['subjectSpeed']['reportedSamples'] == 7 for p in evidence))

    def test_channel_partition_preserves_invalid_and_unavailable_samples(self):
        rows = with_speed(shadow_rows(), 0.1)
        for row in rows:
            row['evidence'].append({**row['evidence'][0], 'channel': 'input-1'})
            row['evidence'][1].pop('subjectSpeed')
        rows[0]['invalidFields'] = ['evidence[1].subjectSpeed']
        for phased in (False, True):
            data = (analyze_phases(rows, [phase_binding(rows, 0, 6, 'whole')]) if phased else
                    analyze_shadow(rows, [binding(rows)]))
            with self.subTest(phased=phased):
                samples = {p['scope']['channel']: p['subjectSpeed'] for p in data['parameterEvidence']}
                self.assertEqual(samples['input-2']['reportedSamples'], 7)
                self.assertEqual(samples['input-1']['reportedSamples'], 0)
                self.assertEqual(samples['input-1']['invalidSamples'], 1)
                self.assertEqual(samples['input-1']['unavailableSamples'], 6)
                self.assertIsNone(samples['input-1']['median'])
                memo = report.parameter_memo(report.evaluate(envelope(), shadow_data=data))
                self.assertIn('"channel": "input-1"', memo)
                self.assertIn('"segmentType": "presenter"', memo)

    def test_legacy_session_status_retains_capture_loss_without_comparison_rows(self):
        for fault in ('drop', 'gap', 'orphan', 'unknownShot'):
            rows = shadow_rows()
            if fault == 'drop':
                rows[3]['droppedRecordsBefore'] = '1'
            elif fault == 'gap':
                for row in rows:
                    row['sequence'] = str(int(row['sequence']) + 10)
            elif fault == 'orphan':
                rows = rows[1:2]
                rows[0]['sequence'] = '0'
            else:
                rows[2]['context'].pop('programShot', None)
            with self.subTest(fault=fault):
                data = analyze_shadow(rows, [binding(rows)])
                self.assertEqual(data['sessions'][0]['status'], 'incomplete')
                text = report.markdown(report.evaluate(envelope(), shadow_data=data))
                self.assertIn('scope incomplete.', text)
                if fault == 'orphan':
                    self.assertEqual(data['rows'], [])

    def test_legacy_session_loss_does_not_taint_another_session(self):
        affected, complete = shadow_rows(), shadow_rows()
        affected[3]['droppedRecordsBefore'] = '1'
        for row in complete:
            row['sessionID'] = token('complete-session')
            row['recordID'] = token('complete-' + row['sequence'])
        data = analyze_shadow(affected + complete, [binding(affected), binding(complete)])
        self.assertEqual({s['sessionID']: s['status'] for s in data['sessions']},
                         {affected[0]['sessionID']: 'incomplete', complete[0]['sessionID']: 'observed'})

    def test_actual_decision_rehearsal_preserves_missing_per_level_binding(self):
        requested = os.environ.get('ALFIE_DIRECTOR_DECISION_EXPORT')
        if not requested:
            return
        data = report.summarize_shadow(Path(requested), 2, [])
        self.assertTrue(data['exportValidated'])
        self.assertEqual(data['records'], 10)
        self.assertEqual({g['reason'] for g in data['gaps']},
                         {'missingShadowBinding', 'mixedLevelModeOrModel'})
        self.assertTrue(data['rows'])
        self.assertTrue(all(r['status'] == 'incomplete' and r['counts']['compared'] is None
                            and r['counts']['exact'] is None for r in data['rows']))
        self.assertEqual(sum(r['counts']['completed_actions'] for r in data['rows']), 1)
        # C-05 may compare the tightly scoped manual Take. D-06 does not pool
        # this off/assist/auto integration rehearsal into a per-level trial.
        self.assertEqual(data['sessions'][0]['judgeModels'], [['rules', None]])
        self.assertEqual(sum(p['subjectSpeed']['reportedSamples']
                             for p in data['parameterEvidence']), 2)

    def test_wrong_proposal_is_visible_and_never_becomes_wrong_committed_rate(self):
        run = run_fixture(); run['metrics']['wrongSubjectProposals'] = 1
        result = report.evaluate(envelope(run))
        row = result['runs'][0]
        self.assertEqual(row['warnings'], ['wrongSubjectProposalObserved'])
        self.assertIsNone(row['wrongCommittedPreparationRate'])
        self.assertIsNone(row['usefulPreparationCoverage'])
        self.assertFalse(result['qualified'])
        self.assertEqual([r['status'] for r in result['levels']], ['incomplete', 'notRun', 'notRun'])
        text = report.markdown(result)
        self.assertIn('1/1', text)
        self.assertIn('zero Director cuts is structural', text)
        self.assertNotIn('| pass |', text)

    def test_empty_is_unavailable_and_all_levels_not_run(self):
        result = report.evaluate(envelope())
        self.assertTrue(all(r['status'] == 'notRun' for r in result['levels']))
        self.assertEqual(result['qualificationStatus'], 'incomplete')
        self.assertIn('all measurements unavailable', report.markdown(result))

    def test_strict_envelope_and_counts_reject_private_or_fabricated_fields(self):
        changes = [lambda e: e.update(qualified=True), lambda e: e.update(evaluationSchemaVersion=True),
                   lambda e: e['runs'][0].update(name='PRIVATE'),
                   lambda e: e['runs'][0]['metrics'].update(preparationsCommitted=True),
                   lambda e: e['runs'][0]['metrics'].update(wrongSubjectAttempts=2),
                   lambda e: e['runs'][0]['parameters']['replay'].update(maximumEvidenceAge=float('nan')),
                   lambda e: e['runs'][0]['metrics'].update(cutsPerMinute=1),
                   lambda e: e['runs'][0]['metrics'].update(directorCuts=1)]
        for change in changes:
            value = envelope(run_fixture()); change(value)
            with self.subTest(change=change), self.assertRaises(ValueError):
                report.validate_evaluation(value)

    def test_replay_cannot_be_relabelled_as_live_auto_model_or_output_route(self):
        for field, value in [('evidenceClass', 'live'), ('evidenceClass', 'recorded'), ('level', 'auto'),
                             ('executionMode', 'shadow'), ('route', 'direct'), ('route', 'virtualCamera'),
                             ('judgeKind', 'learned')]:
            run = run_fixture(); run[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                report.validate_evaluation(envelope(run))

    def test_missing_opportunities_and_ui_latency_stay_unknown(self):
        for change in [lambda r: r['opportunities'].update(eligible=0),
                       lambda r: r['metrics'].update(manualOverridesHonoured=1, manualOverrideLatencies=[0])]:
            run = run_fixture(); change(run)
            with self.assertRaises(ValueError):
                report.validate_evaluation(envelope(run))
        run = run_fixture(); run['metrics'].update(manualOverridesHonoured=1, manualOverrideLatencies=[None])
        self.assertIsNone(report.evaluate(envelope(run))['runs'][0]['metrics']['manualOverrideLatencies'][0])

    def test_duplicate_session_and_inconsistent_configuration_refuse(self):
        first, second = run_fixture('one'), run_fixture('two')
        second['sessionID'] = first['sessionID']
        with self.assertRaises(ValueError):
            report.evaluate(envelope(first, second))
        second = run_fixture('two'); second['parameters']['replay']['maximumEvidenceAge'] = 6
        with self.assertRaises(ValueError):
            report.evaluate(envelope(first, second))
        second['configurationID'] = 'replay-study-2'
        result = report.evaluate(envelope(first, second))
        self.assertEqual(len(result['runs']), 2)
        self.assertNotEqual(result['runs'][0]['partition'], result['runs'][1]['partition'])

    def test_critical_commit_is_flagged_separately_from_rejected_attempt(self):
        run = run_fixture(); run['metrics']['staleEffectsCommitted'] = 1
        self.assertEqual(report.evaluate(envelope(run))['runs'][0]['softwareStatus'], 'criticalObservation')
        run['metrics']['staleEffectsCommitted'] = 0
        run['metrics']['staleProposalsRejected'] = {'expired': 1}
        self.assertEqual(report.evaluate(envelope(run))['runs'][0]['softwareStatus'], 'observed')

    def test_commits_and_acknowledgements_cannot_exceed_their_observed_denominators(self):
        for field, value in [('preparationsCommitted', 2), ('acknowledgementsAccepted', 2)]:
            run = run_fixture(); run['metrics'][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                report.validate_evaluation(envelope(run))
        # Equal observed counts remain valid; a rejected attempt needs no commit/ack.
        report.validate_evaluation(envelope(run_fixture()))
        run = run_fixture(); run['metrics'].update(preparationsCommitted=0, acknowledgementsAccepted=0, rejectedAttempts=1)
        report.validate_evaluation(envelope(run))

    def test_zero_wide_cadence_is_invalid_but_positive_study_values_remain_valid(self):
        run = run_fixture(); run['parameters']['shotPolicy']['wideCadence'] = 0
        with self.assertRaises(ValueError):
            report.validate_evaluation(envelope(run))
        run['parameters']['shotPolicy']['wideCadence'] = 0.001
        report.validate_evaluation(envelope(run))

    def test_shadow_binding_cannot_claim_another_class_level_or_parameter(self):
        rows = shadow_rows()
        for field, value in [('evidenceClass', 'live'), ('level', 'auto'), ('parameterVersion', '2')]:
            sidecar = binding(rows); sidecar[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                analyze_shadow(rows, [sidecar])
        sidecar = binding(rows, judge='learned', model='invented-model')
        with self.assertRaises(ValueError):
            analyze_shadow(rows, [sidecar])

    def test_shadow_session_model_and_configuration_partitions_are_retained(self):
        first, second = with_model(shadow_rows(), 'model-A'), with_model(shadow_rows(), 'model-B')
        for row in second:
            row['sessionID'] = token('another-session')
            row['recordID'] = token('another-record-' + row['recordID'])
        data = analyze_shadow(first + second, [binding(first, 'config-A', 'learned', 'model-A'), binding(second, 'config-B', 'learned', 'model-B')])
        self.assertEqual(len(data['rows']), 4)
        self.assertEqual({row['binding']['modelVersion'] for row in data['rows']}, {'model-A', 'model-B'})
        self.assertEqual({row['binding']['configurationID'] for row in data['rows']}, {'config-A', 'config-B'})
        self.assertTrue(all(row['counts']['compared'] == 1 for row in data['rows']))
        for configuration in ('config-A', 'config-B'):
            self.assertEqual(sum(row['counts']['compared'] for row in data['rows']
                if row['binding']['configurationID'] == configuration), 2)

    def test_mixed_level_mode_or_model_never_silently_matches(self):
        for field, value in [('level', 'assist'), ('executionMode', 'observing'), ('modelVersion', 'model-B')]:
            rows = with_model(shadow_rows(), 'model-A')
            if field == 'level': rows[1]['context']['level'] = value
            elif field == 'executionMode': rows[1][field] = value
            else: rows[1]['judgements'][0][field] = value
            data = analyze_shadow(rows, [])
            self.assertTrue(all(row['counts']['compared'] is None for row in data['rows']))
            self.assertFalse(data['dwell'])
            self.assertIn('mixedLevelModeOrModel', [gap['reason'] for gap in data['gaps']])

    def test_loss_and_missing_binding_are_explicitly_incomplete(self):
        rows = shadow_rows(); rows[3]['droppedRecordsBefore'] = '1'
        data = analyze_shadow(rows, [binding(rows)])
        self.assertEqual(data['rows'][0]['counts']['compared'], 0)
        self.assertEqual(data['rows'][0]['status'], 'incomplete')
        data = analyze_shadow(shadow_rows(), [])
        self.assertIn('missingShadowBinding', [gap['reason'] for gap in data['gaps']])
        self.assertEqual(data['rows'][0]['status'], 'incomplete')

    def test_regression_matrix_reports_observations_not_test_counts(self):
        rows = report.negative_shadow_regressions(FIXTURES / 'director-shadow-synthetic-export', 2)
        cases = {r['case']: r for r in rows}
        self.assertEqual((cases['baseline']['counts']['exact'], cases['baseline']['counts']['compared']), (2, 2))
        self.assertEqual(cases['wrongPredictedPreset']['counts']['exact'], 1)
        self.assertEqual(cases['reportedDrop']['counts']['unscored_actions'], 2)
        self.assertEqual(cases['sequenceGap']['counts']['compared'], 0)
        self.assertEqual(cases['unknownPostTakeShot']['counts']['unscored_actions'], 1)
        self.assertEqual(cases['unknownPostTakeShot']['status'], 'incomplete')
        self.assertEqual(cases['empty']['status'], 'incomplete')

    def test_parameter_memo_uses_actual_snapshots_and_never_invents_notice(self):
        rows = shadow_rows()
        data = analyze_shadow(rows, [binding(rows)])
        memo = report.parameter_memo(report.evaluate(envelope(run_fixture()), shadow_data=data))
        self.assertIn('AWAITING OWNER', memo)
        self.assertIn('"onAirMoveRate": 0.1', memo)
        self.assertIn('"reportedSamples": 0', memo)
        self.assertIn('Notice-length observations are unavailable', memo)
        self.assertIn('No numeric recommendation', memo)

    def test_speed_distributions_and_memo_partition_evidence_level_mode_and_model(self):
        for field in ('evidenceClass', 'level', 'executionMode', 'modelVersion', 'unobservedModel'):
            with self.subTest(field=field):
                rows = with_speed(with_model(shadow_rows(), 'model-A'), 0.1)
                for row in rows[4:]:
                    row['evidence'][0]['subjectSpeed'] = 0.9
                    if field == 'evidenceClass': row[field] = 'recorded'
                    elif field == 'level': row['context'][field] = 'assist'
                    elif field == 'executionMode': row[field] = 'observing'
                    elif field == 'modelVersion': row['judgements'][0][field] = 'model-B'
                    else: row['judgements'] = []
                data = analyze_shadow(rows, [])
                evidence = data['parameterEvidence']
                self.assertEqual(len(evidence), 2)
                self.assertEqual({item['subjectSpeed']['median'] for item in evidence}, {0.1, 0.9})
                self.assertEqual({item['subjectSpeed']['reportedSamples'] for item in evidence}, {3, 4})
                self.assertTrue(all(item['subjectSpeed']['minimum'] == item['subjectSpeed']['maximum'] for item in evidence))
                scopes = {json.dumps(item['scope'], sort_keys=True) for item in evidence}
                self.assertEqual(len(scopes), 2)
                memo = report.parameter_memo(report.evaluate(envelope(), shadow_data=data))
                self.assertEqual(memo.count('Actual evidence/level/mode/judge-model scope'), 2)
                self.assertIn('"median": 0.1', memo)
                self.assertIn('"median": 0.9', memo)
                for item in evidence:
                    self.assertIn(json.dumps(item['scope'], sort_keys=True, indent=2), memo)

    def test_multiple_models_on_one_record_keep_sample_counts_without_a_pooled_distribution(self):
        rows = with_speed(with_model(shadow_rows(), 'model-A'), 0.3)
        for row in rows:
            second = copy.deepcopy(row['judgements'][0]); second['modelVersion'] = 'model-B'
            row['judgements'].append(second)
        data = analyze_shadow(rows, [])
        self.assertEqual(len(data['parameterEvidence']), 1)
        evidence = data['parameterEvidence'][0]
        self.assertEqual(evidence['scope']['judgeModels'], [['learned', 'model-A'], ['learned', 'model-B']])
        self.assertEqual(evidence['subjectSpeed']['reportedSamples'], 7)
        self.assertEqual(evidence['subjectSpeed']['distributionStatus'], 'unavailableMixedModelScope')
        self.assertTrue(all(evidence['subjectSpeed'][field] is None for field in ('minimum', 'median', 'maximum')))
        memo = report.parameter_memo(report.evaluate(envelope(), shadow_data=data))
        self.assertIn('unavailableMixedModelScope', memo)
        self.assertIn('"median": null', memo)

    def test_cli_fixed_errors_strict_json_and_nonoverwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            src, out = Path(directory) / 'input.json', Path(directory) / 'report.md'
            src.write_text(json.dumps(envelope(run_fixture())))
            command = [sys.executable, str(Path(report.__file__)), str(src), '--output', str(out)]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            before = out.read_bytes()
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)
            self.assertEqual(out.read_bytes(), before)
            src.write_text('{"evaluationSchemaVersion":1,"evaluationSchemaVersion":1,"PRIVATE":true}')
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn(b'PRIVATE', result.stderr)
            self.assertEqual(out.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
