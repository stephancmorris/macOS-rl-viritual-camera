//
//  ConsolePresentationTests.swift
//  CinematicCoreMacOSTests
//

import Testing
@testable import Alfie

struct ConsolePresentationTests {
    @Test func multiCamGetsMultiview() {
        #expect(ConsolePresentation.resolve(for: .multiCam) == .multiview)
        #expect(ConsolePresentation.multiview.allowsMultipleInputs)
    }

    @Test func singleCamAndWebcamKeepTheTraditionalSingleCameraView() {
        #expect(ConsolePresentation.resolve(for: .singleCam) == .traditional)
        #expect(ConsolePresentation.resolve(for: .webcam) == .traditional)
        #expect(!ConsolePresentation.traditional.allowsMultipleInputs)
    }

    @Test func formatSwitchRefusedOnlyDuringAMultiCameraShow() {
        #expect(ConsolePresentation.canSwitchFormat(isShowRunning: false, runningInputs: 2))
        #expect(ConsolePresentation.canSwitchFormat(isShowRunning: true, runningInputs: 1))
        #expect(!ConsolePresentation.canSwitchFormat(isShowRunning: true, runningInputs: 2))
    }
}
