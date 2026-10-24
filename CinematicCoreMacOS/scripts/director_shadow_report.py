#!/usr/bin/env python3
"""C-05: local metadata-only schema-1/2 JSONL analysis. No authority or I/O to the app."""
import argparse
from collections import Counter, defaultdict, deque
from datetime import datetime, timedelta
import json
import math
from pathlib import Path
import re
import statistics
import struct
import sys
import uuid

SCHEMA = json.loads(Path(__file__).with_name('director_shadow_schema.json').read_text())
DEFAULT_MAX_RECORDS = 100000
MAX_LINE_BYTES = 1048576
MAX_INPUT_BYTES = 67108864
SOURCE_RETENTION = timedelta(days=30)
BLOCKING_INPUT_ISSUES = (
    'rejected_records', 'input_limit', 'invalid_export_manifest', 'missing_bundle_records',
)
REASONS = {
    'proposalStale': 'authorityRevoked routeChanged sourceRestarted shotChangedByOperator targetBecameProgram sourceMissing expired requestReplaced policyChanged nominationChanged evidenceUnavailable',
    'policy': 'invalidInput minimumDuration noEligibleCandidate repetition movement noPreview',
    'judge': 'lowConfidence notRecorded nothingAllowed invalidJudgement',
    'readiness': 'compositionUnavailable evidenceUnavailable takeUnavailable invalidParameters invalidEvidence identityUncertain framingUnsettled moving cropMoving',
    'selection': 'advisoryWideReminder advisoryMaximumDwell subjectEvidence unclassified',
    'observation': 'parametersUnavailable parametersInvalid judgementStale cutPolicyUnavailable unclassified',
    'authorityRefusal': 'notQualified prerequisites paused exhausted',
}
PAYLOAD = {
    'wouldPrepare': 'decisionID target shot reason proposalID requestID proposalCreatedAt judgementIndex',
    'wouldCut': 'decisionID target shot reason judgementIndex',
    'abstention': 'decisionID stage reasons target proposalID requestID judgementIndex',
    'operatorAction': 'actionID action phase targetScope target shot outcome reasons programAfter previewAfter',
}
SESSION_ACTIONS = set('take startSession stopSession settingsChanged formatChanged editLive setLevel handToAlfie takeOver cancelNextCut advanceSegment'.split())
CHANNEL_ACTIONS = set('detect cancelDetect selectSubject unlock resumeTracking setMode selectPreset beginZoom endZoom moveManualCenter returnToWide overrideSubject'.split())


def require(condition):
    if not condition:
        raise ValueError('invalid metadata')


def canonical_token(value):
    require(type(value) is str and str(uuid.UUID(value)).upper() == value)
    return value


