//
//  SingleCamTests.swift
//  CinematicCoreMacOSTests
//
//  SINGLE-CAM card: Single Cam gets the single-camera view (not the
//  Multiview console or Show setup), the Stage pill with every Stage shot,
//  Manual and Auto Pan, a zoom ladder over all three Stage shots, A as the
//  only channel and Program, and Program frames on the route.
//

#if DEBUG
import AppKit
import CoreVideo
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
private final class SingleCamFakeSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .display
    private(set) var sent: [CVPixelBuffer] = []
    var isAvailable: Bool { true }
    var summary: String { "fake" }
    var detail: String { "fake" }
    var lastErrorDescription: String? { nil }
    var onStateChange: (() -> Void)?
    func connect() {}
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        sent.append(pixelBuffer)
        return true
    }
}

@MainActor
struct SingleCamTests {
    private func store(_ mode: OperatorMode) -> OperatorModeStore {
        OperatorModeStore(defaults: UserDefaults(suiteName: "alfie-single-\(UUID().uuidString)")!
            .with(mode: mode), multiviewEnabled: true)
    }

    private func show(_ mode: OperatorMode, sink: SingleCamFakeSink? = nil) -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: [sink ?? SingleCamFakeSink()]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-single-\(UUID().uuidString)")!),
            operatorModes: store(mode))
    }

    // MARK: Screen selection

    @Test func everyModeAndCaptureStateGetsItsScreen() {
        let table: [(OperatorMode, Bool, ConsolePresentation.Screen)] = [
            (.singleCam, true, .singleCameraLive),
            (.singleCam, false, .stopped),
            (.multiCam, true, .multiviewConsole),
            (.multiCam, false, .showSetup),
            (.webcam, true, .singleCameraLive),
            (.webcam, false, .stopped),
        ]
        for (mode, running, screen) in table {
            #expect(ConsolePresentation.screen(for: mode, isCaptureRunning: running, hasShow: true) == screen,
                    "\(mode) running \(running)")
        }
        // Without a show (previews) Multi Cam has no console to show.
        #expect(ConsolePresentation.screen(for: .multiCam, isCaptureRunning: true, hasShow: false) == .singleCameraLive)
        #expect(ConsolePresentation.screen(for: .multiCam, isCaptureRunning: false, hasShow: false) == .stopped)
    }

    // MARK: Channels and Program

    @Test func singleCamRunsTheStageFormatOnCameraAAlone() {
        let show = show(.singleCam)
        #expect(show.channelA.shotComposer.config.cinematicFormat == .stage)
        #expect(show.channel(.b) == nil)
        #expect(show.programChannel == .a)
        #expect(show.previewChannel == nil)
    }

    @Test func enteringSingleCamWhileStoppedDropsCamBAndKeepsAAsProgram() {
        let show = show(.multiCam)
        show.addChannel(.b)
        #expect(show.previewChannel == .b)

        show.operatorModes.select(.singleCam)
        #expect(show.channel(.b) == nil)
        #expect(show.programChannel == .a)
        #expect(show.previewChannel == nil)
        #expect(show.controlTarget == .a)
        // No Preview: Take has nothing to take.
        #expect(show.makeTakeRequest() == nil)
    }

    @Test func enteringSingleCamNeverStopsARunningCamB() {
        // Leaving Multi Cam with B live is refused by MODE-SWITCH; until then
        // the mode change must at least never drop a running input.
        let show = show(.multiCam)
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        show.operatorModes.select(.singleCam)
        #expect(show.channel(.b) === b)
    }

    @Test func programFramesFromCamAReachTheRouteInSingleCam() throws {
        let sink = SingleCamFakeSink()
        let show = show(.multiCam, sink: sink)
        show.addChannel(.b)
        show.operatorModes.select(.singleCam)

        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let frame = try #require(buffer)
        show.channelA.outputPort.sendFrame(frame, timestamp: 1, isRepeat: false)
        #expect(sink.sent.last === frame)
    }

    // MARK: Shots

    private func settle(_ manager: CameraManager, start: Double = 100) {
        for frame in 0...1000 { manager.advanceShotMove(now: start + Double(frame) / 50) }
    }

    @Test func zoomWalksAllThreeStageShotsBothWays() throws {
        let manager = show(.singleCam).channelA
        let engine = try #require(manager.cropEngine)
        manager.selectPreset(.stage(.wide))
        #expect(manager.canBeginZoom(.pushIn) && !manager.canBeginZoom(.pullOut))

        manager.beginZoom(.pushIn)
        settle(manager)
        #expect(manager.shotComposer.config.shotPreset == .fullBody)
        #expect(abs(engine.currentCrop.size.height - 0.8) < 0.00001)

        manager.beginZoom(.pushIn)
        settle(manager, start: 130)
        #expect(manager.shotComposer.config.shotPreset == .waistUp)
        #expect(abs(engine.currentCrop.size.height - 0.5) < 0.00001)
        #expect(!manager.canBeginZoom(.pushIn) && manager.canBeginZoom(.pullOut))

        manager.beginZoom(.pullOut)
        settle(manager, start: 160)
        #expect(manager.shotComposer.config.shotPreset == .fullBody)

        manager.beginZoom(.pullOut)
        settle(manager, start: 190)
        #expect(manager.shotComposer.config.shotPreset == .wide)
        #expect(manager.canBeginZoom(.pushIn) && !manager.canBeginZoom(.pullOut))
    }

    // MARK: Pill

    @Test func singleCamPillOffersEveryStageShotManualAndAutoPan() {
        let pill = OperatorPill(cameraManager: show(.singleCam).channelA)
        #expect(pill.sections == [.lockState, .detect, .stageShots, .crop, .manual, .autoPan,
                                  .zoom, .returnToWide, .stopSession])
        #expect(ShotComposer.Config.ShotPreset.allCases.map(\.operatorTitle) == ["Wide", "Full Body", "Waist Up"])
    }

    @Test func webcamPillKeepsWideAndTightWithoutManualOrAutoPan() {
        let pill = OperatorPill(cameraManager: show(.webcam).channelA)
        #expect(pill.sections == [.lockState, .detect, .webcamShots, .crop, .zoom, .returnToWide, .stopSession])
        #expect(ShotComposer.Config.WebcamPreset.allCases.map(\.operatorTitle) == ["Wide", "Tight"])
    }

    @Test func multiCamTargetPillHasTheStageShotsAndNoStop() {
        let pill = OperatorPill(cameraManager: show(.multiCam).channelA, controlTarget: .preview(channel: .a))
        #expect(pill.sections == [.targetChip, .lockState, .detect, .stageShots, .crop, .manual, .autoPan,
                                  .zoom, .returnToWide])
    }

    @Test func singleCamPillFitsA1280PointWindow() {
        let manager = show(.singleCam).channelA
        let width = NSHostingView(rootView: OperatorPill(cameraManager: manager)).fittingSize.width
        #expect(width > 800)
        #expect(width <= 1232, "Single Cam pill width \(width) must fit 1280 with 24 pt margins")
    }
}

private extension UserDefaults {
    func with(mode: OperatorMode) -> UserDefaults {
        set(mode.rawValue, forKey: OperatorModeStore.key)
        return self
    }
}
#endif
