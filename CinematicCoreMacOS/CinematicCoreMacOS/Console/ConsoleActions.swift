//
//  ConsoleActions.swift
//  CinematicCoreMacOS
//
//  The only verbs the Multiview console can send. Views call these and never
//  mutate routing directly; ShowCoordinator implements them against the live
//  pipeline (TAKE / CHANNEL-CMD / CUE), FakeConsoleModel for the gallery.
//

import Foundation

protocol ConsoleActions: AnyObject {
    /// Request a Take of the current Preview. Implementations refuse (and
    /// leave routing unchanged) unless Preview is take-eligible; there is no
    /// armed or queued cut.
    func take()

    /// Enter or leave the explicit live-edit state for Program.
    func setEditLive(_ enabled: Bool)

    /// Cue a channel as Preview. Two-input R2 builds treat this as a no-op;
    /// cueing never cuts.
    func cue(_ channel: ChannelID)

    /// Operator-requested reconnect/reclaim of a missing source.
    func reconnect(_ channel: ChannelID)

    /// Shot/Source toggle on the control-target pane.
    func setPaneView(_ view: ConsoleSnapshot.PaneView)
}