def parse_utc(value):
    require(type(value) is str and re.fullmatch(
        r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z', value))
    return datetime.strptime(value, '%Y-%m-%dT%H:%M:%S.%fZ')


def blocking_input(issues):
    return any(issues.get(key, 0) for key in BLOCKING_INPUT_ISSUES)


def validate(value, typename='Record', path=''):
    """Closed typed schema: unknown keys, duplicate JSON keys and free text refuse."""
    if typename.endswith('?'):
        return value is None or validate(value, typename[:-1], path)
    if typename.startswith('['):
        require(type(value) is list)
        for i, item in enumerate(value):
            validate(item, typename[1:-1], f'{path}[{i}]')
    elif typename in SCHEMA['objects']:
        shape = SCHEMA['objects'][typename]
        require(type(value) is dict and set(value) <= set(shape))
        for key, fieldtype in shape.items():
            require(key in value or fieldtype.endswith('?'))
            validate(value.get(key), fieldtype, f'{path}.{key}'.lstrip('.'))
    elif typename in SCHEMA['enums']:
        require(type(value) is str and value in SCHEMA['enums'][typename])
    elif typename == 'Bool':
        require(type(value) is bool)
    elif typename == 'Int':
        require(type(value) is int and 0 <= value <= 2**63 - 1)
    elif typename == 'Double':
        require(type(value) in (int, float) and math.isfinite(value) and value >= 0)
    elif typename == 'Counter':
        require(type(value) is str and re.fullmatch(r'0|[1-9][0-9]{0,19}', value) and int(value) <= 2**64 - 1)
    elif typename == 'Token':
        canonical_token(value)
    elif typename == 'UTC':
        parse_utc(value)
    elif typename == 'String':
        require(type(value) is str)
        if path.endswith('.modelVersion'):
            require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', value))
        elif path.startswith('invalidFields['):
            require(re.fullmatch(r'[A-Za-z]+(?:\[\d+\])?(?:\.[A-Za-z]+(?:\[\d+\])?)+', value))
        else:
            require(re.fullmatch(r'input-[1-9][0-9]*', value))
    else:
        raise ValueError('unsupported type')
    return True


def semantic(record):
    c, p, e = (record[k] for k in ('context', 'parameters', 'event'))
    require(record['schemaVersion'] in SCHEMA['supportedVersions'])
    require(record['schemaVersion'] != 1 or 'scorerInputs' not in record)
    inputs = c['inputs']
    require(inputs and len(set(inputs)) == len(inputs) and c['program'] in inputs)
    for key in ('preview', 'pinnedInput'):
        require(c.get(key) is None or c[key] in inputs)
    require(c.get('preview') != c['program'])
    optional = {'context.programStartedAt', 'context.lastWideAt', 'parameters.judgeMaximumAge', 'parameters.minimumProbability'}
    if e['kind'] == 'wouldPrepare':
        optional.add('event.proposalCreatedAt')

    def shot(s):
        require(s['preset'] in ({'wide', 'fullBody', 'waistUp'} if s['format'] == 'stage' else {'wide', 'tight'}))

    if c.get('programShot') is not None:
        shot(c['programShot'])
    require(p.get('preferencesVersion') in (None, 2))
    require(p.get('minimumProbability') is None or p['minimumProbability'] <= 1)
    if p['status'] == 'available':
        require(p.get('parametersVersion') is not None and p.get('preferencesVersion') == 2 and p.get('resolvedStyle') is not None)
    else:
        require(p.get('resolvedStyle') is None)
    if p.get('resolvedStyle'):
        s = p['resolvedStyle']
        require(s['minimumShotDuration'] <= s['preferredShotDuration'] <= s['softMaximumShotDuration'] and s['wideCadence'] > 0 and s['onAirMoveRate'] > 0)
    if p.get('readiness'):
        s = p['readiness']
        require(s['minimumCutSettledTime'] >= s['minimumSettledTime'] and s['maximumCutMotion'] <= s['maximumMotion'])
    require(len({v['channel'] for v in record['evidence']}) == len(record['evidence']))
    diagnostic = p['status'] == 'invalid' and e['kind'] in ('abstention', 'operatorAction')
    for i, v in enumerate(record['evidence']):
        require(v['channel'] in inputs)
        for key in ('sampledAt', 'observationAge', 'subjectSpeed', 'settledSince', 'framingSettledFor', 'observedPersonCount'):
            optional.add(f'evidence[{i}].{key}')
        for key in ('prepareReadiness', 'cutReadiness'):
            if v.get(key) is not None:
                require(v[key]['isReady'] == (not v[key]['reasons']))
                require(p.get('readiness') is not None or (diagnostic and not v[key]['isReady'] and 'invalidParameters' in v[key]['reasons']))
        if v['identitySource'] == 'adapter' or any(v.get(k) is not None for k in ('adapterEvidenceAvailable', 'settledSince', 'framingSettledFor')):
            require(p.get('adapter') is not None or (diagnostic and v['identity'] == 'unavailable' and v.get('adapterEvidenceAvailable') is not True and v.get('settledSince') is None))
        if v['identitySource'] == 'sampleClassifier' and v['identity'] != 'unavailable':
            require(p.get('adapter') is not None)
    for i, j in enumerate(record['judgements']):
        optional.add(f'judgements[{i}].computedAt')
        require(j['judgeKind'] != 'learned' or j.get('modelVersion') is not None)
        if j['gateResult'] != 'notEvaluated':
            require(p.get('judgeMaximumAge') is not None or (diagnostic and j['gateResult'] == 'stale' and 'parameters.judgeMaximumAge' in record['invalidFields']))
        o = j['outcome']
        if o['kind'] == 'ranked':
            require(o.get('ranked') is not None and o.get('reason') is None)
            for k, item in enumerate(o['ranked']):
                v = item['candidate']; require(v['channel'] in inputs); shot(v['shot'])
                for number in ('subjectConfidence',):
                    require(v.get(number) is None or v[number] <= 1)
                require(item.get('probability') is None or item['probability'] <= 1)
                require(j['judgeKind'] != 'rules' or item.get('probability') is None)
                for suffix in ('candidate.subjectConfidence', 'candidate.movement', 'probability'):
                    optional.add(f'judgements[{i}].outcome.ranked[{k}].{suffix}')
        else:
            require(o.get('ranked') is None and o.get('reason') is not None)
        require((j['gateResult'] == 'abstained') == (j.get('gateReason') is not None))
        if j['gateResult'] == 'accepted':
            require(j.get('acceptedRank') is not None and o.get('ranked') is not None and j['acceptedRank'] < len(o['ranked']))
        else:
            require(j.get('acceptedRank') is None)
    validate_scorer_inputs(record)
    def traverse(v):
        if isinstance(v, dict):
            if set(v) == {'domain', 'code'}:
                require(v['code'] in REASONS[v['domain']].split())
            for child in v.values():
                traverse(child)
        elif isinstance(v, list):
            for child in v:
                traverse(child)
    traverse(record)
    markers = record['invalidFields']
    require(markers == sorted(set(markers)))
    for marker in markers:
        require(marker in optional)
        obj = record
        for name in re.findall(r'[A-Za-z]+|\d+', marker):
            obj = obj[int(name)] if name.isdigit() else obj.get(name)
            if obj is None:
                break
        require(obj is None)
    present = set(e) - {'kind'}
    require(present <= set(PAYLOAD[e['kind']].split()))
    for key in ('target', 'programAfter', 'previewAfter'):
        require(e.get(key) is None or e[key] in inputs)
    if e.get('shot') is not None:
        shot(e['shot'])
    if e.get('judgementIndex') is not None:
        require(e['judgementIndex'] < len(record['judgements']))
    if e['kind'] in ('wouldPrepare', 'wouldCut'):
        require(p['status'] == 'available' and all(e.get(k) is not None for k in ('decisionID', 'target', 'shot', 'reason')) and e['target'] == c.get('preview'))
    elif e['kind'] == 'abstention':
        require(e.get('decisionID') is not None and e.get('stage') is not None and bool(e.get('reasons')))
    else:
        require(all(e.get(k) is not None for k in ('actionID', 'action', 'phase', 'targetScope')))
        require((e['targetScope'] == 'channel') == (e.get('target') is not None))
        require((e['action'] == 'selectPreset') == (e.get('shot') is not None))
        require((e['phase'] == 'result') == (e.get('outcome') is not None))
        require(e['phase'] != 'attempt' or (e.get('programAfter') is None and e.get('previewAfter') is None))
        require(e.get('programAfter') is None or e['programAfter'] != e.get('previewAfter'))
        require(e['action'] != 'take' or e.get('outcome') != 'completed' or e.get('programAfter') is not None)
        require(e['action'] not in SESSION_ACTIONS or e['targetScope'] == 'session')
        require(e['action'] not in CHANNEL_ACTIONS or e['targetScope'] == 'channel')



def float32(value):
    """Round exactly as the Swift feature extractor; overflow refuses input."""
    require(type(value) in (int, float) and math.isfinite(value))
    rounded = struct.unpack('<f', struct.pack('<f', value))[0]
    require(math.isfinite(rounded))
    return rounded


DIRECTOR_FEATURE_NAMES = (
    'subjectConfidence', 'movement', 'programDwellSeconds', 'sinceWideSeconds',
    'historyCount', 'sameShotHistoryCount', 'candidateStageWide', 'candidateStageFullBody',
    'candidateStageWaistUp', 'candidateWebcamWide', 'candidateWebcamTight', 'programStageWide',
    'programStageFullBody', 'programStageWaistUp', 'programWebcamWide', 'programWebcamTight',
)
DIRECTOR_SHOTS = (('stage', 'wide'), ('stage', 'fullBody'), ('stage', 'waistUp'),
                  ('webcam', 'wide'), ('webcam', 'tight'))


def validate_scorer_inputs(record):
    """Schema 2 captures actual vectors; it cannot reconstruct missing history."""
    captured = record.get('scorerInputs')
    if captured is None:
        return
    require(record['schemaVersion'] == 2 and bool(captured))
    keys = [(item['judgementIndex'], item['candidateRank']) for item in captured]
    require(keys == sorted(set(keys)))
    groups = defaultdict(list)
    for item in captured:
        groups[item['judgementIndex']].append(item)
    for index, items in groups.items():
        validate_scorer_group(record, index, items)


def validate_scorer_group(record, index, captured):
    require(index < len(record['judgements']))
    judgement = record['judgements'][index]
    context, parameters = record['context'], record['parameters']
    require(judgement['judgeKind'] == 'rules' and judgement['outcome']['kind'] == 'ranked')
    ranked = judgement['outcome']['ranked']
    require(bool(ranked) and len(captured) == len(ranked))
    now = judgement.get('computedAt')
    require(now is not None and now <= record['eventTime'] and
            judgement['evidenceRevision'] == context['evidenceRevision'])
    require(parameters['status'] == 'available' and context.get('preview') is not None and
            context.get('programShot') is not None)
    origins = [context.get('programStartedAt'), context.get('lastWideAt')]
    require(all(origin is not None and origin <= now for origin in origins))
    shared_history = None
    same_shot_counts = {}
    program = context['programShot']
    program_index = DIRECTOR_SHOTS.index((program['format'], program['preset']))
    for rank, item in enumerate(captured):
        require(item['featureSchemaVersion'] == 1 and item['judgementIndex'] == index and
                item['candidateRank'] == rank)
        values = item['features']
        require(len(values) == len(DIRECTOR_FEATURE_NAMES) and
                all(value == float32(value) for value in values))
        candidate = ranked[rank]['candidate']
        shot = candidate['shot']
        identity = (shot['format'], shot['preset'])
        require(candidate['channel'] == context['preview'] and shot != program and
                candidate['isWide'] == (shot['preset'] == 'wide'))
        require(candidate.get('subjectConfidence') is not None and candidate.get('movement') is not None)
        require(values[:4] == [float32(candidate['subjectConfidence']), float32(candidate['movement']),
                              float32(now - origins[0]), float32(now - origins[1])])
        require(values[0] <= 1 and values[4] == int(values[4]) and values[5] == int(values[5]) and
                values[5] <= values[4])
        if shared_history is None:
            shared_history = values[4]
        require(values[4] == shared_history)
        previous = same_shot_counts.setdefault(identity, values[5])
        require(previous == values[5])
        candidate_index = DIRECTOR_SHOTS.index(identity)
        require(values[6:11] == [int(i == candidate_index) for i in range(5)] and
                values[11:16] == [int(i == program_index) for i in range(5)])
    require(sum(same_shot_counts.values()) <= shared_history)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result)
        result[key] = value
    return result


def strict_json(raw):
    # The transport is UTF-8, not JSON's optional UTF-16/32 byte autodetection.
    return json.loads(raw.decode('utf-8'), object_pairs_hook=unique_object,
                      parse_constant=lambda _: require(False))


def load_records(stream, maximum_records=DEFAULT_MAX_RECORDS,
                 maximum_line_bytes=MAX_LINE_BYTES, maximum_input_bytes=MAX_INPUT_BYTES):
    records, issues, ids, sequences = [], Counter(), set(), {}
    total_bytes = 0
    for count in range(maximum_records + 1):
        raw = stream.readline(maximum_line_bytes + 1)
        if not raw:
            break
        total_bytes += len(raw)
        if count == maximum_records or len(raw) > maximum_line_bytes or total_bytes > maximum_input_bytes:
            issues['input_limit'] += 1
            break
        try:
            value = strict_json(raw)
            validate(value)
            semantic(value)
            session, sequence = value['sessionID'], int(value['sequence'])
            require(value['recordID'] not in ids and sequence > sequences.get(session, -1))
            ids.add(value['recordID'])
            sequences[session] = sequence
            records.append(value)
        except (ValueError, TypeError, KeyError, OverflowError, RecursionError, UnicodeError):
            issues['rejected_records'] += 1
    return records, issues


def validate_export_manifest(manifest, records):
    """The eight-field export projection is closed and must describe these rows.

    Source retention is checked at export time. The exported copy itself has
    no automatic expiry; the current analysis clock is deliberately unused.
    """
    validate(manifest, 'ExportManifest')
    require(manifest['exportSchemaVersion'] == 1)
    require(manifest['recordCount'] == len(records))
    summaries = {
        'sessionIDs': sorted({record['sessionID'] for record in records}),
        'evidenceClasses': sorted({record['evidenceClass'] for record in records}),
        'recordSchemaVersions': sorted({record['schemaVersion'] for record in records}),
    }
    for field, expected in summaries.items():
        require(manifest[field] == expected)
    require(set(manifest['recordSchemaVersions']) <= set(SCHEMA['supportedVersions']))
    exported_at = parse_utc(manifest['exportedAtUTC'])
    for record in records:
        age = exported_at - parse_utc(record['recordedAtUTC'])
        require(timedelta(0) <= age < SOURCE_RETENTION)
    return manifest


def load_input(path, maximum_records=DEFAULT_MAX_RECORDS,
               maximum_line_bytes=MAX_LINE_BYTES, maximum_input_bytes=MAX_INPUT_BYTES):
    """A directory is an export bundle; a file is explicitly unbundled JSONL.

    No companion guessing or recursive discovery can select a different
    dataset. Bundle metadata and records share the existing byte budget.
    """
    path = Path(path)
    if not path.is_dir():
        with path.open('rb') as stream:
            records, issues = load_records(stream, maximum_records, maximum_line_bytes, maximum_input_bytes)
        return records, issues, {'kind': 'unbundled'}

    source = {'kind': 'bundle', 'manifest': None}
    issues = Counter()
    manifest = None
    manifest_bytes = 0
    manifest_path = path / 'manifest.json'
    if not manifest_path.is_file():
        issues['invalid_export_manifest'] += 1
    else:
        with manifest_path.open('rb') as stream:
            raw = stream.read(maximum_input_bytes + 1)
        manifest_bytes = len(raw)
        if manifest_bytes > maximum_input_bytes:
            issues['input_limit'] += 1
            return [], issues, source
        try:
            manifest = strict_json(raw)
        except (ValueError, TypeError, KeyError, OverflowError, RecursionError, UnicodeError):
            issues['invalid_export_manifest'] += 1

    records_path = path / 'records.jsonl'
    if not records_path.is_file():
        issues['missing_bundle_records'] += 1
        return [], issues, source
    with records_path.open('rb') as stream:
        records, record_issues = load_records(
            stream, maximum_records, maximum_line_bytes, maximum_input_bytes - manifest_bytes)
    issues.update(record_issues)
    if not issues.get('invalid_export_manifest'):
        try:
            validate_export_manifest(manifest, records)
            if not blocking_input(issues):
                source['manifest'] = manifest
        except (ValueError, TypeError, KeyError, OverflowError, RecursionError, UnicodeError):
            issues['invalid_export_manifest'] += 1
    return records, issues, source


def stratum(r):
    c, p = r['context'], r['parameters']
    return (r['sessionID'], r['evidenceClass'], c['segmentType'], c.get('segmentToken'), p.get('parametersVersion'), p.get('preferencesVersion'), c['policyRevision'], c['routeGeneration'])


def action_pair_scope_matches(attempt, result):
    """Allow only the scope transitions committed by the named synchronous action.

    Predictions still use the attempt's original stratum. These exceptions do
    not join independent source, parameter, model or policy observations.
    """
    ac, bc = attempt['context'], result['context']
    ap, bp = attempt['parameters'], result['parameters']
    ae, be = attempt['event'], result['event']
    models = lambda row: [(j['judgeKind'], j.get('modelVersion')) for j in row['judgements']]
    if (attempt['sessionID'] != result['sessionID'] or attempt['evidenceClass'] != result['evidenceClass']
            or ac['inputs'] != bc['inputs'] or ac['nominationRevision'] != bc['nominationRevision']
            or models(attempt) != models(result)):
        return False
    if be['action'] == 'take' and be['outcome'] == 'completed':
        return (stratum(attempt)[:-1] == stratum(result)[:-1] and ap == bp
                and int(bc['routeGeneration']) == int(ac['routeGeneration']) + 1
                and be.get('programAfter') == ac.get('preview')
                and bc['program'] == be['programAfter']
                and bc.get('preview') == ac['program'] and be.get('previewAfter') == ac['program'])
    if be['action'] == 'advanceSegment' and be['outcome'] == 'accepted':
        # Only explicit advance can change segment/style and increment the
        # policy once. Readiness, adapter, judge settings and preference version
        # cannot change under cover of this action.
        stable_parameters = lambda p: {k: v for k, v in p.items() if k not in ('parametersVersion', 'resolvedStyle')}
        parameter_versions_match = ((ap.get('parametersVersion') is None and bp.get('parametersVersion') is None)
            or (ap.get('parametersVersion') == ac['policyRevision'] and bp.get('parametersVersion') == bc['policyRevision']))
        return (ac['program'] == bc['program'] and ac.get('preview') == bc.get('preview')
                and ac['routeGeneration'] == bc['routeGeneration']
                and int(bc['policyRevision']) == int(ac['policyRevision']) + 1
                and ac.get('segmentToken') is not None and bc.get('segmentToken') is not None
                and ac['segmentToken'] != bc['segmentToken']
                and stable_parameters(ap) == stable_parameters(bp) and parameter_versions_match)
    return stratum(attempt) == stratum(result) and ap == bp


def analyze(records, window, issues=None, source=None):
    require(math.isfinite(window) and window >= 0)
    issues = Counter(issues or {})
    pairs, sessions, groups, abstentions = defaultdict(list), defaultdict(list), defaultdict(list), Counter()
    for r in records:
        sessions[r['sessionID']].append(r); groups[stratum(r)].append(r)
        e = r['event']
        if e['kind'] == 'operatorAction':
            pairs[(r['sessionID'], e['actionID'])].append(r)
        if e['kind'] == 'abstention':
            for reason in e['reasons']:
                abstentions[(r['evidenceClass'], r['context']['segmentType'], reason['domain'], reason['code'])] += 1
    blocked, actions = set(), []
    for session, rows in sessions.items():
        previous = None
        if int(rows[0]['sequence']):
            issues['leading_sequence_offset'] += int(rows[0]['sequence']); blocked.add(session)
        for r in rows:
            if int(r['droppedRecordsBefore']):
                issues['reported_drops'] += int(r['droppedRecordsBefore']); blocked.add(session)
            if previous:
                gap = int(r['sequence']) - int(previous['sequence']) - 1
                issues['sequence_gaps'] += gap
                if gap or r['eventTime'] < previous['eventTime']:
                    blocked.add(session)
                    if r['eventTime'] < previous['eventTime']:
                        issues['backward_clocks'] += 1
            issues['invalid_measurements'] += len(r['invalidFields'])
            previous = r
    snapshots = {}
    for r in records:
        p = r['parameters']
        if p['status'] != 'available':
            continue
        key = (r['sessionID'], r['evidenceClass'], r['context']['segmentType'], p['parametersVersion'])
        prior = snapshots.setdefault(key, {})
        for name, value in p.items():
            if value is None:
                continue
            if name in prior and prior[name] != value:
                issues['inconsistent_parameters'] += 1; blocked.add(r['sessionID'])
            prior[name] = value
    for (session, _), rows in pairs.items():
        a = [r for r in rows if r['event']['phase'] == 'attempt']
        b = [r for r in rows if r['event']['phase'] == 'result']
        if len(a) != 1 or len(b) != 1:
            issues['incomplete_or_duplicate_action_pairs'] += 1; blocked.add(session); continue
        a, b = a[0], b[0]; ae, be = a['event'], b['event']
        intervening = [r for r in sessions[session] if int(a['sequence']) < int(r['sequence']) < int(b['sequence'])]
        raced = any(r['event']['kind'] == 'operatorAction' or stratum(r) != stratum(a)
                    or r['evidenceClass'] != a['evidenceClass'] or r['context']['inputs'] != a['context']['inputs']
                    for r in intervening)
        if (a['eventTime'] > b['eventTime'] or int(a['sequence']) >= int(b['sequence']) or raced
                or not action_pair_scope_matches(a, b) or
                any(ae.get(k) != be.get(k) for k in ('action', 'target', 'shot', 'targetScope'))):
            issues['inconsistent_action_pairs'] += 1; blocked.add(session); continue
        if be['outcome'] != 'completed':
            issues['operator_' + be['outcome']] += 1; continue
        if be['action'] == 'take':
            if be.get('programAfter') != a['context'].get('preview') or b['context']['program'] != be['programAfter'] or b['context'].get('preview') != a['context']['program']:
                issues['inconsistent_take_roles'] += 1; blocked.add(session); continue
            actions.append((a, b, 'wouldCut', be['programAfter'], b['context'].get('programShot')))
        elif be['action'] == 'selectPreset' and ae['target'] == a['context'].get('preview'):
            actions.append((a, b, 'wouldPrepare', be['target'], be['shot']))
    # Invalid/unattributable input invalidates scoring globally; identified losses invalidate their session.
    if blocking_input(issues):
        blocked.update(sessions)
    result, dwell = [], defaultdict(list)
    for key, rows in sorted(groups.items(), key=lambda kv: repr(kv[0])):
        for kind in ('wouldPrepare', 'wouldCut'):
            predictions = [r for r in rows if r['event']['kind'] == kind]
            stats = Counter(predictions=len(predictions))
            comparable = [x for x in actions if stratum(x[0]) == key and x[2] == kind]
            if not predictions and not comparable:
                continue
            stats['completed_actions'] = len(comparable)
            used = set()
            ordered = sorted(predictions, key=lambda r: (r['eventTime'], int(r['sequence'])))
            cursor, pending = 0, deque()
            if key[0] not in blocked:
                for a, b, action_kind, target, shot in sorted(comparable, key=lambda x: (x[0]['eventTime'], int(x[0]['sequence']))):
                    if shot is None or a['parameters']['status'] != 'available':
                        stats['unscored_actions'] += 1; continue
                    while cursor < len(ordered) and ordered[cursor]['eventTime'] <= a['eventTime']:
                        pending.append(ordered[cursor]); cursor += 1
                    while pending and pending[0]['eventTime'] < a['eventTime'] - window:
                        pending.popleft()
                    if not pending:
                        stats['unmatched_actions'] += 1; continue
                    p = pending.pop()
                    used.add(p['recordID']); stats['compared'] += 1
                    stats['exact'] += int(p['event']['target'] == target and p['event']['shot'] == shot)
            else:
                stats['unscored_actions'] = len(comparable)
            stats['unmatched_predictions'] = len(predictions) - len(used)
            result.append((key + (kind,), stats, key[0] in blocked))
    # Only complete, continuous consecutive observed Takes support an interior dwell.
    takes = defaultdict(list)
    for a, b, kind, _, _ in actions:
        if kind == 'wouldCut':
            takes[a['sessionID']].append((a, b))
    for session, values in takes.items():
        if session in blocked:
            continue
        positions = {r['recordID']: i for i, r in enumerate(sessions[session])}
        values.sort(key=lambda pair: (pair[1]['eventTime'], int(pair[1]['sequence'])))
        for (a, b), (next_a, next_b) in zip(values, values[1:]):
            start, end = positions[b['recordID']], positions[next_a['recordID']]
            if start >= end:
                continue
            intervening = sessions[session][start + 1:end]
            disruption = any(stratum(r) != stratum(b) or (r['event']['kind'] == 'operatorAction' and r['event']['action'] not in ('take',)) or r['context']['program'] != b['context']['program'] for r in intervening)
            if stratum(b) == stratum(next_a) and b['context']['program'] == next_a['context']['program'] and not disruption:
                dwell[stratum(b)].append(next_b['eventTime'] - b['eventTime'])
    return {'groups': result, 'issues': issues, 'abstentions': abstentions, 'dwell': dwell,
            'records': len(records), 'source': source or {'kind': 'unbundled'}}


def markdown(data, window):
    lines = ['# Director shadow report', '', 'Metadata observations only; no qualification or tuning recommendation.', '']
    source = data.get('source', {'kind': 'unbundled'})
    if source['kind'] == 'bundle':
        manifest = source.get('manifest')
        if manifest is None:
            lines += ['Input: export bundle not validated. Agreement and dwell are unavailable.', '']
        else:
            lines += [
                'Input: explicit-export bundle. Manifest summaries and source age at export are validated.',
                f'Export ID: {manifest["exportID"]}. Exported at UTC: {manifest["exportedAtUTC"]}.',
                'Retention: explicitExport. The exported copy is not aged out by the analysis clock.',
                'Manifest validation does not prove complete capture. Session loss checks still apply.', '',
            ]
    else:
        lines += ['Input: unbundled JSONL. Export metadata is unavailable; explicit-export retention is not established.', '']
    lines += [
             f'Accepted records: {data["records"]}. Matching window: {window:g} seconds (supplied).', '',
             'Matching: latest unused preceding prediction of the same kind, within the supplied window,',
             'matched to a paired completed operator action at its attempt time. Target and preset must both agree.',
             'Partitions: session, source class, segment/token, parameter/preference versions, policy and route revision.',
             'Agreement = exact / compared; coverage = compared / predictions. Unmatched and unscored counts remain visible.',
             'Malformed input or export metadata suppresses all scoring; sequence loss, backward clocks or incomplete action pairs suppress their session.', '',
             '| Session | Evidence | Segment | Decision | Parameter version | Predictions | Completed actions | Compared | Exact | Agreement | Unmatched predictions | Unmatched actions | Unscored actions | Status |',
             '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- |']
    for key, s, blocked in data['groups']:
        agreement = f'{s["exact"]}/{s["compared"]}' if s['compared'] else 'unavailable'
        label = f'{key[2]}/{key[3] or "none"}; policy {key[6]}; route {key[7]}; prefs {key[5] or "unknown"}'
        lines.append(f'| {key[0]} | {key[1]} | {label} | {key[8]} | {key[4] or "unknown"} | {s["predictions"]} | {s["completed_actions"]} | {s["compared"]} | {s["exact"]} | {agreement} | {s["unmatched_predictions"]} | {s["unmatched_actions"]} | {s["unscored_actions"]} | {"incomplete" if blocked else "observed"} |')
    lines += ['', '## Abstentions', '', 'Reason totals count reasons, not independent opportunities.', '']
    for key, count in sorted(data['abstentions'].items()):
        lines.append(f'- {" / ".join(key)}: {count}')
    if not data['abstentions']:
        lines.append('No observed abstentions.')
    lines += ['', '## Interior Program dwell', '', 'Seconds between consecutive completed Takes with continuous roles and no observed disruption.', 'First/last censored holds and missing intervals are excluded; this is not downstream presentation.', '']
    for key, values in sorted(data['dwell'].items(), key=lambda kv: repr(kv[0])):
        lines.append(f'- {key[0]} / {key[1]} / {key[2]} / parameters {key[4]}: n={len(values)}, min={min(values):g}, median={statistics.median(values):g}, max={max(values):g} s')
    if not data['dwell']:
        lines.append('Unavailable: no complete continuous interior dwell intervals.')
    lines += ['', '## Completeness', '']
    for key, value in sorted(data['issues'].items()):
        if value:
            lines.append(f'- {key}: {value}')
    lines.append('Zero reported loss does not prove complete capture. No source frames or raw rejected content are included.')
    return '\n'.join(lines) + '\n'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path, help='export bundle directory or unbundled JSONL file')
    parser.add_argument('--match-window-seconds', type=float, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--max-records', type=int, default=DEFAULT_MAX_RECORDS, help='offline analysis resource bound')
    args = parser.parse_args(argv)
    if not math.isfinite(args.match_window_seconds) or args.match_window_seconds < 0 or args.max_records <= 0:
        parser.error('window must be finite/nonnegative and record limit positive')
    try:
        records, issues, source = load_input(args.input, args.max_records)
        data = analyze(records, args.match_window_seconds, issues, source)
        text = markdown(data, args.match_window_seconds)
        if args.output:
            with args.output.open('x', encoding='utf-8') as output:
                output.write(text)
        else:
            sys.stdout.write(text)
        return 2 if blocking_input(issues) else 0
    except OSError:
        print('Input/output unavailable; no existing output is overwritten.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
