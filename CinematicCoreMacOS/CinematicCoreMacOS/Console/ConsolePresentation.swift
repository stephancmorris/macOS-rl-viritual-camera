//
//  ConsolePresentation.swift
//  CinematicCoreMacOS
//
//  Which main view the operator gets. The Multiview console (and everything
//  multi-camera: Preview, Take, a second input) exists only in Stage format.
//  Webcam format keeps the traditional single-camera view — wide source plus
//  crop and the existing pill — exactly as today. ContentView resolves this
//  once integration lands; see docs/ALFIE_MULTICAMERA_SPEC.md "Format scope".
//

import Foundation

nonisolated enum ConsolePresentation: Equatable, Sendable {
    /// Webcam format: the existing single-camera console.
    case traditional
    /// Stage format: the Multiview console (Preview / Program / Take).
    case multiview

    static func resolve(for profile: CaptureProfilePolicy.Profile) -> ConsolePresentation {
        switch profile {
        case .stage: return .multiview
        case .webcam: return .traditional
        }
    }

    /// Multi-camera (a Preview input, Take, cueing) is Stage-only.
    var allowsMultipleInputs: Bool { self == .multiview }

    /// Changing format swaps the whole console, so it is refused while a
    /// multi-camera show runs; the operator stops the show first. A
    /// single-camera session can switch as it does today.
    static func canSwitchFormat(isShowRunning: Bool, runningInputs: Int) -> Bool {
        !(isShowRunning && runningInputs > 1)
    }
}
