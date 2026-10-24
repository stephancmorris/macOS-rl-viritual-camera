# Alfie CI

Design: [CI-CD-RESEARCH.md](CI-CD-RESEARCH.md).

## Workflows

| Workflow | When | What it proves |
|---|---|---|
| `ci.yml` | Every pull request, including one whose base is not `main`, and every push to `main` | Debug build (app and extension), unit tests except the frame-cost timing test, unsigned Release build, Python tests, version and entitlement checks. |
| `ci.yml` job `timing` | Same triggers | `perFrameInstrumentationCostIsSmall` alone. Not a required check. **AWAITING OWNER** whether it ever should be. |
| `release-dmg.yml` | Manual | Re-runs `ci.yml`, then stops until the `release` environment has secrets. It does not notarize yet. |
| `release-appstore.yml` | Manual | Re-runs `ci.yml`, then stops. It does not upload. StoreKit and the basic/paid split are **AWAITING OWNER**. |

`build_release.sh` is unchanged and remains the local Developer ID path.

## Run the checks locally

```sh
sudo xcode-select -s /Applications/Xcode_26.2.app

xcodebuild build -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests \
  -skip-testing:CinematicCoreMacOSTests/ProgramOutputMetricsTests/perFrameInstrumentationCostIsSmall \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

(cd CinematicCoreMacOS && python3 -m unittest scripts/test_diagnostics_report.py)
bash scripts/ci/check_consistency.sh
```

The timing test, alone:

```sh
xcodebuild test -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -only-testing:CinematicCoreMacOSTests/ProgramOutputMetricsTests/perFrameInstrumentationCostIsSmall \
  CODE_SIGNING_ALLOWED=NO
```

## Owner checklist

Do not put these values in the repo.

1. Create environment `release` with a required reviewer.
2. Create environment `appstore` with a required reviewer.
3. Add the secret names listed in [CI-CD-RESEARCH.md](CI-CD-RESEARCH.md).
4. On `main`, require the `Build and unit tests` check. Do not require `Frame-cost timing (not required)` until you decide that.
5. Leave branch deletion off. Keep merge commits for stacked pull requests.
6. Pull-request workflows are not limited to `main`, so a pull request into another branch still runs the checks.

An entitlement change is allowed on a pull request labelled `allow-entitlement-change`.
