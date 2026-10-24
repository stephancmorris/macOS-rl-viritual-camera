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
}
