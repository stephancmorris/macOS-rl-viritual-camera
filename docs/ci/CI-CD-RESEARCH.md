# Alfie CI/CD research and design

Status: Phase 1 design. No workflow files yet. Base: `main` at `bcc4ae7` (10 Oct 2026).

Alfie is a sandboxed macOS app with an embedded CMIO camera system extension. The pipeline has to make a bad change fail before a release. Two channels exist:

1. **Now:** a Developer ID-signed, notarized, stapled `Alfie.dmg`, built by the existing `CinematicCoreMacOS/build_release.sh`.
2. **Later:** the Mac App Store, with a basic version and a paid version. Those products are not defined. This doc does not choose tiers, prices, product IDs or features.

## What was re-checked in this repo

- Public GitHub repo `stephancmorris/macOS-rl-viritual-camera`. Default branch `main`. No `.github/` directory on `main`.
- Local toolchain: Xcode 26.2 (17C52). Shared scheme: `CinematicCoreMacOS` only. The extension target builds as an app dependency.
- `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, approachable concurrency, `MemberImportVisibility`, Swift 5 language mode.
- `DiagnosticsLog.swift`, `ProgramOutputManager.swift`, `ShowStandard.swift` and `CropRenderer.metal` compile into both the app and the extension.
- Unit tests are Swift Testing in module `Alfie`. On `main` at this SHA the suite is **586 passed, 0 failed, 3 skipped**.
- `ProgramOutputMetricsTests/perFrameInstrumentationCostIsSmall` is timing-sensitive. Under parallel CPU load it failed at **265 µs** against its **250 µs** limit, and it passes when run alone. The test is not to be edited.
- Team ID `EPZDEPSV69`. The extension's `CMIOExtensionMachServiceName` is `EPZDEPSV69.Morris.CinematicCoreMacOS.extension` (`CinematicCoreExtension/Info.plist`). App and extension versions come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- `DeveloperFlags.allowRehearsalOutput`, `allowInjectedQualification` and `allowStageBelowShowRate` are `true` only inside `#if DEBUG` and `false` otherwise (`DeveloperFlags.swift`, the `a89644b` pattern).
- Release output under `CinematicCoreMacOS/build_out/` is tracked. CI must not read or write those files. This doc does not delete them.
- Stage 3 pull requests are merged with merge commits. Branch deletion is off. A required check has to run for a pull request whose base is not `main`.

## 1. Where the jobs run

| Option | What it is | Fit for Alfie | Cost |
|---|---|---|---|
| GitHub-hosted `macos-26` (arm64, standard) | Apple silicon VM. Current image includes Xcode 26.2 (17C52) at `/Applications/Xcode_26.2.app`. The image default is Xcode 26.6, not 26.2. | Matches the local Mac and the local Xcode build, if the job selects 26.2 explicitly. | Standard runners are free and unlimited on a public repository. The private-repo rate is listed at $0.062 per minute and does not apply here. Larger runners are billed even on public repos. |
| GitHub-hosted `macos-15` | Also has Xcode 26.2 installed. Default Xcode on that image is 16.4. | Usable, but it is not the OS Alfie is built on locally. | Same free standard-runner rule. |
| Self-hosted Mac | A machine the owner controls. | Can hold the notarization keychain the local script already uses (`alfie-notary`). | GitHub says self-hosted runners should almost never be used on a public repository, because a pull request can run code on that machine. |
| Xcode Cloud | Apple's CI, tied to App Store Connect. | Can archive and distribute, but it does not run `build_release.sh` and it is a second system beside GitHub. | **AWAITING OWNER** if this is ever reconsidered. Not recommended as the first pipeline. |

