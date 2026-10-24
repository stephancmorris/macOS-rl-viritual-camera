# Subject selection and optional judge group — 21 October 2026

Software review candidate stacked on PR #70 (`a20a348`). Reuses the A-14 SubjectSelector candidate from PR #58 (`364d0a8`, cherry-picked as `589c94e`). No main merge, project/entitlement/Info.plist change, trained model, media collection, audio or network is introduced.

| Ticket | Implemented software | Remaining acceptance |
| --- | --- | --- |
| [B-10](https://trello.com/c/9ifoF0DZ) | Explicit Debug discovery study configuration; off-air/unlocked eligibility; bounded request and actual-executor start cadence; targeted cancellation, result retirement and counted already-running overlap; separate scan/acquire permissions; normal acquire/gallery path | D-03 named-rig parameters and workload budget, approved Take-overlap interpretation, real soak and qualification. Current nomination/authority prerequisites are preserved, so automatic acquisition cannot bootstrap an absent nomination. |
| [C-08](https://trello.com/c/7BJdvATP) | Current source/selection/route-bound nomination; real acquisition commands; source-space pick overlay and Shot caption; suggested, acquiring, tracking, recovering, ambiguous and unavailable states; seven synthetic gallery examples | Physical source/Take/retarget walkthrough, spoken VoiceOver and operator visibility review. No confirmed identity or readiness is inferred from a suggested pick. |
| [A-16](https://trello.com/c/E4adcm5o) | Optional local CoreML scorer, versioned strict features/model validation, deterministic rule-eligible ranking, exact RuleJudge fallback, explicit low-confidence abstention; bounded passive A/B logging with contributing provenance | C-10 real shadow dataset, complete training feature recording, held-out comparison/calibration and winning model. No model is bundled or activated. |

## Operating boundaries

Ordinary app construction installs no discovery study settings or learned scorer. Release discovery and comparison execution remain disabled. C-08 uses the existing Debug Director console and the normal operator command boundary. Single-input nomination keeps the existing manual rule; when Preview exists, Program changes require Edit Live.

Discovery never waits for Vision at Take or invalidates ordinary tracking observations to hide overlap. Pending starts are checked on the serial executor; work that already crossed that boundary may finish and is counted/rejected after retirement. This is software evidence, not approval of the unresolved literal overlap rule. The explicit study cannot grant authority, a qualification or a nomination. Existing loss/pause/handback prerequisites still apply.

The judge only ranks/vetoes rule-eligible candidates. The scorer's threshold is applied inside LearnedJudge; a rules fallback deliberately has no probability. An outer gate must retain every other check and use no redundant probability threshold for that fallback. Shadow comparison does not install a judge in any execution sink. A producer supplies actual timeline/history and contributing evidence classes; mixed or missing provenance is refused. Policy/style/authority/nomination/evidence changes during the synchronous provider are checked again before logging. Invalid evaluations never masquerade as rules output.

The current metadata schema does not contain the complete history required for the 16-feature training contract. No training dataset is reconstructed from incomplete logs, and no synthetic fixture is described as a trained or calibrated model.

## Validation and review

Evidence class: synthetic software checks only. Root owns serial Xcode validation; separate agents implemented engine discovery, the operator UI and the optional scorer, followed by cross-review of root integration.

The first build found a private shot accessor reference; the existing public Director shot accessor is now used. The next compile found mutating Swift Testing macro calls; requests are evaluated into locals before assertions. The first executable focused run passed 111 expanded cases and failed only the authored CoreML fixture's schema validation; that runtime contract is being diagnosed rather than skipped.

Final test/build results follow below. No live rig drill, calibrated threshold, real training, downstream workload result, signed qualification or owner sign-off is claimed.


### Final validation

- Complete Debug Swift suite: **925 test definitions, 1,436 expanded passes, zero failures and three skips**. Result bundle: `/private/tmp/alfie-subject-tools-20261021/full-unit.xcresult`.
- **31 Python tests passed**. `git diff --check` passed.
- **Unsigned Release app and camera extension build passed**. Log: `/private/tmp/alfie-subject-tools-20261021/release-build.log`.
- Actual authored CoreML inference passed, including repeatable fixed-model scores and incompatible-schema fallback. The fixture revealed that this runtime represents exact fixed shapes as singleton enumerations. Validation now permits only that exact singleton or exact unspecified shape; alternate shapes and ranges remain refused. Temporary diagnostics were removed.
- Regression coverage includes missing/invalid study configuration, Program exclusion, delayed actual starts without catch-up bursts, queued cancellation versus counted running overlap, stale source/authority/freshness, measured stability and ambiguity, scan-only versus acquisition permission, ordinary acquisition/gallery state, nomination supersession, every real Take origin, preservation of acquired identity, and perception-only waiter cancellation preserving render work.
- Source nomination checks cover bound source/selection/route changes, protected Program, stop/mode changes, normal one-click acquisition and retarget, single-input manual compatibility and unavailable geometry. The proposal phase is distinct from acquiring/tracking; Director-owned motion does not disable manual nomination.
- A/B regressions exercise actual bounded logging with synthetic provenance. Missing/mixed/mismatched input classes, provider policy/style mutation, invalid settings and invalid feature evaluations cannot produce misleading comparison rows. Comparison remains passive and its gates are explicitly not evaluated.
- Independent cross-review repaired truthful event selection, current controller bindings, provenance, invalid-versus-rules output, snapshot expiry and empty retirement churn. Existing actor-isolation warnings outside this change remain; no warning-free claim is made.
- Offscreen gallery rendering and accessibility-label assertions passed. Native screenshot capture for the installed `/Applications/Alfie.app` was unavailable; it was not used as candidate visual evidence. No candidate manual walkthrough or live rig drill is claimed.
- Final application source fingerprint: `035ffabeb208aec3e68c4d91c8cee14b2a25510c92ca00fcfd319f08c8596ef8`.

The three cards are ready for human software review, with the table's remaining acceptance retained. Ordinary construction supplies no discovery or model configuration, and no main merge is included.
