//
//  StartGateTests.swift
//  CinematicCoreMacOSTests
//
//  CR-036: when the virtual camera cannot be installed, Start goes ahead only
//  if Program has somewhere else to go.
//

import Testing
@testable import Alfie

@MainActor struct StartGateTests {
    @Test func connectedDirectOutputDoesNotNeedTheVirtualCamera() {
        #expect(!ContentView.startNeedsVirtualCamera(preferredRoute: .display, directOutputAvailable: true))
    }

    @Test func missingDirectOutputFallsBackToTheVirtualCamera() {
        #expect(ContentView.startNeedsVirtualCamera(preferredRoute: .display, directOutputAvailable: false))
    }

    @Test func virtualCameraRouteAlwaysNeedsIt() {
        #expect(ContentView.startNeedsVirtualCamera(preferredRoute: .virtualCamera, directOutputAvailable: true))
        #expect(ContentView.startNeedsVirtualCamera(preferredRoute: .virtualCamera, directOutputAvailable: false))
    }

    @Test func rehearsalDoesNotNeedIt() {
        #expect(!ContentView.startNeedsVirtualCamera(preferredRoute: .rehearsal, directOutputAvailable: false))
    }
}
