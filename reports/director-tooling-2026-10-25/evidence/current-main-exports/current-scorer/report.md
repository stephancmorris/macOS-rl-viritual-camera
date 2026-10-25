# Offline Director scorer evaluation

Evidence class: **synthetic**. Model: `synthetic-1bdfb60edb7e6c2e`.

Explicit supplied ranks are choice labels. Nonselection does not establish poor shot quality or safety. These results are descriptive; no qualification, calibrated probability claim, production threshold or promotion is supplied.

| Split | Groups | Candidates | Model exact | RuleJudge exact | Model Brier | Model log loss |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| train | 4 | 8 | 2/4 | 2/4 | 0.250034 | 0.693215 |
| validation | 4 | 8 | 2/4 | 2/4 | 0.250034 | 0.693215 |
| test | 4 | 8 | 2/4 | 2/4 | 0.250034 | 0.693215 |

Validation and test are whole held-out sessions. Training uses only train-session features and labels. RuleJudge has no probability; its Brier, log loss and probability calibration are unavailable. Candidate probability metrics weight candidates equally; exact-choice agreement weights comparison groups equally.

Reliability bins are descriptive candidate-level summaries, not fitted calibration or release criteria. Zero observed loss cannot establish complete capture, authentic labels or representative sessions.

## Validation reliability

| Probability interval | Candidates | Mean probability | Selected fraction |
| --- | ---: | ---: | ---: |
| [0, 0.2) | 0 | unavailable | unavailable |
| [0.2, 0.4) | 0 | unavailable | unavailable |
| [0.4, 0.6) | 8 | 0.494186 | 0.5 |
| [0.6, 0.8) | 0 | unavailable | unavailable |
| [0.8, 1] | 0 | unavailable | unavailable |

## Test reliability

| Probability interval | Candidates | Mean probability | Selected fraction |
| --- | ---: | ---: | ---: |
| [0, 0.2) | 0 | unavailable | unavailable |
| [0.2, 0.4) | 0 | unavailable | unavailable |
| [0.4, 0.6) | 8 | 0.494186 | 0.5 |
| [0.6, 0.8) | 0 | unavailable | unavailable |
| [0.8, 1] | 0 | unavailable | unavailable |
