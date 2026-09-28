//
//  MultiviewGallerySnapshotTests.swift
//  CinematicCoreMacOSTests
//
//  Renders the CONSOLE / TAKE-BAR / NEXT-PANEL gallery sections for every
//  FakeConsoleModel scenario at 1280 pt. Always checks that each renders at
//  the card size; set ALFIE_GALLERY_SNAPSHOTS=1 (via
//  TEST_RUNNER_ALFIE_GALLERY_SNAPSHOTS=1 on xcodebuild) to also write PNGs
//  for review into the test host's temporary directory.
//

#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct MultiviewGallerySnapshotTests {
    private static let writesFiles = ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1"
    private static let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)

    @Test(arguments: FakeConsoleModel.Scenario.allCases)
    func rendersEveryScenario(scenario: FakeConsoleModel.Scenario) throws {
        try renderSheet(FakeConsoleModel(scenario: scenario), name: scenario.rawValue)
    }

    @Test(arguments: [FakeConsoleModel.Scenario.ready, .editLive])
    func rendersSourceViewOnControlTarget(scenario: FakeConsoleModel.Scenario) throws {
        let model = FakeConsoleModel(scenario: scenario)
        model.setPaneView(.source)
        try renderSheet(model, name: "\(scenario.rawValue)-source")
    }

    private func renderSheet(_ model: FakeConsoleModel, name: String) throws {
        let sheet = GallerySheet(scenario: model.scenario, model: model)

        // 1280 console + 24 pt padding each side; console + label + bars.
        let size = CGSize(width: 1328, height: 1000)
        let image: NSBitmapImageRep = try #require(render(sheet, size: size))
        let width = image.pixelsWide
        let height = image.pixelsHigh
        #expect(width >= 1328)
        #expect(height >= 1000)

        if Self.writesFiles {
            try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
            let url = Self.outputDirectory.appendingPathComponent("gallery-\(name).png")
            let png: Data? = image.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
            let data = try #require(png)
            try data.write(to: url)
            print("[GALLERY] wrote \(url.path)")
        }
    }

    private func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

/// One screenshot per scenario: console frame plus both bars.
private struct GallerySheet: View {
    let scenario: FakeConsoleModel.Scenario
    @ObservedObject var model: FakeConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SCENARIO · \(scenario.title.uppercased())")
                .font(ConsoleStyle.label(12))
                .foregroundStyle(.white.opacity(0.7))
            PanesDemo(model: model)
            HStack(alignment: .top, spacing: 32) {
                NextPanelDemo(model: model)
                TakeBarDemo(model: model)
            }
        }
        .padding(24)
        .background(ConsoleStyle.background)
    }
}
#endif
