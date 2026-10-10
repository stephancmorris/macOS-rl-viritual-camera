//
//  DirectorNextShotTests.swift
//  CinematicCoreMacOSTests
//
//  C-03: the director line uses the status model's own sentences, AUTO
//  appears only when Alfie set the shot, and the panel stays inside 600×70.
//

import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct DirectorNextShotTests {
    @Test func directorLineUsesPreparedShotAndStatus() {
        let line = NextShotPanel.directorLine(DirectorNextDemo.preparing)
        #expect(line == "Cam B · Waist Up · Preparing Cam B Waist Up · subject settled")
        let empty = NextShotPanel.directorLine(DirectorNextDemo.nothingPrepared)
        #expect(empty == "No shot prepared · Preview is the wide camera · nothing to prepare")
    }

    @Test func autoBadgeFollowsTheStatus() {
        #expect(DirectorNextDemo.preparing.showsAutoBadge(on: .b))
        #expect(DirectorNextDemo.preparing.showsAutoBadge(on: .a) == false)
        #expect(DirectorNextDemo.nothingPrepared.alfieSetShot.isEmpty)
        #expect(NextShotStatus.DirectorSection.autoBadge == "AUTO")
    }

    @Test func withoutADirectorSectionThePanelStaysTwoLines() {
        let status = DirectorNextDemo.readyStatus
        #expect(status.director == nil)
        #expect(status.withDirector(DirectorNextDemo.preparing).director?.statusLine == DirectorNextDemo.preparing.statusLine)
    }

    @Test func directorLineFitsThePanelBudget() throws {
        let panel = NextShotPanel(status: DirectorNextDemo.readyStatus.withDirector(DirectorNextDemo.preparing))
            .frame(width: 600, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
        let host = NSHostingView(rootView: panel.environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        #expect(height > 0)
        #expect(height <= MultiviewLayout.barHeight)
    }

    @Test func rendersThePanelAndTheBadge() throws {
        let view = DirectorNextDemo()
            .padding(24)
            .frame(width: 1280, alignment: .topLeading)
            .background(ConsoleStyle.background)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let height = min(max(host.fittingSize.height, 200), 700)
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: height)
        window.setContentSize(NSSize(width: 1280, height: height))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 1280)
        guard ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1",
              let path = ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try data.write(to: dir.appendingPathComponent("director-next-shot.png"))
    }
}
