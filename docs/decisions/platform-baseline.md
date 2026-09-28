# Platform baseline and distribution decision

Status: decision requested; source audit on `r2/sol`, 28 September 2026. No deployment or signing setting changed here.

## Current contract and evidence

The Xcode project sets `MACOSX_DEPLOYMENT_TARGET = 26.2` for Debug and Release. The host used for this audit is macOS 26.6.2 on arm64; an app build and unit tests pass there. The product text elsewhere still says macOS 14+, which the current binary cannot support. There is no build-and-launch evidence for 14, 15, 16, 25, or a separate Intel Mac.

| Component | Repository evidence | Baseline implication |
| --- | --- | --- |
| Virtual camera | `CinematicCoreExtension/CinematicCoreExtensionProvider.swift` implements `CMIOExtensionProvider`, device and stream sources; `SystemExtensionActivationManager.swift` activates it. | Apple introduced Core Media I/O camera extensions in macOS 12.3; this alone does not justify 26.2 or prove 14 compatibility. [Apple camera-extension guide](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o) |
| UI | `CinematicCoreMacOSApp.swift` uses `WindowGroup`, `Settings`, and a Debug-only Multiview gallery `Window` scene; Program Display uses `NSWindow`. | Check each API/modifier against the chosen minimum and test the complete workflow, including the gallery only where applicable. The gallery is not a release capability. |
| Tests and compiler | Unit tests import Swift Testing; project uses default MainActor isolation and MemberImportVisibility. | These are build/toolchain constraints. They do not by themselves set the end-user OS minimum, but the tested Xcode/Swift version must be recorded. |
| Capture and output | `CameraManager`, `DisplayOutputSink`, `ProgramOutputManager`, and the system extension use AVCapture, IOSurface/Core Video and SystemExtensions. | Launch, consent, extension activation, output routing and unplug behavior need tests on the proposed floor and each representative architecture/rig. |
| Packaging | Host and extension are sandboxed with a matching application group and system-extension install entitlement. The extension is embedded under `Contents/Library/SystemExtensions`. | Apple requires same-team signing and either Mac App Store distribution or notarization for app plus system extension. [Apple System Extensions](https://developer.apple.com/documentation/systemextensions) |

## OS options

1. **Ship with macOS 26.2 minimum initially.** This matches the project and current host evidence. It limits the supported Mac population, so all operator copy must say 26.2 until a lower baseline passes. It still needs a clean 26.2 build/launch and two-camera rig qualification; 26.6.2 success is not a 26.2 pass.
2. **Target macOS 14 or another lower version.** This may widen support, but requires an API availability audit, guarded or replacement APIs, a changed deployment target, and build/install/permission/extension/Program Display/two-input tests on that exact OS. Product copy must wait for those results. macOS 12.3 is an API floor for camera extensions, not a supported-product decision.
3. **Use an intermediate floor.** Select only after collecting the same evidence on a representative Mac at that OS; do not infer support from compiler availability.

**Recommendation:** keep 26.2 as the provisional engineering baseline and remove the unsupported “14+” release claim. Decide whether wider support is worth a separate compatibility work unit after R1/R2 hardware evidence. The approved minimum is the oldest OS on which the complete candidate was built, installed, launched and qualified, not the oldest OS named in an API declaration.

## Distribution options

| Route | Benefit | Evidence still needed |
| --- | --- | --- |
| Mac App Store | Matches the current R2 product scope; Apple handles store delivery and updates. | App Store Connect signing/provisioning, privacy disclosures, archive validation, CMIO extension installation/update, sandboxed diagnostics access, camera permission and clean install on a supported Mac. Store review outcome is unknown. |
| Direct Developer ID + notarization | Can support controlled rig trials and operator installation outside the store. | Developer ID host/extension signing, notarization/stapling, Gatekeeper/extension approval, update path, support procedure and diagnostics location on a clean Mac. It is an alternate distribution decision, not proof of store readiness. [Apple distribution overview](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) |

**Recommendation:** treat Mac App Store as the release destination already chosen on the board, and use notarized direct builds only if controlled qualification needs them. Apple documents both Mac App Store and notarized distribution for system extensions. [Apple System Extensions](https://developer.apple.com/documentation/systemextensions)

## Decision and test gates to close

- Product owner chooses the minimum OS and whether Intel is supported. Record exact OS builds, Mac models/architecture, camera/capture cards, hubs, output route, and app/extension build identifiers in the release matrix.
- Build and **launch** the candidate on the proposed minimum OS. Test first-run camera consent, denial/revocation, CMIO install/upgrade, virtual camera client, Program Display, single-camera baseline and two-input soak. A build on 26.6.2 is not sufficient.
- Resolve current UI test runner host authorization and privacy-manifest packaging before claiming distribution readiness.
- Update product copy and project settings together after approval; this memo itself authorizes neither change.
