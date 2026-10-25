#!/usr/bin/env python3
"""D-06 synthetic replay and shadow observations; never issues qualification."""
import argparse
from collections import defaultdict
import copy
import hashlib
import io
import json
import math
from pathlib import Path
import re
import statistics
import sys

import director_shadow_report as shadow

SCHEMA = json.loads(Path(__file__).with_name('director_evaluation_schema.json').read_text())
MAX_BYTES = 8 * 1024 * 1024
MAX_RUNS = 1000


def require(condition):
    if not condition:
        raise ValueError('invalid evaluation metadata')


def exact(value, keys):
    require(type(value) is dict and set(value) == set(keys))


def number(value, integer=False):
    require(type(value) is int if integer else type(value) in (int, float))
    require(math.isfinite(value) and value >= 0 and (not integer or value <= 2**63 - 1))


def token(value):
    require(type(value) is str and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,95}', value))


def partition(value):
    """Every output row retains scope; no rates are pooled across partitions."""
    return tuple(value[k] for k in SCHEMA['requiredBindingKeys'])


def validate_scope(value, replay=False):
    shadow.canonical_token(value['sessionID'])
    for field, values in [('evidenceClass', SCHEMA['evidenceClasses']),
                          ('level', SCHEMA['levels'] + ['off', 'suggest']),
                          ('executionMode', SCHEMA['executionModes']),
                          ('route', SCHEMA['routes']), ('judgeKind', SCHEMA['judgeKinds'])]:
        require(type(value[field]) is str and value[field] in values)
    token(value['configurationID'])
    if replay or value['parameterVersion'] is not None:
        token(value['parameterVersion'])
    if value['modelVersion'] is not None:
        token(value['modelVersion'])
    require(value['judgeKind'] != 'learned' or value['modelVersion'] is not None)
    require(value['judgeKind'] == 'learned' or value['modelVersion'] is None)
    if replay:
        # DirectorReplay has only a simulated preparation sink and no output route.
        require(value['evidenceClass'] == 'synthetic' and value['level'] == 'assist'
                and value['executionMode'] == 'observing' and value['route'] == 'none'
                and value['judgeKind'] == 'rules')


def validate_parameters(parameters):
    exact(parameters, SCHEMA['parameterGroups'])
    for group, fields in SCHEMA['parameterGroups'].items():
        exact(parameters[group], fields)
        for field, value in parameters[group].items():
            if field == 'cutOnMotionAllowed':
                require(type(value) is bool)
            else:
                number(value)
    policy, readiness = parameters['shotPolicy'], parameters['readiness']
    require(policy['minimumShotDuration'] <= policy['maximumShotDuration'])
    require(policy['wideCadence'] > 0)
    require(readiness['minimumCutSettledTime'] >= readiness['minimumSettledTime'])
    require(readiness['maximumCutMotion'] <= readiness['maximumMotion'])


