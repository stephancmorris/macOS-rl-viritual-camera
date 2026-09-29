//
//  InputStripTests.swift
//  CinematicCoreMacOSTests
//
//  INPUT-STRIP, view-layer contract: four fixed slots in A–D order, roles
//  and health mapped from ConsoleSnapshot, a Take swaps badges only, and a
//  dropped source keeps its slot, name and role. Also the snapshot matrix
//  (1–4 slots, missing, unsupported), tap routing, VoiceOver strings and the
//  live tile picture sampler.
//

import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct InputStripTests {
    private func tiles(_ snapshot: ConsoleSnapshot) -> [InputTileModel] {
        snapshot.slots.map { InputTileModel(slot: $0, renderedImage: nil) }
    }

    @Test func alwaysFourSlotsInChannelOrder() {
        for scenario in FakeConsoleModel.Scenario.allCases {
            let slots = tiles(FakeConsoleModel.snapshot(for: scenario, standard: .p50)).map(\.slot)
            #expect(slots == [.A, .B, .C, .D], "\(scenario)")
        }
    }

    @Test func twoInputsShowProgramPreviewAndTwoPlaceholders() {
        let row = tiles(FakeConsoleModel.snapshot(for: .ready, standard: .p50))
        #expect(row.map(\.role.badge) == ["PGM", "PVW", nil, nil])
        #expect(row.map(\.isAssigned) == [true, true, false, false])
        #expect(row[0].health.title == "50.0")
    }

    @Test func takeSwapsBadgesButNeverMovesTiles() {
        let model = FakeConsoleModel(scenario: .ready)
        let before = tiles(model.snapshot)
        model.take()
        let after = tiles(model.snapshot)
        #expect(after.map(\.slot) == before.map(\.slot))
        #expect(after.map(\.name) == before.map(\.name))
        #expect(before.map(\.role.badge) == ["PGM", "PVW", nil, nil])
        #expect(after.map(\.role.badge) == ["PVW", "PGM", nil, nil])
    }

    @Test func droppedSourceKeepsSlotNameAndRole() {
        let row = tiles(FakeConsoleModel.snapshot(for: .missing, standard: .p50))
        #expect(row[1].isAssigned)
        #expect(row[1].name == "Band side")
        #expect(row[1].role.badge == "PVW")
        #expect(row[1].health.title == "No signal · holding slot")
    }

    @Test func unsupportedAndRatesUseTheActiveStandard() {
        #expect(tiles(FakeConsoleModel.snapshot(for: .unsupported, standard: .p50))[1].health.title == "Unsupported")
        #expect(tiles(FakeConsoleModel.snapshot(for: .ready, standard: .p60))[0].health.title == "60.0")
    }

    @Test func programTileHintNamesTheProgramCamera() {
        #expect(InputStripView.programHint(for: .A) == "Cam A is Program · use Edit Live to change it")
    }

    // MARK: Snapshot matrix (renders when ALFIE_GALLERY_SNAPSHOTS=1)

    private func snapshot(_ scenario: FakeConsoleModel.Scenario, filled: Int? = nil) -> ConsoleSnapshot {
        var snap = FakeConsoleModel.snapshot(for: scenario, standard: .p50)
        if let filled {
            for index in snap.slots.indices where index >= filled { snap.slots[index].input = nil }
        }
        return snap
    }

    /// A stand-in rendered shot per channel so the pictures read in the PNG.
    private func stubImages(for snap: ConsoleSnapshot) -> [ChannelID: NSImage] {
        var images: [ChannelID: NSImage] = [:]
        for (index, slot) in snap.slots.enumerated() where slot.isAssigned {
            let hue = 0.08 + 0.22 * CGFloat(index)
            images[slot.channel] = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { rect in
                NSGradient(colors: [NSColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1),
                                    NSColor(hue: hue, saturation: 0.6, brightness: 0.18, alpha: 1)])?
                    .draw(in: rect, angle: 90)
                NSColor(white: 0.9, alpha: 0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.midX - 40, y: rect.midY + 10, width: 80, height: 80)).fill()
                NSBezierPath(roundedRect: NSRect(x: rect.midX - 70, y: rect.minY, width: 140, height: rect.midY + 10),
                             xRadius: 40, yRadius: 40).fill()
                return true
            }
        }
        return images
    }

    private func render(_ snap: ConsoleSnapshot, named name: String) throws {
        let model = FakeConsoleModel()
        let strip = InputStripView(snapshot: snap, actions: model, renderedImages: stubImages(for: snap))
            .frame(width: 1232, height: MultiviewLayout.stripLabelHeight + 168)
            .padding(24)
            .background(ConsoleStyle.background)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: strip)
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: MultiviewLayout.stripLabelHeight + 168 + 48)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 1280)
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
            try data.write(to: dir.appendingPathComponent(name))
        }
    }

    @Test func rendersOneTwoThreeAndFourSlots() throws {
        try render(snapshot(.oneInput), named: "strip-1-slot.png")
        try render(snapshot(.ready), named: "strip-2-slots.png")
        try render(snapshot(.fourInputs, filled: 3), named: "strip-3-slots.png")
        try render(snapshot(.fourInputs), named: "strip-4-slots.png")
    }

    @Test func rendersMissingAndUnsupported() throws {
        try render(snapshot(.missing), named: "strip-missing.png")
        try render(snapshot(.unsupported), named: "strip-unsupported.png")
    }

    @Test func filledSlotCountMatchesTheMatrix() {
        let counts = [snapshot(.oneInput), snapshot(.ready), snapshot(.fourInputs, filled: 3), snapshot(.fourInputs)]
            .map { tiles($0).filter(\.isAssigned).count }
        #expect(counts == [1, 2, 3, 4])
    }

    @Test func fourInputsCarryProgramPreviewAndIdle() {
        let row = tiles(snapshot(.fourInputs))
        #expect(row.map(\.role.badge) == ["PGM", "PVW", nil, nil])
        #expect(row.map(\.name) == ["Stage wide", "Band side", "Pulpit", "Choir"])
    }

    // MARK: Taps

    private func strip(_ snap: ConsoleSnapshot, model: FakeConsoleModel) -> InputStripView {
        InputStripView(snapshot: snap, actions: model)
    }

    @Test func programTileTapShowsTheHintAndDoesNotRoute() {
        let model = FakeConsoleModel(scenario: .ready)
        let view = strip(model.snapshot, model: model)
        #expect(view.tap(.A) == "Cam A is Program · use Edit Live to change it")
        #expect(model.actionLog.isEmpty)
    }

    @Test func otherTileTapCuesThroughActionsAndNeverCuts() {
        let model = FakeConsoleModel(scenario: .fourInputs)
        let view = strip(model.snapshot, model: model)
        #expect(view.tap(.B) == nil)
        #expect(view.tap(.C) == nil)
        #expect(model.actionLog == ["cue B", "cue C"])
        #expect(model.snapshot.programChannel == .a)
        #expect(model.snapshot.previewChannel == .b)
    }

    @Test func afterATakeTheNewProgramTileGetsTheHint() {
        let model = FakeConsoleModel(scenario: .ready)
        model.take()
        let view = strip(model.snapshot, model: model)
        #expect(view.tap(.B) == "Cam B is Program · use Edit Live to change it")
        #expect(view.tap(.A) == nil)
    }

    // MARK: VoiceOver

    @Test func voiceOverLabelsPerState() {
        let ready = tiles(snapshot(.ready))
        #expect(ready[0].accessibilityLabel == "Cam A, Stage wide, Program, Waist Up, 50 frames per second")
        #expect(ready[1].accessibilityLabel == "Cam B, Band side, Preview, Waist Up, 50 frames per second")
        let four = tiles(snapshot(.fourInputs))
        #expect(four[2].accessibilityLabel == "Cam C, Pulpit, Full Body, 50 frames per second")
        #expect(tiles(snapshot(.missing))[1].accessibilityLabel == "Cam B, Band side, Preview, Waist Up, no signal, holding slot")
        #expect(tiles(snapshot(.unsupported))[1].accessibilityLabel == "Cam B, Band side, Preview, Waist Up, unsupported")
        #expect(ready[2].accessibilityLabel == "Input C, not assigned")
    }

    @Test func voiceOverSpeaksFractionalRatesToOneDecimal() {
        var snap = snapshot(.ready)
        snap.slots[0].input?.health = .running(deliveredRate: 59.94)
        #expect(tiles(snap)[0].accessibilityLabel.hasSuffix("59.9 frames per second"))
    }

    @Test func voiceOverHints() {
        let row = tiles(snapshot(.ready))
        #expect(row[0].accessibilityHint == "Program camera. Use Edit Live to change it.")
        #expect(row[1].accessibilityHint == "Cue this camera for Preview. Does not Take.")
        #expect(row[2].accessibilityHint == "Add a camera in Setup.")
    }
}

