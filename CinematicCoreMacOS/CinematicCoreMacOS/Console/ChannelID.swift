//
//  ChannelID.swift
//  CinematicCoreMacOS
//
//  Stable identity for one camera input slot. The Multiview console reserves
//  four fixed slots (A–D); the R2 technical release runs exactly two (A, B).
//  Declaring C and D here does not instantiate channels for them — see
//  docs/ALFIE_MULTICAMERA_SPEC.md "Input capacity". The CHANNEL card extends
//  this type with per-channel state; keep it a plain value.
//

import Foundation

nonisolated enum ChannelID: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }

    /// Single capital letter used in every operator-facing label.
    var letter: String { rawValue }

    /// "Cam A" — the console's short name for a channel.
    var cameraLabel: String { "Cam \(rawValue)" }
}
