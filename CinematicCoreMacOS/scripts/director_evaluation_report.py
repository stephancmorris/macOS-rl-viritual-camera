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
    require(type(value['evaluationSchemaVersion']) is int and value['evaluationSchemaVersion'] == 1)
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
    binding_sessions = set()
    for binding in value['shadowBindings']:
        exact(binding, SCHEMA['requiredBindingKeys']); validate_scope(binding)
        require(binding['sessionID'] not in binding_sessions)
        binding_sessions.add(binding['sessionID'])
    return value


def load_evaluation(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    require(len(raw) <= MAX_BYTES)
    return validate_evaluation(shadow.strict_json(raw)), hashlib.sha256(raw).hexdigest()


def summarize_shadow(path, window, bindings):
    records, issues, source = shadow.load_input(path)
    data = shadow.analyze(records, window, issues, source)
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
                         'status': 'incomplete' if scope_problem or binding is None else 'observed'})
        parameter_scopes = defaultdict(list)
        for record in records_in_session:
            record_models = tuple(sorted({(j['judgeKind'], j.get('modelVersion')) for j in record['judgements']}, key=repr))
            parameter_scopes[(record['evidenceClass'], record['context']['level'], record['executionMode'], record_models)].append(record)
        for scope_key, scoped_records in sorted(parameter_scopes.items(), key=lambda item: repr(item[0])):
            scope = {'evidenceClass': scope_key[0], 'level': scope_key[1], 'executionMode': scope_key[2],
                     'judgeModels': [list(model) for model in scope_key[3]]}
            snapshots = {}
            speeds, unavailable_speeds, invalid_speeds = [], 0, 0
            for record in scoped_records:
                snapshot = {**scope, 'segmentType': record['context']['segmentType'], 'parameters': record['parameters']}
                snapshots[json.dumps(snapshot, sort_keys=True)] = snapshot
                for index, evidence in enumerate(record['evidence']):
                    speed = evidence.get('subjectSpeed')
                    if speed is not None:
                        speeds.append(speed)
                    elif f'evidence[{index}].subjectSpeed' in record['invalidFields']:
                        invalid_speeds += 1
                    else:
                        unavailable_speeds += 1
            # Multiple judge/model identities on one record cannot be attributed
            # to a single model. Preserve sample counts but suppress distributions.
            distribution_available = bool(speeds) and len(scope_key[3]) <= 1
            distribution_status = ('unavailableMixedModelScope' if len(scope_key[3]) > 1 else
                                   'observed' if speeds else 'unavailableNoSamples')
            parameter_evidence.append({'sessionID': session, 'scope': scope, 'snapshots': list(snapshots.values()),
                                       'subjectSpeed': {'reportedSamples': len(speeds), 'unavailableSamples': unavailable_speeds,
                                                        'invalidSamples': invalid_speeds, 'distributionStatus': distribution_status,
                                                        'minimum': min(speeds) if distribution_available else None,
                                                        'median': statistics.median(speeds) if distribution_available else None,
                                                        'maximum': max(speeds) if distribution_available else None,
                                                        'unit': 'normalizedFrameUnitsPerSecond'}})
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
    return {'records': data['records'], 'rows': rows, 'gaps': gaps, 'sessions': sessions,
            'parameterEvidence': parameter_evidence,
            'issues': {k: v for k, v in data['issues'].items() if v},
            'abstentions': [{'stratum': list(k), 'count': v} for k, v in sorted(data['abstentions'].items())],
            'dwell': [{'stratum': list(k), 'seconds': v} for k, v in sorted(data['dwell'].items(), key=lambda item: repr(item[0]))
                      if len({(r['context']['level'], r['executionMode']) for r in by_session[k[0]]}) == 1
                      and len({(j['judgeKind'], j.get('modelVersion')) for r in by_session[k[0]] for j in r['judgements']}) <= 1],
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
    return {'evaluationSchemaVersion': 1, 'inputSHA256': digest, 'qualified': False,
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
        lines += ['## C-05 shadow observations', '', f'Accepted records: {data["records"]}. Explicit export validated: {str(data["exportValidated"]).lower()}.', '',
                  'Agreement describes operator matching, not independent correctness. Bindings are declared evaluation scope, not verified physical-route observations.', '',
                  '| Session | Scope | Exact / compared | Predictions | Unmatched predictions | Unmatched actions | Unscored actions | Status |',
                  '| --- | --- | --- | ---: | ---: | ---: | ---: | --- |']
        for row in data['rows']:
            c, b = row['counts'], row['binding']
            scope = 'unbound' if b is None else ' / '.join(str(b[k]) for k in SCHEMA['requiredBindingKeys'][1:])
            agreement = fraction(c.get('exact'), c.get('compared')) if c.get('compared') is not None else 'unavailable'
            lines.append(f'| {row["sessionID"]} | {scope} | {agreement} | {c.get("predictions", 0)} | {c.get("unmatched_predictions", 0)} | {c.get("unmatched_actions", 0)} | {c.get("unscored_actions", 0)} | {row["status"]} |')
        if not data['rows']:
            lines.append('No comparison opportunities observed; agreement is unavailable.')
        lines.append('')
        for item in data['sessions']:
            lines.append(f'- Session `{item["sessionID"]}`: actual scopes `{json.dumps(item["actualScopes"])}`, judge/models `{json.dumps(item["judgeModels"])}`; scope {item["status"]}.')
        for item in data['abstentions']:
            lines.append(f'- Abstention reasons {" / ".join(str(x) for x in item["stratum"])}: {item["count"]}. Reasons are not independent opportunities.')
        for item in data['dwell']:
            values = item['seconds']
            lines.append(f'- Interior dwell `{json.dumps(item["stratum"])}`: n={len(values)}, min={min(values):g}, median={statistics.median(values):g}, max={max(values):g} s. Censored first/last holds excluded.')
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
    for run in result['runs']:
        lines += [f'## {run["scenarioID"]} / {run["configurationID"]}', '',
                  '```json', json.dumps(run['parameters'], sort_keys=True, indent=2), '```', '']
    if result['shadow'] is not None:
        for item in result['shadow']['parameterEvidence']:
            lines += [f'## Shadow session {item["sessionID"]}', '',
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
        if args.shadow_sidecar:
            require(args.shadow_bundle is not None and not bindings)
            with args.shadow_sidecar.open('rb') as stream:
                raw_sidecar = stream.read(MAX_BYTES + 1)
            require(len(raw_sidecar) <= MAX_BYTES)
            sidecar = shadow.strict_json(raw_sidecar)
            exact(sidecar, ['evaluationSchemaVersion', 'shadowBindings'])
            candidate = {**value, **sidecar}
            validate_evaluation(candidate)
            bindings = sidecar['shadowBindings']
        data = summarize_shadow(args.shadow_bundle, args.match_window_seconds, bindings) if args.shadow_bundle else None
        regressions = negative_shadow_regressions(args.regression_fixture, args.match_window_seconds) if args.regression_fixture else []
        result = evaluate(value, digest, data, regressions)
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
