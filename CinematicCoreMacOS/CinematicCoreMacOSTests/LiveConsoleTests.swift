//
//  LiveConsoleTests.swift
//  CinematicCoreMacOSTests
//
//  Console integration: the live snapshot built from ShowCoordinator drives
//  the same view-layer contracts the gallery proved (roles, health, Take
//  inputs, Edit Live, Program status), and the model's actions go through the
//  show. Renders the live console once for review when
//  ALFIE_GALLERY_SNAPSHOTS=1.
//

#if DEBUG
import AppKit
import CoreVideo
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct LiveConsoleTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-live-\(UUID().uuidString)")!))
    }

    private func snapshot(_ show: ShowCoordinator, rates: [ChannelID: Double] = [:]) -> ConsoleSnapshot {
        LiveConsoleSnapshot.make(show: show, paneView: .shot, rates: rates, note: nil)
    }

    @Test func singleInputShowsProgramOnlyWithNoPreview() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        let snap = snapshot(show, rates: [.a: 50])
        #expect(snap.programChannel == .a)
        #expect(snap.previewChannel == nil)
        #expect(snap.assignedInputCount == 1)
        #expect(snap.slot(.a).input?.health == .running(deliveredRate: 50))
        #expect(TakeAvailability.evaluate(snap).reason == .noPreviewCamera)
        #expect(PaneOverlayState.preview(for: snap) == .noPreviewCamera)
    }

    @Test func secondInputAppearsAsPreviewInSlotB() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        let snap = snapshot(show, rates: [.a: 50, .b: 49.5])
        #expect(snap.previewChannel == .b)
        #expect(snap.slot(.b).input?.role == .preview)
        #expect(snap.slot(.b).input?.health == .running(deliveredRate: 49.5))
        #expect(snap.slot(.c).input == nil && snap.slot(.d).input == nil)
        #expect(snap.controlTarget == .init(channel: .b, role: .preview))
    }

    @Test func secondInputNeverAutoSelectsACamera() {
        let show = show()
        #expect(show.addChannel(.b).selectedCamera == nil)
    }

    @Test func stoppedOrMissingSecondInputHoldsItsSlot() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b)
        #expect(snapshot(show).slot(.b).input?.health == .missing)     // added, not started
        b.setRunningForTesting(true)
        b.setSourceMissingForTesting(true)
        let snap = snapshot(show)
        #expect(snap.slot(.b).input?.health == .missing)
        #expect(snap.slot(.b).input?.role == .preview)
        #expect(TakeAvailability.evaluate(snap).reason == .sourceMissing)
    }

    @Test func refusedPairShowsPreviewUnsupported() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        let reason = AdmissionReason(code: "program.render", bottleneck: .render, message: "x")
        show.admissionRecords.record(.unsupported([reason]), for: show.admissionFingerprint())
        let snap = snapshot(show)
        #expect(snap.slot(.b).input?.health == .unsupported)
        #expect(TakeAvailability.evaluate(snap).reason == .unsupported)
    }

    @Test func editLiveMovesTheControlTargetToProgram() {
        let show = show()
        show.addChannel(.b)
        show.setEditLive(true)
        let snap = snapshot(show)
        #expect(snap.editLive)
        #expect(snap.controlTarget == .init(channel: .a, role: .program))
        #expect(PaneModel.program(from: snap).showsEditLiveBanner)
    }

    @Test func programSourceMissingReadsReconnecting() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.channelA.setSourceMissingForTesting(true)
        #expect(snapshot(show).programOutput == .reconnecting)
        #expect(PaneOverlayState.programStatus(for: snapshot(show).programOutput) == "Reconnecting · standby")
    }

    @Test func legalCropIsConvertedToTopLeftOrigin() {
        let crop = CropEngine.CropRect(origin: CGPoint(x: 0.2, y: 0.1), size: CGSize(width: 0.5, height: 0.4))
        let rect = LiveConsoleSnapshot.topLeft(crop)
        #expect(abs(rect.minY - 0.5) < 0.0001)
        #expect(rect.width == 0.5 && rect.height == 0.4 && rect.minX == 0.2)
    }

    @Test func modelTakeWithoutPreviewExplainsWhy() {
        let model = LiveConsoleModel(show: show())
        model.take()
        #expect(model.message == "No Preview camera")
    }

    @Test func modelEditLiveGoesThroughTheShow() {
        let show = show()
        show.addChannel(.b)
        let model = LiveConsoleModel(show: show)
        model.setEditLive(true)
        #expect(show.editLive)
        #expect(model.snapshot.editLive)
        model.setEditLive(false)
        #expect(!show.editLive)
    }

    @Test func removingTheSecondInputReturnsToSingleCamera() {
        let show = show()
        show.addChannel(.b)
        let model = LiveConsoleModel(show: show)
        #expect(model.hasSecondInput)
        model.removeSecondInput()
        #expect(!model.hasSecondInput)
        #expect(model.snapshot.previewChannel == nil)
    }

    @Test func programPaneFollowsTheChannelWhileRouted() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        // Idle / routed: the Program channel's rendered buffer is what is sent.
        #expect(LivePanePicture.heldProgramBuffer(show: show) == nil)
    }

    @Test func unmeasuredPairIsMeasuredOnceBRenders() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b)
        let model = LiveConsoleModel(show: show)
        model.refresh()
        #expect(model.pairCheckText == nil)                      // B not rendering yet
        b.setRunningForTesting(true)
        b.setLatestRenderedFrameForTesting(RenderedChannelFrame(
            channelID: .b, revisions: b.revisions, sourceTimestamp: 1, processingStartedAt: 0,
            renderedAt: 0, crop: .fullFrame, outputSize: .zero, isRepeat: false,
            pixelBuffer: ProgramRouter.makeBlackFrame(width: 16, height: 16)!))
        model.refresh()
        #expect(model.pairCheckText == "Measuring pair · warming up")
    }

    @Test func knownPairIsNotMeasuredAgain() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        b.setLatestRenderedFrameForTesting(RenderedChannelFrame(
            channelID: .b, revisions: b.revisions, sourceTimestamp: 1, processingStartedAt: 0,
            renderedAt: 0, crop: .fullFrame, outputSize: .zero, isRepeat: false,
            pixelBuffer: ProgramRouter.makeBlackFrame(width: 16, height: 16)!))
        show.admissionRecords.record(.provisional, for: show.admissionFingerprint())
        let model = LiveConsoleModel(show: show)
        model.refresh()
        #expect(model.pairCheckText == nil)
    }

    @Test func rendersTheLiveConsoleAt1280() throws {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        let host = NSHostingView(rootView: LiveMultiviewConsole(show: show).environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 1280)
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
            try data.write(to: dir.appendingPathComponent("live-console.png"))
        }
    }
}

