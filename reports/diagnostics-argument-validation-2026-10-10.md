# Diagnostics report argument validation

10 October 2026. Branch codex/alfie-quality-sprint-2026-10-04; unit base be838fd6d3c805bced158bf753579f67544445b2. [DIAGNOSTICS-ARGS](https://trello.com/c/Boj6LxeY), parents [METRICS](https://trello.com/c/jiY5JFaH) and [LAG](https://trello.com/c/D6KPsTw4).

The evidence CLI accepted NaN, infinite, zero and negative expected-rate/cadence-floor overrides. NaN comparisons silently reported zero cadence shortfalls and could overwrite reviewed Markdown evidence. The checked-in August034717.csv reproduces exit0 with0of35 windows below a NaN target/floor. This is an explicit CLI boundary, not an assumed nonfinite live producer.

Explicit user cadence settings now require finite positive values before input loading or output writes; build_report enforces the same API boundary. argparse reports an actionable exit2 error. Default0.97, positive custom FPS and floor multipliers above1 remain supported, with no invented upper-bound policy. Raw CSV/manifest numeric interpretation and stage/clock/retention semantics are unchanged.

Six new Python unittest definitions exercise invalid CLI settings with absent/preexisting output, invalid API overrides, rejection before input loading, and three positive custom settings including floor1.1. Temporary fixture rates50/25 verify ordinary comparisons. Existing UUID trio/session selection and recorded schema1 evidence checks still pass. No meaningless Swift wrapper tests were added for this standalone Python boundary.

| Verification | Result |
| --- | --- |
| /private/tmp/alfie-oct10-args-baseline.log | 14 Python definitions ran; five definitions produced35 failing subcases, no errors/skips |
| /private/tmp/alfie-oct10-args-targeted.log | All14 Python definitions passed, no errors/skips |
| /private/tmp/alfie-oct10-args-full.xcresult | 522 Swift definitions/724 case runs passed,0 failed,5 skipped |

Python command: python3 -m unittest discover -s CinematicCoreMacOS/scripts -p test_diagnostics_report.py -v. Regression fixtures store no operator data outside temporary test directories. The immutable legacy report fixture is checked-in repository evidence, not a new live measurement. Its CLI repro was independently run against staged source copies; /private/tmp/alfie-oct10-diagnostics-args/recorded-session-repro.txt retains exit/status excerpts.

Full Swift counts read from xcresulttool summary/tests, with argument runs replacing definition parents. Full skips remain accelerated stress, cadence study, clock-window study, consented-folder readiness and two-real-webcam test. xcodebuild test uses CinematicCoreMacOS project/scheme, platform=macOS, parallel-testing-enabled NO, only-testing:CinematicCoreMacOSTests, CODE_SIGNING_ALLOWED=NO and derivedDataPath /private/tmp/alfie-quality-sprint-dd. Matching full .log retained. Xcode26.2(17C52), arm64 M4Pro, macOS26.6.2(25G83). git diff --check passed.

Tooling/evidence correctness only. No new live cadence, physical presentation, beta-lag attribution, end-to-end latency, privacy or release qualification. Parent acceptance remains open, child Human Review, separate pushed commit, primary checkout preserved, no main merge.
