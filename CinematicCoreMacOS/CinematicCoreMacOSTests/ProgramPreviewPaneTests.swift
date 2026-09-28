//
//  ProgramPreviewPaneTests.swift
//  CinematicCoreMacOSTests
//
//  CONSOLE card, view-layer contract: 1280×800 geometry, every pane overlay
//  state rendered from a PaneOverlayState value with exact copy, Shot/Source
//  only on the control target, Edit Live banner visibility, and VoiceOver.
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

struct ProgramPreviewPaneTests {
    private func snapshot(_ scenario: FakeConsoleModel.Scenario, _ standard: ShowStandard = .p50) -> ConsoleSnapshot {
        FakeConsoleModel.snapshot(for: scenario, standard: standard)
    }

    // MARK: - Geometry

    @Test func minimumWindowMatchesCardGeometry() {
        let layout = MultiviewLayout(size: MultiviewLayout.minimumSize)
        #expect(layout.header == CGRect(x: 0, y: 0, width: 1280, height: 52))
        #expect(layout.previewPane == CGRect(x: 24, y: 64, width: 600, height: 338))
        #expect(layout.programPane == CGRect(x: 656, y: 64, width: 600, height: 338))
        #expect(layout.nextPanel == CGRect(x: 24, y: 414, width: 600, height: 70))
        #expect(layout.takeBar == CGRect(x: 656, y: 414, width: 600, height: 70))
        #expect(layout.stripLabel.minY == 498)
        #expect(layout.strip == CGRect(x: 24, y: 518, width: 1232, height: 168))
        #expect(layout.tileSize == CGSize(width: 299, height: 168))
        #expect(layout.strip.maxY + MultiviewLayout.pillBand == 800)
    }

    @Test(arguments: [CGSize(width: 1600, height: 1000), CGSize(width: 1920, height: 1200), CGSize(width: 2560, height: 1440)])
    func widerWindowsScalePanesAndKeepGutter(size: CGSize) {
        let layout = MultiviewLayout(size: size)
        #expect(layout.previewPane.width > 600)
        #expect(layout.programPane.minX - layout.previewPane.maxX == MultiviewLayout.centreGutter)
        #expect(abs(layout.previewPane.height - layout.previewPane.width * 9 / 16) <= 0.5)
        #expect(layout.previewPane.size == layout.programPane.size)
        // Nothing below the panes clips.
        #expect(layout.strip.maxY + MultiviewLayout.pillBand <= size.height + 1)
        #expect(layout.strip.maxX <= size.width)
    }

    @Test func wideButShortWindowIsLimitedByHeight() {
        let layout = MultiviewLayout(size: CGSize(width: 2000, height: 800))
        #expect(layout.previewPane.width <= 601)
        #expect(layout.strip.maxY + MultiviewLayout.pillBand <= 801)
    }

    // MARK: - Overlays (exact copy)

    @Test func previewPreparing() {
        let overlay = PaneOverlayState.preview(for: snapshot(.preparing))
        #expect(overlay == .previewPreparing(.b))
        #expect(overlay.title == "Preparing Cam B · Take unavailable")
        #expect(!overlay.isBlocking)
    }

    @Test func previewUnsupportedUsesActiveStandard() {
        let overlay = PaneOverlayState.preview(for: snapshot(.unsupported))
        #expect(overlay.title == "Unsupported at 1080p50")
        #expect(overlay.detail == "This Mac could not keep this camera at 50 fps alongside Program. "
                + "Alfie will not lower the output rate. Program keeps running.")

