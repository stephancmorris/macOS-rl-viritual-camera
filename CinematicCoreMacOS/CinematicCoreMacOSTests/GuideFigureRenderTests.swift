//
//  GuideFigureRenderTests.swift
//  CinematicCoreMacOSTests
//
//  GUIDE-RENDERS: offscreen renders of the Settings pages the user guide
//  describes (headroom, output). With ALFIE_GALLERY_SNAPSHOTS=1 the PNGs are
//  written to $TMPDIR/AlfieMultiviewGallery/ for docs/user-guide/figures/.
//  Synthetic renders, not live captures.
//

#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct GuideFigureRenderTests {
    private func render(_ tab: SettingsTab, file: String) throws {
        let defaults = UserDefaults(suiteName: "alfie-guide-\(UUID().uuidString)")!
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
                                   admissionRecords: AdmissionRecordStore(defaults: defaults),
                                   operatorModes: OperatorModeStore(defaults: defaults, multiviewEnabled: true))
        let controller = SettingsWindowController()
        controller.selectedTab = tab
        let view = SettingsWindow(cameraManager: show.channelA, show: show,
                                  systemExtensionManager: SystemExtensionActivationManager(),
                                  controller: controller)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 960, height: 720)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 960)
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: dir.appendingPathComponent(file))
        }
    }

    @Test func rendersSettingsAutoFraming() throws { try render(.framing, file: "settings-framing.png") }
    @Test func rendersSettingsOutput() throws { try render(.output, file: "settings-output.png") }
}
#endif
