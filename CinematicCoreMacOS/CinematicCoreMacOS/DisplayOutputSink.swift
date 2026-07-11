//
//  DisplayOutputSink.swift
//  CinematicCoreMacOS
//
//  Third program-output route: a borderless, fullscreen, clean-feed window on a
//  selected display. Feeds an ATEM switcher via the Mac's HDMI port →
//  HDMI-to-SDI converter, sidestepping the Thunderbolt bus-power problems of the
//  DeckLink hardware. No genlock — the window free-runs at the compositor's
//  refresh; the downstream ATEM frame-syncs.
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

    /// The last buffer handed to the window. The layer holds the backing
    /// IOSurface *unretained*, so this strong reference is the only thing
    /// stopping the CropEngine's `CVPixelBufferPool` from re-vending a surface
    /// that is still on screen. Replaced (not appended) each frame — one frame
    /// of retention is enough because the compositor samples the previous
    /// surface synchronously before we swap in the next. This codebase has a
    /// documented history of exactly that surface-recycling tear.
    private var lastSentBuffer: CVPixelBuffer?

    private var isCaptureRunning = false
    private var lastError: String?

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

    deinit {
        NotificationCenter.default.removeObserver(self)
        // `deinit` is nonisolated; tear the window down on the MainActor. The
        // controller owns the NSWindow, so releasing it there closes the window.
        MainActor.assumeIsolated {
            program.teardown()
        }
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

    var summary: String {
        guard let screen = targetScreen else {
            return "No program display is connected. Select a display in Settings."
        }
        if program.isShowing {
            return "Program feed is fullscreen on “\(screen.localizedName)”."
        }
        return "Program display “\(screen.localizedName)” is ready. Start capture to go fullscreen."
    }

    var detail: String {
        guard let screen = targetScreen else {
            return "The selected program display is not present. Plug it in or pick another display in Settings, then the feed falls back to the virtual camera."
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
        lastSentBuffer = nil
        onStateChange?()
    }

    func updateCaptureStatus(isRunning: Bool) {
        isCaptureRunning = isRunning
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
        // Retain the just-shown buffer so the crop pool cannot recycle its
        // surface while the compositor is still reading it. Replacing the
        // previous reference releases the frame before last, which is safe: the
        // compositor has already sampled it.
        lastSentBuffer = pixelBuffer
        lastError = nil
        return true
    }

    // MARK: - Window presence

    /// Single source of truth for whether the program window should exist. The
    /// window is shown iff capture is running and the target screen is present;
    /// otherwise it is torn down. Called from connect/disconnect, capture-status
    /// changes, and screen-parameter changes, so no path leaks a window.
    private func refreshWindowPresence() {
        if isCaptureRunning, let screen = targetScreen {
            program.present(on: screen)
        } else {
            program.teardown()
            lastSentBuffer = nil
        }
    }

    @objc private func screenParametersChanged() {
        let available = isAvailable
        if !available {
            // Target display vanished (hot-unplug) — close the window and let
            // ProgramOutputManager re-route (fallback to virtual camera).
            program.teardown()
            lastSentBuffer = nil
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

    /// Static config check: the target display's current mode vs. the show
    /// standard. Warns when the refresh rate differs from the standard's frame
    /// rate by more than 0.5 Hz — a cheap correctness gate, not runtime
    /// telemetry (this route has no playout clock of its own).
    private func displayModeCheck() -> OutputBringUpCheck {
        guard let id = targetDisplayID, let screen = targetScreen else {
            return OutputBringUpCheck(
                id: "display.mode",
                title: "Program Display · Mode",
                status: "Missing",
                detail: "The selected program display is not connected. Output will fall back to the virtual camera.",
                level: .warning
            )
        }

        let standard = ShowStandard.current
        guard let mode = CGDisplayCopyDisplayMode(id) else {
            return OutputBringUpCheck(
                id: "display.mode",
                title: "Program Display · Mode",
                status: "Present",
                detail: "“\(screen.localizedName)” is connected. Could not read its current display mode; verify it is set to \(standard.title) in System Settings → Displays.",
                level: .info
            )
        }

        let width = mode.pixelWidth
        let height = mode.pixelHeight
        let refresh = mode.refreshRate // Hz; 0 for some internal/variable panels.
        let target = standard.frameRate

        // A reported refresh of 0 (common on built-in panels) is not a mismatch
        // signal — treat it as "unknown" rather than warning falsely.
        let refreshMismatch = refresh > 0 && abs(refresh - target) > 0.5
        let statusText: String
        if refresh > 0 {
            statusText = String(format: "%d×%d @ %.2f Hz", width, height, refresh)
        } else {
            statusText = "\(width)×\(height)"
        }

        let detail: String
        let level: OutputCheckLevel
        if refreshMismatch {
            detail = String(
                format: "“%@” is running at %.2f Hz but the show standard is %@ (%.2f Hz). Set the display's resolution and refresh to %@ in System Settings → Displays.",
                screen.localizedName, refresh, standard.title, target, standard.title
            )
            level = .warning
        } else {
            detail = "“\(screen.localizedName)” is set to \(statusText). Confirm it matches the show standard (\(standard.title)) in System Settings → Displays."
            level = .ok
        }

        return OutputBringUpCheck(
            id: "display.mode",
            title: "Program Display · Mode",
            status: statusText,
            detail: detail,
            level: level
        )
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
