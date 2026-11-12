#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

/// Shared only by Astra's journey galleries; each caller owns its output names.
@MainActor
enum OperatorJourneySnapshot {
    static func capture<V: View>(_ view: V, name: String, dark: Bool,
                                 width: CGFloat = 1280, height: CGFloat = 800) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: width, height: height)
            .background(AlfieColor.background))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = JourneyGalleryWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        #expect(image.pixelsWide >= Int(width) && image.pixelsHigh >= Int(height))
        let environment = ProcessInfo.processInfo.environment
        guard environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" else { return }
        let root = environment["ALFIE_GALLERY_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        let folder = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try #require(image.representation(using: .png, properties: [:]))
        try data.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }
}

private final class JourneyGalleryWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
#endif
