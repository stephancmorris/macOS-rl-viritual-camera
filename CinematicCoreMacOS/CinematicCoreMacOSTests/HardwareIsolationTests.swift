import AVFoundation
import Foundation
import Testing
@testable import Alfie

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_CAMERA_TESTS"] != "1"))
struct HardwareIsolationTests {
    @Test func ordinaryFixturesAndTheAppHostNeverEnumerateSystemCameras() {
        #expect(CinematicCoreMacOSApp.isUnitTestHost)
        let camera = TestHardware.makeCamera()
        let show = TestHardware.makeShow()
        let b = show.addChannel(.b)
        #expect(camera.availableCameras.isEmpty && show.channelA.availableCameras.isEmpty && b.availableCameras.isEmpty)
        #expect(!camera.observesCameraDeviceNotifications && !b.observesCameraDeviceNotifications)
        #expect(camera.programOutput.configuredRoutes.isEmpty)
        #expect(show.programOutput.configuredRoutes.isEmpty)
        #expect(CameraManager.systemDeviceDiscoveryCount == 0)
    }

    @Test func realDeviceNotificationCannotRediscoverAnIsolatedSetup() async {
        var discoveries = 0
        let source = CameraManager.DeviceSource(discover: { discoveries += 1; return [] }, permitsHardwareAccess: false)
        let show = TestHardware.makeShow(cameraDeviceSource: source)
        let setup = LiveShowSetupModel(show: show, startChannelA: {})
        let initial = discoveries
        NotificationCenter.default.post(name: AVCaptureDevice.wasConnectedNotification, object: nil)
        NotificationCenter.default.post(name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(discoveries == initial)
        #expect(setup.setup.devices.isEmpty)
        #expect(CameraManager.systemDeviceDiscoveryCount == 0)
    }

    @Test func ordinaryUnitSourcesCannotUseLiveConstructors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" && !["RealCameraTests.swift", "TestHardware.swift", "HardwareIsolationTests.swift"].contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("CameraManager("), "Use TestHardware.makeCamera in \(file.lastPathComponent)")
            #expect(!source.contains("ShowCoordinator("), "Use TestHardware.makeShow in \(file.lastPathComponent)")
        }
    }
}