        let ntsc = PaneOverlayState.preview(for: snapshot(.unsupported, .p5994))
        #expect(ntsc.title == "Unsupported at 1080p59.94")
        #expect(ntsc.detail?.contains("at 59.94 fps alongside Program") == true)
    }

    @Test func previewMissing() {
        let overlay = PaneOverlayState.preview(for: snapshot(.missing))
        #expect(overlay.title == "Cam B source missing")
        #expect(overlay.detail == "Program is unaffected.")
        #expect(overlay.reconnectTitle == "Reconnect Cam B")
        #expect(overlay.reconnectChannel == .b)
        #expect(overlay.isBlocking)
    }

    @Test func programHold() {
        let overlay = PaneOverlayState.program(for: snapshot(.programHold))
        #expect(overlay.title == "Hold · last good frame · standby in 2 s")
        #expect(PaneModel.program(from: snapshot(.programHold)).status == "Holding last good frame")
    }

    @Test func programStandby() {
        let overlay = PaneOverlayState.program(for: snapshot(.programStandby))
        #expect(overlay.title == "Standby · Program source missing")
        #expect(overlay.detail == "Cam A disconnected. Alfie is sending black at 1080p50 and will not switch to Cam B on its own.")
        #expect(overlay.reconnectTitle == "Reconnect Cam A")
        #expect(PaneModel.program(from: snapshot(.programStandby)).status == "Standby · source missing")
    }

    @Test func programStatusCopyNeverSaysOnAir() {
        let outputs: [ConsoleSnapshot.ProgramOutput] = [.routed, .holding(standbyIn: 2), .standby, .reconnecting]
        let labels = outputs.map(PaneOverlayState.programStatus(for:))
        #expect(labels == ["Routed", "Holding last good frame", "Standby · source missing", "Reconnecting · standby"])
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("on air") })
    }

    @Test func singleInputPreviewIsEmptyNotASecondShot() {
        let model = PaneModel.preview(from: snapshot(.oneInput))
        #expect(model.overlay == .noPreviewCamera)
        #expect(model.overlay.title == "No Preview camera")
        #expect(model.channel == nil)
        #expect(model.input == nil)
    }

    @Test func readyPanesHaveNoOverlay() {
        #expect(PaneOverlayState.preview(for: snapshot(.ready)) == .none)
        #expect(PaneOverlayState.program(for: snapshot(.ready)) == .none)
    }

    // MARK: - Labels, control target, Edit Live

    @Test func paneLabelsMatchCard() {
        #expect(PaneModel.preview(from: snapshot(.ready)).label == "PREVIEW · CAM B · Band side · Waist Up")
        #expect(PaneModel.program(from: snapshot(.ready)).label == "PROGRAM · CAM A · Stage wide · Waist Up")
        #expect(PaneModel.program(from: snapshot(.ready)).status == "Routed")
    }

    @Test func sourceToggleOnlyOnControlTarget() {
        var ready = snapshot(.ready)
        ready.paneView = .source
        #expect(PaneModel.preview(from: ready).isControlTarget)
        #expect(PaneModel.preview(from: ready).paneView == .source)
        #expect(!PaneModel.program(from: ready).isControlTarget)
        // Program never shows Source unless it is the target.
        #expect(PaneModel.program(from: ready).paneView == .shot)

        var live = snapshot(.editLive)
        live.paneView = .source
        #expect(PaneModel.program(from: live).isControlTarget)
        #expect(!PaneModel.preview(from: live).isControlTarget)
    }

    @Test func editLiveBannerOnlyWhileControlsTargetProgram() {
        let live = PaneModel.program(from: snapshot(.editLive))
        #expect(live.showsEditLiveBanner)
        #expect(live.editLiveBannerText == "EDITING LIVE · Controls change Program · Cam A now")
        #expect(!PaneModel.preview(from: snapshot(.editLive)).showsEditLiveBanner)
        #expect(!PaneModel.program(from: snapshot(.ready)).showsEditLiveBanner)
    }

    @MainActor @Test func bannerHiddenAfterDoneOrSuccessfulTake() {
        let done = FakeConsoleModel(scenario: .editLive)
        done.setEditLive(false)
        #expect(!PaneModel.program(from: done.snapshot).showsEditLiveBanner)

        let took = FakeConsoleModel(scenario: .editLive)
        took.take()
        #expect(!PaneModel.program(from: took.snapshot).showsEditLiveBanner)
    }

    @Test func voiceOverReadsRoleCameraShotAndStatus() {
        #expect(PaneModel.program(from: snapshot(.ready)).accessibilityLabel
                == "Program, Cam A, Stage wide, Waist Up, Routed")
        #expect(PaneModel.preview(from: snapshot(.preparing)).accessibilityLabel
                == "Preview, Cam B, Band side, Waist Up, Preparing Cam B · Take unavailable")
    }
}