#if DEBUG
import CoreVideo

/// The live console path: snapshot from a real ShowCoordinator, cue through
/// LiveConsoleModel, and the 15 Hz tile picture sampler.
@MainActor
struct LiveInputStripTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-strip-\(UUID().uuidString)")!))
    }

    private func liveTiles(_ show: ShowCoordinator) -> [InputTileModel] {
        LiveConsoleSnapshot.make(show: show, paneView: .shot, rates: [.a: 50, .b: 50], note: nil)
            .slots.map { InputTileModel(slot: $0, renderedImage: nil) }
    }

    private func surfaceBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        #expect(status == kCVReturnSuccess)
        return try #require(buffer)
    }

    private func renderedFrame(_ buffer: CVPixelBuffer, channel: ChannelID) -> RenderedChannelFrame {
        RenderedChannelFrame(
            channelID: channel,
            revisions: ChannelRevisions(sourceGeneration: 0, controlEpoch: 0, shotRevision: 0),
            sourceTimestamp: 0, processingStartedAt: 0, renderedAt: 0,
            crop: .fullFrame, outputSize: .zero, isRepeat: false, pixelBuffer: buffer)
    }

    @Test func liveSnapshotFillsSlotsAandBAndLabelsThem() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        let row = liveTiles(show)
        #expect(row.map(\.slot) == [.A, .B, .C, .D])
        #expect(row.map(\.role.badge) == ["PGM", "PVW", nil, nil])
        #expect(row.map(\.isAssigned) == [true, true, false, false])
        #expect(row[0].accessibilityLabel.hasPrefix("Cam A, "))
        #expect(row[2].accessibilityLabel == "Input C, not assigned")
    }

    @Test func cuingFromTheStripNeverChangesRouting() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        let model = LiveConsoleModel(show: show)
        let view = InputStripView(snapshot: model.snapshot, actions: model)
        #expect(view.tap(.B) == nil)     // cue: a no-op for two inputs
        #expect(show.programChannel == .a)
        #expect(show.previewChannel == .b)
        #expect(view.tap(.A) == InputStripView.programHint(for: .A))
        #expect(show.programChannel == .a)
        #expect(show.previewChannel == .b)
    }

    @Test func droppedLiveSourceKeepsSlotNameAndRole() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        b.setSourceMissingForTesting(true)
        let row = liveTiles(show)
        #expect(row[1].isAssigned)
        #expect(row[1].role.badge == "PVW")
        #expect(row[1].health.title == "No signal · holding slot")
        #expect(row.map(\.slot) == [.A, .B, .C, .D])
    }

    @Test func tilePictureSamplesTheChannelsLatestRenderedBuffer() throws {
        let show = show()
        let buffer = try surfaceBuffer()
        show.channelA.setLatestRenderedFrameForTesting(renderedFrame(buffer, channel: .a))
        let picture = LiveTilePicture(channel: show.channelA, id: .a, show: show)
        #expect(picture.frame === buffer)
        show.channelA.setLatestRenderedFrameForTesting(nil)
        #expect(picture.frame == nil)
    }

    @Test func tileLayerHoldsTheDisplayedBufferAndDrawsItsSurface() throws {
        let view = TilePictureLayerView()
        let first = try surfaceBuffer()
        view.display(first)
        #expect(view.displayed === first)
        #expect(view.layer?.contents != nil)
        let second = try surfaceBuffer()
        view.display(second)
        #expect(view.displayed === second)
        view.display(nil)
        #expect(view.displayed == nil)
        #expect(view.layer?.contents == nil)
    }
}
#endif
