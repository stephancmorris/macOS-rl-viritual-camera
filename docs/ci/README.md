# Alfie CI

Design and distribution research: [CI-CD-RESEARCH.md](CI-CD-RESEARCH.md) (10 October snapshot; release options remain awaiting owner decisions).

## Workflows

| Workflow | When | What it proves |
|---|---|---|
| `ci.yml` | Every pull request, push to `main`, manual dispatch, or reusable call | Unsigned Debug build-for-testing (app and extension), full Swift unit suite, Python diagnostics/Director report and Director dataset/training tests, unsigned Release build, version and entitlement checks. |
| `release-dmg.yml` | Manual only | Re-runs CI, then stops at the unconfigured signing placeholder. It does not sign or notarize. |
| `release-appstore.yml` | Manual only | Re-runs CI, then stops at the unconfigured validation placeholder. It does not validate an archive or upload. StoreKit and the basic/paid split are **AWAITING OWNER**. |

CI uses `macos-26` (Apple silicon) and pins `DEVELOPER_DIR` to Xcode **26.2 (17C52)**. The [runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists that toolchain. This retains the handoff's Xcode 26.x baseline: the local machine was found to have **27.1 (27A9275)** on 4 November, so local runs and hosted runs are recorded separately. CI logs its actual tool versions. It uses fresh DerivedData under `runner.temp`, never tracked build output.

The job times out after 60 minutes; Swift tests have a 50-minute step timeout and a 45-minute process alarm so artifact upload can run on a test hang. Test results and the JSON totals are uploaded with `always()` for 14 days. Ordinary test failures fail the job. The full Swift suite includes the frame instrumentation regression test; no separate timing exclusion remains. The existing opt-in tests retain their own skip conditions. The gallery snapshot test fixes its SwiftUI root to the requested canvas, disables automatic hosting-size updates and uses an unconstrained offscreen window. Without explicit sizing, the hosted 1000 pt canvas shrank to its 989 pt intrinsic content height. The full image-size assertions remain in place.

Python checks use the standard library and need no credentials or pip installation. All `test_*.py` suites in `CinematicCoreMacOS/scripts` run, plus `training/test_director_dataset.py` and `training/test_director_scorer.py` via discovery. The older RL environment/BC/CoreML smoke scripts require `training/requirements.txt` and are outside this Director CI gate.

`build_release.sh` remains the local Developer ID path.

## Run the checks locally

From the repository root, with Xcode selected locally (or set `DEVELOPER_DIR` to an installed 26.2):

```sh
xcodebuild -version
xcodebuild build-for-testing -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/alfie-ci-dd CODE_SIGNING_ALLOWED=NO

perl -e 'alarm 2700; exec @ARGV' xcodebuild test-without-building \
  -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -destination 'platform=macOS' \
  -derivedDataPath /tmp/alfie-ci-dd -only-testing:CinematicCoreMacOSTests \
  -resultBundlePath /tmp/alfie-ci-unit.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/alfie-ci-unit.xcresult

(cd CinematicCoreMacOS/scripts && python3 -m unittest)
(cd training && python3 -m unittest discover -p 'test_director_*.py')
xcodebuild build -project CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj \
  -scheme CinematicCoreMacOS -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/alfie-ci-release-dd CODE_SIGNING_ALLOWED=NO
bash scripts/ci/check_consistency.sh
```

Use a fresh result-bundle path on every run.

## Owner checklist

Do not put credentials in the repo. Signing workflows remain intentionally fail-closed placeholders, even if secrets are supplied.

1. Create environment `release` with a required reviewer before configuring Developer ID signing.
2. Create environment `appstore` with a required reviewer before configuring Store validation.
3. Add the secret names listed in [CI-CD-RESEARCH.md](CI-CD-RESEARCH.md) only when implementing those paths.
4. Decide whether to require `Build and unit tests` in branch protection; this PR makes no repository-setting changes.
5. Keep merge commits for stacked pull requests.

An entitlement change needs the pull request label `allow-entitlement-change`. Pushes to `main` still compare with the prior commit, so the label does not waive the push check; an owner-approved entitlement change also needs an explicit follow-up to that policy before merging. CI software checks do not qualify a rig, release, privacy or Director authority gate.
