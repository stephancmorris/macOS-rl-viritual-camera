//
//  DisplayOutputSink.swift
//  CinematicCoreMacOS
//
//  "Direct output (HDMI / USB-C)": a borderless, fullscreen, clean-feed window
//  on the port the ATEM chain is plugged into (Mac HDMI → HDMI-to-SDI
//  converter → ATEM). Behaves like a camera's HDMI out:
//  - a port picked explicitly is reserved while this route is selected: it
//    shows black whenever Alfie is not live, never the Mac desktop;
//  - at Start the port is switched to the show standard (e.g. 1080p50) for
//    this app only (macOS restores it if Alfie quits) and kept there until
//    the route is deselected.
//  No genlock — the window free-runs at the compositor's refresh; the
//  downstream ATEM frame-syncs.
//

import AppKit
import Combine
import CoreGraphics
import CoreVideo
import Foundation
import OSLog

@MainActor
final class DisplayOutputSink: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .display
    private static let logger = Logger(subsystem: "com.alfie", category: "DisplayOutput")

    private let program = ProgramDisplayWindowController()

    /// The last few buffers handed to the window, newest last. The layer holds
    /// the backing IOSurface *unretained*, so these strong references are what
    /// stop the CropEngine's `CVPixelBufferPool` from re-vending a surface that
    /// may still be on screen. Setting `contents` does not wait for the window
    /// server, so one frame of retention is not a guarantee; a short ring is
    /// (CR-024). This codebase has a documented history of exactly that
    /// surface-recycling tear.
    private var recentSentBuffers: [CVPixelBuffer] = []
    static let sentBufferRetention = 3

    private var isCaptureRunning = false
    private var lastError: String?
    /// This route is the operator's chosen destination.
    private var isSelected = false
    private let formatLock = DirectOutputFormatLock()

    /// A port chosen explicitly (not "Automatic") is reserved: it carries
    /// standby black while Alfie is not live. Automatic never takes over a
    /// screen that merely happens to be plugged in.
    private var reservesPort: Bool {
        UserDefaults.standard.integer(forKey: ProgramDisplaySelection.userDefaultsKey) != 0
    }

    var onStateChange: (() -> Void)?

    init() {
        // Re-resolve availability whenever displays are added, removed, or
        // reconfigured. This is the hot-unplug / re-plug path: it closes an
        // orphaned window and asks ProgramOutputManager to re-route.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Isolated: if the last reference is dropped off the main thread, the
    /// runtime runs this on the main actor instead of trapping (CR-023). The
    /// controller owns the NSWindow, so tearing it down closes the window.
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        program.teardown()
    }

    /// The `CGDirectDisplayID` the operator selected, or the default (first
    /// non-main screen if one exists). Resolved live so it always reflects
    /// current settings without rewiring this sink.
    private var targetDisplayID: CGDirectDisplayID? {
        ProgramDisplaySelection.resolvedTargetDisplayID()
    }

    /// The `NSScreen` for the target display ID, if it currently exists.
    private var targetScreen: NSScreen? {
        guard let id = targetDisplayID else { return nil }
        return ProgramDisplaySelection.screen(for: id)
    }

    var isAvailable: Bool {
        targetScreen != nil
    }

    /// Free-running display; deliberately no genlock and no rate-match check.
    var playoutFrameRate: Double? { nil }

    /// Handoff here is assigning the IOSurface to the program window's layer.
    /// The window server composites it on its own schedule and reports nothing
    /// back, so presentation stays unknown (measuring the display link is the
    /// SCREEN-LINK card, not this sink).
    var presentationObservability: String {
        "Direct output: handoff = IOSurface assigned to the program window's layer; the compositor does not report when it is shown"
    }

    var summary: String {
        guard let screen = targetScreen else {
            return "No output port is connected. Choose the HDMI / USB-C output in Settings."
        }
        if program.isShowing {
            return "Program is live on “\(screen.localizedName)”."
        }
        if isSelected && reservesPort {
            return "“\(screen.localizedName)” is reserved: sending black until the show starts."
        }
        return "Output port “\(screen.localizedName)” is ready. Start the show to send Program."
    }

    var detail: String {
        guard let screen = targetScreen else {
            return "The selected output port is not connected. Program output is paused until it is reconnected; Alfie does not move Program to another output during a show."
        }
        let size = screen.frame.size
        return "Clean fullscreen feed on “\(screen.localizedName)” (\(Int(size.width))×\(Int(size.height)) pt). Feed the display's HDMI into an HDMI-to-SDI converter for the ATEM."
    }

    var lastErrorDescription: String? { lastError }

    var bringUpChecks: [OutputBringUpCheck] {
        [displayModeCheck()]
    }

    func connect() {
        lastError = nil
        // Bring up the window only when it should actually be on screen: the
        // active route and capture running. `refreshWindowPresence` is the
        // single gate for create/teardown.
        refreshWindowPresence()
        onStateChange?()
    }

    func disconnect() {
        program.teardown()
        recentSentBuffers.removeAll()
        onStateChange?()
    }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        // Leaving this route hands the port back exactly as it was.
        if !selected { formatLock.release() }
        refreshWindowPresence()
    }

    func updateCaptureStatus(isRunning: Bool) {
        isCaptureRunning = isRunning
        if isRunning, let id = targetDisplayID {
            formatLock.lock(displayID: id, frameRate: ShowStandard.activeOrCurrent.frameRate)
        }
        refreshWindowPresence()
    }

    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        guard program.isShowing else {
            lastError = "Program display window is not open."
            return false
        }
        guard program.display(pixelBuffer) else {
            lastError = "Program frame has no IOSurface backing."
            return false
        }
        // Retain the just-shown buffer, and the few before it, so the crop
        // pool cannot recycle a surface the compositor may still be reading.
        recentSentBuffers.append(pixelBuffer)
        if recentSentBuffers.count > Self.sentBufferRetention {
            recentSentBuffers.removeFirst(recentSentBuffers.count - Self.sentBufferRetention)
        }
        lastError = nil
        return true
    }

    // MARK: - Window presence

    /// Single source of truth for whether the program window should exist:
    /// live while capture runs on this route; standby black while this route
    /// is selected with an explicitly reserved port; otherwise torn down.
    /// Called from connect/disconnect, selection and capture-status changes,
    /// and screen-parameter changes, so no path leaks a window.
    private func refreshWindowPresence() {
        guard let screen = targetScreen else {
            program.teardown()
            recentSentBuffers.removeAll()
            return
        }
        if isCaptureRunning {
            program.present(on: screen)
        } else if isSelected && reservesPort {
            program.present(on: screen)
            program.showStandby()
            recentSentBuffers.removeAll()
        } else {
            program.teardown()
            recentSentBuffers.removeAll()
        }
    }

    @objc private func screenParametersChanged() {
        let available = isAvailable
        if !available {
            // Target display vanished (hot-unplug) — close the window. The
            // manager marks the route missing; it does not re-route mid-show.
            program.teardown()
            recentSentBuffers.removeAll()
            Self.logger.notice("Program display disappeared; closing window and re-routing.")
        } else {
            // Reconfiguration: the target might have moved/resized, or come
            // back. Re-present on the current screen frame if we should be up.
            refreshWindowPresence()
        }
        // Availability may have flipped either way; let the manager re-resolve.
        onStateChange?()
    }

    // MARK: - Bring-up check

    /// The output port's current format vs. the show standard, including what
    /// the Start-time format lock did. A config check, not runtime telemetry
    /// (this route has no playout clock of its own).
    private func displayModeCheck() -> OutputBringUpCheck {
        let title = "Direct output · Format"
        guard let id = targetDisplayID, let screen = targetScreen else {
            return OutputBringUpCheck(
                id: "display.mode", title: title, status: "Missing",
                detail: "The selected output port is not connected. Program output is paused until it returns; choose another destination only while stopped.",
                level: .warning)
        }
        let standard = ShowStandard.activeOrCurrent
        guard let mode = CGDisplayCopyDisplayMode(id) else {
            return OutputBringUpCheck(
                id: "display.mode", title: title, status: "Present",
                detail: "“\(screen.localizedName)” is connected. Could not read its format; Alfie will try to set \(standard.title) at Start.",
                level: .info)
        }
        let current = DirectOutputFormat.Mode(mode)
        let statusText = current.title
        let detail: String
        let level: OutputCheckLevel
        if DirectOutputFormat.matches(current, frameRate: standard.frameRate) {
            detail = formatLock.isLocked(displayID: id)
                ? "“\(screen.localizedName)” is set to \(statusText) for this show; macOS restores its own setting when you switch output or quit Alfie."
                : "“\(screen.localizedName)” is at \(statusText), matching \(standard.title)."
            level = .ok
        } else if let failure = formatLock.lastFailure {
            detail = "“\(screen.localizedName)” is at \(statusText): \(failure) The ATEM frame-syncs, but motion may judder."
            level = .warning
        } else {
            detail = "“\(screen.localizedName)” is at \(statusText). Alfie switches it to \(standard.title) when the show starts."
            level = .info
        }
        return OutputBringUpCheck(id: "display.mode", title: title, status: statusText, detail: detail, level: level)
    }
}

