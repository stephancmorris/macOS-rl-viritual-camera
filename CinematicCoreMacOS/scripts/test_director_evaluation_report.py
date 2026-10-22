#!/usr/bin/env python3
"""Synthetic evaluation metadata and report regressions; no app or real evidence."""
import copy
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
            'configurationID': configuration, 'parameterVersion': first['parameters']['parametersVersion'],
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


class EvaluationTests(unittest.TestCase):
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
