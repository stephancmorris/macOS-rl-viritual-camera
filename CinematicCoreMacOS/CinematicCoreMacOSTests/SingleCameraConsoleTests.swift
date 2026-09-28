//
//  SingleCameraConsoleTests.swift
//  CinematicCoreMacOSTests
//

import CoreGraphics
import Testing
@testable import Alfie

struct SingleCameraConsoleTests {
    private func inputs(running: Bool = true, holding: Bool = false) -> SingleCameraConsole.Inputs {
        .init(cameraName: "Stage wide", shot: "Waist Up", isRunning: running, deliveredFPS: 50,
              isProgramHolding: holding, showStandard: .p50,
              legalCrop: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.4), operatorNote: nil)
    }

    @Test func runningCameraIsRoutedProgramWithNoPreview() {
        let snapshot = SingleCameraConsole.snapshot(inputs())
        #expect(snapshot.programOutput == .routed)
        #expect(snapshot.previewChannel == nil)
        #expect(snapshot.assignedInputCount == 1)
        #expect(snapshot.slot(.a).input?.role == .program)
        #expect(PaneModel.program(from: snapshot).label == "PROGRAM · CAM A · Stage wide · Waist Up")
        #expect(PaneOverlayState.preview(for: snapshot).title == "No Preview camera")
        #expect(TakeAvailability.evaluate(snapshot).reasonText == "No Preview camera")
        // With no Preview, the controls act on Program (the only camera).
        #expect(snapshot.controlTarget == .init(channel: .a, role: .program))
    }

    @Test func singleCameraHoldHasNoStandbyCountdown() {
        let snapshot = SingleCameraConsole.snapshot(inputs(holding: true))
        #expect(PaneModel.program(from: snapshot).status == "Holding last good frame")
        #expect(PaneOverlayState.program(for: snapshot).title == "Hold · last good frame")
    }

    @Test func stoppedCaptureIsStandbyAndMissing() {
        let snapshot = SingleCameraConsole.snapshot(inputs(running: false))
        #expect(snapshot.programOutput == .standby)
        #expect(snapshot.slot(.a).input?.health == .missing)
        // One input: standby copy names no second camera.
        #expect(PaneOverlayState.program(for: snapshot).detail == "Cam A disconnected. Alfie is sending black at 1080p50.")
    }
}
