# Style-specific settling evidence

25 October 2026. Follow-up [SU-03-SETTLE-EVIDENCE](https://trello.com/c/JRBFINdK), based on [PR #82](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/82) at `82cca822d191c867c8f5a341b9f3ada43c82949d`. This is a separate stacked change, not an alteration of [PR #81](https://github.com/stephancmorris/macOS-rl-viritual-camera/pull/81)'s verified integration preview.

## Reproduction

The style can tighten cut motion below the adapter's general stillness limit. The existing cut-ready duration still came from the general clock: authored samples at speed 0.01 for two seconds count as settled under adapter limit 0.05, but exceed style limit 0.005. The first zero-speed sample at 2.1 seconds then immediately passed the tightened one-second cut bar. A temporary test against unmodified PR #82 reported empty readiness reasons where `framingUnsettled` was expected: one failing definition, no compile failure or skipped/empty selection. The [baseline probe](evidence/PR82BaselineProbe.swift) is retained outside the app test target. It reproduces the legacy adapter-to-readiness flow; the fixed production path uses the cut-specific clock tested below.

These values are synthetic test inputs, not production recommendations. No camera, automatic Take or live subject was observed.

## Change

The adapter retains its existing preparation clock and one additional bounded cut clock per channel. Each tick supplies the effective cut motion bound already derived from the configured study parameters and active style. Cut settlement accumulates only while the ordinary settlement conditions hold and motion stays under that effective bound. Exceeding it, changing it, losing evidence/identity, a nomination change or an invalid sample clock clears the cut history. Historical samples cannot rewind configuration or time. A query under a different bound or stale observation returns zero.

The production final-cut input path requests this cut-specific duration and evaluates the same effective bound. Existing callers without a cut configuration retain their preparation behavior. There is no new `@Published` frame state, timer, queue, policy default, numeric recommendation, wire schema or authority grant. Actual cut readiness inputs continue through the existing shadow recorder.

## Verification

Eight new definitions cover the real adapter plus final-cut input factory, movement recurrence, changed bounds, gestures/stale evidence/nomination/invalid clocks, historical samples, invalid bounds and the unconfigured preparation path. The initial focused adapter/readiness/Take selection passed **50 definitions / 70 expanded cases**, zero failures/skips. A subsequent raw-lock review added a brief-hold regression and cut-only raw-confirmation guard; the final full suite covers that refinement. The full app target passes **1,114 definitions / 1,712 expanded cases**, zero failures and three explicit opt-in investigation/consented-folder/real-camera skips. Actual existing synthetic CoreML CPU interoperability was configured. Unsigned Release app and extension build successfully; embedded fingerprint is verified.

[validation.json](validation.json) retains the exact baseline, tested source-file hashes, source fingerprint, result bundles and binary hash. Native camera/receiver behavior, signed installation and Director per-level qualification remain open. This source is based on PR #82 and does not claim combined validation with PR #81 or any later run-sheet work.

A further review of the initial fix (`be54078`) found that a brief raw lock hold could retain cut age while the debounced identity remained confirmed. One added regression reproduced that condition. Cut settlement now also requires the raw sample identity to be confirmed; the preparation debounce and its clock remain unchanged. The final full suite and Release results above include this guard.
