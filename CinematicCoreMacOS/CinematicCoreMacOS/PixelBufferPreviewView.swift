//
//  PixelBufferPreviewView.swift
//  CinematicCoreMacOS
//
//  Zero-copy IOSurface preview path for the two main operator panes.
//

import SwiftUI
import AppKit
import CoreVideo

/// Displays a `CVPixelBuffer` by handing its backing `IOSurface` straight to a
/// layer's `contents`. There is no CGImage conversion and no CIContext render —
/// the compositor samples the surface directly, so a per-frame update is just a
/// pointer assignment. This replaces the old `Image(decorative:)` path that
/// created a fresh `CIContext` and did a synchronous full-frame `createCGImage`
/// on every SwiftUI body evaluation (twice, for two 4K panes) on the MainActor
/// that also owns the 20 ms frame budget.
///
/// Orientation: an `IOSurface` used as layer contents renders row 0 at the top,
/// which matches the CGImage path this replaces (SwiftUI's `Image` also draws
/// row 0 at top). No flip is required, so we never touch pixel data.
struct PixelBufferPreviewView: NSViewRepresentable {
    let pixelBuffer: CVPixelBuffer?
    /// When true, fill the pane and crop overflow (`.resizeAspectFill`); when
    /// false, letterbox to fit (`.resizeAspect`). Mirrors `CameraPreviewView`'s
    /// `aspectFill` flag.
    var aspectFill: Bool = false

    func makeNSView(context: Context) -> PixelBufferLayerView {
        let view = PixelBufferLayerView()
        view.aspectFill = aspectFill
        return view
    }

    func updateNSView(_ nsView: PixelBufferLayerView, context: Context) {
        // Trivial: assign contents and the gravity flag. No allocation — this
        // runs at up to 50 Hz.
        nsView.aspectFill = aspectFill
        nsView.display(pixelBuffer)
    }
}

/// Layer-backed host whose layer displays a pixel buffer's IOSurface.
///
/// Not `final`: the Program Display route subclasses this in
/// `DisplayOutputSink.swift` (`ProgramDisplayContentView`) to add cursor
/// hygiene while reusing the exact same zero-copy display path.
class PixelBufferLayerView: NSView {
    var aspectFill: Bool = false {
        didSet {
            guard aspectFill != oldValue else { return }
            layer?.contentsGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    private func configureLayer() {
        wantsLayer = true
        // Composite over black, matching the old `Color.black` backdrop.
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        // Clip overflow when filling so the pane stays inside its frame.
        layer?.masksToBounds = true
    }

    /// The buffer whose surface is installed as `contents`. Holding the buffer,
    /// not just the surface, is what keeps its pool from re-vending the surface
    /// while the layer still shows it. The upstream published property is
    /// replaced on the next frame, before this view is told, so it cannot be
    /// relied on (CR-028). Released when the next `display` replaces it.
    private var installedBuffer: CVPixelBuffer?

    /// Point the layer at the buffer's backing IOSurface and keep the buffer
    /// until the next call replaces it.
    func display(_ pixelBuffer: CVPixelBuffer?) {
        guard let pixelBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            layer?.contents = nil
            installedBuffer = nil
            return
        }
        layer?.contents = surface
        installedBuffer = pixelBuffer
    }
}

/// A preview that samples its buffer on the display's refresh (D-01).
///
/// `CameraManager`'s two picture buffers are assigned on every frame. They
/// used to be `@Published`, which re-evaluated every observing view up to 100
/// times a second on the thread that runs the frame path. They are plain
/// storage now, and this view pulls the newest one itself: no SwiftUI update
/// is involved in showing a new frame.
struct SampledPixelBufferView: NSViewRepresentable {
    /// Returns the newest buffer to show. Called on the main thread.
    let source: () -> CVPixelBuffer?
    var aspectFill: Bool = false

    func makeNSView(context: Context) -> SampledPixelBufferLayerView {
        let view = SampledPixelBufferLayerView()
        view.aspectFill = aspectFill
        view.source = source
        return view
    }

    func updateNSView(_ nsView: SampledPixelBufferLayerView, context: Context) {
        nsView.aspectFill = aspectFill
        nsView.source = source
        nsView.sample()
    }

    static func dismantleNSView(_ nsView: SampledPixelBufferLayerView, coordinator: ()) {
        nsView.source = nil
        nsView.stopSampling()
    }
}

final class SampledPixelBufferLayerView: PixelBufferLayerView {
    var source: (() -> CVPixelBuffer?)?
    /// The buffer on screen. It stays retained here (and in the base class)
    /// until `sample()` replaces it, so its pool cannot re-vend the surface
    /// while the layer still shows it.
    private(set) var displayed: CVPixelBuffer?
    private var link: CADisplayLink?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopSampling()
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopSampling() {
        link?.invalidate()
        link = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) { sample() }

    /// Show the source's newest buffer. The same buffer needs no layer work.
    func sample() {
        let next = source?()
        if next === displayed { return }
        displayed = next
        display(next)
    }
}
