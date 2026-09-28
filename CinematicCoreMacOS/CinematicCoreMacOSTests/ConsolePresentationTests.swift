//
//  ConsolePresentationTests.swift
//  CinematicCoreMacOSTests
//

import Testing
@testable import Alfie

struct ConsolePresentationTests {
    @Test func stageGetsMultiview() {
        #expect(ConsolePresentation.resolve(for: .stage) == .multiview)
        #expect(ConsolePresentation.multiview.allowsMultipleInputs)
    }

    @Test func webcamKeepsTheTraditionalSingleCameraView() {
        #expect(ConsolePresentation.resolve(for: .webcam) == .traditional)
        #expect(!ConsolePresentation.traditional.allowsMultipleInputs)
    }

    @Test func formatSwitchRefusedOnlyDuringAMultiCameraShow() {
        #expect(ConsolePresentation.canSwitchFormat(isShowRunning: false, runningInputs: 2))
        #expect(ConsolePresentation.canSwitchFormat(isShowRunning: true, runningInputs: 1))
        #expect(!ConsolePresentation.canSwitchFormat(isShowRunning: true, runningInputs: 2))
    }
}
