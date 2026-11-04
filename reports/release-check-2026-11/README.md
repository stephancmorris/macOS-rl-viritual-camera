# Release check (4 November 2026)

Trello: [RELEASE-CHECK](https://trello.com/c/RTAC7XJV). An unsigned Release build of `origin/main` (`3ea830e`) after PRs #85–#94, which turns every `#if DEBUG` flag off.

- **Build:** succeeded. The CMIO extension is embedded at `Contents/Library/SystemExtensions/`. Hashes are in `validation.json`.
- **Warnings:** Release (and Debug) had three Swift isolation warnings that would be errors in the Swift 6 language mode:
  - `DirectorShadowRecorder.alias`
  - `SegmentType.styleTitle`
  - `RunSheet.PositionHint.title`

  All three are pure and are now marked `nonisolated`, so the Release build has **0** Swift warnings in app sources.
- **Finding:** `AlfieSourceFingerprint` is empty in a plain `xcodebuild` Release. Only `build_release.sh` stamps it. Use that script for any candidate whose diagnostics must name its source.
- **Not done:** signing, notarization, install, launch and any rig check. This proves the build compiles and packages, nothing more.
