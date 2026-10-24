# Alfie — operator-controlled live framing

Alfie frames camera pictures into one Program feed. The operator chooses the subject and composition. Choose Single Cam for one stage camera and every Stage shot, Multi Cam for Camera A/B Program/Preview with manual Take and deliberate Edit Live, or Webcam for the close-range single-camera workflow.

The Debug candidate also attaches Director status and controls. Preparation, automatic-cut, Backup, discovery and local-model study components require explicit settings and current prerequisites; ordinary app construction installs no execution-study settings, discovery budget or learned scorer. Every launch starts Manual. Release disables Director shadow, Assist and automatic effects. Active-speaker listening, microphone control and hardware motion remain deferred.

See the [current candidate operator guide](docs/user-guide/README.md). The [combined candidate review](reports/operator-followups-2026-10-21/README.md) includes the PR #66 modes and stopped Release screenshots. Installation, live mode/refusal checks, exact point-size and VoiceOver acceptance, and real-camera/downstream-output checks remain open. Verify the supplied build fingerprint before use. Source and synthetic evidence describe a software review candidate, not a certified rig or released build.

## Inputs and framing

Camera/capture devices supply the delivered resolution and rate. Stage framing benefits from a clean wide 4K source; Webcam supports a closer source. Check actual delivery rather than advertised camera specifications. Capture follows the session show standard: default 1080p50, with 59.94/60 options. The active standard is frozen until Stop/restart.

Vision body/pose/face observations support operator-selected subject tracking. ShotComposer provides rule-based framing and recovery; the RL agent remains developer scaffolding. Core Image renders the crop to Program. Detection confidence alone is not qualified identity readiness.

With two inputs, prepare Preview without changing Program, then Take explicitly. A successful Take swaps roles. Controls normally target Preview; Edit Live targets Program deliberately. Return to Wide affects the controlled camera, so widening Preview does not widen Program. C/D slots are reserved; three/four live inputs remain separate follow-on work.

## One routed output

- Direct output (HDMI / USB-C) uses a selected Output port for converter/switcher chains. An explicitly selected port is reserved black before Start; Start requests the show format. Automatic does not reserve a port.
- Virtual Camera uses a local CoreMediaIO system extension and IOSurface/XPC handoff to a compatible receiving client.

These are alternative Program destinations, not a required dual-output feed. Rehearsal output does not prove an external route works. No Blackmagic Desktop Video SDK/SDI integration is implemented. Verify the receiving device independently; app handoff counters are not physical presentation.

## Build and verification

Use an Apple Silicon Mac and an Xcode/toolchain supporting the project's Swift features and macOS 26.2 deployment target. Open `CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj`; scheme `CinematicCoreMacOS` builds the app named Alfie. Camera permission and system-extension approval depend on the selected input/output workflow. Launching the stopped setup does not by itself start capture.

Current implementation includes framing, manual A/B routing/Take, Multiview and diagnostics. Release qualification remains open: candidate fingerprints, named rigs, sustained single/two-input loads, faults/recovery, install and actual downstream output. Development overrides are not certified production behavior. See [R1 evidence](reports/release-1/README.md) and the [multicamera specification](docs/ALFIE_MULTICAMERA_SPEC.md).

Optional Training Data recording persists person/pose/crop observations and metadata after explicit consent; it is not raw video recording. Consent can be revoked during recording: new observation admission stops immediately, existing batches finish with normal drop accounting, and restart waits for shutdown and renewed consent. Existing files remain.

Session diagnostics are automatic. The separate [explicit metrics exporter](docs/privacy/current-source-audit.md#explicit-metrics-export) creates a local allowlisted projection from selected CSV files; the detailed diagnostics report and raw logs retain identifying context. Review the [current-source privacy inventory](docs/privacy/current-source-audit.md) and the selected artifact before sharing.

The [subject-tools software report](reports/auto-director/subject-tools-2026-10-21/README.md) and [execution-boundary report](reports/auto-director/execution-sinks-2026-10-21/README.md) describe the preceding Director candidate evidence. Current PRIVACY/DOCS software changes need human review; live permission/install/output and operator walkthrough acceptance remain open.

## License

Proprietary / Internal Use Only
