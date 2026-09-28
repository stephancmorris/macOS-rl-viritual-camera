//
//  ChannelFrame.swift
//  CinematicCoreMacOS
//
//  Immutable identity for work a channel produces. Every rendered program
//  frame carries the channel it came from and the three revisions that decide
//  whether it may still be used (docs/ALFIE_MULTICAMERA_SPEC.md, "Message and
//  time model"):
//
//  - sourceGeneration: start / stop / rebind of the capture source. Work from
//    an earlier generation is retired.
//  - controlEpoch: the channel's command epoch. It cancels superseded command
//    effects; it is not a frame counter.
//  - shotRevision: discrete shot intent (preset, mode, zoom move, manual
//    target, subject lock, acquisition / recovery transitions). Ordinary
//    tracking motion and interpolation do not change it.
//

import CoreGraphics
import CoreVideo
import Foundation

nonisolated struct ChannelRevisions: Equatable, Hashable, Sendable {
    var sourceGeneration: UInt64
    var controlEpoch: UInt64
    var shotRevision: UInt64
}

/// The latest program frame a channel rendered, as the router (ROUTER) and a
/// Take (TAKE) will validate it. Holds a strong reference to the rendered
/// surface; never a raw capture buffer.
struct RenderedChannelFrame {
    let channelID: ChannelID
    let revisions: ChannelRevisions
    /// Source presentation time of the capture it was rendered from (seconds).
    /// Ordering within one sourceGeneration only; never compared with host time.
    let sourceTimestamp: Double
    /// Host monotonic time frame processing began — the closest host-clock
    /// proxy for when the source frame arrived (source PTS is not compared
    /// with host time).
    let processingStartedAt: TimeInterval
    /// Host monotonic time the render completed (CACurrentMediaTime).
    let renderedAt: TimeInterval
    /// Legal crop that produced it, normalised.
    let crop: CropEngine.CropRect
    let outputSize: CGSize
    /// True when this is the last good render repeated (HOLD), not a new one.
    let isRepeat: Bool
    let pixelBuffer: CVPixelBuffer

    /// True if this frame is still the current shot from the current source:
    /// no start/stop/rebind and no discrete intent change since it rendered.
    func matches(_ current: ChannelRevisions) -> Bool {
        revisions.sourceGeneration == current.sourceGeneration
            && revisions.shotRevision == current.shotRevision
    }
}
