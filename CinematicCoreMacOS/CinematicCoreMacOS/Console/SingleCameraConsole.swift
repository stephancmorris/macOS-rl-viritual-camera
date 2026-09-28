//
//  SingleCameraConsole.swift
//  CinematicCoreMacOS
//
//  Maps today's single-camera pipeline onto the Multiview console contract,
//  so the console can be shown in Stage mode before multi-camera exists:
//  Cam A is Program, Preview reads "No Preview camera", Take is unavailable.
//  Pure and nonisolated: the caller copies plain values out of CameraManager
//  (coalesced, not per frame). Not wired into ContentView yet.
//

import CoreGraphics
import Foundation

nonisolated enum SingleCameraConsole {

    /// Plain values read from the running single-camera pipeline.
    struct Inputs: Equatable, Sendable {
        var cameraName: String
        /// Current framing title, e.g. "Waist Up".
        var shot: String
        var isRunning: Bool
        /// Delivered capture rate (measured), fps.
        var deliveredFPS: Double
        /// Program is repeating the last good render (render-failure HOLD).
        var isProgramHolding: Bool
        var showStandard: ShowStandard
        /// Current crop, normalised, top-left origin (for Source view).
        var legalCrop: CGRect
        var operatorNote: String?
    }

    static func snapshot(_ inputs: Inputs, paneView: ConsoleSnapshot.PaneView = .shot) -> ConsoleSnapshot {
        let camA = ConsoleSnapshot.Slot.Input(
            name: inputs.cameraName,
            shot: inputs.shot,
            role: .program,
            health: inputs.isRunning ? .running(deliveredRate: inputs.deliveredFPS) : .missing,
            legalCrop: inputs.legalCrop)

        let output: ConsoleSnapshot.ProgramOutput
        if !inputs.isRunning {
            output = .standby
        } else if inputs.isProgramHolding {
            // Single-camera HOLD repeats the last good frame with no standby timer.
            output = .holding(standbyIn: nil)
        } else {
            output = .routed
        }

        return ConsoleSnapshot(
            slots: [
                .init(channel: .a, input: camA),
                .init(channel: .b, input: nil),
                .init(channel: .c, input: nil),
                .init(channel: .d, input: nil),
            ],
            programChannel: .a,
            previewChannel: nil,
            programOutput: output,
            // Irrelevant with no Preview: TakeAvailability reports "No Preview camera".
            take: .ready,
            editLive: false,
            showStandard: inputs.showStandard,
            paneView: paneView,
            operatorNote: inputs.operatorNote)
    }
}
