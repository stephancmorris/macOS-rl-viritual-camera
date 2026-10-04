# Alfie — operator-controlled live framing

Alfie frames camera pictures into one Program feed. The operator chooses the subject and composition. Current Stage code provides Camera A/B Program/Preview, manual Take and deliberate Edit Live; Webcam uses the single-camera workflow. Automatic Director cuts, active-speaker listening, hardware motion and microphone control are not integrated.

See the [current candidate operator guide](docs/user-guide/README.md). Its workflow was source-checked against `7691e6e`, with consent and pair-history instructions updated for `bb7e692` and `1bcb3d6`; actual installation, 1280-point walkthrough, screenshots and real-camera/downstream-output qualification remain pending. This README describes implemented code, not a certified rig or released build.

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

Optional Training Data recording persists person/pose/crop observations and metadata after explicit consent; it is not raw video recording. Session diagnostics are automatic. Review the [current-source privacy audit](docs/privacy/current-source-audit.md) before making storage/retention/export claims.

## License

Proprietary / Internal Use Only
