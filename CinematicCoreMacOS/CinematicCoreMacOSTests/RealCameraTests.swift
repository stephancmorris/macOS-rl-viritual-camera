//
//  RealCameraTests.swift
//  CinematicCoreMacOSTests
//
//  Opt-in checks against the cameras attached to this Mac (two webcams are
//  enough). Skipped unless ALFIE_CAMERA_TESTS=1 is set for the test runner:
//  TEST_RUNNER_ALFIE_CAMERA_TESTS=1 xcodebuild test ...
//

#if DEBUG
import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALFIE_CAMERA_TESTS"] == "1"))
struct RealCameraTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-camera-\(UUID().uuidString)")!))
    }

    private func waitForRender(_ channel: CameraManager, seconds: Double = 8) async -> RenderedChannelFrame? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let frame = channel.latestRenderedFrame, channel.renderedFrameCount > 10 { return frame }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return channel.latestRenderedFrame
    }

    /// Mean of the sampled 8-bit channels (BGRA or luma plane); 0 is black.
    private func meanLevel(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer) else { return -1 }
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0, count = 0.0
        for row in stride(from: 0, to: height, by: max(1, height / 32)) {
            for column in stride(from: 0, to: rowBytes, by: max(1, rowBytes / 64)) {
                total += Double(bytes[row * rowBytes + column]); count += 1
            }
        }
        return count > 0 ? total / count : -1
    }

    @Test func twoWebcamsRenderPicturesAndBJoinsWithoutCrashing() async throws {
        let show = show()
        let a = show.channelA
        a.discoverCameras()
        let cameras = a.availableCameras
        print("[camera-test] cameras: \(cameras.map(\.name)) format=\(a.shotComposer.config.cinematicFormat)")
        try #require(cameras.count >= 2, "needs two cameras")

        a.selectedCamera = cameras[0]
        _ = a.dispatch(a.makeCommand(.startSession))
        let frameA = await waitForRender(a)
        print("[camera-test] A=\(cameras[0].name) running=\(a.isRunning) rendered=\(a.renderedFrameCount) error=\(String(describing: a.error)) cropped=\(a.croppedFrameBuffer != nil)")
        let renderedA = try #require(frameA)
        let levelA = meanLevel(renderedA.pixelBuffer)
        print("[camera-test] A mean level \(levelA) format=\(CVPixelBufferGetPixelFormatType(renderedA.pixelBuffer)) size=\(CVPixelBufferGetWidth(renderedA.pixelBuffer))x\(CVPixelBufferGetHeight(renderedA.pixelBuffer))")
        #expect(levelA > 8)

        let b = show.addChannel(.b)
        b.selectedCamera = cameras[1]
        _ = b.dispatch(b.makeCommand(.startSession))
        let frameB = await waitForRender(b)
        print("[camera-test] B=\(cameras[1].name) running=\(b.isRunning) rendered=\(b.renderedFrameCount) error=\(String(describing: b.error))")
        let renderedB = try #require(frameB)
        print("[camera-test] B mean level \(meanLevel(renderedB.pixelBuffer))")
        #expect(meanLevel(renderedB.pixelBuffer) > 8)
        #expect(a.renderedFrameCount > 20)

        show.stopShow()
    }
}
#endif