/// Exercises the callbacks passed by LivePanePicture.body to CameraPreviewView.
/// No gesture expression or command construction is duplicated in these tests.
@MainActor
struct LivePaneCommandTests {
    enum Gesture: String, CaseIterable {
        case manual, select, retarget
    }

    private struct ChannelState: Equatable {
        let epoch: UInt64
        let shotRevision: UInt64
        let mode: CameraManager.OperationMode
        let manualPoint: CGPoint
        let trackingOwnsControl: Bool
        let discovery: Bool
        let tapPending: Bool
        let lockedTarget: UUID?
        let detectionGeneration: UInt64
        let zoom: OperatorCommand.ZoomDirection?
        let crop: CropEngine.CropRect?
    }

    private let point = CGPoint(x: 0.25, y: 0.75)

    private func show(twoInputs: Bool = true) -> ShowCoordinator {
        let show = ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults:
                UserDefaults(suiteName: "alfie-pane-command-\(UUID().uuidString)")!))
        show.channelA.setRunningForTesting(true)
        if twoInputs { show.addChannel(.b).setRunningForTesting(true) }
        return show
    }

    private func prepare(_ channel: CameraManager, for gesture: Gesture) {
        switch gesture {
        case .manual:
            channel.setOperationMode(.manualCrop)
        case .select:
            channel.beginDetection()
        case .retarget:
            channel.shotComposer.lockTarget(UUID())
            channel.shotComposer.forceTrackingForTesting()
            channel.setOperationMode(.autoTracking)
        }
    }

    private func pane(_ show: ShowCoordinator, channel: CameraManager) -> LivePanePicture {
        let snapshot = LiveConsoleSnapshot.make(
            show: show, paneView: .source, rates: [:], note: nil)
        let pane = channel.channelID == show.programChannel
            ? PaneModel.program(from: snapshot) : PaneModel.preview(from: snapshot)
        return LivePanePicture(channel: channel, pane: pane, show: show)
    }

    private func callback(_ pane: LivePanePicture, for gesture: Gesture) throws -> (CGPoint) -> Void {
        try #require(gesture == .retarget ? pane.holdHandler : pane.tapHandler)
    }

    private func state(_ channel: CameraManager) -> ChannelState {
        ChannelState(
            epoch: channel.commands.epoch, shotRevision: channel.shotRevision,
            mode: channel.activeMode, manualPoint: channel.manualCropPoint,
            trackingOwnsControl: channel.commands.trackingOwnsControl,
            discovery: channel.detectionDiscoveryActive, tapPending: channel.tapPending,
            lockedTarget: channel.manualLockedTargetID,
            detectionGeneration: channel.detectionGenerationForTesting,
            zoom: channel.zoomMoveDirection, crop: channel.cropEngine?.currentCrop)
    }

    private func expectEffect(_ channel: CameraManager, gesture: Gesture, previousEpoch: UInt64) {
        #expect(channel.commands.epoch == previousEpoch + 1)
        switch gesture {
        case .manual:
            #expect(channel.manualCropPoint == point)
            #expect(!channel.tapPending)
        case .select, .retarget:
            #expect(channel.tapPending)
            #expect(channel.commands.trackingOwnsControl)
        }
    }

    @Test(arguments: Gesture.allCases)
    func retainedPreviewCallbackCannotEditLive(gesture: Gesture) throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        prepare(a, for: gesture)
        prepare(b, for: gesture)
        let retained = try callback(pane(show, channel: b), for: gesture)
        show.setEditLive(true)
        let beforeA = state(a)
        let beforeB = state(b)
        retained(point)
        #expect(state(a) == beforeA)
        #expect(state(b) == beforeB)
        #expect(show.programChannel == .a && show.router.routeGeneration == 0)
    }

    @Test(arguments: Gesture.allCases)
    func retainedLiveCallbackCannotChangePreviewAfterDone(gesture: Gesture) throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        prepare(a, for: gesture)
        prepare(b, for: gesture)
        show.setEditLive(true)
        let retained = try callback(pane(show, channel: a), for: gesture)
        show.setEditLive(false)
        let beforeA = state(a)
        let beforeB = state(b)
        retained(point)
        #expect(state(a) == beforeA)
        #expect(state(b) == beforeB)
        #expect(show.programChannel == .a && show.router.routeGeneration == 0)
    }

    @Test(arguments: Gesture.allCases)
    func switchingAwayAndBackDoesNotReviveCallback(gesture: Gesture) throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        prepare(b, for: gesture)
        let retained = try callback(pane(show, channel: b), for: gesture)
        let originalEpoch = b.commands.epoch
        show.setEditLive(true)
        show.setEditLive(false)
        // Target changes cancel discovery. Re-arm it without changing the
        // command epoch, so this regression isolates the target revision.
        if gesture == .select { b.beginDetection() }
        #expect(b.commands.epoch == originalEpoch)
        let beforeA = state(a)
        let beforeB = state(b)
        retained(point)
        #expect(state(a) == beforeA)
        #expect(state(b) == beforeB)
    }

    @Test(arguments: Gesture.allCases)
    func stoppedAndRestartedChannelRejectsItsOldCallback(gesture: Gesture) throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        prepare(b, for: gesture)
        let retained = try callback(pane(show, channel: b), for: gesture)
        let targetRevision = show.controlTargetRevision
        b.stopCapture()
        b.setRunningForTesting(true)
        prepare(b, for: gesture)
        // Direct channel Stop retires the epoch without changing the show's
        // target revision. No source or device is started by this fixture.
        #expect(show.controlTargetRevision == targetRevision)
        let beforeA = state(a)
        let beforeB = state(b)
        retained(point)
        #expect(state(a) == beforeA)
        #expect(state(b) == beforeB)
        let fresh = try callback(pane(show, channel: b), for: gesture)
        fresh(point)
        expectEffect(b, gesture: gesture, previousEpoch: beforeB.epoch)
        #expect(state(a) == beforeA)
    }

    @Test func supersededManualCallbackCannotCancelANewShotMove() throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        prepare(b, for: .manual)
        let retained = try callback(pane(show, channel: b), for: .manual)
        #expect(b.dispatch(b.makeCommand(.beginZoom(.pushIn))) == .accepted)
        #expect(b.zoomMoveDirection == .pushIn)
        let beforeA = state(a)
        let beforeB = state(b)
        retained(point)
        #expect(state(a) == beforeA)
        #expect(state(b) == beforeB)
        #expect(b.zoomMoveDirection == .pushIn)
    }

    @Test(arguments: Gesture.allCases)
    func stalePaneCannotCreateANewCallback(gesture: Gesture) throws {
        let show = show()
        let b = try #require(show.channel(.b))
        prepare(b, for: gesture)
        let stalePane = pane(show, channel: b)
        show.setEditLive(true)
        // Read the production property after its pane lost control. Retarget
        // and Manual remain eligible locally; the pane binding must refuse.
        if gesture == .select { b.beginDetection() }
        if gesture == .retarget {
            #expect(stalePane.holdHandler == nil)
        } else {
            #expect(stalePane.tapHandler == nil)
        }
    }

    @Test(arguments: Gesture.allCases)
    func freshPreviewCallbackChangesOnlyPreview(gesture: Gesture) throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        prepare(b, for: gesture)
        let beforeA = state(a)
        let previousEpoch = b.commands.epoch
        let fresh = try callback(pane(show, channel: b), for: gesture)
        fresh(point)
        expectEffect(b, gesture: gesture, previousEpoch: previousEpoch)
        #expect(state(a) == beforeA)
        #expect(show.programChannel == .a && show.router.routeGeneration == 0)
    }

    @Test(arguments: Gesture.allCases)
    func freshEditLiveCallbackChangesOnlyProgram(gesture: Gesture) throws {
        let show = show()
        let a = show.channelA
        let b = try #require(show.channel(.b))
        show.setEditLive(true)
        prepare(a, for: gesture)
        let beforeB = state(b)
        let previousEpoch = a.commands.epoch
        let fresh = try callback(pane(show, channel: a), for: gesture)
        fresh(point)
        expectEffect(a, gesture: gesture, previousEpoch: previousEpoch)
        #expect(state(b) == beforeB)
        #expect(show.programChannel == .a && show.router.routeGeneration == 0)
    }

    @Test(arguments: Gesture.allCases)
    func freshSingleInputCallbackKeepsProgramControl(gesture: Gesture) throws {
        let show = show(twoInputs: false)
        let a = show.channelA
        prepare(a, for: gesture)
        let previousEpoch = a.commands.epoch
        let fresh = try callback(pane(show, channel: a), for: gesture)
        fresh(point)
        expectEffect(a, gesture: gesture, previousEpoch: previousEpoch)
        #expect(show.previewChannel == nil && !show.editLive)
        #expect(show.programChannel == .a && show.router.routeGeneration == 0)
    }
}
#endif
