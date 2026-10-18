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

    /// Changing format swaps the whole console, so it is refused while a
    /// multi-camera show runs; the operator stops the show first. A
    /// single-camera session can switch as it does today.
    static func canSwitchFormat(isShowRunning: Bool, runningInputs: Int) -> Bool {
        !(isShowRunning && runningInputs > 1)
    }
}
