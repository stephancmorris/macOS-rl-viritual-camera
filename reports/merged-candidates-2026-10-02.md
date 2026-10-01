# Combined candidate merge

2 October 2026. User authorized merging the completed changes into the current engine. Base: `7691e6e1046ab40bca9b4e27a80e0b500f409c83`. Merge prepared in isolated managed worktree, branch `codex/merge-reviewed-candidates`; shared working checkout's concurrent changes and untracked guide were preserved.

## Included candidates

- Director authority/lifecycle: `7553a9d23a7faebe5aaaff9d922c171bcf520e45`; merge `05339c5`.
- Degradation/readiness validation: `8b9f71236252a7c37b1b216b8b3913aaae811c45`; merge `341db76`.
- Operator documentation/audit: `8777b0d76928d812f79686a7fc8ab240fabe0caa`; merge `254599f`.
- Documentation correction `9135e0f23db3c65f9c6bd85257956066373a7cfb`: current route is Direct output (HDMI / USB-C), Output port. Explicit port reservation/black before Start, show-format request and restoration replace stale Program Display/manual-format instructions.

All merges were conflict-free. Tested combined implementation tip: `9135e0f23db3c65f9c6bd85257956066373a7cfb`. This report is the only subsequent change before delivery. Previous reports describe isolated deliveries at their dates; this combined delivery supersedes their unmerged/local status, not their evidence limitations.

## Validation

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -parallel-testing-enabled NO -only-testing:CinematicCoreMacOSTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-merged-dd \
  -resultBundlePath /private/tmp/alfie-merged-full.xcresult
xcrun xcresulttool get test-results summary --path /private/tmp/alfie-merged-full.xcresult --format json
xcrun xcresulttool get test-results tests --path /private/tmp/alfie-merged-full.xcresult --format json
```

Authoritative summary/tree: 441 passed definitions, zero failed, three skipped; 545 passed case runs. Eighteen parameterized definitions contain 122 argument runs: 441−18+122=545. Total definitions: 444. Skipped: real two-webcam test, unconfigured consented-folder readiness test, opt-in instrumentation investigation. No skipped gate becomes a pass. Log: `/private/tmp/alfie-merged-full.log`; summary/tree JSON: `/private/tmp/alfie-merged-full-{summary,tests}.json`. No earlier totals were substituted for this combined run.

Static guide checks: unique IDs, resolved anchors and current route labels. Visual/print and actual app walkthrough remain pending. Production ShowCoordinator, ContentView, DeveloperFlags, Hardware/Speech, project settings and capture/output implementation are unchanged by these merges. Director/DegradePolicy remain unwired. No motion, microphone or automatic Take was enabled.

## Remaining gates

All 37 Director decisions remain OPEN. Integration, independent replay committed-effect accounting, privacy cleanup/consent/export repairs, live lag evidence, held-out readiness calibration, real-camera/downstream-output qualification and operator rehearsal remain separate requirements. Merging isolated foundations and documentation does not approve proposed policies or establish live directing, editorial utility or physical safety.

Target shared branch: origin/r2/engine. Publication is a normal fast-forward push, with remote ancestry checked and no force push. The dirty original checkout is deliberately not reset or overwritten; its local branch may remain at the older source until its concurrent files are safely reconciled. Use the merged managed checkout for a clean review of the delivered source.