/// Owns the borderless fullscreen program window and its zero-copy content view.
/// Kept separate from the sink so window lifecycle (create/show/teardown) is one
/// small object with no protocol surface.
/// The program window's content view: the shared zero-copy `PixelBufferLayerView`
/// with cursor hygiene added. Because `ignoresMouseEvents` only stops *events*,
/// the cursor can still be visible if the operator drags it onto the program
/// screen. A tracking area hides it while it is over this view — scoped to this
/// window only, so the operator's main-display cursor is never affected. We do
/// NOT call global `NSCursor.hide()`.
private final class ProgramDisplayContentView: PixelBufferLayerView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    override func mouseExited(with event: NSEvent) {
        // Leaving the program screen re-reveals the cursor immediately so the
        // operator regains it on their control surface.
        NSCursor.setHiddenUntilMouseMoves(false)
    }
}

@MainActor
private final class ProgramDisplayWindowController {
    private var window: NSWindow?
    private let contentView = ProgramDisplayContentView()

    /// The display ID the window is currently up on, so `present(on:)` can skip
    /// redundant work but still re-seat the window if the screen frame changed.
    private var presentedDisplayID: CGDirectDisplayID?

    var isShowing: Bool { window != nil }

    init() {
        // The program feed fills the panel and crops overflow; the source is
        // already 16:9 1920×1080, so this is a straight fill on a 16:9 display.
        contentView.aspectFill = true
    }

