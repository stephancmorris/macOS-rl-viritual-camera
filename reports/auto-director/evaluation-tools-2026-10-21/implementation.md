# 21 October ticket group: software implementation and review

Tickets: **C-10, D-06, R2 PRIVACY, R1 DOCS**. This candidate is stacked on PR #71 (`codex/director-subject-tools`). It also reconciles the existing D-05 runbooks, D-07 consent/fixture procedure and missing training-consent shutdown fix. Owner review and physical/real-data acceptance remain open; none of these cards is marked Done.

## Result

- **C-10:** versioned schema-2 capture preserves the actual sixteen scorer inputs, including history-derived counts, through the bounded shadow writer and explicit export. Schema 1 remains readable under its original closed contract. An offline loader requires explicit labels and disjoint whole-session train/validation/test splits. A deterministic local sigmoid MLP produces a reviewable model, held-out comparison, calibration summaries and optional CoreML export. It does not install or promote a model.
- **D-06:** the Swift harness exports all five actual synthetic replay fixtures. A strict scoped evaluator combines those results with C-05 missing-data regressions and explicit opportunity labels, preserving denominators and missing evidence. The supporting D-08 memo remains AWAITING OWNER; D-08 is not advanced by this package.
- **R2 PRIVACY:** restored consent revocation, serialized writer shutdown/drain and matching tests, preserving newer bounded writer/error handling. A separate explicit metrics exporter allowlists numeric diagnostics while excluding identities, arbitrary strings, paths, wall clocks, person geometry and adjacent text/media. Exact UInt64 parsing prevents silent large-counter rounding.
- **R1 DOCS:** README, engineering contract and user guides match present single/two-camera routing, Debug/Release Director boundaries and actual local data handling. The privacy inventory records source behavior and unresolved owner gates.

## Evidence and limits

The [evaluation report](README.md) retains a visible panel failure: one wrong proposal and one wrong attempt out of one independently labelled opportunity each. Its five fixtures show zero audited stale preparation commits. Committed-subject correctness and live visible override latency remain unlabelled. This harness has no automatic Take entry point, so its structural zero Director cuts supplies no automatic-cut safety claim. Assist remains incomplete; Auto and Backup are not run.

The [cross-layer scorer rehearsal](evidence/scorer-synthetic/README.md) used a bundle produced by the actual Swift capture/writer/export path. Python read twelve comparison groups from three sessions, fitted/exported the scorer, and actual CoreML CPU inference matched Python probabilities within the explicitly authored test tolerance. Both model and RuleJudge agreed on 2/4 held-out choices: a tie, with no model-win or probability-calibration claim. The binary model remains in the explicit temporary output, outside app resources.

Cross-review checked dataset joins/splits and train-only preprocessing, evaluation denominators/scope, and privacy export minimization/nonoverwrite behavior. Review found and repaired exact-counter parsing and evaluator scope/counter integrity issues. Validation details and source fingerprint are recorded in [validation.json](validation.json).

## Verification

The complete Swift suite passed **932 test definitions / 1,449 expanded executions**, with zero failures and three skips. Skips were the consented-folder replay, two-real-webcam integration and explicitly configured cadence investigation. The separate focused capture/privacy selection passed 145 executions; the explicit export selection passed two; the actual generated CoreML interoperability selection passed one. The full suite also forwarded the interoperability configuration. Release built successfully with code signing disabled. No signed installation, camera walkthrough or Store validation is claimed.

All **81 Python tests** passed after review fixes (67 script tests and 14 training tests). The authored fixtures exercise software behavior only. No real footage, live observations, owner approvals or qualified directing capabilities were created.

Remaining acceptance requires consented representative sessions, credible independent labels, event-aware held-out study design, model workload/calibration evidence, frozen owner tuning choices, current R2 physical-rig evidence on both output routes and per-level sign-off. PRIVACY retains live permission/refusal/revocation and owner retention/Store checks; DOCS retains the candidate's 1280-point, VoiceOver and downstream installation walkthroughs. Project settings, entitlements and Info.plist were not changed. The shared DiagnosticsLog file adds only an injected cleanup clock/directory and an asynchronous file-queue barrier; no Director type crosses the extension boundary.

## Final privacy cleanup follow-up

The existing diagnostics deletion path is now exercisable in a disposable directory with an injected wall clock. Production defaults still use the same app directory, utility queue, thirty-day duration and strict `modified < cutoff` comparison. Five expanded cases verify actual deletion/preservation across soak CSV, memory CSV and session JSON, exact-cutoff preservation, subsequent-session expiry, unrelated/outside-root preservation and isolated session artifacts. The focused selection passed 17 expanded executions, including existing diagnostics regressions. The final full suite and Release build above include this shared-file change. No operator files were used.

The new seam establishes the existing cleanup behavior only. It creates no new cleanup trigger or retention policy for other stores. The [next group](next-group.md) identifies remaining candidate/manual checks and evidence-gated work. GitHub reported no CI checks on this branch; validation here is the recorded local execution.
