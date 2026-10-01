# Operator documentation and audit work package

2 October 2026. Branch `codex/operator-audit-review`, base `7691e6e1046ab40bca9b4e27a80e0b500f409c83` (fresh origin fetch confirmed). Local review package; no merge, PR, Trello changes, live app integration, camera/microphone permission changes, motion or automatic Take. Main checkout's concurrent draft/build artifacts were preserved.

## Delivered

| Work item | Artifact / result | Remaining acceptance |
| --- | --- | --- |
| Operator documentation | README.md and docs/user-guide: current A/B setup, Preview/Program, manual Take swaps, Edit Live, target-specific Return to Wide, single-camera Webcam and two different log folders. Removed automatic active-speaker/dual-output/shipping claims. | Actual candidate install, 1280-point walkthrough, approved screenshots, visual/print check, receiving-output evidence. |
| Privacy audit | docs/privacy/current-source-audit.md inventories frames, face evidence, training observations, diagnostics, logs and preferences. Safe synthetic guard/schema tests passed. | Runtime permission/cleanup/export tests and retention/disclosure choices. No private user data was read/deleted/shared. |
| Lag investigation | reports/release-1/lag-investigation.md: reproducible matched-build/rig protocol and cause discriminators. | Affected-run logs and receiver observations; no live cause or fix confirmed. |
| Candidate review | docs/handoff/stage3-4/CANDIDATE-REVIEW-2026-10-02.md: exact candidates, fresh tests and P2 structural stale-effect counter finding. | Independent committed-effect accounting and production adapter/product/qualification gates. |
| Benchmark investigation | reports/release-1/instrumentation-investigation.md plus two raw synthetic JSON cohorts and opt-in test harness. Retained sample growth measured as major fixture contributor. | Allocation/scheduling profile before production optimization or benchmark redesign. Original 250 µs limit unchanged. |

Concrete repair follow-ups: CSV pruning leaves manifests; text logs have no rotation; model consent revocation has no recording/write boundary (UI disallows changing it while recording); manual export is not sanitized; current engine has no tracked privacy manifest; replay committed-stale counter cannot independently measure stale commits. These are documented findings, not silently implemented app changes.

## Fresh authoritative tests

| Exact source | Bundle | Passed definitions | Passed case runs | Failed | Skipped |
| --- | --- | ---: | ---: | ---: | ---: |
| Director 7553a9d | /private/tmp/alfie-candidate-director-review.xcresult | 32 | 65 | 0 | 0 |
| Degradation/readiness 8b9f712 | /private/tmp/alfie-candidate-readiness-review.xcresult | 14 | 17 | 0 | 1 |
| New controlled benchmark study | /private/tmp/alfie-instrumentation-study-final.xcresult | 1 | 1 | 0 | 0 |
| Final opt-in benchmark study | /private/tmp/alfie-instrumentation-study-optin.xcresult | 1 | 1 | 0 | 0 |
| Privacy/default-skip checks | /private/tmp/alfie-audit-default-tests.xcresult | 2 | 2 | 0 | 1 |

Counts read with `xcrun xcresulttool get test-results summary/tests --path BUNDLE --format json`. Director: 3 parameterized definitions / 36 argument runs, 32−3+36=65. Degradation/readiness: 1 parameterized definition / 4 runs, 14−1+4=17. Other selected tests are nonparameterized. No sum across different candidate builds is represented as a full suite. No full-unit suite was rerun for this documentation/test-only package. Prior full-suite evidence stays in each candidate's existing report, including the earlier performance failure/recheck.

Commands use `xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Director selectors are DirectorAuthorityTests, DirectorProposalTests, DirectorShotPolicyTests, DirectorReplayTests. Readiness selectors are DegradePolicyTests and ReadinessEvaluationTests. New audit selectors are PrivacyAuditTests and InstrumentationInvestigationTests, with `-parallel-testing-enabled NO`. Opt-in run supplies `TEST_RUNNER_ALFIE_INSTRUMENTATION_STUDY=1` and selects InstrumentationInvestigationTests. Derived data paths: `/private/tmp/alfie-candidate-director-review-dd`, `/private/tmp/alfie-ticket-validation-dd`, `/private/tmp/alfie-operator-audit-dd`. Logs have the matching bundle basename and `.log` extension.

First benchmark-study build failed on an investigation-only reflection API use; corrected before measurements. Study/default tests are synthetic, and consented-dataset readiness remains unavailable. Heavy study skips by default. No measurements qualify real-camera, external presentation, UI override latency, identity recovery, editorial utility or physical safety.

## Documentation verification and isolation

HTML parser checks found unique IDs, resolved internal anchors and existing local CSS; no remote assets are used. Browser URL policy rejected the local `file:` render. No alternate browser/server workaround was attempted. Visual/print verification and real app screenshots remain pending, rather than being inferred from static checks. Documents identify the reviewed base and unapproved gates.

Only README, new guide/audit/report files and two test-only fixtures changed. Production Swift, project settings, entitlements, capture/output, running orchestration and reviewed candidate branches were not modified. DECISIONS.md approval status is unchanged. No remote publication is included in this local work package.