    /// Create (or re-seat) the borderless fullscreen window on the given screen.
    func present(on screen: NSScreen) {
        let displayID = ProgramDisplaySelection.displayID(for: screen)

        if let window {
            // Already up. Re-seat only if the screen or its frame changed
            // (e.g. resolution switch), otherwise leave it alone.
            if presentedDisplayID != displayID || window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
                presentedDisplayID = displayID
            }
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        // Never a click target: the program window must not steal focus or
        // mouse events from the operator's control surface.
        window.ignoresMouseEvents = true
        // Above the menu bar, without native fullscreen (no Spaces animation,
        // no menu-bar reveal on hover). Shielding-window level clears the menu
        // bar and Dock.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        window.orderFrontRegardless()

        self.window = window
        presentedDisplayID = displayID
    }

    /// Point the content view's layer at the buffer's IOSurface. Returns false
    /// if the buffer has no surface backing.
    func display(_ pixelBuffer: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetIOSurface(pixelBuffer) != nil else {
            return false
        }
        contentView.display(pixelBuffer)
        return true
    }

    /// Black, no picture: what a reserved port carries while Alfie is not live.
    func showStandby() {
        contentView.display(nil)
    }

    /// Close and release the window. Idempotent — safe to call when nothing is
    /// up. Clears the layer so no stale surface is held.
    func teardown() {
        guard let window else { return }
        contentView.display(nil)
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        self.window = nil
        presentedDisplayID = nil
    }
}

// MARK: - Format lock

