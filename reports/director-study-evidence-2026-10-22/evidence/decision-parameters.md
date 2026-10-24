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

## Shadow session 7FB628A4-40A4-41F0-8374-EF784F8337B8 / phase capture-decision-1

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "configurationID": "capture-decision-1-config",
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeKind": "unobserved",
  "judgeModels": [],
  "level": "off",
  "modelVersion": null,
  "parameterVersion": null,
  "phaseID": "capture-decision-1",
  "route": "none",
  "routeGenerations": [
    "0"
  ]
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "configurationID": "capture-decision-1-config",
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeKind": "unobserved",
    "judgeModels": [],
    "level": "off",
    "modelVersion": null,
    "parameterVersion": null,
    "parameters": {
      "preferencesVersion": 2,
      "status": "unavailable"
    },
    "phaseID": "capture-decision-1",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentType": "liveEvent"
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

## Shadow session 7FB628A4-40A4-41F0-8374-EF784F8337B8 / phase capture-decision-2

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "configurationID": "capture-decision-2-config",
  "evidenceClass": "synthetic",
  "executionMode": "observing",
  "judgeKind": "unobserved",
  "judgeModels": [],
  "level": "assist",
  "modelVersion": null,
  "parameterVersion": null,
  "phaseID": "capture-decision-2",
  "route": "none",
  "routeGenerations": [
    "0"
  ]
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "configurationID": "capture-decision-2-config",
    "evidenceClass": "synthetic",
    "executionMode": "observing",
    "judgeKind": "unobserved",
    "judgeModels": [],
    "level": "assist",
    "modelVersion": null,
    "parameterVersion": null,
    "parameters": {
      "preferencesVersion": 2,
      "status": "unavailable"
    },
    "phaseID": "capture-decision-2",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentType": "liveEvent"
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

