//
//  DeveloperFlags.swift
//  CinematicCoreMacOS
//
//  Compile-time switches for developer-only surfaces. Operator-facing builds
//  keep every flag `false`; flip a flag and rebuild to expose experimental
//  controls such as the RL agent and the training-data recorder.
//

import Foundation

enum DeveloperFlags {
    /// Exposes the Gate 5 validation playback controls so recorded church
    /// clips can be routed through the same detection/crop pipeline as the
    /// live camera feed.
    nonisolated static let exposeClipPlaybackControls = true

    /// Exposes the ML agent toggle, agent settings popover, and enables
    /// `useMLAgent` as a runtime-selectable controller. Church MVP ships
    /// with this off so `ShotComposer` is the only controller operators see.
    nonisolated static let exposeMLAgentControls = false

    /// Exposes the training-data recorder UI. Recorder infrastructure stays
    /// compiled in regardless; this only controls whether operators can
    /// start/stop recordings from the toolbar.
    nonisolated static let exposeTrainingRecorderControls = false

    /// Enables verbose per-frame logging in the capture loop. Keep this off
    /// for operator-facing builds because it can emit hundreds of log lines
    /// per second while tracking is active.
    nonisolated static let verboseFrameLogging = false

    /// Emits one structured `[LATENCY]` line per processed frame summarising
    /// total, detection, crop, and compose timings plus accumulated gate-drop
    /// counts. Use this when diagnosing choppy output — see the
    /// "as-a-senior-software-stateful-penguin" plan for expected baselines.
    ///
    /// MUST stay `false` in operator builds. This emits an `os_log` `.notice`
    /// with a `.public` string on **every processed frame** — 50 persisted log
    /// entries per second from the MainActor. Sustained logging at that rate
    /// backs up `logd` ingestion and progressively slows the emitting process,
    /// and it feeds back on itself: as frames start dropping, the drop paths
    /// log too. The throttled `[SOAK]` line (ProgramOutputManager, ~5 s) and the
    /// 1 Hz `CaptureThroughput` summary carry the same signal at a sane rate.
    nonisolated static let latencyConsoleLogging = false
}
