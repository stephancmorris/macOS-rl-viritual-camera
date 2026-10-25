#!/usr/bin/env python3
"""C-05 synthetic fixtures; no person/media or live qualifications."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
import director_shadow_report as report


def token(name):
    return str(uuid.uuid5(uuid.NAMESPACE_OID, name)).upper()


def record(sequence, time, event, *, session='synthetic-session', program='input-1', preview='input-2', preset='wide', evidence='synthetic', segment='presenter', parameter='1'):
    return {
        'schemaVersion': 1, 'recordID': token(f'{session}-{sequence}'), 'sessionID': token(session),
        'sequence': str(sequence), 'recordedAtUTC': '2026-10-18T00:00:00.000Z', 'eventTime': time,
        'evidenceClass': evidence, 'executionMode': 'shadow',
        'context': {'inputs': ['input-1', 'input-2'], 'program': program, 'preview': preview,
                    'programShot': {'format': 'stage', 'preset': preset}, 'level': 'suggest',
                    'paused': False, 'editLive': False, 'running': True, 'healthy': True,
                    'evidenceAvailable': True, 'mayPropose': True, 'mayPrepare': False, 'mayTake': False,
                    'authorityEpoch': '1', 'routeGeneration': '1', 'policyRevision': '1',
                    'nominationRevision': '1', 'evidenceRevision': '1', 'segmentType': segment},
        'parameters': {'status': 'available', 'parametersVersion': parameter, 'preferencesVersion': 2,
                       'resolvedStyle': {'minimumShotDuration': 8, 'preferredShotDuration': 20,
                                         'softMaximumShotDuration': 40, 'wideCadence': 90,
                                         'repetitionWindow': 10, 'maximumMovement': 0.2,
                                         'settleTime': 1, 'onAirMoveRate': 0.1, 'cutOnMotionAllowed': False}},
        'evidence': [], 'judgements': [], 'event': event, 'invalidFields': [], 'droppedRecordsBefore': '0',
    }


def prediction(kind='wouldCut', target='input-2', preset='waistUp', name='decision'):
    return {'kind': kind, 'decisionID': token(name), 'target': target,
            'shot': {'format': 'stage', 'preset': preset},
            'reason': {'domain': 'selection', 'code': 'subjectEvidence'}}


def action(phase, name='take-1', outcome='completed', kind='take', target=None, preset='waistUp', after='input-2', preview='input-1'):
    e = {'kind': 'operatorAction', 'actionID': token(name), 'action': kind, 'phase': phase,
         'targetScope': 'channel' if target else 'session'}
    if target:
        e['target'] = target
    if kind == 'selectPreset':
        e['shot'] = {'format': 'stage', 'preset': preset}
    if phase == 'result':
        e['outcome'] = outcome
        if kind == 'take' and outcome == 'completed':
            e.update(programAfter=after, previewAfter=preview)
    return e


def fixture():
    rows = [
        record(0, 9, prediction()),
        record(1, 10, action('attempt')),
        record(2, 10.1, action('result'), program='input-2', preview='input-1', preset='waistUp'),
        record(3, 19, prediction(target='input-1', preset='wide', name='decision-2'), program='input-2', preview='input-1', preset='waistUp'),
        record(4, 20, action('attempt', name='take-2'), program='input-2', preview='input-1', preset='waistUp'),
        record(5, 20.1, action('result', name='take-2', after='input-1', preview='input-2')),
        record(6, 21, {'kind': 'abstention', 'decisionID': token('abstention'), 'stage': 'prepare', 'reasons': [{'domain': 'policy', 'code': 'minimumDuration'}]}),
    ]
    for index, row in enumerate(rows):
        row['context']['routeGeneration'] = str(1 + (index >= 2) + (index >= 5))
    return rows


def run(rows, window=2):
    records, issues = report.load_records(io.BytesIO(('\n'.join(json.dumps(r) for r in rows) + ('\n' if rows else '')).encode()))
    return report.analyze(records, window, issues)


class PredictionSequencePrecedenceTests(unittest.TestCase):
    def test_displayed_matching_window_round_trips_at_a_comparison_boundary(self):
        rows = fixture()
        rows[0]['eventTime'] = 8.99999997
        window = 1.00000004
        data = run(rows, window)
        self.assertEqual(sum(c['compared'] for _, c, _ in data['groups']), 2)
        displayed = report.markdown(data, window).split('Matching window: ', 1)[1].split(' seconds', 1)[0]
        self.assertEqual(float(displayed), window)
        repeated = run(rows, float(displayed))
        self.assertEqual(sum(c['compared'] for _, c, _ in repeated['groups']), 2)

    def test_input_fingerprints_identify_exact_bytes_and_suppress_partial_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'records.jsonl'
            raw = b''.join((json.dumps(row) + '\n').encode() for row in fixture())
            for content in (raw, raw.replace(b': ', b':'), raw + b'PRIVATE INVALID ROW\n', b''):
                path.write_bytes(content)
                records, issues, source = report.load_input(path)
                self.assertEqual(source['recordsSHA256'], hashlib.sha256(content).hexdigest())
                text = report.markdown(report.analyze(records, 2, issues, source), 2)
                self.assertIn(source['recordsSHA256'], text)
                self.assertNotIn('PRIVATE', text)
            path.write_bytes(raw)
            for limits in ({'maximum_records': 1}, {'maximum_line_bytes': 5}, {'maximum_input_bytes': 5}):
                with self.subTest(limits=limits):
                    _, issues, source = report.load_input(path, **limits)
                    self.assertTrue(issues['input_limit'])
                    self.assertIsNone(source['recordsSHA256'])

    def test_legacy_unscored_take_is_incomplete_in_markdown(self):
        rows = fixture()
        rows[2]['context'].pop('programShot')
        data = run(rows)
        self.assertFalse(data['captureBlockedSessions'])
        self.assertTrue(any(counts['unscored_actions'] for _, counts, _ in data['groups']))
        self.assertIn('| incomplete |', report.markdown(data, 2))

    def assert_matching_in_v1_and_v2(self, rows, expected):
        records, issues = report.load_records(io.BytesIO(('\n'.join(json.dumps(r) for r in rows) + '\n').encode()))
        self.assertEqual(len(records), len(rows))
        self.assertFalse(issues)
        for phased in (False, True):
            assignments = {r['recordID']: 'whole' for r in records} if phased else None
            data = report.analyze(records, 2, issues, phase_assignments=assignments)
            counts = sum((s for _, s, _ in data['groups']), report.Counter())
            with self.subTest(mode='v2' if phased else 'v1'):
                self.assertFalse(any(blocked for _, _, blocked in data['groups']))
                for metric, value in expected.items():
                    self.assertEqual(counts[metric], value, metric)

    def test_equal_clock_future_prediction_cannot_receive_take_credit(self):
        rows = [record(0, 10, action('attempt')),
                record(1, 10, prediction()),
                record(2, 10.1, action('result'), program='input-2', preview='input-1', preset='waistUp')]
        rows[-1]['context']['routeGeneration'] = '2'
        self.assert_matching_in_v1_and_v2(rows, {'predictions': 1, 'completed_actions': 1,
            'compared': 0, 'exact': 0, 'unmatched_predictions': 1, 'unmatched_actions': 1,
            'unscored_actions': 0})

    def test_equal_clock_future_prediction_preserves_latest_earlier_candidate(self):
        rows = [record(0, 10, prediction('wouldPrepare', preset='fullBody', name='older')),
                record(1, 10, prediction('wouldPrepare', name='latest-before')),
                record(2, 10, action('attempt', kind='selectPreset', target='input-2')),
                record(3, 10, prediction('wouldPrepare', preset='fullBody', name='after')),
                record(4, 10.1, action('result', kind='selectPreset', target='input-2'))]
        self.assert_matching_in_v1_and_v2(rows, {'predictions': 3, 'completed_actions': 1,
            'compared': 1, 'exact': 1, 'unmatched_predictions': 2, 'unmatched_actions': 0,
            'unscored_actions': 0})

    def test_equal_clock_future_prediction_remains_available_for_later_attempt(self):
        rows = [record(0, 10, action('attempt', name='first', kind='selectPreset', target='input-2')),
                record(1, 10, prediction('wouldPrepare')),
                record(2, 10.1, action('result', name='first', kind='selectPreset', target='input-2')),
                record(3, 10.2, action('attempt', name='second', kind='selectPreset', target='input-2')),
                record(4, 10.3, action('result', name='second', kind='selectPreset', target='input-2'))]
        self.assert_matching_in_v1_and_v2(rows, {'predictions': 1, 'completed_actions': 2,
            'compared': 1, 'exact': 1, 'unmatched_predictions': 0, 'unmatched_actions': 1,
            'unscored_actions': 0})


class ShowStopPairTests(unittest.TestCase):
    def rows(self, *, program='input-2', single=False, route=1):
        preview = None if single else ('input-2' if program == 'input-1' else 'input-1')
        rows = [record(0, 10, action('attempt', name='show-stop', kind='stopSession'), program=program, preview=preview),
                record(1, 10.1, action('result', name='show-stop', kind='stopSession', outcome='accepted'),
                       program='input-1', preview=None if single else 'input-2')]
        rows[0]['context'].update(level='auto', editLive=True)
        rows[0]['executionMode'] = 'observing'
        rows[0]['context']['routeGeneration'] = str(route)
        rows[1]['context'].update(level='off', running=False, editLive=False, paused=False,
                                  mayPropose=False, mayPrepare=False, mayTake=False,
                                  routeGeneration=str(route + int(program != 'input-1')))
        rows[1]['event']['programAfter'] = 'input-1'
        if not single:
            rows[1]['event']['previewAfter'] = 'input-2'
        if single:
            for row in rows:
                row['context']['inputs'] = ['input-1']
        return rows

    def test_explicit_show_stop_closes_only_its_exact_logical_reset(self):
        for program, single in [('input-1', True), ('input-1', False), ('input-2', False)]:
            rows = self.rows(program=program, single=single)
            data = run(rows)
            with self.subTest(program=program, single=single):
                self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
                self.assertEqual(data['issues']['incomplete_or_duplicate_action_pairs'], 0)
                self.assertEqual(data['issues']['operator_accepted'], 1)
                self.assertEqual(data['groups'], [])
                self.assertFalse(data['dwell'])

    def test_explicit_show_stop_rejects_unrelated_scope_or_terminal_changes(self):
        mutations = [lambda r: r[1]['event'].update(programAfter='input-2'),
                     lambda r: r[1]['event'].update(previewAfter='input-1'),
                     lambda r: r[1]['context'].update(program='input-2', preview='input-1'),
                     lambda r: r[1]['context'].update(routeGeneration='1'),
                     lambda r: r[1]['context'].update(routeGeneration='3'),
                     lambda r: r[1].update(evidenceClass='recorded'),
                     lambda r: r[1]['context'].update(inputs=['input-1', 'input-2', 'input-3']),
                     lambda r: r[1]['parameters'].update(parametersVersion='2'),
                     lambda r: r[1]['context'].update(policyRevision='2'),
                     lambda r: r[1]['context'].update(nominationRevision='2'),
                     lambda r: r[1]['event'].update(outcome='completed'),
                     lambda r: r[1]['event'].update(outcome='refused'),
                     lambda r: r[1]['context'].update(editLive=True),
                     lambda r: r[1]['context'].update(running=True),
                     lambda r: r[1]['context'].update(level='auto'),
                     lambda r: r[1].update(executionMode='observing'),
                     lambda r: r[1]['context'].update(paused=True),
                     lambda r: r[1]['context'].update(pinnedInput='input-1'),
                     lambda r: r[1]['context'].update(mayPrepare=True),
                     lambda r: r[1]['judgements'].append({'judgeKind': 'learned', 'modelVersion': 'other',
                         'evidenceRevision': '1', 'outcome': {'kind': 'abstain',
                         'reason': {'domain': 'judge', 'code': 'lowConfidence'}}, 'gateResult': 'notEvaluated'})]
        for mutate in mutations:
            rows = self.rows(); mutate(rows)
            with self.subTest(mutate=mutate):
                self.assertFalse(report.action_pair_scope_matches(*rows))
                issues = run(rows)['issues']
                self.assertGreater(issues['inconsistent_action_pairs'] + issues['rejected_records'], 0)
        rows = self.rows()
        rows[0]['context']['routeGeneration'] = str(2**64 - 1)
        rows[1]['context']['routeGeneration'] = '0'
        self.assertFalse(report.action_pair_scope_matches(*rows))
        self.assertGreater(run(rows)['issues']['inconsistent_action_pairs'], 0)

    def test_supported_long_alias_does_not_require_integer_conversion(self):
        rows = self.rows()
        alias = 'input-' + '9' * 5000
        for row in rows:
            context = row['context']
            context['inputs'] = ['input-1', alias]
            for key in ('program', 'preview'):
                if context.get(key) == 'input-2':
                    context[key] = alias
        rows[1]['event']['previewAfter'] = alias
        data = run(rows)
        self.assertEqual(data['issues']['rejected_records'], 0)
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual(data['issues']['operator_accepted'], 1)

    def test_legacy_camera_stop_keeps_its_exact_scope_rule(self):
        rows = [record(0, 10, action('attempt', kind='stopSession')),
                record(1, 10.1, action('result', kind='stopSession', outcome='accepted'))]
        self.assertEqual(run(rows)['issues']['operator_accepted'], 1)
        changed = self.rows()
        changed[1]['event'].pop('programAfter'); changed[1]['event'].pop('previewAfter')
        self.assertGreater(run(changed)['issues']['inconsistent_action_pairs'], 0)

    def test_show_stop_does_not_block_prior_valid_matching_or_dwell(self):
        rows = fixture()
        stop = self.rows(program='input-1', route=3)
        for index, row in enumerate(stop, start=7):
            row['sequence'] = str(index)
            row['recordID'] = token('stop-after-' + str(index))
            row['eventTime'] = 22 + (index - 7) * 0.1
        data = run(rows + stop)
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 2)
        self.assertEqual(sum(s['exact'] for _, s, _ in data['groups']), 2)
        values = [value for group in data['dwell'].values() for value in group]
        self.assertEqual(len(values), 1)
        self.assertAlmostEqual(values[0], 10)

    def test_actual_swift_show_stop_bundle_when_explicitly_supplied(self):
        requested = os.environ.get('ALFIE_DIRECTOR_SHOW_STOP_EXPORT')
        if not requested:
            return
        records, issues, source = report.load_input(Path(requested))
        data = report.analyze(records, 2, issues, source,
            phase_assignments={r['recordID']: 'actual-stop' for r in records})
        self.assertFalse(report.blocking_input(data['issues']))
        self.assertIsNotNone(source['manifest'])
        self.assertEqual(len(records), 2)
        self.assertEqual({r['evidenceClass'] for r in records}, {'live'})
        attempt, result = records
        self.assertEqual((attempt['context']['program'], result['context']['program']), ('input-2', 'input-1'))
        self.assertEqual(int(result['context']['routeGeneration']), int(attempt['context']['routeGeneration']) + 1)
        self.assertEqual(result['event']['outcome'], 'accepted')
        self.assertEqual(data['issues']['operator_accepted'], 1)
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual(data['issues']['incomplete_or_duplicate_action_pairs'], 0)
        self.assertEqual(data['blockedSessions'], [])
        self.assertEqual(data['groups'], [])
        self.assertFalse(data['dwell'])


class ShadowReportTests(unittest.TestCase):
    def test_completed_take_requires_exact_route_increment_and_preserves_attempt_partition(self):
        data = run(fixture())
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual({key[7] for key, _, _ in data['groups']}, {'1', '2'})
        for route in ('0', '1', '3', str(2**64 - 1)):
            rows = fixture()[:3]; rows[2]['context']['routeGeneration'] = route
            data = run(rows)
            self.assertEqual(data['issues']['inconsistent_action_pairs'], 1)
            self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)

    def test_take_pair_rejects_source_parameter_model_and_intervening_control_races(self):
        mutations = [lambda r: r.update(evidenceClass='recorded'),
                     lambda r: r['context'].update(nominationRevision='2'),
                     lambda r: r['context'].update(policyRevision='2'),
                     lambda r: r['parameters'].update(parametersVersion='2'),
                     lambda r: r['parameters'].update(judgeMaximumAge=1),
                     lambda r: r['event'].update(previewAfter='input-2')]
        for mutate in mutations:
            rows = fixture()[:3]; mutate(rows[2]); data = run(rows)
            self.assertGreater(data['issues']['inconsistent_action_pairs'] + data['issues']['rejected_records'], 0)
            self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)
        a, b = fixture()[1:3]
        a['judgements'] = [{'judgeKind': 'learned', 'modelVersion': 'before'}]
        b['judgements'] = [{'judgeKind': 'learned', 'modelVersion': 'after'}]
        self.assertFalse(report.action_pair_scope_matches(a, b))
        rows = fixture()[:3]
        rows[2]['sequence'] = '4'
        rows[2]['recordID'] = token('outer-result-after-control')
        nested = [record(2, 10.01, action('attempt', name='takeover', kind='takeOver')),
                  record(3, 10.02, action('result', name='takeover', kind='takeOver', outcome='accepted'))]
        data = run(rows[:2] + nested + rows[2:])
        self.assertGreater(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)

    def test_only_accepted_advance_can_change_one_policy_and_segment_binding(self):
        rows = [record(0, 10, action('attempt', name='advance', kind='advanceSegment')),
                record(1, 10, action('result', name='advance', kind='advanceSegment', outcome='accepted'))]
        rows[0]['context']['segmentToken'] = token('first-segment')
        rows[1]['context'].update(segmentType='panel', segmentToken=token('next-segment'), policyRevision='2')
        rows[1]['parameters']['parametersVersion'] = '2'
        rows[1]['parameters']['resolvedStyle']['minimumShotDuration'] = 9
        self.assertEqual(run(rows)['issues']['inconsistent_action_pairs'], 0)
        for change in ('refused', 'doublePolicy', 'sameSegment', 'judge', 'preferences', 'route', 'nomination'):
            changed = copy.deepcopy(rows)
            if change == 'refused': changed[1]['event']['outcome'] = 'refused'
            elif change == 'doublePolicy': changed[1]['context']['policyRevision'] = '3'
            elif change == 'sameSegment': changed[1]['context']['segmentToken'] = changed[0]['context']['segmentToken']
            elif change == 'judge': changed[1]['parameters']['judgeMaximumAge'] = 1
            elif change == 'preferences': changed[1]['parameters']['preferencesVersion'] = 3
            elif change == 'route': changed[1]['context']['routeGeneration'] = '2'
            else: changed[1]['context']['nominationRevision'] = '2'
            issues = run(changed)['issues']
            self.assertGreater(issues['inconsistent_action_pairs'] + issues['rejected_records'], 0)

    def explicit_segment_pair(self, *, changed=True, before='10', after='11'):
        rows = [record(0, 10, action('attempt', name='explicit-advance', kind='advanceSegment')),
                record(1, 10, action('result', name='explicit-advance', kind='advanceSegment', outcome='accepted'))]
        rows[0]['context']['segmentToken'] = token('explicit-first')
        rows[1]['context'].update(segmentType='panel', segmentToken=token('explicit-next'), policyRevision='2')
        for row, version in zip(rows, (before, after)):
            row['parameters'].update(parametersVersion=version,
                readiness={'minimumSettledTime': 0, 'minimumCutSettledTime': 0,
                           'maximumMotion': 0.2, 'maximumCutMotion': 0.1, 'cutOnMotionAllowed': False},
                adapter={'stillSpeed': 0.2, 'maximumObservationAge': 2, 'debounce': 0}, judgeMaximumAge=1)
        if changed:
            rows[1]['parameters']['resolvedStyle']['minimumShotDuration'] = 9
        return rows

    def test_complete_segment_capture_uses_explicit_versions_independent_of_policy(self):
        for rows in (self.explicit_segment_pair(),
                     self.explicit_segment_pair(changed=False, after='10'),
                     self.explicit_segment_pair(changed=False)):
            data = run(rows)
            self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
            self.assertEqual(data['issues']['inconsistent_parameters'], 0)

    def test_complete_segment_capture_rejects_rollback_reuse_or_unrelated_setting_changes(self):
        cases = [self.explicit_segment_pair(after='10'), self.explicit_segment_pair(after='9')]
        for group, key, value in [('readiness', 'maximumMotion', 0.3),
                                  ('adapter', 'debounce', 0.1)]:
            rows = self.explicit_segment_pair(); rows[1]['parameters'][group][key] = value; cases.append(rows)
        rows = self.explicit_segment_pair(); rows[1]['parameters']['judgeMaximumAge'] = 2; cases.append(rows)
        rows = self.explicit_segment_pair(); rows[1]['context']['policyRevision'] = '3'; cases.append(rows)
        rows = self.explicit_segment_pair(); rows[1]['context']['routeGeneration'] = '2'; cases.append(rows)
        for rows in cases:
            self.assertGreater(run(rows)['issues']['inconsistent_action_pairs'], 0)

    def test_complete_parameter_version_cannot_change_groups_across_segment_types(self):
        rows = self.explicit_segment_pair(after='10')
        data = run(rows)
        self.assertGreater(data['issues']['inconsistent_parameters'], 0)
        # A legacy partial row keeps its historical segment-scoped contract.
        for row in rows:
            row['parameters'].pop('readiness'); row['parameters'].pop('adapter')
        self.assertEqual(run(rows)['issues']['inconsistent_parameters'], 0)

    def test_complete_version_namespace_spans_evidence_classes_and_never_rolls_back(self):
        rows = self.explicit_segment_pair(after='10')
        rows[1]['evidenceClass'] = 'recorded'
        self.assertGreater(run(rows)['issues']['inconsistent_parameters'], 0)
        complete = self.explicit_segment_pair()[0]['parameters']
        rows = fixture()
        for row in rows:
            row['parameters'] = copy.deepcopy(complete)
        rows[0]['parameters']['parametersVersion'] = '11'
        data = run(rows)
        self.assertGreater(data['issues']['parameter_version_rollback_records'], 0)
        self.assertEqual(sum(stats['compared'] for _, stats, _ in data['groups']), 0)
        # Unavailable rows cannot reset the high-water mark.
        rows[1]['parameters'] = {'status': 'unavailable', 'preferencesVersion': 2}
        self.assertGreater(run(rows)['issues']['parameter_version_rollback_records'], 0)

    def test_control_state_changes_and_unobserved_settings_are_complete_pairs_without_cut_credit(self):
        for kind, outcome in [('setLevel', 'accepted'), ('setLevel', 'refused'), ('handToAlfie', 'accepted'),
                              ('takeOver', 'accepted'), ('settingsChanged', 'unobserved')]:
            rows = [record(0, 10, action('attempt', name=kind, kind=kind)),
                    record(1, 10, action('result', name=kind, kind=kind, outcome=outcome))]
            rows[1]['context']['authorityEpoch'] = '2'
            data = run(rows)
            self.assertEqual(data['issues']['incomplete_or_duplicate_action_pairs'], 0)
            self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
            self.assertEqual(data['groups'], [])

    def test_actual_swift_control_bundle_when_explicitly_supplied(self):
        requested = os.environ.get('ALFIE_DIRECTOR_CONTROL_EXPORT')
        if not requested:
            return
        records, issues, source = report.load_input(Path(requested))
        data = report.analyze(records, 2, issues, source)
        self.assertFalse(report.blocking_input(data['issues']))
        self.assertIsNotNone(source['manifest'])
        self.assertEqual(len(records), 16)
        self.assertEqual({r['evidenceClass'] for r in records}, {'synthetic'})
        self.assertEqual(data['issues']['incomplete_or_duplicate_action_pairs'], 0)
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual(sum(s['completed_actions'] for _, s, _ in data['groups']), 1)
        self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)
        self.assertEqual(sum(s['unscored_actions'] for _, s, _ in data['groups']), 1)

    def test_actual_complete_binding_bundle_when_explicitly_supplied(self):
        requested = os.environ.get('ALFIE_DIRECTOR_BINDING_EXPORT')
        if not requested:
            return
        records, issues, source = report.load_input(Path(requested))
        data = report.analyze(records, 2, issues, source)
        self.assertEqual(len(records), 6)
        self.assertFalse(report.blocking_input(data['issues']), data['issues'])
        self.assertTrue(all(report.complete_parameter_group(r['parameters']) for r in records))
        self.assertEqual({r['parameters']['parametersVersion'] for r in records}, {'10', '11'})
        self.assertEqual(sum(len(r['judgements']) for r in records), 4)
        self.assertEqual(data['issues']['incomplete_or_duplicate_action_pairs'], 0)
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        self.assertEqual(data['issues']['inconsistent_parameters'], 0)
        self.assertEqual(data['groups'], [])  # Off-level decisions give no cut credit.

    def test_actual_swift_decision_bundle_when_explicitly_supplied(self):
        requested = os.environ.get('ALFIE_DIRECTOR_DECISION_EXPORT')
        if not requested:
            return
        records, issues, source = report.load_input(Path(requested))
        data = report.analyze(records, 2, issues, source)
        self.assertFalse(report.blocking_input(data['issues']), data['issues'])
        self.assertIsNotNone(source['manifest'])
        self.assertEqual({r['evidenceClass'] for r in records}, {'synthetic'})
        self.assertEqual(sum(r['event']['kind'] == 'wouldPrepare' for r in records), 1)
        self.assertGreaterEqual(sum(r['event']['kind'] == 'wouldCut' for r in records), 1)
        self.assertEqual(data['issues']['incomplete_or_duplicate_action_pairs'], 0)
        self.assertEqual(data['issues']['inconsistent_action_pairs'], 0)
        totals = sum((stats for _, stats, _ in data['groups']), report.Counter())
        self.assertEqual((totals['completed_actions'], totals['compared'], totals['exact']), (1, 1, 1))
        self.assertEqual(totals['unscored_actions'], 0)
        # Preparation intent is recorded before dispatch, not credited as an
        # operator completion or independent quality/safety opportunity.
        self.assertGreaterEqual(totals['unmatched_predictions'], 1)

    def test_known_agreement_and_interior_dwell(self):
        data = run(fixture()); s = sum((stats for _, stats, _ in data['groups']), report.Counter())
        self.assertEqual((s['predictions'], s['completed_actions'], s['compared'], s['exact']), (2, 2, 2, 2))
        self.assertEqual(len(data['dwell']), 1)
        self.assertAlmostEqual(next(iter(data['dwell'].values()))[0], 10.0)
        self.assertEqual(sum(data['abstentions'].values()), 1)
        self.assertEqual(len(data['groups']), 2)
        self.assertIn('1/1', report.markdown(data, 2))

    def test_latest_prediction_is_used_once_and_mismatch_is_not_hidden(self):
        rows = fixture()[:3]
        rows[0]['event']['shot']['preset'] = 'fullBody'
        data = run(rows); s = data['groups'][0][1]
        self.assertEqual((s['compared'], s['exact']), (1, 0))
        self.assertEqual(s['unmatched_predictions'], 0)
        rows[0]['eventTime'] = 1
        self.assertEqual(run(rows)['groups'][0][1]['compared'], 0)

    def test_latest_preceding_choice_is_not_selected_for_agreement(self):
        rows = fixture()[:3]
        earlier = record(0, 8, prediction(name='earlier'))
        rows[0]['sequence'] = '1'; rows[0]['recordID'] = token('later-decision')
        rows[0]['event']['shot']['preset'] = 'fullBody'
        rows[1]['sequence'] = '2'; rows[2]['sequence'] = '3'
        data = run([earlier] + rows)
        s = data['groups'][0][1]
        self.assertEqual((s['predictions'], s['compared'], s['exact'], s['unmatched_predictions']), (2, 1, 0, 1))
        rows = fixture()[:3]
        rows += [record(3, 10.2, action('attempt', name='duplicate-opportunity'), program='input-2', preview='input-1', preset='waistUp'),
                 record(4, 10.3, action('result', name='duplicate-opportunity', after='input-1', preview='input-2'))]
        rows[3]['context']['routeGeneration'] = '2'; rows[4]['context']['routeGeneration'] = '3'
        s = sum((stats for _, stats, _ in run(rows)['groups']), report.Counter())
        self.assertEqual((s['compared'], s['unmatched_actions']), (1, 1))

    def test_loss_is_not_averaged_across_sessions(self):
        clean = fixture()
        other = []
        for r in fixture():
            r['sessionID'] = token('damaged-session')
            r['recordID'] = token('damaged-' + r['sequence'])
            other.append(r)
        other[0]['droppedRecordsBefore'] = '1'
        data = run(clean + other)
        self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 2)
        self.assertEqual(sum(blocked for _, _, blocked in data['groups']), 2)

    def test_refusal_and_acceptance_are_not_completed_cuts(self):
        for outcome in ('accepted', 'refused', 'unobserved'):
            rows = fixture()[:3]; rows[2]['event'] = action('result', outcome=outcome)
            rows[2]['context'].update(program='input-1', preview='input-2')
            rows[2]['context']['routeGeneration'] = rows[1]['context']['routeGeneration']
            s = run(rows)['groups'][0][1]
            self.assertEqual(s['completed_actions'], 0)
            self.assertEqual(s['compared'], 0)

    def test_prepare_comparison_requires_completed_offair_preset(self):
        rows = [record(0, 9, prediction('wouldPrepare')),
                record(1, 10, action('attempt', kind='selectPreset', target='input-2')),
                record(2, 10.1, action('result', kind='selectPreset', target='input-2'))]
        self.assertEqual(run(rows)['groups'][0][1]['exact'], 1)
        for r in rows[1:]:
            r['event']['target'] = 'input-1'
        self.assertEqual(run(rows)['groups'][0][1]['completed_actions'], 0)

    def test_session_evidence_segment_and_parameter_boundaries_do_not_match(self):
        for field, value in [('evidenceClass', 'recorded'), ('sessionID', token('other'))]:
            rows = fixture()[:3]
            for r in rows[1:]:
                r[field] = value
            self.assertEqual(sum(s['compared'] for _, s, _ in run(rows)['groups']), 0)
        for where, field, value in [('context', 'segmentType', 'panel'), ('parameters', 'parametersVersion', '2')]:
            rows = fixture()[:3]
            for r in rows[1:]:
                r[where][field] = value
            self.assertEqual(sum(s['compared'] for _, s, _ in run(rows)['groups']), 0)

    def test_missing_pairs_drops_gaps_and_backward_clocks_suppress_scoring(self):
        variants = []
        variants.append(fixture()[:2])
        rows = fixture(); rows[3]['droppedRecordsBefore'] = '1'; variants.append(rows)
        rows = fixture(); rows[3]['sequence'] = '100'; variants.append(rows)
        rows = fixture(); rows[3]['eventTime'] = 0; variants.append(rows)
        for rows in variants:
            data = run(rows)
            self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)
            self.assertFalse(data['dwell'])

    def test_unknown_schema_keys_malformed_numbers_and_private_payloads_are_rejected(self):
        changes = [lambda r: r['event'].update(phase=None), lambda r: r.update(schemaVersion=3), lambda r: r.update(frame='PRIVATE_FRAME'),
                   lambda r: r['context'].update(name='PRIVATE_NAME'),
                   lambda r: r.update(eventTime=float('nan')),
                   lambda r: r['event']['shot'].update(format='webcam'),
                   lambda r: r.update(recordedAtUTC='2026-02-30T00:00:00.000Z'),
                   lambda r: r.update(sequence=True),
                   lambda r: r['event']['reason'].update(code='PRIVATE_PATH')]
        for change in changes:
            rows = fixture(); change(rows[0]); data = run(rows)
            text = report.markdown(data, 2)
            self.assertGreater(data['issues']['rejected_records'], 0)
            self.assertNotIn('PRIVATE', text)
            self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)

    def test_duplicate_ids_sequences_and_duplicate_json_keys_are_rejected(self):
        for field in ('recordID', 'sequence'):
            rows = fixture(); rows[1][field] = rows[0][field]
            self.assertGreater(run(rows)['issues']['rejected_records'], 0)
        records, issues = report.load_records(io.BytesIO(b'{"schemaVersion":1,"schemaVersion":1}\n'))
        self.assertEqual(records, []); self.assertEqual(issues['rejected_records'], 1)

    def test_unknown_shot_and_intervening_manual_edit_exclude_metrics(self):
        rows = fixture(); rows[2]['context'].pop('programShot')
        data = run(rows)
        self.assertEqual(data['groups'][0][1]['unscored_actions'], 1)
        # Exact roles still establish input tenure, independently of composition.
        self.assertAlmostEqual(next(iter(data['dwell'].values()))[0], 10)
        rows = fixture(); rows[3]['event'] = action('attempt', kind='setLevel')
        self.assertFalse(run(rows)['dwell'])
        self.assertFalse(run(fixture()[:3])['dwell'])

    def test_changed_values_cannot_reuse_a_parameter_version(self):
        rows = fixture()
        rows[1]['parameters']['resolvedStyle']['minimumShotDuration'] = 9
        data = run(rows)
        self.assertGreater(data['issues']['inconsistent_parameters'], 0)
        self.assertEqual(sum(s['compared'] for _, s, _ in data['groups']), 0)

    def test_empty_bounded_input_and_cli_nonoverwrite(self):
        text = report.markdown(run([]), 2)
        self.assertIn('Accepted records: 0', text); self.assertIn('Unavailable', text)
        records, issues = report.load_records(io.BytesIO(b'x' * 10), maximum_line_bytes=4)
        self.assertEqual(issues['input_limit'], 1)
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp)/'input.jsonl', Path(tmp)/'report.md'
            src.write_text('\n'.join(json.dumps(r) for r in fixture()) + '\n')
            command = [sys.executable, str(Path(report.__file__)), str(src), '--match-window-seconds', '2', '--output', str(out)]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            before = out.read_bytes()
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)
            self.assertEqual(out.read_bytes(), before)
            invalid = [sys.executable, str(Path(report.__file__)), str(src), '--match-window-seconds', 'nan']
            self.assertEqual(subprocess.run(invalid, capture_output=True).returncode, 2)


def manifest_for(rows, exported_at='2026-10-19T00:00:00.000Z'):
    return {
        'exportSchemaVersion': 1,
        'exportID': '3C38781E-8078-4D22-912E-0FB9A9C50154',
        'exportedAtUTC': exported_at,
        'sessionIDs': sorted({row['sessionID'] for row in rows}),
        'recordCount': len(rows),
        'evidenceClasses': sorted({row['evidenceClass'] for row in rows}),
        'recordSchemaVersions': sorted({row['schemaVersion'] for row in rows}),
        'retention': 'explicitExport',
    }


def jsonl_bytes(rows):
    return ('\n'.join(json.dumps(row) for row in rows) + ('\n' if rows else '')).encode()


def write_bundle(directory, rows, manifest=None, raw_manifest=None):
    directory.mkdir(exist_ok=True)
    (directory / 'records.jsonl').write_bytes(jsonl_bytes(rows))
    if raw_manifest is None:
        raw_manifest = json.dumps(manifest if manifest is not None else manifest_for(rows)).encode()
    (directory / 'manifest.json').write_bytes(raw_manifest)


def run_bundle(rows, manifest=None, raw_manifest=None, **limits):
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        write_bundle(directory, rows, manifest, raw_manifest)
        records, issues, source = report.load_input(directory, **limits)
        return report.analyze(records, 2, issues, source)


class PhaseAssignmentTests(unittest.TestCase):
    def analyze(self, rows, labels):
        records, issues = report.load_records(io.BytesIO(jsonl_bytes(rows)))
        assignments = {r['recordID']: label for r, label in zip(records, labels)}
        return report.analyze(records, 2, issues, phase_assignments=assignments)

    def totals(self, data):
        return sum((counts for _, counts, _ in data['groups']), report.Counter())

    def test_one_phase_preserves_whole_session_counts_and_original_strata(self):
        baseline = run(fixture())
        phased = self.analyze(fixture(), ['whole'] * 7)
        self.assertEqual(self.totals(phased), self.totals(baseline))
        self.assertEqual([(k[:-2] + (k[-1],), c, b) for k, c, b in phased['groups']], baseline['groups'])
        self.assertEqual({k[:-1]: v for k, v in phased['dwell'].items()}, baseline['dwell'])
        self.assertEqual(phased['blockedSessions'], [])

    def test_predictions_and_interior_dwell_never_cross_phases(self):
        phased = self.analyze(fixture(), ['before'] + ['after'] * 6)
        counts = self.totals(phased)
        self.assertEqual((counts['predictions'], counts['completed_actions'], counts['compared']), (2, 2, 1))
        self.assertEqual((counts['unmatched_predictions'], counts['unmatched_actions']), (1, 1))
        phased = self.analyze(fixture(), ['first'] * 3 + ['second'] * 4)
        self.assertEqual(self.totals(phased)['compared'], 2)
        self.assertFalse(phased['dwell'])

    def test_cross_phase_completed_take_is_retained_as_unscored_at_attempt(self):
        phased = self.analyze(fixture(), ['first'] * 2 + ['second'] * 5)
        counts = self.totals(phased)
        self.assertEqual((counts['completed_actions'], counts['compared'], counts['unscored_actions']), (2, 1, 1))
        first = next(c for k, c, _ in phased['groups'] if k[-2] == 'first')
        self.assertEqual((first['completed_actions'], first['unscored_actions']), (1, 1))
        self.assertEqual(phased['issues']['phase_boundary_actions'], 1)
        self.assertEqual(phased['issues']['incomplete_or_duplicate_action_pairs'], 0)
        self.assertFalse(phased['dwell'])
        text = report.markdown(phased, 2)
        self.assertIn('phase first | wouldCut', text)
        self.assertIn('Original whole-session loss', text)

    def test_reused_phase_label_cannot_match_across_an_intervening_phase(self):
        rows = [record(0, 9, prediction('wouldPrepare')),
                record(1, 9.5, fixture()[-1]['event']),
                record(2, 10, action('attempt', kind='selectPreset', target='input-2')),
                record(3, 10.1, action('result', kind='selectPreset', target='input-2'))]
        counts = self.totals(self.analyze(rows, ['same', 'other', 'same', 'same']))
        self.assertEqual((counts['compared'], counts['unmatched_actions']), (0, 1))

    def test_full_session_loss_and_bad_pairs_still_block_every_phase(self):
        variants = []
        rows = fixture(); rows[0]['droppedRecordsBefore'] = '1'; variants.append(rows)
        rows = fixture()
        for row in rows:
            row['sequence'] = str(int(row['sequence']) + 10)
        variants.append(rows)
        rows = fixture(); rows[-1]['event'] = action('attempt', name='orphan'); variants.append(rows)
        for rows in variants:
            with self.subTest(rows=rows[0]['sequence']):
                data = self.analyze(rows, ['first'] * 3 + ['second'] * 4)
                self.assertEqual(self.totals(data)['compared'], 0)
                self.assertEqual(self.totals(data)['unscored_actions'], 2)
                self.assertTrue(data['blockedSessions'])
                self.assertFalse(data['dwell'])
        self.assertEqual(self.analyze(variants[1], ['first'] * 3 + ['second'] * 4)['issues']['leading_sequence_offset'], 10)

    def test_phase_assignment_requires_exact_record_coverage_and_safe_labels(self):
        rows = fixture()
        assignments = {r['recordID']: 'phase' for r in rows}
        variants = [None, True, {}, {**assignments, token('extra'): 'phase'},
                    {**assignments, rows[0]['recordID']: True},
                    {**assignments, rows[0]['recordID']: 'PRIVATE TEXT'}]
        for candidate in variants[1:]:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                report.analyze(rows, 2, phase_assignments=candidate)
        self.assertEqual(report.analyze(rows, 2, phase_assignments=None), report.analyze(rows, 2))


class ExportBundleTests(unittest.TestCase):
    def assert_blocked(self, data):
        self.assertTrue(report.blocking_input(data['issues']))
        self.assertIsNone(data['source']['manifest'])
        self.assertEqual(sum(stats['compared'] for _, stats, _ in data['groups']), 0)
        self.assertFalse(data['dwell'])
        text = report.markdown(data, 2)
        self.assertIn('export bundle not validated', text)
        self.assertNotIn('PRIVATE', text)

    def test_shared_swift_python_bundle_preserves_known_metrics(self):
        directory = Path(__file__).parent / 'fixtures/director-shadow-synthetic-export'
        records, issues, source = report.load_input(directory)
        data = report.analyze(records, 2, issues, source)
        self.assertFalse(report.blocking_input(issues))
        self.assertEqual(source['manifest'], manifest_for(records))
        self.assertEqual(source['recordsSHA256'], hashlib.sha256((directory / 'records.jsonl').read_bytes()).hexdigest())
        self.assertEqual(source['manifestSHA256'], hashlib.sha256((directory / 'manifest.json').read_bytes()).hexdigest())
        _, limited, partial = report.load_input(directory, maximum_records=1)
        self.assertTrue(limited['input_limit'])
        self.assertIsNone(partial['recordsSHA256'])
        self.assertEqual(partial['manifestSHA256'], source['manifestSHA256'])
        _, limited, partial = report.load_input(directory, maximum_input_bytes=5)
        self.assertTrue(limited['input_limit'])
        self.assertIsNone(partial['manifestSHA256'])
        self.assertIsNone(partial['recordsSHA256'])
        stats = sum((stats for _, stats, _ in data['groups']), report.Counter())
        self.assertEqual((stats['compared'], stats['exact']), (2, 2))
        self.assertAlmostEqual(next(iter(data['dwell'].values()))[0], 10)
        text = report.markdown(data, 2)
        self.assertIn('explicit-export bundle', text)
        self.assertIn('2026-10-19T00:00:00.000Z', text)
        self.assertIn('Retention: explicitExport', text)
        self.assertNotIn('unbundled', text)

    def test_every_required_key_and_unknown_private_additions_are_rejected(self):
        rows = fixture()
        original = manifest_for(rows)
        for field in original:
            with self.subTest(missing=field):
                changed = copy.deepcopy(original)
                changed.pop(field)
                self.assert_blocked(run_bundle(rows, changed))
        for field, value in [('destination', '/PRIVATE_PATH'), ('name', 'PRIVATE_NAME'), ('frame', 'PRIVATE_FRAME')]:
            with self.subTest(unknown=field):
                changed = copy.deepcopy(original)
                changed[field] = value
                self.assert_blocked(run_bundle(rows, changed))

    def test_manifest_rejects_noncanonical_types_tokens_dates_and_versions(self):
        rows = fixture()
        changes = [
            ('exportSchemaVersion', True), ('exportSchemaVersion', 1.0), ('exportSchemaVersion', '1'),
            ('exportSchemaVersion', 2), ('exportSchemaVersion', 0),
            ('recordCount', True), ('recordCount', 7.0), ('recordCount', -1), ('recordCount', 2**63),
            ('exportID', token('export').lower()), ('exportID', 'PRIVATE_NOT_A_TOKEN'),
            ('exportedAtUTC', '2026-02-30T00:00:00.000Z'),
            ('exportedAtUTC', '2026-10-19T00:00:00Z'),
            ('exportedAtUTC', '2026-10-19T00:00:00.000+00:00'),
            ('exportedAtUTC', None), ('exportedAtUTC', True),
            ('sessionIDs', [token('session').lower()]), ('sessionIDs', None),
            ('evidenceClasses', ['PRIVATE_CLASS']), ('evidenceClasses', 'synthetic'),
            ('recordSchemaVersions', [True]), ('recordSchemaVersions', [2]),
            ('retention', 'ordinaryLog'), ('retention', None),
        ]
        for field, value in changes:
            with self.subTest(field=field, value=value):
                changed = manifest_for(rows)
                changed[field] = value
                self.assert_blocked(run_bundle(rows, changed))
        for raw in [b'null', b'[]', b'true', b'1', b'"PRIVATE_STRING"', b'{"recordCount":NaN}']:
            with self.subTest(root=raw):
                self.assert_blocked(run_bundle(rows, raw_manifest=raw))

    def test_summaries_must_be_exact_sorted_unique_sets_of_the_actual_rows(self):
        rows = fixture() + [record(0, 1, {
            'kind': 'abstention', 'decisionID': token('recorded-abstention'), 'stage': 'cut',
            'reasons': [{'domain': 'observation', 'code': 'cutPolicyUnavailable'}],
        }, session='second-session', evidence='recorded')]
        original = manifest_for(rows)
        clean = run_bundle(rows, original)
        self.assertFalse(report.blocking_input(clean['issues']))
        self.assertEqual(clean['source']['manifest']['evidenceClasses'], ['recorded', 'synthetic'])
        changes = [
            ('recordCount', len(rows) - 1), ('recordCount', len(rows) + 1),
            ('sessionIDs', list(reversed(original['sessionIDs']))),
            ('sessionIDs', original['sessionIDs'] + [original['sessionIDs'][0]]),
            ('sessionIDs', original['sessionIDs'][:1]),
            ('sessionIDs', sorted(original['sessionIDs'] + [token('unobserved-session')])),
            ('evidenceClasses', ['synthetic', 'recorded']),
            ('evidenceClasses', ['recorded', 'synthetic', 'synthetic']),
            ('evidenceClasses', ['synthetic']), ('evidenceClasses', ['live', 'recorded', 'synthetic']),
            ('recordSchemaVersions', []), ('recordSchemaVersions', [1, 1]),
        ]
        for field, value in changes:
            with self.subTest(field=field, value=value):
                changed = copy.deepcopy(original)
                changed[field] = value
                self.assert_blocked(run_bundle(rows, changed))

    def test_source_retention_uses_export_time_and_exact_thirty_day_boundary(self):
        rows = fixture()
        before_expiry = manifest_for(rows, '2026-11-16T23:59:59.999Z')
        self.assertFalse(report.blocking_input(run_bundle(rows, before_expiry)['issues']))
        for exported_at in ['2026-10-17T23:59:59.999Z', '2026-11-17T00:00:00.000Z', '2026-11-17T00:00:00.001Z']:
            with self.subTest(exported_at=exported_at):
                self.assert_blocked(run_bundle(rows, manifest_for(rows, exported_at)))

    def test_old_explicit_export_is_not_expired_by_the_analysis_clock(self):
        rows = fixture()
        for row in rows:
            row['recordedAtUTC'] = '2000-01-01T00:00:00.000Z'
        data = run_bundle(rows, manifest_for(rows, '2000-01-02T00:00:00.000Z'))
        self.assertFalse(report.blocking_input(data['issues']))
        self.assertEqual(sum(stats['exact'] for _, stats, _ in data['groups']), 2)
        self.assertTrue(data['dwell'])

    def test_empty_export_has_empty_summaries_and_no_invented_observations(self):
        data = run_bundle([])
        self.assertFalse(report.blocking_input(data['issues']))
        self.assertEqual(data['records'], 0)
        self.assertEqual(data['source']['manifest']['sessionIDs'], [])
        self.assertEqual(data['source']['manifest']['evidenceClasses'], [])
        self.assertEqual(data['source']['manifest']['recordSchemaVersions'], [])
        self.assertEqual(data['groups'], [])
        self.assertIn('Unavailable', report.markdown(data, 2))

    def test_valid_manifest_does_not_clear_partial_session_or_pair_losses(self):
        for rows in [fixture()[3:], fixture()[:2]]:
            with self.subTest(sequences=[row['sequence'] for row in rows]):
                data = run_bundle(rows)
                self.assertIsNotNone(data['source']['manifest'])
                self.assertEqual(sum(stats['compared'] for _, stats, _ in data['groups']), 0)
                self.assertTrue(all(blocked for _, _, blocked in data['groups']))
                self.assertFalse(data['dwell'])

    def test_invalid_record_cannot_be_laundered_by_a_matching_accepted_record_count(self):
        rows = fixture()
        manifest = manifest_for(rows[1:])
        rows[0]['frame'] = 'PRIVATE_FRAME'
        data = run_bundle(rows, manifest)
        self.assertEqual(data['issues']['rejected_records'], 1)
        self.assert_blocked(data)

    def test_duplicate_json_keys_and_non_utf8_transport_are_rejected(self):
        rows = fixture()
        encoded = json.dumps(manifest_for(rows)).encode()
        duplicate = encoded[:-1] + b',"exportSchemaVersion":1}'
        for raw in [duplicate, json.dumps(manifest_for(rows)).encode('utf-16'), b'\xff']:
            with self.subTest(encoding=raw[:16]):
                self.assert_blocked(run_bundle(rows, raw_manifest=raw))
        records, issues = report.load_records(io.BytesIO(json.dumps(rows[0]).encode('utf-16')))
        self.assertEqual(records, [])
        self.assertGreater(issues['rejected_records'], 0)

    def test_manifest_and_jsonl_share_the_same_bounded_input_budget(self):
        rows = fixture()
        raw_manifest = json.dumps(manifest_for(rows)).encode()
        exact_bytes = len(raw_manifest) + len(jsonl_bytes(rows))
        exact = run_bundle(rows, raw_manifest=raw_manifest, maximum_input_bytes=exact_bytes)
        self.assertFalse(report.blocking_input(exact['issues']))
        for limits in [
            {'maximum_input_bytes': exact_bytes - 1},
            {'maximum_input_bytes': len(raw_manifest) - 1},
            {'maximum_records': len(rows) - 1},
            {'maximum_line_bytes': 4},
        ]:
            with self.subTest(limits=limits):
                data = run_bundle(rows, raw_manifest=raw_manifest, **limits)
                self.assertGreater(data['issues']['input_limit'], 0)
                self.assert_blocked(data)

    def test_cli_bundle_failures_are_fixed_diagnostics_and_never_overwrite_output(self):
        command = [sys.executable, str(Path(report.__file__))]
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'PRIVATE_DIRECTORY'
            write_bundle(directory, fixture())
            arguments = command + [str(directory), '--match-window-seconds', '2']
            good = subprocess.run(arguments, capture_output=True, text=True)
            self.assertEqual(good.returncode, 0)
            self.assertIn('explicit-export bundle', good.stdout)
            output = Path(temporary) / 'report.md'
            self.assertEqual(subprocess.run(arguments + ['--output', str(output)], capture_output=True).returncode, 0)
            before = output.read_bytes()
            self.assertEqual(subprocess.run(arguments + ['--output', str(output)], capture_output=True).returncode, 1)
            self.assertEqual(output.read_bytes(), before)
            (directory / 'manifest.json').unlink()
            invalid = subprocess.run(arguments, capture_output=True, text=True)
            self.assertEqual(invalid.returncode, 2)
            self.assertIn('export bundle not validated', invalid.stdout)
            self.assertIn('invalid_export_manifest: 1', invalid.stdout)
            self.assertNotIn('PRIVATE', invalid.stdout + invalid.stderr)
            write_bundle(directory, fixture())
            (directory / 'records.jsonl').unlink()
            missing = subprocess.run(arguments, capture_output=True, text=True)
            self.assertEqual(missing.returncode, 2)
            self.assertIn('missing_bundle_records: 1', missing.stdout)
            unavailable = subprocess.run(command + [str(directory / 'PRIVATE_MISSING.jsonl'), '--match-window-seconds', '2'],
                                         capture_output=True, text=True)
            self.assertEqual(unavailable.returncode, 1)
            self.assertNotIn('PRIVATE', unavailable.stdout + unavailable.stderr)

    def test_file_input_is_explicitly_unbundled_even_beside_a_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_bundle(directory, fixture())
            (directory / 'manifest.json').write_text('PRIVATE_INVALID_MANIFEST')
            records, issues, source = report.load_input(directory / 'records.jsonl')
            data = report.analyze(records, 2, issues, source)
            self.assertEqual(sum(stats['exact'] for _, stats, _ in data['groups']), 2)
            self.assertEqual(set(source), {'kind', 'recordsSHA256'})
            self.assertEqual(source['kind'], 'unbundled')
            self.assertEqual(source['recordsSHA256'], hashlib.sha256((directory / 'records.jsonl').read_bytes()).hexdigest())
            text = report.markdown(data, 2)
            self.assertIn('unbundled JSONL', text)
            self.assertIn('explicit-export retention is not established', text)
            self.assertNotIn('PRIVATE', text)




class ScorerInputSchemaTests(unittest.TestCase):
    @staticmethod
    def captured():
        row = record(0, 10, {'kind': 'abstention', 'decisionID': token('scorer'), 'stage': 'judge',
                             'reasons': [{'domain': 'observation', 'code': 'unclassified'}]})
        row['schemaVersion'] = 2
        row['context'].update(programStartedAt=0, lastWideAt=0)
        ranked, captured = [], []
        for rank, (preset, confidence) in enumerate((('fullBody', 0.9), ('waistUp', 0.8))):
            ranked.append({'candidate': {'channel': 'input-2', 'shot': {'format': 'stage', 'preset': preset},
                                          'isWide': False, 'subjectConfidence': confidence, 'movement': 0.1},
                           'reason': {'domain': 'selection', 'code': 'subjectEvidence'}})
            values = [report.float32(confidence), report.float32(0.1), 10, 10, 1, 0] + [int(i == rank + 1) for i in range(5)] + [1, 0, 0, 0, 0]
            captured.append({'featureSchemaVersion': 1, 'judgementIndex': 0, 'candidateRank': rank, 'features': values})
        row['judgements'] = [{'judgeKind': 'rules', 'evidenceRevision': '1', 'computedAt': 10,
                               'outcome': {'kind': 'ranked', 'ranked': ranked}, 'gateResult': 'notEvaluated'}]
        row['scorerInputs'] = captured
        return row

    def accepts(self, row):
        rows, issues = report.load_records(io.BytesIO((json.dumps(row) + '\n').encode()))
        return len(rows) == 1 and not issues

    def test_v1_unchanged_v2_optional_and_complete_capture(self):
        self.assertTrue(self.accepts(self.captured()))
        row = self.captured(); del row['scorerInputs']
        self.assertTrue(self.accepts(row))
        row['scorerInputs'] = None
        self.assertTrue(self.accepts(row))
        row['schemaVersion'] = 1
        self.assertFalse(self.accepts(row))
        del row['scorerInputs']
        self.assertTrue(self.accepts(row))

    def test_capture_rejects_partial_reordered_duplicate_learned_and_extra_fields(self):
        for mutation in (
            lambda r: r['scorerInputs'].pop(),
            lambda r: r['scorerInputs'].reverse(),
            lambda r: r['scorerInputs'].append(copy.deepcopy(r['scorerInputs'][0])),
            lambda r: r['judgements'][0].update(judgeKind='learned', modelVersion='synthetic-1'),
            lambda r: r['scorerInputs'][0].update(media='forbidden'),
            lambda r: r['scorerInputs'][0].update(featureSchemaVersion=True),
            lambda r: r['scorerInputs'][0].update(judgementIndex=1),
        ):
            row = self.captured(); mutation(row)
            self.assertFalse(self.accepts(row))

    def test_capture_rejects_missing_mismatched_and_non_float32_values(self):
        for mutation in (
            lambda r: r['scorerInputs'][0]['features'].__setitem__(0, 0.9),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(1, float('nan')),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(2, 1e39),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(3, 11),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(4, 0.5),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(5, 2),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(7, 0),
            lambda r: r['scorerInputs'][0]['features'].__setitem__(11, 0),
            lambda r: r['scorerInputs'][0]['features'].pop(),
            lambda r: r['context'].pop('programStartedAt'),
            lambda r: r['judgements'][0].update(computedAt=11),
            lambda r: r['judgements'][0].update(evidenceRevision='2'),
            lambda r: r['judgements'][0]['outcome']['ranked'][0]['candidate'].update(channel='input-1'),
            lambda r: r['judgements'][0]['outcome']['ranked'][0]['candidate'].update(isWide=True),
        ):
            row = self.captured(); mutation(row)
            self.assertFalse(self.accepts(row))

    def test_capture_history_consistency_and_multiple_complete_groups(self):
        row = self.captured()
        row['scorerInputs'][1]['features'][4] = 2
        self.assertFalse(self.accepts(row))
        row = self.captured()
        row['scorerInputs'][0]['features'][5] = 1
        row['scorerInputs'][1]['features'][5] = 1
        self.assertFalse(self.accepts(row))
        row = self.captured()
        row['judgements'].append(copy.deepcopy(row['judgements'][0]))
        more = copy.deepcopy(row['scorerInputs'])
        for item in more:
            item['judgementIndex'] = 1
        row['scorerInputs'] += more
        self.assertTrue(self.accepts(row))

    def test_export_manifest_supports_v1_and_v2(self):
        rows = [record(0, 9, prediction(), session='old'), self.captured()]
        manifest = {'exportSchemaVersion': 1, 'exportID': token('scorer-export'),
                    'exportedAtUTC': '2026-10-18T00:01:00.000Z',
                    'sessionIDs': sorted(r['sessionID'] for r in rows), 'recordCount': 2,
                    'evidenceClasses': ['synthetic'], 'recordSchemaVersions': [1, 2], 'retention': 'explicitExport'}
        self.assertEqual(report.validate_export_manifest(manifest, rows), manifest)
        manifest['recordSchemaVersions'] = [1, 2, 3]
        with self.assertRaises(ValueError):
            report.validate_export_manifest(manifest, rows)


if __name__ == '__main__':
    unittest.main()
