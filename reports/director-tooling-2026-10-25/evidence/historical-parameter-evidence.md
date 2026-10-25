# Observed parameter evidence — AWAITING OWNER

Synthetic fixture settings and observed metadata only. No numeric recommendation, tuning choice, approved bar or qualification is derived here.

Configured durations, movement bounds and rates describe test inputs; they are not measured subject speed or measured notice/on-air behavior.

Evaluation input SHA-256: `0789608de68a766193538a10bf270f0dc038d434a8676b271d3547395d4d58d7`.

Shadow sidecar SHA-256: `c07bfbc0f242c801179b6cf37b6434419154b26600d91c44aba7e22039989173`.

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

Records SHA-256: `d913c617a0986462502228fe7f4efee3c9471f489c168f0175f9859436df3ed2`.
Manifest SHA-256: `2cfe8be808bd39dbe4794a28bef4685dd8a33394c16e1a047fe9d502fef54958`.
Fingerprints identify consumed bytes, not consent, complete capture or qualification. Partial bounded reads have no full-file fingerprint.

## Shadow session 73CA8376-001F-5EB7-B23C-AD2FA2F82A33

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [],
  "level": "suggest",
  "parameterContext": {
    "adapter": null,
    "judgeMaximumAge": null,
    "minimumProbability": null,
    "parametersVersion": "1",
    "preferencesVersion": 2,
    "readiness": null,
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
  "segmentToken": null,
  "segmentType": "presenter"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [],
    "level": "suggest",
    "parameterContext": {
      "adapter": null,
      "judgeMaximumAge": null,
      "minimumProbability": null,
      "parametersVersion": "1",
      "preferencesVersion": 2,
      "readiness": null,
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
    "segmentToken": null,
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
