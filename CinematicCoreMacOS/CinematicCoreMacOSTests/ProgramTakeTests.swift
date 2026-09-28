//
//  ProgramTakeTests.swift
//  CinematicCoreMacOSTests
//
//  TAKE card: a valid Take cuts to the prepared Preview on sink acceptance;
//  stale / revised / held / missing / unsupported frames are rejected at the
//  click with the old Program preserved; duplicate clicks cannot cut back;
//  an output refusal keeps the old roles.
//

import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
private final class TakeFakeSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .display
    var available = true { didSet { onStateChange?() } }
    var accepts = true
    private(set) var sent: [CVPixelBuffer] = []
    var isAvailable: Bool { available }
    var summary: String { "fake" }
    var detail: String { "fake" }
    var lastErrorDescription: String? { nil }
    var onStateChange: (() -> Void)?
    func connect() {}
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) {}
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        guard accepts else { return false }
        sent.append(pixelBuffer)
        return true
    }
}

@MainActor
struct ProgramTakeTests {
    private final class Clock { var now: TimeInterval = 1000 }

    private struct Rig {
        let show: ShowCoordinator
        let sink: TakeFakeSink
        let clock: Clock
        var a: CameraManager { show.channelA }
        var b: CameraManager { show.channel(.b)! }
    }

    private func rig() -> Rig {
        let sink = TakeFakeSink()
        let records = AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-take-\(UUID().uuidString)")!)
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]), admissionRecords: records)
        let clock = Clock()
        show.clock = { clock.now }
        show.router.clock = { clock.now }
        show.addChannel(.b)
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        return Rig(show: show, sink: sink, clock: clock)
    }

    private func buffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return try #require(buffer)
    }

    /// Give `channel` a freshly rendered frame under its current revisions.
    @discardableResult
    private func prepare(_ channel: CameraManager, rig: Rig, age: TimeInterval = 0, isRepeat: Bool = false,
                         revisions: ChannelRevisions? = nil) throws -> RenderedChannelFrame {
        let frame = RenderedChannelFrame(
            channelID: channel.channelID, revisions: revisions ?? channel.revisions,
            sourceTimestamp: 1, processingStartedAt: rig.clock.now - age, renderedAt: rig.clock.now - age,
            crop: .fullFrame, outputSize: CGSize(width: 1920, height: 1080), isRepeat: isRepeat,
            pixelBuffer: try buffer())
        channel.setLatestRenderedFrameForTesting(frame)
        return frame
    }

    private func expectOldRolesKept(_ rig: Rig) {
        #expect(rig.show.programChannel == .a)
        #expect(rig.show.router.routeGeneration == 0)
        #expect(rig.sink.sent.isEmpty)
    }

    @Test func validTakeCutsToThePreparedPreview() throws {
        let rig = rig()
        rig.show.setEditLive(true)
        let frame = try prepare(rig.b, rig: rig)
        #expect(TakeAvailability.evaluate(take: rig.show.takeInputs()!, program: .a, preview: .b,
                                          standard: .p50, editLive: false).isEligible)
        #expect(rig.show.take() == .committed(newProgram: .b))
        #expect(rig.show.programChannel == .b)
        #expect(rig.show.previewChannel == .a)
        #expect(rig.sink.sent.last === frame.pixelBuffer)       // exactly the prepared shot
        #expect(!rig.show.editLive)                             // Take leaves Edit Live
        #expect(rig.show.controlTarget == .a)                   // controls return to the new Preview
    }

    @Test func staleRenderIsRejected() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig, age: 0.1)                  // > 2 frame periods at 50 fps
        #expect(rig.show.take() == .rejected(.notEligible(.preparing)))
        expectOldRolesKept(rig)
    }

    @Test func frameFromBeforeAShotChangeIsRejected() throws {
        let rig = rig()
        // Rendered under the current shot, then the operator picks a preset.
        try prepare(rig.b, rig: rig)
        rig.b.setRunningForTesting(true)
        #expect(rig.b.dispatch(rig.b.makeCommand(.selectPreset(.stage(.fullBody)))) == .accepted)
        #expect(rig.show.take() == .rejected(.notEligible(.preparing)))
        expectOldRolesKept(rig)
    }

    @Test func heldFrameIsNeverTaken() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig, isRepeat: true)
        #expect(rig.show.take() == .rejected(.notEligible(.preparing)))
        expectOldRolesKept(rig)
    }

    @Test func missingPreviewSourceIsRejected() throws {
        let rig = rig()
        let request = rig.show.makeTakeRequest()!
        try prepare(rig.b, rig: rig)
        rig.b.setSourceMissingForTesting(true)                  // unplugged after the click was bound
        #expect(rig.show.take(request) == .rejected(.notEligible(.sourceMissing)))
        expectOldRolesKept(rig)
    }

    @Test func unsupportedPairIsRejected() throws {
        let rig = rig()
        let reason = AdmissionReason(code: "program.render", bottleneck: .render, message: "x")
        rig.show.admissionRecords.record(.unsupported([reason]), for: rig.show.admissionFingerprint())
        try prepare(rig.b, rig: rig)
        #expect(rig.show.take() == .rejected(.notEligible(.unsupported)))
        expectOldRolesKept(rig)
    }

    @Test func noPreviewNoTake() {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        #expect(show.take() == .rejected(.noPreview))
        #expect(show.makeTakeRequest() == nil)
    }

    @Test func doubleClickCommitsOnce() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig)
        try prepare(rig.a, rig: rig)                            // old Program also has a fresh frame
        let first = rig.show.makeTakeRequest()!
        let second = rig.show.makeTakeRequest()!
        #expect(rig.show.take(first) == .committed(newProgram: .b))
        #expect(rig.show.take(second) == .rejected(.superseded))
        #expect(rig.show.programChannel == .b)
        #expect(rig.sink.sent.count == 1)
    }

    @Test func separateClickInsideTheGuardIntervalCannotCutBack() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig)
        #expect(rig.show.take() == .committed(newProgram: .b))
        try prepare(rig.a, rig: rig)
        #expect(rig.show.take() == .rejected(.tooSoon))
        rig.clock.now += TakeRules.minimumInterval + 0.01
        try prepare(rig.a, rig: rig)
        #expect(rig.show.take() == .committed(newProgram: .a))  // deliberate second Take works
    }

    @Test func controlEpochChangeAloneDoesNotInvalidateTheShot() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig)
        rig.b.cancelOperatorMotion()                             // epoch moves; shot does not
        #expect(rig.show.take() == .committed(newProgram: .b))
    }

    @Test func outputRefusalKeepsTheOldRoles() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig)
        rig.sink.accepts = false
        #expect(rig.show.take() == .rejected(.outputRefused))
        #expect(rig.show.programChannel == .a)
        #expect(rig.show.router.routeGeneration == 0)
    }

    @Test func missingOutputRouteRejectsAndReconnectAllowsTake() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig)
        rig.sink.available = false                               // destination unplugged
        #expect(rig.show.take() == .rejected(.outputRefused))
        rig.sink.available = true                                // same endpoint back
        #expect(rig.show.take() == .committed(newProgram: .b))
    }

    @Test func oldProgramFramesAreRefusedAfterTheCut() throws {
        let rig = rig()
        try prepare(rig.b, rig: rig)
        let stamped = rig.a.outputPort.routeGeneration
        #expect(rig.show.take() == .committed(newProgram: .b))
        rig.a.outputPort.submitFrame(try buffer(), timestamp: 1, isRepeat: false, routeGeneration: stamped)
        #expect(rig.sink.sent.count == 1)                        // late old-Program render never shown
    }
}
