//
//  ConsolePresentation.swift
//  CinematicCoreMacOS
//
//  Which main view the operator gets. The Multiview console (and everything
//  multi-camera: Preview, Take, a second input) exists only in Multi Cam.
//  Single Cam and Webcam keep the traditional single-camera view — wide
//  source plus crop and the existing pill. ContentView resolves this from the
//  operator mode; see docs/ALFIE_MULTICAMERA_SPEC.md "Operator modes".
//

import Foundation

nonisolated enum ConsolePresentation: Equatable, Sendable {
    /// Single Cam and Webcam: the single-camera console.
    case traditional
    /// Multi Cam: the Multiview console (Preview / Program / Take).
    case multiview

    /// The single mapping from operator mode to view.
    static func resolve(for mode: OperatorMode) -> ConsolePresentation {
        switch mode {
        case .multiCam: return .multiview
        case .singleCam, .webcam: return .traditional
        }
    }

    /// Multi-camera (a Preview input, Take, cueing) is Multi Cam only.
    var allowsMultipleInputs: Bool { self == .multiview }

    /// What fills ContentView's main layer.
    enum Screen: Equatable, Sendable {
        /// Multi Cam while capture runs.
        case multiviewConsole
        /// Multi Cam while stopped (SHOW-SETUP).
        case showSetup
        /// Single Cam or Webcam while capture runs: wide source + crop, the
        /// overlays and the operator pill.
        case singleCameraLive
        /// Single Cam or Webcam while stopped.
        case stopped
    }

    /// The single mapping from mode and capture state to the main screen.
    /// Without a show (previews) there is no Multiview console.
    static func screen(for mode: OperatorMode, isCaptureRunning: Bool, hasShow: Bool) -> Screen {
        if resolve(for: mode) == .multiview, hasShow {
            return isCaptureRunning ? .multiviewConsole : .showSetup
        }
        return isCaptureRunning ? .singleCameraLive : .stopped
    }
}
