//
//  LiveTilePicture.swift
//  CinematicCoreMacOS
//
//  The live picture behind each input-strip tile (INPUT-STRIP).
//
//  Why a sampler and not an observer: `CameraManager.croppedFrameBuffer` is
//  @Published and assigned on every rendered frame (50 Hz). Four tiles
//  observing it would re-evaluate SwiftUI four times per frame on the
//  MainActor. Instead each tile reads the channel's plain (unpublished)
//  `latestRenderedFrame` from a 15 Hz TimelineView, the same 15 Hz UI-mirror
//  budget as the console snapshot, and hands its IOSurface straight to a
//  layer (zero copy, no NSImage). The tile never subscribes to the channel.
//
//  Retention: the layer view keeps the one CVPixelBuffer it last displayed so
//  the crop pool cannot re-vend that surface while it is on screen (the same
//  rule the panes follow), and drops it on the next sample. That is at most a
//  few frames older than the channel's latest render, and one buffer per tile.
//

import AppKit
import CoreVideo
import SwiftUI

/// Rendered output of one channel, sampled at ≤15 Hz. Shows RENDERED shots
/// only (never a raw capture buffer). Black when it is the Program channel
/// and the router is in standby, exactly what is downstream.
struct LiveTilePicture: View {
    let channel: CameraManager
    let id: ChannelID
    let show: ShowCoordinator

    static let refreshInterval: TimeInterval = 1.0 / 15.0
    /// Fixed schedule origin so a parent re-render never restarts the timeline.
    private static let scheduleOrigin = Date(timeIntervalSinceReferenceDate: 0)

    /// Picture slot for `InputStripView`.
    static func make(id: ChannelID, show: ShowCoordinator) -> AnyView {
        guard let channel = show.channel(id) else { return AnyView(Color.clear) }
        return AnyView(LiveTilePicture(channel: channel, id: id, show: show))
    }

    var body: some View {
        TimelineView(.periodic(from: Self.scheduleOrigin, by: Self.refreshInterval)) { _ in
            TilePictureSurface(pixelBuffer: frame)
        }
    }

    var frame: CVPixelBuffer? {
        if id == show.programChannel, show.router.state == .standby { return nil }
        return channel.latestRenderedFrame?.pixelBuffer
    }
}

/// Zero-copy surface for a tile: `PixelBufferPreviewView`'s layer path plus
/// retention of the displayed buffer (see the file header).
struct TilePictureSurface: NSViewRepresentable {
    let pixelBuffer: CVPixelBuffer?

    func makeNSView(context: Context) -> TilePictureLayerView {
        let view = TilePictureLayerView()
        view.aspectFill = true
        return view
    }

    func updateNSView(_ nsView: TilePictureLayerView, context: Context) {
        nsView.display(pixelBuffer)
    }
}

final class TilePictureLayerView: PixelBufferLayerView {
    /// The buffer whose surface is currently on screen.
    private(set) var displayed: CVPixelBuffer?

    override func display(_ pixelBuffer: CVPixelBuffer?) {
        // The same buffer (a repeat, or no new frame since the last tick)
        // needs no layer work.
        if let pixelBuffer, let displayed, pixelBuffer === displayed { return }
        displayed = pixelBuffer
        super.display(pixelBuffer)
    }
}
