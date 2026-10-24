# Observed parameter evidence — AWAITING OWNER

Synthetic fixture settings and observed metadata only. No numeric recommendation, tuning choice, approved bar or qualification is derived here.

Configured durations, movement bounds and rates describe test inputs; they are not measured subject speed or measured notice/on-air behavior.

## calm-presenter / replay-study-1

```json
{
  "readiness": {
    "cutOnMotionAllowed": false,
    "maximumCutMotion": 0.1,
    "maximumMotion": 0.1,
    "minimumCutSettledTime": 0.2,
    "minimumSettledTime": 0.2
  },
  "replay": {
    "maximumEvidenceAge": 5,
    "maximumProposalAge": 5
  },
  "shotPolicy": {
    "cutOnMotionAllowed": false,
    "maximumMovement": 0.1,
    "maximumShotDuration": 35,
    "minimumShotDuration": 8,
    "repetitionWindow": 20,
    "wideCadence": 90
  }
}
```

## walking-presenter / replay-study-1

```json
{
  "readiness": {
    "cutOnMotionAllowed": false,
    "maximumCutMotion": 0.1,
    "maximumMotion": 0.1,
    "minimumCutSettledTime": 0.2,
    "minimumSettledTime": 0.2
  },
  "replay": {
    "maximumEvidenceAge": 5,
    "maximumProposalAge": 5
  },
  "shotPolicy": {
    "cutOnMotionAllowed": false,
    "maximumMovement": 0.1,
    "maximumShotDuration": 35,
    "minimumShotDuration": 8,
    "repetitionWindow": 20,
    "wideCadence": 90
  }
}
```

## panel-of-three / replay-study-1

```json
{
  "readiness": {
    "cutOnMotionAllowed": false,
    "maximumCutMotion": 0.1,
    "maximumMotion": 0.1,
    "minimumCutSettledTime": 0.2,
    "minimumSettledTime": 0.2
  },
  "replay": {
    "maximumEvidenceAge": 5,
    "maximumProposalAge": 5
  },
  "shotPolicy": {
    "cutOnMotionAllowed": false,
    "maximumMovement": 0.1,
    "maximumShotDuration": 35,
    "minimumShotDuration": 8,
    "repetitionWindow": 20,
    "wideCadence": 90
  }
}
```

## camera-b-drops / replay-study-1

```json
{
  "readiness": {
    "cutOnMotionAllowed": false,
    "maximumCutMotion": 0.1,
    "maximumMotion": 0.1,
    "minimumCutSettledTime": 0.2,
    "minimumSettledTime": 0.2
  },
  "replay": {
    "maximumEvidenceAge": 5,
    "maximumProposalAge": 5
  },
  "shotPolicy": {
    "cutOnMotionAllowed": false,
    "maximumMovement": 0.1,
    "maximumShotDuration": 35,
    "minimumShotDuration": 8,
    "repetitionWindow": 20,
    "wideCadence": 90
  }
}
```

## operator-intervention / replay-study-1

```json
{
  "readiness": {
    "cutOnMotionAllowed": false,
    "maximumCutMotion": 0.1,
    "maximumMotion": 0.1,
    "minimumCutSettledTime": 0.2,
    "minimumSettledTime": 0.2
  },
  "replay": {
    "maximumEvidenceAge": 5,
    "maximumProposalAge": 5
  },
  "shotPolicy": {
    "cutOnMotionAllowed": false,
    "maximumMovement": 0.1,
    "maximumShotDuration": 35,
    "minimumShotDuration": 8,
    "repetitionWindow": 20,
    "wideCadence": 90
  }
}
```

## Shadow session 73CA8376-001F-5EB7-B23C-AD2FA2F82A33

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [],
  "level": "suggest"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [],
    "level": "suggest",
    "parameters": {
      "parametersVersion": "1",
      "preferencesVersion": 2,
      "resolvedStyle": {
        "cutOnMotionAllowed": false,
        "maximumMovement": 0.2,
        "minimumShotDuration": 8,
        "onAirMoveRate": 0.1,
        "preferredShotDuration": 20,
        "repetitionWindow": 10,
        "settleTime": 1,
        "softMaximumShotDuration": 40,
        "wideCadence": 90
      },
      "status": "available"
    },
    "segmentType": "presenter"
  }
]
```

Observed subject-speed metadata; repeated samples are not independent opportunities:

```json
{
  "distributionStatus": "unavailableNoSamples",
  "invalidSamples": 0,
  "maximum": null,
  "median": null,
  "minimum": null,
  "reportedSamples": 0,
  "unavailableSamples": 0,
  "unit": "normalizedFrameUnitsPerSecond"
}
```

Notice-length observations are unavailable in the supported records. On-air move rate is reported only when an actual shadow parameter snapshot contains it; configured rate does not establish achieved motion. Useful-opportunity and live-baseline evidence is missing; T1–T3, N4, P3, A4 and N2 recommendations remain pending.
