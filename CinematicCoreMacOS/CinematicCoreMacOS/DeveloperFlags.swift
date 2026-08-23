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

    /// Run Vision at most every Nth captured frame. 1 = every frame.
    ///
    /// This is a *load* limiter, not the throughput fix. Detection no longer
    /// blocks the frame path (see `CameraManager.scheduleDetectionIfDue`), so
    /// the program feed runs at full rate regardless of this value; the interval
    /// only decides how much background CPU detection is allowed to consume.
    ///
    /// Measured 26 July: detection costs ~16.4 ms of wall time per run. At
    /// interval 2 that is roughly half a core's worth of sustained background
    /// work instead of a full one, with the newest detection 20–40 ms old —
    /// well inside the crop spring's own time constant.
    ///
    /// Set to 1 to restore per-frame detection for an A/B comparison.
    nonisolated static let detectionFrameInterval = 2

    /// How often (seconds) to drop Core Image's internal caches. 0 disables.
    ///
    /// Measured 26 July: Alfie retains ~40 small allocations per frame. They
    /// accumulate until something releases them in bulk, and as the pile grows
    /// the MainActor gets slower — past ~5 ms of frame-start delay the capture
    /// gate begins discarding frames and the feed visibly stutters. Three
    /// natural releases were observed in one 42-minute session, at 13, 5 and
    /// 20-minute intervals; each restored 50 fps instantly. Left to itself that
    /// is a choppy patch of unpredictable length arriving mid-show.
    ///
    /// **Now 0 (off), deliberately.** This was a stop-gap that swept up the mess
    /// periodically. The real cause turned out to be autorelease pools that were
    /// never draining per work item — fixed at source in `PersonDetector`,
    /// `CameraManager` and `FaceSignatureExtractor`. Leaving both in place would
    /// mask whether that fix actually worked, so the flush stays off while the
    /// before/after soak is run. Set to 30 only to A/B it back.
    nonisolated static let imageCacheFlushInterval: TimeInterval = 0
}
