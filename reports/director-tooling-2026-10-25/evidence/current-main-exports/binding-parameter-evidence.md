# Observed parameter evidence — AWAITING OWNER

Exported replay settings and shadow metadata only. No numeric recommendation, tuning choice, approved bar or qualification is derived here.

Configured durations, movement bounds and rates describe test inputs; they are not measured subject speed or measured notice/on-air behavior.

## Supplied evidence inventory

| Input unit | Declared evidence class | Accepted count |
| --- | --- | ---: |
| Replay scenarios | synthetic | 5 |
| Shadow records | synthetic | 6 |

Counts retain their input units and declared classes. They do not authenticate collection, establish exposure or prove complete capture.

Evaluation input SHA-256: `fbbe869ba9ad3014afcda1413a7800892dc7a08fea59745021bbe4456711139d`.

Shadow sidecar SHA-256: `7a0a129d291d77a5b40185eb69499c23a0e3e264b1ca42c5c3077340f95b954f`.

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

Records SHA-256: `c6a9a80707e404428924f290e12c202078e1799271a8f27136f28d7cdbd4cda5`.
Manifest SHA-256: `fb395d017164a387d437f5b6bc166662deeb4a47b36290ad3513cd3c43a71828`.
Fingerprints identify consumed bytes, not consent, complete capture or qualification. Partial bounded reads have no full-file fingerprint.

Matching window: 2 seconds (supplied). This is an analysis setting, not a directing recommendation.

