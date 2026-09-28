# Alfie operator guide — Beta 1.0 build 4

Open [index.html](index.html) locally for the operator steps. This guide describes the **current single-camera window** on the `r2/engine` source baseline, checked against `ContentView`, `OperatorPill`, `RecoveryState`, `CaptureProfilePolicy`, `InspectorDrawer` and Output settings on 28 September 2026. The R2 Multiview gallery and two-input engine are not available through this operator window.

The project currently builds for macOS **26.2 or later**. The guide is a source-checked draft; the candidate walk at 1280×800 pt, extension install/upgrade, camera permission refusal, downstream output, recovery with real subjects, and 60-minute rig checks remain **not rig-verified**. See [screenshot-checklist.md](screenshot-checklist.md), [R1 evidence](../../reports/release-1/README.md), and the [platform decision](../decisions/platform-baseline.md) before publishing a compatibility or performance claim.

For an issue report, record app version/build, Mac and macOS, camera/capture card, selected show standard and output route, what the operator pressed, and the matching diagnostic session files. Use **Settings → Output → Diagnostics → Open in Finder**. Inspect names, timestamps and notes before sharing; the app does not automatically upload them.
