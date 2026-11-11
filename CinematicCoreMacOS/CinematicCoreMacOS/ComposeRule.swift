//
//  ComposeRule.swift
//  CinematicCoreMacOS
//
//  When the tracking branch of the frame path runs the composer (D-02
//  path 2). Before this rule the composer ran on every frame. Under it, the
//  composer runs on a frame only when something it reads has changed:
//
//  1. a fresh detection arrived;
//  2. a framing command landed (a preset, headroom or format change) and no
//     compose has applied it yet;
//  3. a shot move changed the crop size on this frame (a push-in or pull-out
//     in flight, or the frame it starts or is cleared on).
//
//  `FreshOnlyComposeTests` compare the crop this rule gives against composing
//  on every frame.
//

import CoreGraphics

nonisolated struct ComposeRule: Sendable {
    /// The crop height the shot move showed the last time the rule was asked.
    private var lastZoomHeight: CGFloat?

    /// The rule itself.
    static func composes(freshDetection: Bool, framingChangePending: Bool, shotMoveChangedSize: Bool) -> Bool {
        freshDetection || framingChangePending || shotMoveChangedSize
    }

    /// Ask once per frame, after the shot move has stepped. `zoomHeight` is
    /// `CropEngine.adjustedHeight`: nil when no shot move owns the size.
    mutating func composes(freshDetection: Bool, framingChangePending: Bool, zoomHeight: CGFloat?) -> Bool {
        let moved = zoomHeight != lastZoomHeight
        lastZoomHeight = zoomHeight
        return Self.composes(freshDetection: freshDetection, framingChangePending: framingChangePending,
                             shotMoveChangedSize: moved)
    }
}
