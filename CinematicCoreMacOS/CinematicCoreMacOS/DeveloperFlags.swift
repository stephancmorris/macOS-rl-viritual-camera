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
    /// Exposes the ML agent toggle, agent settings popover, and enables
    /// `useMLAgent` as a runtime-selectable controller. Church MVP ships
    /// with this off so `ShotComposer` is the only controller operators see.
    static let exposeMLAgentControls = false

    /// Exposes the training-data recorder UI. Recorder infrastructure stays
    /// compiled in regardless; this only controls whether operators can
    /// start/stop recordings from the toolbar.
    static let exposeTrainingRecorderControls = false
}
