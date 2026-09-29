//
//  PillTargetTests.swift
//  CinematicCoreMacOSTests
//
//  PILL-TARGET card: every operator pill action is bound to the show's
//  control target at gesture start (never "whatever is selected now"), a
//  target switch cannot retarget a gesture or cancel an admitted move, the
//  chip and VoiceOver name the target, and the pill fits 1280 pt with the
//  longest labels.
//

#if DEBUG
import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct PillTargetTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-pill-\(UUID().uuidString)")!))
    }

    /// A (Program) and B (Preview), both running, in Stage format.
    private func twoChannelShow() -> ShowCoordinator {
        let show = show()
        let b = show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        b.setRunningForTesting(true)
        show.channelA.shotComposer.config.cinematicFormat = .stage
        b.shotComposer.config.cinematicFormat = .stage
        return show
    }

    private func sink(_ show: ShowCoordinator, _ id: ChannelID) -> PillCommandSink {
        PillCommandSink(cameraManager: show.channel(id)!, show: show)
    }

    // MARK: Binding

    @Test func everyActionOnPreviewLandsOnTheControlTarget() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        let pill = sink(show, .b)
        // Each action is bound to B at the gesture, and B accepts it.
        for action: OperatorCommand.Action in [.setMode(.manualCrop), .setMode(.autoPan), .returnToWide,
                                               .selectPreset(.stage(.fullBody)), .beginZoom(.pushIn)] {
            let bound = show.makeCommand(action)
            #expect(bound.command.target == .channel(.b))
            #expect(bound.command.epoch == b.commands.epoch)
            #expect(pill.send(action) == .accepted, "\(action)")
        }
        #expect(a.commands.epoch == 0)
    }

    @Test func rehearsalOnBLeavesALockCropAndModeUnchanged() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        let mode = a.activeMode
        let lock = a.manualLockedTargetID
        let crop = a.cropEngine?.currentCrop
        let revision = a.shotRevision
        let epoch = a.commands.epoch
        let pill = sink(show, .b)
        pill.send(.detect)
        pill.send(.cancelDetect)
        pill.send(.selectPreset(.stage(.fullBody)))
        pill.send(.selectPreset(.stage(.waistUp)))
        pill.send(.beginZoom(.pullOut))
        pill.send(.setMode(.manualCrop))
        pill.send(.setMode(.autoPan))
        pill.send(.returnToWide)
        #expect(b.activeMode == .wide)
        #expect(a.activeMode == mode)
        #expect(a.manualLockedTargetID == lock)
        #expect(a.cropEngine?.currentCrop == crop)
        #expect(a.shotRevision == revision)
        #expect(a.commands.epoch == epoch)
        #expect(!a.detectionDiscoveryActive)
    }

    @Test func pushInAndPullOutMoveOnlyTheTargetsCrop() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        #expect(sink(show, .b).send(.beginZoom(.pushIn)) == .accepted)
        #expect(b.zoomMoveDirection == .pushIn)
        #expect(a.zoomMoveDirection == nil)
    }

    @Test func aTargetSwitchDoesNotRetargetTheGesture() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        let pill = sink(show, .b)          // drawn for B
        show.setEditLive(true)             // the target is now A
        let mode = a.activeMode
        let revision = a.shotRevision
        // B's pill is stale; its gesture is refused, not sent to A.
        #expect(pill.send(.setMode(.manualCrop)) == .rejected("Control target changed"))
        #expect(pill.send(.returnToWide) == .rejected("Control target changed"))
        #expect(a.activeMode == mode && a.shotRevision == revision)
        #expect(b.activeMode == .wide)
    }

    @Test func aMoveAdmittedOnBSurvivesTheTargetSwitchAndRebuild() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        #expect(sink(show, .b).send(.beginZoom(.pushIn)) == .accepted)
        #expect(b.zoomMoveDirection == .pushIn)
        // The pill for B is on screen, then Edit Live changes the target and
        // the console rebuilds the pill (`.id`), tearing the old one down.
        let host = NSHostingView(rootView: AnyView(
            OperatorPill(cameraManager: b, controlTarget: .preview(channel: .b), show: show)))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        show.setEditLive(true)
        host.rootView = AnyView(
            OperatorPill(cameraManager: a, controlTarget: .editingLive(channel: .a), show: show))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        #expect(b.zoomMoveDirection == .pushIn, "Rebuilding the pill must not cancel an admitted move")
        #expect(a.zoomMoveDirection == nil)
    }

    @Test func aTargetSwitchCancelsAPendingDetectOnTheOldTarget() {
        let show = twoChannelShow()
        let b = show.channel(.b)!
        #expect(sink(show, .b).send(.detect) == .accepted)
        #expect(b.detectionDiscoveryActive)
        show.setEditLive(true)
        #expect(!b.detectionDiscoveryActive)
    }

    @Test func singleCameraKeepsTodaysDirectPath() {
        let manager = CameraManager()
        manager.setRunningForTesting(true)
        let pill = PillCommandSink(cameraManager: manager, show: nil)
        #expect(pill.send(.setMode(.manualCrop)) == .accepted)
        #expect(manager.activeMode == .manualCrop)
    }

    @Test func aSingleInputShowStillBindsToProgram() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        #expect(show.previewChannel == nil)
        #expect(sink(show, .a).send(.setMode(.manualCrop)) == .accepted)
        #expect(show.channelA.activeMode == .manualCrop)
    }

    // MARK: Editing live

    @Test func editLiveFlipsTheChipAndTargetsA() {
        let show = twoChannelShow()
        let a = show.channelA
        let b = show.channel(.b)!
        show.setEditLive(true)
        #expect(show.controlTarget == .a)
        let pill = sink(show, .a)
        #expect(pill.send(.setMode(.manualCrop)) == .accepted)
        #expect(a.activeMode == .manualCrop)
        #expect(b.activeMode == .wide)
        show.setEditLive(false)
        #expect(show.controlTarget == .b)
        // Done returns to Preview: A's pill is stale now, B's works.
        #expect(pill.send(.returnToWide) == .rejected("Control target changed"))
        #expect(sink(show, .b).send(.returnToWide) == .accepted)
        #expect(ControlTarget.preview(channel: .b).chipTitle == "CAM B · PREVIEW")
        #expect(ControlTarget.editingLive(channel: .a).chipTitle == "CAM A · EDITING LIVE")
    }

    // MARK: VoiceOver

    @Test func labelsNameTheTarget() {
        let preview = ControlTarget.preview(channel: .b)
        let live = ControlTarget.editingLive(channel: .a)
        #expect(preview.accessibleLabel("Push in") == "Push in, Cam B, Preview")
        #expect(preview.accessibleLabel("Return B to Wide") == "Return B to Wide, Cam B, Preview")
        #expect(live.accessibleLabel("Auto Pan") == "Auto Pan, Cam A, Editing live")
        #expect(live.accessibleLabel("Return A to Wide") == "Return A to Wide, Cam A, Editing live")
        // Single camera keeps today's labels.
        #expect(ControlTarget.singleCamera.accessibleLabel("Push in") == "Push in")
        #expect(ControlTarget.singleCamera.accessibilityContext == nil)
    }

    @Test func returnToWideAlwaysNamesTheTargetLetter() {
        #expect(ControlTarget.preview(channel: .b).camera == "B")
        #expect(ControlTarget.editingLive(channel: .a).camera == "A")
        #expect(ControlTarget.singleCamera.camera == nil)   // "Return to Wide"
    }

    // MARK: Fit at 1280

    /// 1280 pt window less the console's 24 pt margins.
    private let availableWidth: CGFloat = 1232

    private func pillWidth(_ target: ControlTarget, _ style: OperatorPill.ChipStyle, format: ShotComposer.Config.CinematicFormat = .stage) -> CGFloat {
        let manager = CameraManager()
        manager.shotComposer.config.cinematicFormat = format
        return NSHostingView(rootView: OperatorPill(
            cameraManager: manager, controlTarget: target, show: nil, chipStyle: style)).fittingSize.width
    }

    @Test func targetPillsFitTheMultiviewWidthWithTheLongestLabels() {
        for target in [ControlTarget.preview(channel: .b), .editingLive(channel: .a)] {
            for format in [ShotComposer.Config.CinematicFormat.stage, .webcam] {
                let compact = pillWidth(target, .compact, format: format)
                let full = pillWidth(target, .full, format: format)
                print("PILLWIDTH \(target) \(format) compact=\(compact) full=\(full)")
                #expect(compact <= availableWidth, "Compact \(target) pill width \(compact)")
                #expect(full <= availableWidth, "Full \(target) pill width \(full)")
            }
        }
    }

    /// The console shows the full chip because the widest pill (Edit Live,
    /// Stage) is 1183 pt, inside the 1232 pt available at 1280 with margins;
    /// compact stays available for narrower hosts. Rule is static: the
    /// console's minimum width is 1280, so it never needs to switch at runtime.
    @Test func consoleDefaultsToTheFullChipAndItFits() {
        let manager = CameraManager()
        manager.shotComposer.config.cinematicFormat = .stage
        let pill = OperatorPill(cameraManager: manager, controlTarget: .editingLive(channel: .a), show: nil)
        #expect(pill.chipStyle == .full)
        #expect(NSHostingView(rootView: pill).fittingSize.width <= availableWidth)
        #expect(MultiviewLayout.minimumSize.width >= 1280)
    }

    // MARK: Renders

    private func render(editLive: Bool, name: String) throws {
        let show = twoChannelShow()
        if editLive { show.setEditLive(true) }
        let host = NSHostingView(rootView: LiveMultiviewConsole(show: show).environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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

    @Test func rendersThePreviewPillAt1280() throws {
        try render(editLive: false, name: "pill-preview-1280.png")
    }

    @Test func rendersTheEditLivePillAt1280() throws {
        try render(editLive: true, name: "pill-editlive-1280.png")
    }
}
#endif
