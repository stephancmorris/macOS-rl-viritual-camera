//
//  DebugLaunchHooks.swift
//  CinematicCoreMacOS
//
//  DEBUG-only launch hooks for checking the live console without clicking:
//
//  - ALFIE_DEBUG_AUTOSTART=a | pair — the show setup screen starts Camera A,
//    or A + B (first two cameras if none are chosen), once per launch.
//  - ALFIE_DEBUG_WINDOW_DUMP=<seconds> — once, that long after launch, the
//    key window is written to <tmp>/AlfieMultiviewGallery/window-dump.png. IOSurface pictures do not
//    render through cacheDisplay (panes come out black); layout, text and
//    the pill do.
//
//  Not compiled into Release.
//

#if DEBUG
import AppKit
import Foundation
import OSLog
import SwiftUI

enum DebugLaunchHooks {
    /// Environment variable, or launch argument (`open -n Alfie.app --args
    /// -ALFIE_DEBUG_AUTOSTART pair`), which lands in UserDefaults.
    private static func value(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key] ?? UserDefaults.standard.string(forKey: key)
    }
    static var autostart: String? { value("ALFIE_DEBUG_AUTOSTART") }
    private static var didAutostart = false
    private static let logger = Logger(subsystem: "com.alfie", category: "DebugHooks")

    static func autostartIfRequested(_ model: LiveShowSetupModel, cameras: () -> [CameraManager.CameraDevice]) async {
        logger.notice("[DEBUG] setup appeared; autostart=\(autostart ?? "none", privacy: .public)")
        guard let mode = autostart, !didAutostart else { return }
        didAutostart = true
        try? await Task.sleep(for: .seconds(1.5))
        let available = cameras()
        logger.notice("[DEBUG] autostart \(mode, privacy: .public) with \(available.map(\.name), privacy: .public)")
        if mode == "pair", available.count >= 2 {
            model.select(available[0].uniqueID, for: .a)
            model.select(available[1].uniqueID, for: .b)
            model.startPair()
        } else if let first = available.first {
            model.select(first.uniqueID, for: .a)
            model.startAOnly()
        }
    }

    /// One dump, `ALFIE_DEBUG_WINDOW_DUMP` seconds after launch. Rendering
    /// the window on the CPU (large blurred shadows) takes seconds of main
    /// thread, so never repeat it while measuring.
    static func startWindowDumps() {
        guard let delay = value("ALFIE_DEBUG_WINDOW_DUMP").flatMap(Double.init), delay > 0 else { return }
        logger.notice("[DEBUG] window dump in \(delay) s")
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { dumpKeyWindow() }
        }
    }

    private static func dumpKeyWindow() {
        guard let view = (NSApp.keyWindow ?? NSApp.windows.first)?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("window-dump.png"))
        } catch {
            logger.error("[DEBUG] window dump failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
