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

    /// One input-strip state per file. `StripDemo` shows every scenario at
    /// once; these captures are the rows in `docs/gallery-screenshots`.
    @Test(arguments: FakeConsoleModel.Scenario.allCases)
    func rendersEachInputStripOnItsOwn(scenario: FakeConsoleModel.Scenario) throws {
        let model = FakeConsoleModel(scenario: scenario)
        // 1232 pt row plus 24 pt padding on each side is the 1280 pt capture.
        // The tile row is 168 pt; the label is `stripLabelHeight`.
        let strip = InputStripView(snapshot: model.snapshot, actions: model)
            .frame(width: 1232, height: MultiviewLayout.stripLabelHeight + 168)
            .padding(24)
            .background(ConsoleStyle.background)
        try renderNamed(strip, size: CGSize(width: 1280, height: MultiviewLayout.stripLabelHeight + 168 + 48),
                        name: "input-\(scenario.rawValue).png")
    }

    /// The four pair-check results the gallery README names. Certified and
    /// a missing saved camera exist on `GalleryScenario` and are not rows.
    @Test(arguments: [
        (ShowSetupModel.GalleryScenario.notRun, "setup-not-run.png"),
        (.checking, "setup-checking.png"),
        (.pass, "setup-pass.png"),
        (.unsupported, "setup-unsupported.png")
    ])
    func rendersEachNamedSetupResult(scenario: ShowSetupModel.GalleryScenario, name: String) throws {
        let setup = ShowSetupView(model: .gallery(scenario), actions: ShowSetupActions(
            selectDevice: { _, _ in }, selectStandard: { _ in }, selectOutput: { _ in },
            startAOnly: {}, startPair: {}, checkPair: nil))
            .frame(width: 1280, height: 800)
        try renderNamed(setup, size: CGSize(width: 1280, height: 800), name: name)
    }

    /// `PillDemo` shows one target derived from the fake console. These three
    /// scenarios are the README's single, Preview and Edit Live rows.
    @Test(arguments: [
        (FakeConsoleModel.Scenario.oneInput, "pill-single.png"),
        (.ready, "pill-preview.png"),
        (.editLive, "pill-editing-live.png")
    ])
    func rendersEachNamedPillTarget(scenario: FakeConsoleModel.Scenario, name: String) throws {
        let model = FakeConsoleModel(scenario: scenario)
        switch scenario {
        case .oneInput:
            #expect(model.snapshot.previewChannel == nil && !model.snapshot.editLive)
        case .ready:
            #expect(model.snapshot.previewChannel == .b && !model.snapshot.editLive)
        case .editLive:
            #expect(model.snapshot.editLive)
        default:
            Issue.record("\(scenario) is not a named pill capture")
        }
        let pill = PillDemo(model: model)
            .frame(width: 1280)
            .padding(.vertical, 24)
            .background(ConsoleStyle.background)
        try renderNamed(pill, size: CGSize(width: 1280, height: 220), name: name)
    }

    private func renderNamed<V: View>(_ view: V, size: CGSize, name: String) throws {
        let image: NSBitmapImageRep = try #require(render(view, size: size))
        #expect(image.pixelsWide >= Int(size.width))
        #expect(image.pixelsHigh >= Int(size.height))
        guard Self.writesFiles else { return }
        let directory = Self.namedOutputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png: Data? = image.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
        try #require(png).write(to: directory.appendingPathComponent(name))
    }

    /// Where the named README captures go. `ALFIE_GALLERY_SNAPSHOT_DIR`
    /// overrides the temporary directory so a run can write the committed set.
    private static var namedOutputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return outputDirectory
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
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height))
        // Keep SwiftUI's intrinsic content size from resizing the test canvas.
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let window = GallerySnapshotWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        #expect(host.bounds.size == size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        #expect(host.bounds.size == size)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

/// Snapshot canvases may exceed a hosted runner's virtual screen. AppKit's
/// constraints can shrink oversized windows; keep the
/// requested offscreen size rather than weakening the image-size assertions.
private final class GallerySnapshotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
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
