//
//  OperatorModeChoiceTests.swift
//  CinematicCoreMacOSTests
//
//  MODE-PICKER: Single Cam is the default and always offered; Multi Cam
//  unlocks once a second camera is connected; Webcam shows only with a
//  built-in camera; the current mode is never hidden or greyed out; and
//  Alfie's own virtual camera is never counted as a source.
//

#if DEBUG
import Foundation
import Testing
@testable import Alfie

struct OperatorModeChoiceTests {
    private typealias Cameras = OperatorModeChoice.Cameras

    private func choices(_ cameras: Cameras, current: OperatorMode = .singleCam,
                         available: [OperatorMode] = OperatorMode.allCases) -> [OperatorModeChoice] {
        OperatorModeChoice.choices(available: available, current: current, cameras: cameras)
    }

    @Test func oneStageCameraOffersSingleCamWithMultiCamLocked() {
        let result = choices(Cameras(count: 1, hasBuiltIn: false))
        #expect(result.map(\.mode) == [.singleCam, .multiCam])
        #expect(result.map(\.isEnabled) == [true, false])
        #expect(result.map(\.note) == ["Default", "Connect a 2nd camera"])
    }

    @Test func secondCameraUnlocksMultiCam() {
        let result = choices(Cameras(count: 2, hasBuiltIn: false))
        #expect(result.first { $0.mode == .multiCam }?.isEnabled == true)
        #expect(result.first { $0.mode == .multiCam }?.note == "2 cameras found")
    }

    @Test func builtInCameraShowsWebcam() {
        let result = choices(Cameras(count: 1, hasBuiltIn: true))
        #expect(result.map(\.mode) == [.singleCam, .multiCam, .webcam])
        #expect(result.last?.isEnabled == true)
        #expect(result.last?.note == "Built-in camera found")
    }

    @Test func theCurrentModeIsNeverHiddenOrLocked() {
        let multi = choices(Cameras(count: 1, hasBuiltIn: false), current: .multiCam)
        #expect(multi.first { $0.mode == .multiCam }?.isEnabled == true)

        let webcam = choices(Cameras(count: 1, hasBuiltIn: false), current: .webcam)
        #expect(webcam.first { $0.mode == .webcam }?.isEnabled == true)
        #expect(webcam.first { $0.mode == .webcam }?.note == "No built-in camera")
    }

    @Test func noCamerasStillOffersSingleCam() {
        let result = choices(Cameras(count: 0, hasBuiltIn: false))
        #expect(result.first?.mode == .singleCam)
        #expect(result.first?.isEnabled == true)
    }

    @Test func killSwitchStillRemovesMultiCam() {
        let available = OperatorMode.available(multiviewEnabled: false)
        let result = choices(Cameras(count: 3, hasBuiltIn: true), available: available)
        #expect(result.map(\.mode) == [.singleCam, .webcam])
    }

    @Test func alfieVirtualCameraAndDuplicatesAreNotCounted() {
        let cameras = Cameras(devices: [
            (uniqueID: "usb-1", isBuiltIn: false),
            (uniqueID: "usb-1", isBuiltIn: false),
            (uniqueID: Cameras.alfieVirtualCameraID.lowercased(), isBuiltIn: false),
        ])
        #expect(cameras == Cameras(count: 1, hasBuiltIn: false))
    }

    @Test func builtInDiscoveryIsCarriedThrough() {
        let cameras = Cameras(devices: [
            (uniqueID: "usb-1", isBuiltIn: false),
            (uniqueID: "facetime", isBuiltIn: true),
        ])
        #expect(cameras == Cameras(count: 2, hasBuiltIn: true))
    }
}
#endif
