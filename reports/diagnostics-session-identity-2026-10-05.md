# Diagnostics session identity — 5 October 2026

Card: https://trello.com/c/zpf1GOxX. Parent: https://trello.com/c/jiY5JFaH; lag evidence https://trello.com/c/D6KPsTw4.

Base `3e85fb7` on `codex/alfie-quality-sprint-2026-10-04`, after fresh fetch of unchanged main `a89644b865e31d179ab9bee5f41fe25b760d2f34`. The primary checkout was preserved.

DiagnosticsLog used second-resolution wall-clock filenames. Two completed captures within the same second, including different recorder instances, appended into one soak/memory CSV pair and replaced the original manifest. A UUID now extends the dated stem shared by all three session files. The manifest continues to reference its matching filenames; column meanings and schema version remain unchanged. The report reader accepts historical timestamp-only names and the new complete UUID stems. Within the same dated second, folder selection uses latest file-write time because UUIDs are unordered; explicit file input selects that exact session.

An injected temporary directory and fixed session-start wall clock test the production serial file writer without operator storage. A nonblocking queue drain makes completion deterministic. The regression reads actual files, checks headers, opening/closing markers, independent identities, window totals and matching memory/manifest names; duplicate Start does not replace an active session. Both same-recorder restart and separate-recorder cases are covered. No retention/deletion policy, permission, capture/routing, timing measurement or presentation claim changed.

Expected-failing baseline `/private/tmp/alfie-oct5-diag-baseline2.xcresult`: 8 passed / 1 failed definitions, 8 passed / 2 failed parameter case runs, no skips. Both rapid-session cases reproduced combined CSV rows and the overwritten manifest. The preceding baseline bundle was a compile failure from the initial test-seam default-argument isolation and is not behavioral evidence. The seam was corrected before the behavioral baseline.

Reader baseline uses the original reader with the three added regressions in `/private/tmp/alfie-oct5-reader-baseline`: 3 tests, 2 errors and 1 failure, retained in `/private/tmp/alfie-oct5-diag-reader-baseline.log`. Fixed reader: all 8 tests pass, including historical schema 1/schema 2 files, every new trio entry point, same-second selection and malformed suffix refusal (`/private/tmp/alfie-oct5-diag-python.log`).

Final targeted `/private/tmp/alfie-oct5-diag-targeted.xcresult`: **11 passed definitions / 12 passed runs, zero failures, 2 skipped** opt-in stress/cadence studies. Selected DiagnosticsLogTests and ProgramOutputMetricsTests.

Final complete target `/private/tmp/alfie-oct5-diag-full.xcresult`: **480 passed definitions / 627 passed runs, zero failures, 5 skipped**. Skips: opt-in stress, cadence and investigation studies; absent consented readiness clips; real two-webcam rig test. Counts come from xcresult summary/test trees, with Arguments children replacing their parent definition for case runs. Exports and count files use the bundle name plus `-summary.json`, `-tests.json`, `-counts.json`. Targeted and full snapshots are not additive.

Both builds use Xcode 26.2 (17C52), arm64 macOS 26.6.2 (25G83), `CODE_SIGNING_ALLOWED=NO`, serial tests, and `/private/tmp/alfie-quality-sprint-dd`. Full command: `xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj -scheme CinematicCoreMacOS -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:CinematicCoreMacOSTests CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/alfie-quality-sprint-dd -resultBundlePath /private/tmp/alfie-oct5-diag-full.xcresult`. Independent read-only review found no material issue.

Files: DiagnosticsLog.swift, DiagnosticsLogTests.swift, diagnostics_report.py, test_diagnostics_report.py and this report. This is synthetic filesystem/provenance evidence, not live-camera, privacy, latency, physical output or release qualification. Broad parent acceptance remains open; child enters Human Review, not Done. No merge to main.
