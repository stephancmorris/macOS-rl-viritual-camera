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
#endif
