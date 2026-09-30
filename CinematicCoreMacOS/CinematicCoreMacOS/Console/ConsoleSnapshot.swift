//
//  ConsoleSnapshot.swift
//  CinematicCoreMacOS
//
//  The Multiview console's entire input, as plain values. Views read one
//  snapshot and never reach into CameraManager or the router; ShowCoordinator
//  (later) publishes a coalesced snapshot, and FakeConsoleModel builds them
//  for the gallery and tests. No pixel buffers live here — pane pictures are
//  supplied separately so the snapshot stays cheap to compare and copy.
//
//  Contract: docs/ALFIE_MULTICAMERA_SPEC.md "Multiview console".
//

import CoreGraphics
import Foundation

nonisolated struct ConsoleSnapshot: Equatable, Sendable {

    /// Role a channel currently holds. Program means Alfie's routed picture,
    /// never ATEM tally.
    enum Role: Equatable, Sendable {
        case program
        case preview
        case idle
    }

    /// Health of one channel's source as the console reports it.
    enum SourceHealth: Equatable, Sendable {
        /// Running and delivering frames at `deliveredRate` fps.
        case running(deliveredRate: Double)
        /// Admission found the pair cannot hold the show standard.
        case unsupported
        /// Source lost; the slot keeps its name and role.
        case missing
        /// Operator pressed Reconnect; waiting for a fresh generation.
        case reconnecting
    }

    /// One of the four fixed input slots (A–D).
    struct Slot: Equatable, Sendable, Identifiable {
        var channel: ChannelID
        /// nil for an unassigned slot (dashed placeholder).
        var input: Input?

        var id: ChannelID { channel }
        var isAssigned: Bool { input != nil }

        struct Input: Equatable, Sendable {
            /// Operator-facing camera name, e.g. "Band side".
            var name: String
            /// Current shot, e.g. "Waist Up".
            var shot: String
            var role: Role
            var health: SourceHealth
            /// Current legal crop in normalised top-left-origin coordinates,
            /// drawn dashed in Source view.
            var legalCrop: CGRect
        }
    }

    /// What the router is sending downstream for the Program channel.
    enum ProgramOutput: Equatable, Sendable {
        /// Show started; no Program frame has reached the output yet.
        case waiting
        case routed
        /// Development rehearsal destination: accepted, sent nowhere.
        case rehearsal
        /// Repeating the last good rendered frame; standby in `standbyIn`
        /// seconds, or nil when no standby timer applies (single-camera HOLD).
        case holding(standbyIn: Int?)
        /// Sending safe black at the show standard; Program source missing.
        case standby
        /// Operator pressed Reconnect on Program; still sending standby.
        case reconnecting
    }

    /// Everything Take eligibility depends on, as the router last committed
    /// it. Mirrors the TAKE card's checks; TakeAvailability maps this to copy.
    struct TakeInputs: Equatable, Sendable {
        /// Preview channel's source is present (not unplugged).
        var sourcePresent: Bool
        /// Admission says Preview can run alongside Program at the standard.
        var supportedAtStandard: Bool
        /// A prepared render completed within the freshness window.
        var hasFreshRender: Bool
        /// That render matches the current source generation.
        var matchesSourceGeneration: Bool
        /// That render matches the current discrete shot revision.
        var matchesShotRevision: Bool
        /// Crop and output geometry are legal.
        var legalGeometry: Bool
        /// The candidate is a repeated/held frame (never takeable).
        var isHeldFrame: Bool
        /// A Take click was admitted and has not committed or expired yet.
        var takePending: Bool

        static let ready = TakeInputs(
            sourcePresent: true, supportedAtStandard: true, hasFreshRender: true,
            matchesSourceGeneration: true, matchesShotRevision: true,
            legalGeometry: true, isHeldFrame: false, takePending: false)
    }

    /// Which pane view the control-target pane shows.
    enum PaneView: Equatable, Sendable {
        /// The rendered shot (default).
        case shot
        /// The wide source with the legal crop dashed and detection boxes.
        case source
    }

    /// Channel and role every console control acts on.
    struct ControlTarget: Equatable, Sendable {
        var channel: ChannelID
        var role: Role
    }

    /// Always four slots, in ChannelID order.
    var slots: [Slot]
    var programChannel: ChannelID
    /// nil with a single running input ("No Preview camera").
    var previewChannel: ChannelID?
    var programOutput: ProgramOutput
    var take: TakeInputs
    var editLive: Bool
    var showStandard: ShowStandard
    var paneView: PaneView
    /// Latest operator/system note for the input row's label, if any.
    var operatorNote: String?

    /// Preview by default; Program only while Edit Live is on (or with no
    /// Preview camera, where Program is the only thing to control).
    var controlTarget: ControlTarget {
        if editLive || previewChannel == nil {
            return ControlTarget(channel: programChannel, role: .program)
        }
        return ControlTarget(channel: previewChannel!, role: .preview)
    }

    func slot(_ channel: ChannelID) -> Slot {
        slots.first { $0.channel == channel } ?? Slot(channel: channel, input: nil)
    }

    func input(_ channel: ChannelID?) -> Slot.Input? {
        guard let channel else { return nil }
        return slot(channel).input
    }

    var assignedInputCount: Int { slots.filter(\.isAssigned).count }
}