## Shadow session 7FB628A4-40A4-41F0-8374-EF784F8337B8 / phase capture-decision-3

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "configurationID": "capture-decision-3-config",
  "evidenceClass": "synthetic",
  "executionMode": "observing",
  "judgeKind": "unobserved",
  "judgeModels": [],
  "level": "assist",
  "modelVersion": null,
  "parameterVersion": "10",
  "phaseID": "capture-decision-3",
  "route": "none",
  "routeGenerations": [
    "0"
  ]
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "configurationID": "capture-decision-3-config",
    "evidenceClass": "synthetic",
    "executionMode": "observing",
    "judgeKind": "unobserved",
    "judgeModels": [],
    "level": "assist",
    "modelVersion": null,
    "parameterVersion": "10",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "parametersVersion": "10",
      "preferencesVersion": 2,
      "readiness": {
        "cutOnMotionAllowed": false,
        "maximumCutMotion": 0.1,
        "maximumMotion": 0.2,
        "minimumCutSettledTime": 0,
        "minimumSettledTime": 0
      },
      "resolvedStyle": {
        "cutOnMotionAllowed": false,
        "maximumMovement": 0.2,
        "minimumShotDuration": 1,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 2,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "phaseID": "capture-decision-3",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentType": "liveEvent"
  }
]
```

Observed subject-speed metadata; repeated samples are not independent opportunities:

```json
{
  "distributionStatus": "observed",
  "invalidSamples": 0,
  "maximum": 0,
  "median": 0,
  "minimum": 0,
  "reportedSamples": 1,
  "unavailableSamples": 0,
  "unit": "normalizedFrameUnitsPerSecond"
}
```

## Shadow session 7FB628A4-40A4-41F0-8374-EF784F8337B8 / phase capture-decision-4

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "configurationID": "capture-decision-4-config",
  "evidenceClass": "synthetic",
  "executionMode": "observing",
  "judgeKind": "unobserved",
  "judgeModels": [],
  "level": "assist",
  "modelVersion": null,
  "parameterVersion": null,
  "phaseID": "capture-decision-4",
  "route": "none",
  "routeGenerations": [
    "0"
  ]
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "configurationID": "capture-decision-4-config",
    "evidenceClass": "synthetic",
    "executionMode": "observing",
    "judgeKind": "unobserved",
    "judgeModels": [],
    "level": "assist",
    "modelVersion": null,
    "parameterVersion": null,
    "parameters": {
      "preferencesVersion": 2,
      "status": "unavailable"
    },
    "phaseID": "capture-decision-4",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentType": "liveEvent"
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

## Shadow session 7FB628A4-40A4-41F0-8374-EF784F8337B8 / phase capture-decision-5

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "configurationID": "capture-decision-5-config",
  "evidenceClass": "synthetic",
  "executionMode": "observing",
  "judgeKind": "unobserved",
  "judgeModels": [],
  "level": "assist",
  "modelVersion": null,
  "parameterVersion": "11",
  "phaseID": "capture-decision-5",
  "route": "none",
  "routeGenerations": [
    "0"
  ]
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "configurationID": "capture-decision-5-config",
    "evidenceClass": "synthetic",
    "executionMode": "observing",
    "judgeKind": "unobserved",
    "judgeModels": [],
    "level": "assist",
    "modelVersion": null,
    "parameterVersion": "11",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "parametersVersion": "11",
      "preferencesVersion": 2,
      "readiness": {
        "cutOnMotionAllowed": false,
        "maximumCutMotion": 0.1,
        "maximumMotion": 0.2,
        "minimumCutSettledTime": 0,
        "minimumSettledTime": 0
      },
      "resolvedStyle": {
        "cutOnMotionAllowed": false,
        "maximumMovement": 0.2,
        "minimumShotDuration": 1,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 2,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "phaseID": "capture-decision-5",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentType": "liveEvent"
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

## Shadow session 7FB628A4-40A4-41F0-8374-EF784F8337B8 / phase capture-decision-6

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "configurationID": "capture-decision-6-config",
  "evidenceClass": "synthetic",
  "executionMode": "observing",
  "judgeKind": "rules",
  "judgeModels": [
    [
      "rules",
      null
    ]
  ],
  "level": "auto",
  "modelVersion": null,
  "parameterVersion": "11",
  "phaseID": "capture-decision-6",
  "route": "none",
  "routeGenerations": [
    "0",
    "1"
  ]
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "configurationID": "capture-decision-6-config",
    "evidenceClass": "synthetic",
    "executionMode": "observing",
    "judgeKind": "rules",
    "judgeModels": [
      [
        "rules",
        null
      ]
    ],
    "level": "auto",
    "modelVersion": null,
    "parameterVersion": "11",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "parametersVersion": "11",
      "preferencesVersion": 2,
      "readiness": {
        "cutOnMotionAllowed": false,
        "maximumCutMotion": 0.1,
        "maximumMotion": 0.2,
        "minimumCutSettledTime": 0,
        "minimumSettledTime": 0
      },
      "resolvedStyle": {
        "cutOnMotionAllowed": false,
        "maximumMovement": 0.2,
        "minimumShotDuration": 1,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 2,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "phaseID": "capture-decision-6",
    "route": "none",
    "routeGenerations": [
      "0",
      "1"
    ],
    "segmentType": "liveEvent"
  }
]
```

Observed subject-speed metadata; repeated samples are not independent opportunities:

```json
{
  "distributionStatus": "observed",
  "invalidSamples": 0,
  "maximum": 0,
  "median": 0,
  "minimum": 0,
  "reportedSamples": 1,
  "unavailableSamples": 0,
  "unit": "normalizedFrameUnitsPerSecond"
}
```

Notice-length observations are unavailable in the supported records. On-air move rate is reported only when an actual shadow parameter snapshot contains it; configured rate does not establish achieved motion. Useful-opportunity and live-baseline evidence is missing; T1–T3, N4, P3, A4 and N2 recommendations remain pending.