## Shadow session C9F2A03B-869C-42F8-A3F0-07D5460025EC / phase capture-binding-1

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": "input-2",
  "configurationID": "capture-binding-1-config",
  "declaredJudgeKind": "rules",
  "declaredModelVersion": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [],
  "level": "off",
  "parameterContext": {
    "adapter": {
      "debounce": 0,
      "maximumObservationAge": 2,
      "stillSpeed": 0.2
    },
    "judgeMaximumAge": 1,
    "minimumProbability": 0.7,
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
  "parameterVersion": "10",
  "phaseID": "capture-binding-1",
  "route": "none",
  "routeGenerations": [
    "0"
  ],
  "segmentToken": "0CA82695-0370-0AFC-BB85-CE893773676C",
  "segmentType": "presenter"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": "input-2",
    "configurationID": "capture-binding-1-config",
    "declaredJudgeKind": "rules",
    "declaredModelVersion": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [],
    "level": "off",
    "parameterContext": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
    "parameterVersion": "10",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
    "phaseID": "capture-binding-1",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentToken": "0CA82695-0370-0AFC-BB85-CE893773676C",
    "segmentType": "presenter"
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

## Shadow session C9F2A03B-869C-42F8-A3F0-07D5460025EC / phase capture-binding-1

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": null,
  "configurationID": "capture-binding-1-config",
  "declaredJudgeKind": "rules",
  "declaredModelVersion": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [
    [
      "rules",
      null
    ]
  ],
  "level": "off",
  "parameterContext": {
    "adapter": {
      "debounce": 0,
      "maximumObservationAge": 2,
      "stillSpeed": 0.2
    },
    "judgeMaximumAge": 1,
    "minimumProbability": 0.7,
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
  "parameterVersion": "10",
  "phaseID": "capture-binding-1",
  "route": "none",
  "routeGenerations": [
    "0"
  ],
  "segmentToken": "0CA82695-0370-0AFC-BB85-CE893773676C",
  "segmentType": "presenter"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": null,
    "configurationID": "capture-binding-1-config",
    "declaredJudgeKind": "rules",
    "declaredModelVersion": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [
      [
        "rules",
        null
      ]
    ],
    "level": "off",
    "parameterContext": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
    "parameterVersion": "10",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
    "phaseID": "capture-binding-1",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentToken": "0CA82695-0370-0AFC-BB85-CE893773676C",
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

## Shadow session C9F2A03B-869C-42F8-A3F0-07D5460025EC / phase capture-binding-1

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": null,
  "configurationID": "capture-binding-1-config",
  "declaredJudgeKind": "rules",
  "declaredModelVersion": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [],
  "level": "off",
  "parameterContext": {
    "adapter": {
      "debounce": 0,
      "maximumObservationAge": 2,
      "stillSpeed": 0.2
    },
    "judgeMaximumAge": 1,
    "minimumProbability": 0.7,
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
  "parameterVersion": "10",
  "phaseID": "capture-binding-1",
  "route": "none",
  "routeGenerations": [
    "0"
  ],
  "segmentToken": "0CA82695-0370-0AFC-BB85-CE893773676C",
  "segmentType": "presenter"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": null,
    "configurationID": "capture-binding-1-config",
    "declaredJudgeKind": "rules",
    "declaredModelVersion": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [],
    "level": "off",
    "parameterContext": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
    "parameterVersion": "10",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
    "phaseID": "capture-binding-1",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentToken": "0CA82695-0370-0AFC-BB85-CE893773676C",
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

## Shadow session C9F2A03B-869C-42F8-A3F0-07D5460025EC / phase capture-binding-2

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": "input-2",
  "configurationID": "capture-binding-2-config",
  "declaredJudgeKind": "rules",
  "declaredModelVersion": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [],
  "level": "off",
  "parameterContext": {
    "adapter": {
      "debounce": 0,
      "maximumObservationAge": 2,
      "stillSpeed": 0.2
    },
    "judgeMaximumAge": 1,
    "minimumProbability": 0.7,
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
      "minimumShotDuration": 2,
      "onAirMoveRate": 0.2,
      "preferredShotDuration": 3,
      "repetitionWindow": 5,
      "settleTime": 0,
      "softMaximumShotDuration": 30,
      "wideCadence": 80
    },
    "status": "available"
  },
  "parameterVersion": "11",
  "phaseID": "capture-binding-2",
  "route": "none",
  "routeGenerations": [
    "0"
  ],
  "segmentToken": "85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D",
  "segmentType": "panel"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": "input-2",
    "configurationID": "capture-binding-2-config",
    "declaredJudgeKind": "rules",
    "declaredModelVersion": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [],
    "level": "off",
    "parameterContext": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
        "minimumShotDuration": 2,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 3,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "parameterVersion": "11",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
        "minimumShotDuration": 2,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 3,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "phaseID": "capture-binding-2",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentToken": "85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D",
    "segmentType": "panel"
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

## Shadow session C9F2A03B-869C-42F8-A3F0-07D5460025EC / phase capture-binding-2

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": null,
  "configurationID": "capture-binding-2-config",
  "declaredJudgeKind": "rules",
  "declaredModelVersion": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [
    [
      "rules",
      null
    ]
  ],
  "level": "off",
  "parameterContext": {
    "adapter": {
      "debounce": 0,
      "maximumObservationAge": 2,
      "stillSpeed": 0.2
    },
    "judgeMaximumAge": 1,
    "minimumProbability": 0.7,
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
      "minimumShotDuration": 2,
      "onAirMoveRate": 0.2,
      "preferredShotDuration": 3,
      "repetitionWindow": 5,
      "settleTime": 0,
      "softMaximumShotDuration": 30,
      "wideCadence": 80
    },
    "status": "available"
  },
  "parameterVersion": "11",
  "phaseID": "capture-binding-2",
  "route": "none",
  "routeGenerations": [
    "0"
  ],
  "segmentToken": "85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D",
  "segmentType": "panel"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": null,
    "configurationID": "capture-binding-2-config",
    "declaredJudgeKind": "rules",
    "declaredModelVersion": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [
      [
        "rules",
        null
      ]
    ],
    "level": "off",
    "parameterContext": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
        "minimumShotDuration": 2,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 3,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "parameterVersion": "11",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
        "minimumShotDuration": 2,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 3,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "phaseID": "capture-binding-2",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentToken": "85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D",
    "segmentType": "panel"
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

## Shadow session C9F2A03B-869C-42F8-A3F0-07D5460025EC / phase capture-binding-2

Actual evidence/level/mode/judge-model scope; distributions are never pooled across scopes:

```json
{
  "channel": null,
  "configurationID": "capture-binding-2-config",
  "declaredJudgeKind": "rules",
  "declaredModelVersion": null,
  "evidenceClass": "synthetic",
  "executionMode": "shadow",
  "judgeModels": [],
  "level": "off",
  "parameterContext": {
    "adapter": {
      "debounce": 0,
      "maximumObservationAge": 2,
      "stillSpeed": 0.2
    },
    "judgeMaximumAge": 1,
    "minimumProbability": 0.7,
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
      "minimumShotDuration": 2,
      "onAirMoveRate": 0.2,
      "preferredShotDuration": 3,
      "repetitionWindow": 5,
      "settleTime": 0,
      "softMaximumShotDuration": 30,
      "wideCadence": 80
    },
    "status": "available"
  },
  "parameterVersion": "11",
  "phaseID": "capture-binding-2",
  "route": "none",
  "routeGenerations": [
    "0"
  ],
  "segmentToken": "85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D",
  "segmentType": "panel"
}
```

Actual recorded parameter snapshots (configured inputs, not measured outcomes):

```json
[
  {
    "channel": null,
    "configurationID": "capture-binding-2-config",
    "declaredJudgeKind": "rules",
    "declaredModelVersion": null,
    "evidenceClass": "synthetic",
    "executionMode": "shadow",
    "judgeModels": [],
    "level": "off",
    "parameterContext": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
        "minimumShotDuration": 2,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 3,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "parameterVersion": "11",
    "parameters": {
      "adapter": {
        "debounce": 0,
        "maximumObservationAge": 2,
        "stillSpeed": 0.2
      },
      "judgeMaximumAge": 1,
      "minimumProbability": 0.7,
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
        "minimumShotDuration": 2,
        "onAirMoveRate": 0.2,
        "preferredShotDuration": 3,
        "repetitionWindow": 5,
        "settleTime": 0,
        "softMaximumShotDuration": 30,
        "wideCadence": 80
      },
      "status": "available"
    },
    "phaseID": "capture-binding-2",
    "route": "none",
    "routeGenerations": [
      "0"
    ],
    "segmentToken": "85DB2AE5-BABE-EE0A-A97A-6F6BF3F73D7D",
    "segmentType": "panel"
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