def validate_evaluation(value):
    exact(value, SCHEMA['requiredTopLevelKeys'])
    require(type(value['evaluationSchemaVersion']) is int and
            value['evaluationSchemaVersion'] in SCHEMA['supportedEvaluationVersions'])
    require(value['producer'] == 'DirectorReplay')
    require(type(value['runs']) is list and len(value['runs']) <= MAX_RUNS)
    require(type(value['shadowBindings']) is list and len(value['shadowBindings']) <= MAX_RUNS)
    ids, sessions, configurations = set(), set(), {}
    for run in value['runs']:
        exact(run, SCHEMA['requiredRunKeys'])
        token(run['scenarioID']); validate_scope(run, replay=True)
        require(run['scenarioID'] not in ids and run['sessionID'] not in sessions)
        ids.add(run['scenarioID']); sessions.add(run['sessionID'])
        number(run['durationSeconds']); require(run['durationSeconds'] > 0)
        validate_parameters(run['parameters'])
        prior = configurations.setdefault(run['configurationID'], run['parameters'])
        require(prior == run['parameters'])
        # The current replay has no independent eligible-opportunity labels.
        # A future observed-opportunity format needs its own version and references.
        exact(run['opportunities'], ['eligible', 'useful', 'unverified'])
        require(all(v is None for v in run['opportunities'].values()))
        metrics = run['metrics']
        exact(metrics, SCHEMA['countMetrics'] + SCHEMA['otherMetrics'])
        for key in SCHEMA['countMetrics']:
            number(metrics[key], integer=True)
        number(metrics['cutsPerMinute'])
        require(type(metrics['finalPaused']) is bool)
        require(metrics['finalLevel'] in ('off', 'suggest', 'assist', 'auto', 'backup'))
        require(metrics['directorCuts'] == 0)  # Structural, explicitly not a scored invariant.
        require(metrics['wrongSubjectAttempts'] <= metrics['labelledSubjectAttempts'] <= metrics['directorAttemptCount'])
        require(metrics['wrongSubjectProposals'] <= metrics['labelledSubjectProposals'] <= metrics['proposalCount'])
        require(metrics['preparationsCommitted'] <= metrics['directorAttemptCount'])
        require(metrics['acknowledgementsAccepted'] <= metrics['preparationsCommitted'])
        require(metrics['staleEffectsCommitted'] <= metrics['preparationsCommitted'])
        require(metrics['operatorCuts'] <= metrics['operatorTakeAttempts'])
        require(math.isclose(metrics['cutsPerMinute'], metrics['operatorCuts'] * 60 / run['durationSeconds'], rel_tol=1e-9, abs_tol=1e-9))
        reasons = metrics['staleProposalsRejected']
        require(type(reasons) is dict and set(reasons) <= set(shadow.REASONS['proposalStale'].split()))
        for count in reasons.values():
            number(count, integer=True)
        latencies = metrics['manualOverrideLatencies']
        require(type(latencies) is list and len(latencies) == metrics['manualOverridesHonoured'])
        for latency in latencies:
            require(latency is None)  # Headless replay cannot measure visible/UI latency.
    binding_sessions, phase_ids, phase_spans, binding_configurations = set(), set(), defaultdict(list), {}
    for binding in value['shadowBindings']:
        phased = value['evaluationSchemaVersion'] == 2
        exact(binding, SCHEMA['requiredPhaseBindingKeys'] if phased else SCHEMA['requiredBindingKeys'])
        validate_scope(binding)
        if phased:
            token(binding['phaseID'])
            require(binding['phaseID'] not in phase_ids)
            phase_ids.add(binding['phaseID'])
            for field in ('firstSequence', 'lastSequence'):
                shadow.validate(binding[field], 'Counter')
            first, last = int(binding['firstSequence']), int(binding['lastSequence'])
            require(first <= last)
            spans = phase_spans[binding['sessionID']]
            require(all(last < start or first > end for start, end in spans))
            spans.append((first, last))
            context = binding['parameterContext']
            exact(context, shadow.SCHEMA['objects']['ParameterContext'])
            shadow.validate(context, 'ParameterContext')
            require(context['parametersVersion'] == binding['parameterVersion'])
            generations = binding['routeGenerations']
            require(type(generations) is list and bool(generations))
            for generation in generations:
                shadow.validate(generation, 'Counter')
            require(generations == sorted(set(generations), key=int))
            prior = binding_configurations.setdefault(binding['configurationID'], context)
            require(prior == context)
        else:
            require(binding['sessionID'] not in binding_sessions)
        binding_sessions.add(binding['sessionID'])
    return value


