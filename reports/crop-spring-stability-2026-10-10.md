# Ordinary crop spring stability

10 October 2026. Branch codex/alfie-quality-sprint-2026-10-04; unit base f175a29765e12bf12c4daca4d03b0297085136ad. [CROP-SPRING-STABILITY](https://trello.com/c/FKTpe5WA), parents [CMD](https://trello.com/c/o9O5EXA1) and [PAN-HITCH](https://trello.com/c/6vPWbhsg).

## Result

The ordinary origin/size path applied one semi-implicit Euler step at the existing100ms cap. Supported smoothing values could backtrack, overshoot or amplify retained velocity. At smoothing0.25 a stationary square crop translating origin x=.05→.45 bounced between clamped x=.5 and0 at repeated100ms ticks. The real Pan cold-start symptom has not been measured or attributed to this defect.

Ordinary x/y/width/height now use the identical analytic critically damped spring already used for zoom origin. The continuous equation y″+2ωy′+ω²y=0 and ω=sqrt(transitionSmoothing×600), targets, tick cap, floor/geometry clamps, settlement thresholds, Pan placement and zoom-size curve are preserved. A read-only mathematical review checked the closed form and composition of40+60ms steps; no physical motion occurred. Exact integration changes numerical approximations of that equation, including normal cadence, without selecting new tuning or product curves.

Three new Swift Testing definitions/17 runs exercise actual tickInterpolation without capture/render: five supported smoothing values at20/100ms (10), a mixed interval sequence (1), and three aspect ratios at20/100ms with a0.25 quality floor (6). Fixed resting targets must approach monotonically, stay legal/preserve aspect/center and settle. Moving-target reversals are not incorrectly asserted monotone.

## Exact verification

| Bundle under /private/tmp | Passed definitions | Failed definitions | Skipped | Passed runs | Failed runs |
| --- | ---: | ---: | ---: | ---: | ---: |
| alfie-oct10-spring-baseline-final.xcresult | 0 | 3 | 0 | 9 | 8 |
| alfie-oct10-spring-targeted-final.xcresult | 51 | 0 | 0 | 74 | 0 |
| alfie-oct10-spring-full.xcresult | 522 | 0 | 5 | 724 | 0 |

Initial spring-baseline.xcresult and spring-targeted.xcresult failed to build on the fixture's integer1/30 expression in a Double array. Corrected to1.0/30.0, restored only this unit's original CropEngine integration, and reran the behavioral baseline above before restoring the repair. These build failures are preserved and excluded from behavioral totals.

Targeted suites: CropSpringRegressionTests3/17, FramingRegressionTests36/45, FramingCapabilityTests6/6, OutputRateRegressionTests6/6. Counts read from xcresulttool summary/tests; argument runs replace parent definitions. Full five opt-in skips remain accelerated stress, cadence study, clock-window study, consented-folder readiness and two-real-webcam test.

xcodebuild test uses CinematicCoreMacOS project/scheme, platform=macOS, parallel-testing-enabled NO, CODE_SIGNING_ALLOWED=NO, derivedDataPath /private/tmp/alfie-quality-sprint-dd. Baseline selects CropSpringRegressionTests, targeted selects suites above, full selects CinematicCoreMacOSTests. Logs use bundle basename+.log. Xcode26.2(17C52), arm64 M4Pro, macOS26.6.2(25G83). git diff --check passed.

## Remaining acceptance

Deterministic numerical correctness only. No measured physical Pan hitch, cold-start cause, UI or receiver latency, camera/output cadence or release qualification. PAN-HITCH stays Spec Ready with its real-rig prerequisite; parent acceptance and curve decisions stay open. Child Human Review, separate pushed commit, primary checkout preserved, no main merge.
