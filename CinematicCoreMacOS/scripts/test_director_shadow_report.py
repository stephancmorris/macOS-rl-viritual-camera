#!/usr/bin/env python3
"""C-05 synthetic fixtures; no person/media or live qualifications."""
import io
import json
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
    return [
        record(0, 9, prediction()),
        record(1, 10, action('attempt')),
        record(2, 10.1, action('result'), program='input-2', preview='input-1', preset='waistUp'),
        record(3, 19, prediction(target='input-1', preset='wide', name='decision-2'), program='input-2', preview='input-1', preset='waistUp'),
        record(4, 20, action('attempt', name='take-2'), program='input-2', preview='input-1', preset='waistUp'),
        record(5, 20.1, action('result', name='take-2', after='input-1', preview='input-2')),
        record(6, 21, {'kind': 'abstention', 'decisionID': token('abstention'), 'stage': 'prepare', 'reasons': [{'domain': 'policy', 'code': 'minimumDuration'}]}),
    ]


def run(rows, window=2):
    records, issues = report.load_records(io.BytesIO(('\n'.join(json.dumps(r) for r in rows) + ('\n' if rows else '')).encode()))
    return report.analyze(records, window, issues)


class ShadowReportTests(unittest.TestCase):
    def test_known_agreement_and_interior_dwell(self):
        data = run(fixture()); s = data['groups'][0][1]
        self.assertEqual((s['predictions'], s['completed_actions'], s['compared'], s['exact']), (2, 2, 2, 2))
        self.assertEqual(len(data['dwell']), 1)
        self.assertAlmostEqual(next(iter(data['dwell'].values()))[0], 10.0)
        self.assertEqual(sum(data['abstentions'].values()), 1)
        self.assertIn('2/2', report.markdown(data, 2))

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
        rows += [record(3, 10.2, action('attempt', name='duplicate-opportunity')),
                 record(4, 10.3, action('result', name='duplicate-opportunity'), program='input-2', preview='input-1', preset='waistUp')]
        s = run(rows)['groups'][0][1]
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
        self.assertEqual(sum(blocked for _, _, blocked in data['groups']), 1)

    def test_refusal_and_acceptance_are_not_completed_cuts(self):
        for outcome in ('accepted', 'refused', 'unobserved'):
            rows = fixture()[:3]; rows[2]['event'] = action('result', outcome=outcome)
            rows[2]['context'].update(program='input-1', preview='input-2')
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
        changes = [lambda r: r['event'].update(phase=None), lambda r: r.update(schemaVersion=2), lambda r: r.update(frame='PRIVATE_FRAME'),
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
        self.assertEqual(run(rows)['groups'][0][1]['unscored_actions'], 1)
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


if __name__ == '__main__':
    unittest.main()