/// Picking the output format: 1920×1080 pixels at the show rate, preferring a
/// 1:1 (non-Retina) mode — what an HDMI-to-SDI converter or ATEM expects.
nonisolated enum DirectOutputFormat {
    struct Mode: Equatable, Sendable {
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Double

        var title: String {
            refreshRate > 0
                ? String(format: "%d×%d @ %.2f Hz", pixelWidth, pixelHeight, refreshRate)
                : "\(pixelWidth)×\(pixelHeight)"
        }

        init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
            self.width = width; self.height = height
            self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
            self.refreshRate = refreshRate
        }

        init(_ mode: CGDisplayMode) {
            self.init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                      pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
        }
    }

    /// 0.02 Hz separates 59.94 from 60 while tolerating reported rounding.
    static func matches(_ mode: Mode, frameRate: Double) -> Bool {
        mode.pixelWidth == 1920 && mode.pixelHeight == 1080 && abs(mode.refreshRate - frameRate) < 0.02
    }

    /// Index of the mode to use, or nil if none carries 1080 at the show rate.
    static func choose(_ modes: [Mode], frameRate: Double) -> Int? {
        let candidates = modes.indices.filter { matches(modes[$0], frameRate: frameRate) }
        return candidates.first { modes[$0].width == modes[$0].pixelWidth } ?? candidates.first
    }
}

/// Applies the show format to the output port for this app only
/// (`.forAppOnly`: macOS reverts it if Alfie quits or crashes) and releases it
/// when the route is deselected. Never touches the operator's own screen:
/// the target is always the resolved output port.
@MainActor
final class DirectOutputFormatLock {
    private(set) var lockedDisplayID: CGDirectDisplayID?
    /// The port's mode before the lock changed it; restored on release so only
    /// that port is touched (CR-015).
    private var previousMode: CGDisplayMode?
    /// Why the last lock could not set the show format, for the bring-up check.
    private(set) var lastFailure: String?
    private static let logger = Logger(subsystem: "com.alfie", category: "DisplayOutput")

    func isLocked(displayID: CGDirectDisplayID) -> Bool { lockedDisplayID == displayID }

    func lock(displayID: CGDirectDisplayID, frameRate: Double) {
        if let locked = lockedDisplayID, locked != displayID { release() }
        lastFailure = nil
        if let current = CGDisplayCopyDisplayMode(displayID),
           DirectOutputFormat.matches(.init(current), frameRate: frameRate) { return }

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        guard let index = DirectOutputFormat.choose(modes.map(DirectOutputFormat.Mode.init), frameRate: frameRate) else {
            lastFailure = String(format: "the device offers no 1920×1080 mode at %.2f Hz.", frameRate)
            Self.logger.warning("Direct output: no 1080 mode at \(frameRate, privacy: .public) Hz on display \(displayID)")
            return
        }
        let modeBeforeLock = CGDisplayCopyDisplayMode(displayID)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            lastFailure = "macOS refused the display change."
            return
        }
        CGConfigureDisplayWithDisplayMode(config, displayID, modes[index], nil)
        let result = CGCompleteDisplayConfiguration(config, .forAppOnly)
        if result == .success {
            lockedDisplayID = displayID
            previousMode = modeBeforeLock
            Self.logger.notice("Direct output: set \(DirectOutputFormat.Mode(modes[index]).title, privacy: .public) on display \(displayID)")
        } else {
            lastFailure = "macOS refused the display change (\(result.rawValue))."
            Self.logger.error("Direct output: display change failed \(result.rawValue)")
        }
    }

    func release() {
        guard let displayID = lockedDisplayID else { return }
        defer {
            lockedDisplayID = nil
            previousMode = nil
        }
        // Put back the mode this port had before the lock, on this port only.
        // `CGRestorePermanentDisplayConfiguration` would reset every display.
        // Still app-only, so macOS also reverts it if Alfie quits.
        if let previousMode {
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success, let config {
                CGConfigureDisplayWithDisplayMode(config, displayID, previousMode, nil)
                let result = CGCompleteDisplayConfiguration(config, .forAppOnly)
                if result == .success { return }
                Self.logger.error("Direct output: restoring display \(displayID) failed \(result.rawValue)")
            }
        }
        // No saved mode, or the targeted restore failed: fall back to the
        // operator's System Settings formats.
        CGRestorePermanentDisplayConfiguration()
    }
}
