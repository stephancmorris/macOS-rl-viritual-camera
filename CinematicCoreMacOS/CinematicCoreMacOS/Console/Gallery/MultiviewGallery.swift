//
//  MultiviewGallery.swift
//  CinematicCoreMacOS
//
//  DEBUG-only component gallery for the Multiview console. A scenario picker
//  drives one FakeConsoleModel; each section renders one console component
//  from that model so every card's states can be reviewed (and screenshotted)
//  without cameras, the router or ContentView. Gated by
//  DeveloperFlags.exposeMultiviewGallery.
//

#if DEBUG
import AppKit
import SwiftUI

struct MultiviewGalleryView: View {
    @StateObject private var model: FakeConsoleModel

    init(model: FakeConsoleModel = FakeConsoleModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    MultiviewGallerySection("Panes · CONSOLE") { PanesDemo(model: model) }
                    MultiviewGallerySection("Take bar · TAKE-BAR") { TakeBarDemo(model: model) }
                    MultiviewGallerySection("Next-shot panel · NEXT-PANEL") { NextPanelDemo(model: model) }
                    MultiviewGallerySection("Director · C-01") { DirectorDemo(model: model) }
                    MultiviewGallerySection("Input strip · INPUT-STRIP") { StripDemo() }
                    MultiviewGallerySection("Show setup · SHOW-SETUP") { SetupDemo() }
                    MultiviewGallerySection("Operator pill · PILL-TARGET") { PillDemo(model: model) }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(white: 0.07))
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Scenario", selection: Binding(
                get: { model.scenario },
                set: { model.load($0) }
            )) {
                ForEach(FakeConsoleModel.Scenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario)
                }
            }
            .frame(width: 280)

            Picker("Show standard", selection: Binding(
                get: { model.snapshot.showStandard },
                set: { model.setShowStandard($0) }
            )) {
                ForEach(ShowStandard.allCases) { standard in
                    Text(standard.title).tag(standard)
                }
            }
            .frame(width: 240)

            Spacer()

            Text(model.actionLog.last.map { "Last action: \($0)" } ?? "No actions yet")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

struct MultiviewGallerySection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Placeholder a *Demo view shows until its card lands.
struct GalleryPendingLabel: View {
    let card: String

    var body: some View {
        Text("\(card) · pending")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }
}

/// Scene an app can add to expose the gallery as its own window.
struct MultiviewGalleryScene: Scene {
    static let windowID = "multiview-gallery"

    var body: some Scene {
        Window("Multiview Gallery", id: Self.windowID) {
            if DeveloperFlags.exposeMultiviewGallery {
                MultiviewGalleryView()
            } else {
                Text("Multiview gallery disabled (DeveloperFlags.exposeMultiviewGallery)")
                    .padding(40)
            }
        }
        .defaultSize(width: 1360, height: 900)
    }
}

/// Opens the gallery in a plain AppKit window, for callers that cannot add a
/// Scene (e.g. a debug menu item). No-op when the flag is off.
enum MultiviewGalleryWindow {
    private static var window: NSWindow?

    static func show() {
        guard DeveloperFlags.exposeMultiviewGallery else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Multiview Gallery"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: MultiviewGalleryView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
#endif