Sources: [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [Actions billing](https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions), [runner image macos-26 arm64](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), [secure use of self-hosted runners](https://docs.github.com/en/actions/reference/secure-use-reference).

**Recommendation:** GitHub Actions on the standard `macos-26` runner, with `xcode-select` pointed at Xcode 26.2 (17C52). Plain `xcodebuild`, `notarytool` and the existing `build_release.sh`. Not fastlane: the release steps are already in that script, and CI should call it rather than replace it. Not a self-hosted runner. Not a paid larger runner.

This recommendation does not need a paid service, a runner on the owner's Mac, or a change to the project's signing settings.

## 2. Signing

Two certificates, used by different jobs:

| Channel | Certificate | What it signs | When it runs |
|---|---|---|---|
| Developer ID DMG | Developer ID Application | App, embedded extension, then the DMG | Manual release job only |
| Mac App Store | Apple Distribution, plus provisioning profiles | App and extension inside an App Store archive | Manual validate job only |

`notarytool` accepts an App Store Connect API key (`--key`, `--key-id`, `--issuer`). A Team key is required for notarization; an Individual key cannot call `notarytool`. The private key is a `.p8` file downloaded once. CI should write it into a temporary file, use a temporary keychain for the Developer ID certificate, and delete both at the end of the job. The local keychain profile `alfie-notary` stays the way `build_release.sh` works on the owner's Mac. CI passes the API key into that script only if the script already accepts it; otherwise the release workflow mirrors the script's steps and the script itself is left unchanged.

Sources: [notarytool man page](https://keith.github.io/xcode-man-pages/notarytool.1.html), [TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool), [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).

### System extension

Apple documents CMIO camera extensions as packaged inside the app and installable through the App Store. The host app needs the system-extension install entitlement and an app group. The extension in this repo is sandboxed and uses the team-prefixed Mach service name above. App Review also requires a Mac App Store app to be sandboxed, self-contained, and updated only through the store.

That is not a promise that this particular extension will pass review. Hardware-camera use inside an extension needs the camera entitlement and a usage string. Whether Alfie's current entitlements are the Store set is **AWAITING OWNER**. No entitlement or `Info.plist` edit belongs in the CI change.

Sources: [Creating a camera extension with Core Media I/O](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o), [WWDC22 session 10022](https://developer.apple.com/videos/play/wwdc2022/10022/), [App Review Guidelines 2.4.5 and 4.4](https://developer.apple.com/app-store/review/guidelines/).

## 3. Notarization

On the Developer ID channel only:

1. `notarytool submit --wait` with the Team API key.
2. `stapler staple` the app and the DMG.
3. `stapler validate`, `codesign --verify --deep --strict`, and `spctl`.

Those are the same checks `build_release.sh` already runs locally. A pull request never notarizes.

## 4. Mac App Store, later

The archive export method is `app-store-connect`. The first Store workflow validates the archive and stops. Upload and TestFlight stay behind a second manual approval. TestFlight exists for macOS, but turning it on is **AWAITING OWNER**.

Basic and paid, as options only:

| Option | Shape | What it needs that we do not have |
|---|---|---|
| A. One app, StoreKit | One Mac App Store product. A paid tier is an in-app purchase. | Product IDs, prices, which features are paid. |
| B. Two apps | A basic bundle ID and a paid bundle ID. | Two products, two provisioning profiles, two version trains. |

**AWAITING OWNER.** Neither option is chosen here. No StoreKit code, prices or product IDs are part of this pipeline.

## 5. Protecting a public repo

- Pull-request workflows use `pull_request`, not `pull_request_target`. GitHub gives fork pull requests a read-only token and does not pass secrets.
- Signing jobs use a GitHub environment with required reviewers. The job cannot read those secrets until a reviewer approves.
- Required checks are the unsigned build, the unit tests (with the timing test handled as below), the Release compile, the Python tests, and the consistency script. They must run for every pull request, including one whose base is not `main`, because stacked Stage 3 pull requests merge that way. The workflow must not filter `pull_request` to `main` only.
- Third-party actions are pinned to a full commit SHA. Each job sets the smallest `permissions:` it needs.
- No self-hosted runner.

Sources: [Secrets](https://docs.github.com/en/actions/concepts/security/secrets), [pull_request_target](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target), [Environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

## 6. Gates

| Gate | Job | Trigger | Failure means |
|---|---|---|---|
| Debug build, including the extension | `ci` | Every pull request, and push to `main` | The app or the extension does not compile. |
| Unit tests, except the timing test | `ci` | Same | A logic test failed. |
| Timing test, non-blocking | `ci-timing` | Same | The 250 µs budget was missed. Does not block merge until the owner says it should. |
| Unsigned Release build | `ci` | Same | Release does not compile, which is how Debug-only code leaks. |
| Python tests | `ci` | Same | `test_diagnostics_report.py`, `training/test_env.py` or `training/test_training.py` failed. |
| Version, Mach-service prefix, entitlements, Debug-only flags | `ci` | Same | App and extension versions diverged, the `EPZDEPSV69.` prefix moved, an entitlement changed without a label, or a Debug-only flag is no longer forced false in Release. |
| Developer ID DMG | `release-dmg` | Manual, protected environment | Archive, notarization, staple or verify failed. |
| App Store validate only | `release-appstore` | Manual, protected environment | The Store export is not valid. Nothing is uploaded. |

`ProgramOutputMetricsTests/perFrameInstrumentationCostIsSmall` is omitted from the required test job with `-skip-testing`, and run in `ci-timing`, which is not a required check. Whether that timing job should ever become required is **AWAITING OWNER**. The test itself stays unchanged.

UI tests stay out of the required job. They need a headed Mac session. **AWAITING OWNER** whether a later optional job should run `CinematicCoreMacOSUITests`.

## Secrets the owner creates

Names only. This work never creates or reads the values.

| Name | Where | Used by |
|---|---|---|
| `APPLE_API_KEY_ID` | Environment `release` | Notarization and Store validation |
| `APPLE_API_ISSUER_ID` | Environment `release` | Team API key |
| `APPLE_API_KEY_P8` | Environment `release` | The `.p8` private key |
| `DEVELOPER_ID_APPLICATION_P12` | Environment `release` | Developer ID certificate |
| `DEVELOPER_ID_APPLICATION_PASSWORD` | Environment `release` | Password for that `.p12` |
| `APPLE_DISTRIBUTION_P12` | Environment `appstore` | Store signing, when that channel is real |
| `APPLE_DISTRIBUTION_PASSWORD` | Environment `appstore` | Password for that `.p12` |
| `MACOS_APPSTORE_PROFILE` | Environment `appstore` | Provisioning profile for the app |
| `MACOS_APPSTORE_EXTENSION_PROFILE` | Environment `appstore` | Provisioning profile for the extension |

Environments `release` and `appstore` need a required reviewer. The owner turns that on. CI does not change branch protection.

## Tracked build output

`CinematicCoreMacOS/build_out/` is tracked release output. CI uses a clean checkout and its own derived data, and it does not read that directory. Removing it from git is a later owner decision. **AWAITING OWNER.** This change does not delete those files.

## Open questions

- **AWAITING OWNER:** Should `ci-timing` stay non-blocking?
- **AWAITING OWNER:** One Store app with StoreKit, or two apps? No product IDs or prices until then.
- **AWAITING OWNER:** Is TestFlight for macOS in scope?
- **AWAITING OWNER:** Do the current entitlements stay for the Store build, or does that channel need a different set?
- **AWAITING OWNER:** Should `build_out/` stop being tracked?
- **AWAITING OWNER:** Should UI tests grow an optional job?

## What Phase 2 will add

On this same branch, after this doc is committed: `.github/workflows/ci.yml`, `release-dmg.yml`, `release-appstore.yml`, `scripts/ci/` for the consistency checks, and `docs/ci/README.md`. No Swift, project, entitlement or `Info.plist` edits. If the Store export needs those, they are listed here and in `integration-requests.md` instead of being made.