def load_evaluation(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    require(len(raw) <= MAX_BYTES)
    return validate_evaluation(shadow.strict_json(raw)), hashlib.sha256(raw).hexdigest()


def summarize_shadow(path, window, bindings, binding_schema_version=1):
    require(type(binding_schema_version) is int and binding_schema_version in SCHEMA['supportedEvaluationVersions'])
    if binding_schema_version == 2:
        return summarize_shadow_phases(path, window, bindings)
    records, issues, source = shadow.load_input(path)
    data = shadow.analyze(records, window, issues, source)
    blocked_sessions = set(data['captureBlockedSessions'])
    unscored_sessions = {key[0] for key, counts, _ in data['groups'] if counts['unscored_actions']}
    by_session = defaultdict(list)
    for record in records:
        by_session[record['sessionID']].append(record)
    declared = {b['sessionID']: b for b in bindings}
    rows, gaps, sessions, parameter_evidence = [], [], [], []
    for session, records_in_session in sorted(by_session.items()):
        scopes = {(r['evidenceClass'], r['context']['level'], r['executionMode']) for r in records_in_session}
        models = {(j['judgeKind'], j.get('modelVersion')) for r in records_in_session for j in r['judgements']}
        binding = declared.get(session)
        scope_problem = len(scopes) != 1 or len(models) > 1
        if binding:
            actual = next(iter(scopes)) if len(scopes) == 1 else None
            require(actual == (binding['evidenceClass'], binding['level'], binding['executionMode']))
            require(models == {(binding['judgeKind'], binding['modelVersion'])} if models else
                    binding['judgeKind'] == 'unobserved' and binding['modelVersion'] is None)
            require({r['parameters'].get('parametersVersion') for r in records_in_session} == {binding['parameterVersion']})
        else:
            gaps.append({'sessionID': session, 'reason': 'missingShadowBinding'})
        if scope_problem:
            gaps.append({'sessionID': session, 'reason': 'mixedLevelModeOrModel'})
        sessions.append({'sessionID': session, 'binding': binding,
                         'actualScopes': [list(s) for s in sorted(scopes)],
                         'judgeModels': [list(m) for m in sorted(models, key=repr)],
                         'status': 'incomplete' if scope_problem or binding is None or
                                   session in blocked_sessions or session in unscored_sessions else 'observed'})
        parameter_scopes = defaultdict(list)
        for record in records_in_session:
            record_models = tuple(sorted({(j['judgeKind'], j.get('modelVersion')) for j in record['judgements']}, key=repr))
            parameter_scopes[(record['evidenceClass'], record['context']['level'], record['executionMode'], record_models)].append(record)
        for scope_key, scoped_records in sorted(parameter_scopes.items(), key=lambda item: repr(item[0])):
            scope = {'evidenceClass': scope_key[0], 'level': scope_key[1], 'executionMode': scope_key[2],
                     'judgeModels': [list(model) for model in scope_key[3]]}
            parameter_evidence.extend(summarize_parameter_samples(session, scoped_records, scope))
        for key, counts, blocked in data['groups']:
            if key[0] != session:
                continue
            # C-05 owns the matching algorithm and may extend its stratum tuple.
            # Retain the complete tuple without coupling to its later positions.
            count_values = {name: counts[name] for name in ('predictions', 'completed_actions', 'compared', 'exact',
                            'unmatched_predictions', 'unmatched_actions', 'unscored_actions')}
            row = {'sessionID': session, 'binding': binding, 'stratum': list(key),
                   'counts': count_values, 'status': 'incomplete' if blocked or scope_problem or binding is None or counts['unscored_actions'] else 'observed'}
            if scope_problem:
                row['counts'].update(compared=None, exact=None, unscored_actions=counts['completed_actions'])
            rows.append(row)
    require(set(declared) <= set(by_session))
    return {'records': data['records'], 'inputFingerprints': input_fingerprints(source),
            'rows': rows, 'gaps': gaps, 'sessions': sessions,
            'parameterEvidence': parameter_evidence,
            'issues': {k: v for k, v in data['issues'].items() if v},
            'abstentions': [{'stratum': list(k), 'count': v} for k, v in sorted(data['abstentions'].items())],
            'dwell': [{'stratum': list(k), 'seconds': v} for k, v in sorted(data['dwell'].items(), key=lambda item: repr(item[0]))
                      if len({(r['context']['level'], r['executionMode']) for r in by_session[k[0]]}) == 1
                      and len({(j['judgeKind'], j.get('modelVersion')) for r in by_session[k[0]] for j in r['judgements']}) <= 1],
            'exportValidated': source['kind'] == 'bundle' and source.get('manifest') is not None}


def canonical_parameter_context(parameters):
    """Absent optional wire values remain unknown; no settings are filled in."""
    return {key: parameters.get(key) for key in shadow.SCHEMA['objects']['ParameterContext']}


def input_fingerprints(source):
    return {key: source.get(key) for key in ('recordsSHA256', 'manifestSHA256')}


def summarize_parameter_samples(session, records, scope):
    """Frame-normalized speeds retain segment, settings and channel attribution."""
    groups = {}
    for record in records:
        context = record['context']
        # Even rows without channel evidence retain their actual settings.
        for index, evidence in enumerate(record['evidence'] or [None]):
            sample_scope = {**scope, 'segmentType': context['segmentType'],
                            'segmentToken': context.get('segmentToken'),
                            'parameterContext': canonical_parameter_context(record['parameters']),
                            'channel': evidence['channel'] if evidence is not None else None}
            key = json.dumps(sample_scope, sort_keys=True)
            group = groups.setdefault(key, {'scope': sample_scope, 'snapshots': {}, 'speeds': [],
                                             'unavailable': 0, 'invalid': 0})
            snapshot = {**sample_scope, 'parameters': record['parameters']}
            group['snapshots'][json.dumps(snapshot, sort_keys=True)] = snapshot
            if evidence is None:
                continue
            speed = evidence.get('subjectSpeed')
            if speed is not None:
                group['speeds'].append(speed)
            elif f'evidence[{index}].subjectSpeed' in record['invalidFields']:
                group['invalid'] += 1
            else:
                group['unavailable'] += 1
    output = []
    for key in sorted(groups):
        group = groups[key]
        speeds = group['speeds']
        mixed_model = len(scope['judgeModels']) > 1
        available = bool(speeds) and not mixed_model
        output.append({'sessionID': session, 'scope': group['scope'],
                       'snapshots': list(group['snapshots'].values()),
                       'subjectSpeed': {'reportedSamples': len(speeds),
                                        'unavailableSamples': group['unavailable'],
                                        'invalidSamples': group['invalid'],
                                        'distributionStatus': 'unavailableMixedModelScope' if mixed_model else
                                                              'observed' if speeds else 'unavailableNoSamples',
                                        'minimum': min(speeds) if available else None,
                                        'median': statistics.median(speeds) if available else None,
                                        'maximum': max(speeds) if available else None,
                                        'unit': 'normalizedFrameUnitsPerSecond'}})
    return output


def summarize_shadow_phases(path, window, bindings):
    """Version 2 explicitly binds every accepted row in original sequence space."""
    validate_evaluation({'evaluationSchemaVersion': 2, 'producer': 'DirectorReplay',
                         'runs': [], 'shadowBindings': bindings})
    records, issues, source = shadow.load_input(path)
    by_session = defaultdict(list)
    for record in records:
        by_session[record['sessionID']].append(record)
    require({b['sessionID'] for b in bindings} == set(by_session))
    assignments, phase_records = {}, {}
    declared = {b['phaseID']: b for b in bindings}
    for binding in bindings:
        phase_id, session = binding['phaseID'], binding['sessionID']
        first, last = int(binding['firstSequence']), int(binding['lastSequence'])
        rows = [r for r in by_session[session] if first <= int(r['sequence']) <= last]
        require(rows and int(rows[0]['sequence']) == first and int(rows[-1]['sequence']) == last)
        require({(r['evidenceClass'], r['context']['level'], r['executionMode']) for r in rows}
                == {(binding['evidenceClass'], binding['level'], binding['executionMode'])})
        models = {(j['judgeKind'], j.get('modelVersion')) for r in rows for j in r['judgements']}
        require(models == {(binding['judgeKind'], binding['modelVersion'])} if models else
                binding['judgeKind'] == 'unobserved' and binding['modelVersion'] is None)
        require(all(canonical_parameter_context(r['parameters']) == binding['parameterContext'] for r in rows))
        require(sorted({r['context']['routeGeneration'] for r in rows}, key=int) == binding['routeGenerations'])
        for record in rows:
            require(record['recordID'] not in assignments)
            assignments[record['recordID']] = phase_id
        phase_records[phase_id] = rows
    require(set(assignments) == {r['recordID'] for r in records})
    # Pass the complete input once. Filtering or rebasing a phase would hide
    # leading loss, invalid histories or the other half of a transition pair.
    data = shadow.analyze(records, window, issues, source, phase_assignments=assignments)
    blocked = set(data['blockedSessions'])
    rows, phases, parameter_evidence = [], [], []
    for key, counts, is_blocked in data['groups']:
        phase_id = key[-2]
        count_values = {name: counts[name] for name in ('predictions', 'completed_actions', 'compared', 'exact',
                        'unmatched_predictions', 'unmatched_actions', 'unscored_actions')}
        rows.append({'sessionID': key[0], 'phaseID': phase_id, 'binding': declared[phase_id],
                     'stratum': list(key[:-2] + (key[-1],)), 'counts': count_values,
                     'status': 'incomplete' if is_blocked or counts['unscored_actions'] else 'observed'})
    for binding in sorted(bindings, key=lambda b: (b['sessionID'], int(b['firstSequence']))):
        phase_id, session = binding['phaseID'], binding['sessionID']
        scoped_records = phase_records[phase_id]
        models = sorted({(j['judgeKind'], j.get('modelVersion')) for r in scoped_records for j in r['judgements']}, key=repr)
        scope = {key: binding[key] for key in SCHEMA['requiredBindingKeys'] if key != 'sessionID'}
        scope.update(phaseID=phase_id, routeGenerations=binding['routeGenerations'],
                     judgeModels=[list(model) for model in models])
        parameter_evidence.extend({**item, 'phaseID': phase_id}
                                  for item in summarize_parameter_samples(session, scoped_records, scope))
        phase_unscored = any(row['phaseID'] == phase_id and row['counts']['unscored_actions'] for row in rows)
        phases.append({'sessionID': session, 'phaseID': phase_id, 'binding': binding,
                       'acceptedRecords': len(scoped_records),
                       'status': 'incomplete' if session in blocked or phase_unscored else 'observed'})
    sessions = []
    for session, session_records in sorted(by_session.items()):
        scopes = {(r['evidenceClass'], r['context']['level'], r['executionMode']) for r in session_records}
        models = {(j['judgeKind'], j.get('modelVersion')) for r in session_records for j in r['judgements']}
        sessions.append({'sessionID': session, 'binding': None,
                         'phaseIDs': [p['phaseID'] for p in phases if p['sessionID'] == session],
                         'actualScopes': [list(s) for s in sorted(scopes)],
                         'judgeModels': [list(m) for m in sorted(models, key=repr)],
                         'status': 'incomplete' if session in blocked or
                                   any(p['sessionID'] == session and p['status'] == 'incomplete' for p in phases) else 'observed'})
    return {'records': data['records'], 'inputFingerprints': input_fingerprints(source),
            'bindingMode': 'explicitPhases', 'rows': rows, 'gaps': [],
            'sessions': sessions, 'phases': phases, 'parameterEvidence': parameter_evidence,
            'issues': {k: v for k, v in data['issues'].items() if v},
            'abstentions': [{'stratum': list(k), 'phaseID': k[-3], 'count': v}
                            for k, v in sorted(data['abstentions'].items(), key=lambda item: repr(item[0]))],
            'dwell': [{'stratum': list(k[:-1]), 'phaseID': k[-1], 'binding': declared[k[-1]], 'seconds': v}
                      for k, v in sorted(data['dwell'].items(), key=lambda item: repr(item[0]))],
            'exportValidated': source['kind'] == 'bundle' and source.get('manifest') is not None}


def negative_shadow_regressions(path, window):
    """Explicitly authored in-memory mutations, never relabelled live observations."""
    records, issues, _ = shadow.load_input(path)
    require(not shadow.blocking_input(issues) and records and {r['evidenceClass'] for r in records} == {'synthetic'})
    require(len({r['sessionID'] for r in records}) == 1)
    cases = [('baseline', copy.deepcopy(records))]
    predictions = [i for i, r in enumerate(records) if r['event']['kind'] in ('wouldPrepare', 'wouldCut')]
    require(predictions and len(records) >= 4)
    changed = copy.deepcopy(records)
    shot = changed[predictions[0]]['event']['shot']
    require(shot['format'] == 'stage')
    shot['preset'] = 'fullBody' if shot['preset'] != 'fullBody' else 'waistUp'
    cases.append(('wrongPredictedPreset', changed))
    changed = copy.deepcopy(records); changed[3]['droppedRecordsBefore'] = '1'; cases.append(('reportedDrop', changed))
    changed = copy.deepcopy(records)
    for row in changed[3:]:
        row['sequence'] = str(int(row['sequence']) + 1)
    cases.append(('sequenceGap', changed))
    cases.append(('orphanAttempt', copy.deepcopy(records[:2])))
    changed = copy.deepcopy(records)
    result = next(r for r in changed if r['event']['kind'] == 'operatorAction' and r['event']['phase'] == 'result' and r['event']['action'] == 'take')
    result['context'].pop('programShot', None); cases.append(('unknownPostTakeShot', changed))
    cases.append(('empty', []))
    output = []
    for name, rows in cases:
        raw = ('\n'.join(json.dumps(r) for r in rows) + ('\n' if rows else '')).encode()
        accepted, row_issues = shadow.load_records(io.BytesIO(raw))
        data = shadow.analyze(accepted, window, row_issues)
        counts = {metric: sum(s[metric] for _, s, _ in data['groups']) for metric in
                  ('predictions', 'completed_actions', 'compared', 'exact', 'unscored_actions', 'unmatched_predictions', 'unmatched_actions')}
        output.append({'case': name, 'evidenceClass': 'synthetic', 'counts': counts,
                       'dwellSeconds': [v for values in data['dwell'].values() for v in values],
                       'issues': {k: v for k, v in data['issues'].items() if v},
                       'status': 'incomplete' if not accepted or counts['unscored_actions'] or any(b for _, _, b in data['groups']) else 'observed'})
    return output


def evaluate(value, digest=None, shadow_data=None, regressions=None):
    validate_evaluation(value)
    runs = []
    for run in value['runs']:
        metrics = run['metrics']
        critical = (metrics['staleEffectsCommitted'] + metrics['programChangesWithoutAuthority']
                    + metrics['minimumDurationViolations'] + metrics['proposalsMadeWhilePaused'])
        warnings = []
        if metrics['wrongSubjectProposals']:
            warnings.append('wrongSubjectProposalObserved')
        if metrics['wrongSubjectAttempts']:
            warnings.append('wrongSubjectAttemptObserved')
        runs.append({**run, 'partition': list(partition(run)),
                     'softwareStatus': 'criticalObservation' if critical else 'observed', 'warnings': warnings,
                     'usefulPreparationCoverage': None, 'wrongCommittedPreparationRate': None,
                     'qualificationStatus': 'incomplete'})
    levels = [{'level': level, 'syntheticScenarios': sum(r['level'] == level for r in runs),
               'status': 'incomplete' if any(r['level'] == level for r in runs) else 'notRun',
               'directLiveRoute': 'notRun', 'virtualCameraLiveRoute': 'notRun'} for level in SCHEMA['levels']]
    return {'evaluationSchemaVersion': value['evaluationSchemaVersion'], 'inputSHA256': digest, 'qualified': False,
            'qualificationStatus': 'incomplete', 'runs': runs, 'levels': levels,
            'shadow': shadow_data, 'shadowRegressions': regressions or [],
            'missingEvidence': ['ownerFrozenPlanAndBudgets', 'independentEligibleOpportunityLabels',
                                'labelledCommittedPreparationOutcomes', 'recordedValidation',
                                'r2RigEvidence', 'bothObservedLiveOutputRoutes', 'perLevelSignatories'],
            'structuralZeros': ['DirectorReplay.directorCuts'],
            'unavailableMeasurements': ['visibleOverrideLatency', 'downstreamPresentation', 'usefulPreparationCoverage']}


def fraction(numerator, denominator):
    return f'{numerator}/{denominator}' if denominator else 'unavailable (0 labelled)'


def markdown(result):
    lines = ['# Director evaluation observations', '',
             '**Synthetic software evidence. Qualification incomplete; no operating permission or parameter recommendation.**', '',
             f'Input SHA-256: `{result["inputSHA256"] or "unavailable"}`.', '',
             'Every scenario is kept in its own session, level, evidence, execution, route, configuration, parameter and judge/model partition. Rates are not pooled.', '',
             '| Level | Synthetic scenarios | Assessment | Direct live output | Virtual Camera live output |',
             '| --- | ---: | --- | --- | --- |']
    if result.get('shadowBindingSHA256'):
        lines[6:6] = [f'Shadow sidecar SHA-256: `{result["shadowBindingSHA256"]}`.', '']
    for row in result['levels']:
        lines.append(f'| {row["level"]} | {row["syntheticScenarios"]} | {row["status"]} | {row["directLiveRoute"]} | {row["virtualCameraLiveRoute"]} |')
    lines += ['', '## Actual replay scenario measurements', '',
              'Wrong proposals and attempts are separate from commits. The replay does not label committed subject correctness or independent useful opportunities.', '',
              '| Scenario | Attempted / committed preparations | Wrong / labelled proposals | Wrong / labelled attempts | Stale commits / all commits | Operator cuts / attempts | Overrides honoured | UI latency | Software observation |',
              '| --- | --- | --- | --- | --- | --- | ---: | --- | --- |']
    partitions = []
    for run in result['runs']:
        m = run['metrics']
        lines.append(f'| {run["scenarioID"]} | {m["directorAttemptCount"]} / {m["preparationsCommitted"]} | {fraction(m["wrongSubjectProposals"], m["labelledSubjectProposals"])} | {fraction(m["wrongSubjectAttempts"], m["labelledSubjectAttempts"])} | {fraction(m["staleEffectsCommitted"], m["preparationsCommitted"])} | {m["operatorCuts"]} / {m["operatorTakeAttempts"]} | {m["manualOverridesHonoured"]} | unavailable | {run["softwareStatus"]}{"; " + ", ".join(run["warnings"]) if run["warnings"] else ""} |')
        partitions.append(f'- {run["scenarioID"]}: `{run["sessionID"]}` / {run["evidenceClass"]} / {run["level"]} / {run["executionMode"]} / route {run["route"]} / {run["configurationID"]} / parameters {run["parameterVersion"]} / {run["judgeKind"]}:{run["modelVersion"] or "none"}. Synthetic timeline: {run["durationSeconds"]:g} s. Rejection reasons: `{json.dumps(m["staleProposalsRejected"], sort_keys=True)}`.')
    lines += ['', *partitions]
    if not result['runs']:
        lines.append('No replay scenarios supplied; all measurements unavailable.')
    else:
        lines += ['', '| Scenario | Unauthorized Program changes | Minimum-duration violations | Proposals while paused | Oscillations | Failed effects | Rejected attempts | Clock anomalies |',
                  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
        for run in result['runs']:
            m = run['metrics']
            lines.append(f'| {run["scenarioID"]} | {m["programChangesWithoutAuthority"]} | {m["minimumDurationViolations"]} | {m["proposalsMadeWhilePaused"]} | {m["oscillations"]} | {m["failedEffects"]} | {m["rejectedAttempts"]} | {m["clockAnomalies"]} |')
    lines += ['', 'DirectorReplay has no Take entry point. Its zero Director cuts is structural and does not demonstrate Auto or Backup cut safety. Synthetic timeline seconds are not live exposure.',
              'Useful-preparation coverage, wrong committed-subject rate, visible override latency and downstream presentation are unavailable. Missing values are never replaced with zero.', '']
    if result['shadow'] is not None:
        data = result['shadow']
        lines += ['', *shadow.fingerprint_lines(data['inputFingerprints'])]
        lines += ['## C-05 shadow observations', '', f'Accepted records: {data["records"]}. Explicit export validated: {str(data["exportValidated"]).lower()}.', '',
                  'Agreement describes operator matching, not independent correctness. Bindings are declared evaluation scope, not verified physical-route observations.', '',
                  '| Session | Scope | Exact / compared | Predictions | Unmatched predictions | Unmatched actions | Unscored actions | Status |',
                  '| --- | --- | --- | ---: | ---: | ---: | ---: | --- |']
        for row in data['rows']:
            c, b = row['counts'], row['binding']
            scope = 'unbound' if b is None else ' / '.join(str(b[k]) for k in SCHEMA['requiredBindingKeys'][1:])
            agreement = fraction(c.get('exact'), c.get('compared')) if c.get('compared') is not None else 'unavailable'
            label = row['sessionID'] + (f' / phase {row["phaseID"]}' if 'phaseID' in row else '')
            lines.append(f'| {label} | {scope} | {agreement} | {c.get("predictions", 0)} | {c.get("unmatched_predictions", 0)} | {c.get("unmatched_actions", 0)} | {c.get("unscored_actions", 0)} | {row["status"]} |')
        if not data['rows']:
            lines.append('No comparison opportunities observed; agreement is unavailable.')
        lines.append('')
        for item in data['sessions']:
            lines.append(f'- Session `{item["sessionID"]}`: actual scopes `{json.dumps(item["actualScopes"])}`, judge/models `{json.dumps(item["judgeModels"])}`; scope {item["status"]}.')
        if data.get('bindingMode') == 'explicitPhases':
            lines += ['', 'Version 2 phases cover accepted records once in their original inclusive sequence spans. Full-session capture and pair checks remain in force. Physical routes are unverified declared labels; route generations are observed metadata. No agreement or dwell crosses a phase boundary.', '']
            for item in data['phases']:
                b = item['binding']
                lines.append(f'- Phase `{item["phaseID"]}` / session `{item["sessionID"]}`: original sequences {b["firstSequence"]}–{b["lastSequence"]}, {item["acceptedRecords"]} accepted records; route generations `{json.dumps(b["routeGenerations"])}`; scope {item["status"]}.')
        for item in data['abstentions']:
            lines.append(f'- Abstention reasons {" / ".join(str(x) for x in item["stratum"])}: {item["count"]}. Reasons are not independent opportunities.')
        for item in data['dwell']:
            values = item['seconds']
            phase = f' / phase {item["phaseID"]}' if 'phaseID' in item else ''
            lines.append(f'- Interior dwell `{json.dumps(item["stratum"])}`{phase}: n={len(values)}, min={min(values):g}, median={statistics.median(values):g}, max={max(values):g} s. Censored first/last holds excluded.')
        if not data['dwell']:
            lines.append('Interior dwell unavailable.')
        lines.append(f'Completeness issues: `{json.dumps(data["issues"], sort_keys=True)}`. Scope gaps: `{json.dumps(data["gaps"], sort_keys=True)}`. Zero reported loss does not prove full capture.')
    if result['shadowRegressions']:
        lines += ['', '## Authored synthetic C-05 regression matrix', '',
                  'These in-memory fixture mutations exercise analysis behavior; they are not camera or sink observations.', '',
                  '| Case | Predictions | Completed operator actions | Compared | Exact | Unscored actions | Interior dwell seconds | Capture status |',
                  '| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |']
        for row in result['shadowRegressions']:
            c = row['counts']
            lines.append(f'| {row["case"]} | {c["predictions"]} | {c["completed_actions"]} | {c["compared"]} | {c["exact"]} | {c["unscored_actions"]} | {", ".join(f"{v:g}" for v in row["dwellSeconds"]) or "unavailable"} | {row["status"]} |')
    lines += ['', '## Missing assessment evidence', '']
    lines += [f'- {item}' for item in result['missingEvidence']]
    lines += ['', 'Assist, Auto and Backup remain incomplete without their required real evidence and explicit owner, event-operator and independent-reviewer sign-off. This tool never creates a qualification record.', '']
    return '\n'.join(lines)


def parameter_memo(result):
    lines = ['# Observed parameter evidence — AWAITING OWNER', '',
             'Synthetic fixture settings and observed metadata only. No numeric recommendation, tuning choice, approved bar or qualification is derived here.', '',
             'Configured durations, movement bounds and rates describe test inputs; they are not measured subject speed or measured notice/on-air behavior.', '']
    lines += [f'Evaluation input SHA-256: `{result["inputSHA256"] or "unavailable"}`.', '']
    if result.get('shadowBindingSHA256'):
        lines += [f'Shadow sidecar SHA-256: `{result["shadowBindingSHA256"]}`.', '']
    for run in result['runs']:
        lines += [f'## {run["scenarioID"]} / {run["configurationID"]}', '',
                  '```json', json.dumps(run['parameters'], sort_keys=True, indent=2), '```', '']
    if result['shadow'] is not None:
        lines += shadow.fingerprint_lines(result['shadow']['inputFingerprints'])
        for item in result['shadow']['parameterEvidence']:
            phase = f' / phase {item["phaseID"]}' if 'phaseID' in item else ''
            lines += [f'## Shadow session {item["sessionID"]}{phase}', '',
                      'Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:', '',
                      '```json', json.dumps(item['scope'], sort_keys=True, indent=2), '```', '',
                      'Actual recorded parameter snapshots (configured inputs, not measured outcomes):', '',
                      '```json', json.dumps(item['snapshots'], sort_keys=True, indent=2), '```', '',
                      'Observed subject-speed metadata; repeated samples are not independent opportunities:', '',
                      '```json', json.dumps(item['subjectSpeed'], sort_keys=True, indent=2), '```', '']
    lines += ['Notice-length observations are unavailable in the supported records. On-air move rate is reported only when an actual shadow parameter snapshot contains it; configured rate does not establish achieved motion. Useful-opportunity and live-baseline evidence is missing; T1–T3, N4, P3, A4 and N2 recommendations remain pending.', '']
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--shadow-bundle', type=Path)
    parser.add_argument('--shadow-sidecar', type=Path)
    parser.add_argument('--regression-fixture', type=Path)
    parser.add_argument('--match-window-seconds', type=float)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--json-output', type=Path)
    parser.add_argument('--parameter-memo', type=Path)
    args = parser.parse_args(argv)
    if args.shadow_bundle or args.regression_fixture:
        if args.match_window_seconds is None or not math.isfinite(args.match_window_seconds) or args.match_window_seconds < 0:
            parser.error('shadow analysis requires a finite, nonnegative supplied matching window')
    try:
        value, digest = load_evaluation(args.input)
        bindings = value['shadowBindings']
        binding_digest = None
        if args.shadow_sidecar:
            require(args.shadow_bundle is not None and not bindings)
            with args.shadow_sidecar.open('rb') as stream:
                raw_sidecar = stream.read(MAX_BYTES + 1)
            require(len(raw_sidecar) <= MAX_BYTES)
            sidecar = shadow.strict_json(raw_sidecar)
            exact(sidecar, ['evaluationSchemaVersion', 'shadowBindings'])
            candidate = {**value, **sidecar}
            validate_evaluation(candidate)
            value = candidate
            bindings = sidecar['shadowBindings']
            binding_digest = hashlib.sha256(raw_sidecar).hexdigest()
        data = summarize_shadow(args.shadow_bundle, args.match_window_seconds, bindings,
                                binding_schema_version=value['evaluationSchemaVersion']) if args.shadow_bundle else None
        regressions = negative_shadow_regressions(args.regression_fixture, args.match_window_seconds) if args.regression_fixture else []
        result = evaluate(value, digest, data, regressions)
        if binding_digest is not None or value['evaluationSchemaVersion'] == 2:
            result['shadowBindingSHA256'] = binding_digest
        outputs = []
        if args.output:
            outputs.append((args.output, markdown(result)))
        if args.json_output:
            outputs.append((args.json_output, json.dumps(result, sort_keys=True, indent=2) + '\n'))
        if args.parameter_memo:
            outputs.append((args.parameter_memo, parameter_memo(result)))
        require(len({str(path.resolve()) for path, _ in outputs}) == len(outputs))
        if any(path.exists() for path, _ in outputs):
            raise FileExistsError()
        for path, content in outputs:
            with path.open('x', encoding='utf-8') as stream:
                stream.write(content)
        if not args.output:
            sys.stdout.write(markdown(result))
        return 0
    except (ValueError, TypeError, KeyError, OverflowError, RecursionError, UnicodeError):
        print('Invalid evaluation metadata; no qualification or assessment produced.', file=sys.stderr)
        return 2
    except OSError:
        print('Input/output unavailable; existing artifacts are never overwritten.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
