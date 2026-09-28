//
//  ChannelIsolationTests.swift
//  CinematicCoreMacOSTests
//
//  CHANNEL card: one show output shared by every channel, only the Program
//  channel's port reaches it, channel state (lock / preset / zoom / pan /
//  revisions / epochs) is independent, and retired work on one channel is
//  rejected without touching the other.
//

import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
struct ChannelIsolationTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
    }

    private func buffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }

    @Test func exactlyOneProgramOutputIsShared() {
        let show = show()
        let b = show.addChannel(.b)
        #expect(show.channelA.programOutput === show.programOutput)
        #expect(b.programOutput === show.programOutput)
        // Adding again returns the same channel, never a second pipeline.
        #expect(show.addChannel(.b) === b)
    }

    @Test func onlyTheProgramChannelPortReachesTheOutput() throws {
        let show = show()
        let b = show.addChannel(.b)
        #expect(show.router.isProgram(.a))
        #expect(!show.router.isProgram(.b))

        // B's send is refused by the router and never reaches the show output.
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        b.outputPort.sendFrame(try buffer(), timestamp: 0)
        #expect(show.router.framesNotRouted == 1)
        #expect(show.programOutput.pipelineTotals.routed == 0)
        show.channelA.outputPort.sendFrame(try buffer(), timestamp: 0)
        #expect(show.programOutput.pipelineTotals.routed == 1)
        show.channelA.outputPort.stop()
    }

    @Test func unroutedChannelCannotStartOrStopTheShowOutput() {
        let show = show()
        let b = show.addChannel(.b)
        b.outputPort.start()
        b.outputPort.stop()
        b.outputPort.updateCaptureStatus(isRunning: true)
        #expect(show.programOutput.activeRoute == nil)
        #expect(show.programOutput.diagnosticsFileName == nil)
    }

    @Test func presetModeAndZoomOnBLeaveAUntouched() {
        let show = show()
        let a = show.channelA
        let b = show.addChannel(.b)
        let aMode = a.activeMode
        let aPreset = a.shotComposer.config.shotPreset
        let aRevision = a.shotRevision

        b.selectPreset(.stage(.fullBody))
        b.setOperationMode(.manualCrop)
        b.beginZoom(.pushIn)

        #expect(b.activeMode == .manualCrop)
        #expect(b.zoomMoveDirection == .pushIn)
        #expect(a.activeMode == aMode)
        #expect(a.shotComposer.config.shotPreset == aPreset)
        #expect(a.zoomMoveDirection == nil)
        #expect(a.shotRevision == aRevision)
    }

    @Test func autoPanOnBDoesNotMoveA() {
        let show = show()
        let a = show.channelA
        let b = show.addChannel(.b)
        b.setOperationMode(.autoPan)
        _ = b.advanceAutoPan(now: 100, width: 0.5)
        _ = b.advanceAutoPan(now: 101, width: 0.5)
        #expect(b.activeMode == .autoPan)
        #expect(a.activeMode != .autoPan)
    }

    @Test func epochsAndGenerationsAreIndependent() {
        let show = show()
        let a = show.channelA
        let b = show.addChannel(.b)
        let aBefore = a.revisions
        let bBefore = b.revisions
        b.cancelOperatorMotion()   // bumps B's control epoch
        b.stopCapture()            // bumps B's source generation
        #expect(b.revisions.controlEpoch > bBefore.controlEpoch)
        #expect(b.revisions.sourceGeneration > bBefore.sourceGeneration)
        #expect(a.revisions == aBefore)
    }

    @Test func shotRevisionTracksAdmittedDiscreteCommands() {
        let manager = CameraManager(channelID: .a, programOutput: ProgramOutputManager(sinks: []), routed: true)
        manager.setRunningForTesting(true)
        let before = manager.shotRevision
        #expect(manager.dispatch(manager.makeCommand(.selectPreset(.stage(.waistUp)))) == .accepted)
        #expect(manager.shotRevision == before + 1)
        // Non-shot commands leave it alone.
        _ = manager.dispatch(manager.makeCommand(.detect))
        #expect(manager.shotRevision == before + 1)
    }

    @Test func retiredCompletionOnBIsRejectedAndAIsUntouched() async throws {
        let show = show()
        let a = show.channelA
        let b = show.addChannel(.b)
        let rendered = try buffer()
        let aRevisions = a.revisions

        // B's source is stopped while its render is in flight: the completion
        // belongs to a retired generation and must not become B's program.
        let result = await b.renderProgramFrame(crop: .fullFrame, timestamp: 1) {
            b.stopCapture()
            return rendered
        }
        #expect(result == nil)
        #expect(b.latestRenderedFrame == nil)
        #expect(a.revisions == aRevisions)
        #expect(a.latestRenderedFrame == nil)
    }

    @Test func renderedFrameMatchesOnlyItsOwnRevisions() throws {
        let revisions = ChannelRevisions(sourceGeneration: 3, controlEpoch: 7, shotRevision: 2)
        let frame = RenderedChannelFrame(
            channelID: .b, revisions: revisions, sourceTimestamp: 1, processingStartedAt: 1, renderedAt: 1,
            crop: .fullFrame, outputSize: CGSize(width: 1920, height: 1080), isRepeat: false,
            pixelBuffer: try buffer())
        #expect(frame.matches(revisions))
        // A newer control epoch alone does not invalidate the shot…
        #expect(frame.matches(ChannelRevisions(sourceGeneration: 3, controlEpoch: 8, shotRevision: 2)))
        // …but a new source generation or shot revision does.
        #expect(!frame.matches(ChannelRevisions(sourceGeneration: 4, controlEpoch: 7, shotRevision: 2)))
        #expect(!frame.matches(ChannelRevisions(sourceGeneration: 3, controlEpoch: 7, shotRevision: 3)))
    }

    @Test func programChannelCannotBeRemoved() {
        let show = show()
        show.addChannel(.b)
        show.removeChannel(.a)
        #expect(show.channel(.a) != nil)
        show.removeChannel(.b)
        #expect(show.channel(.b) == nil)
    }
}
