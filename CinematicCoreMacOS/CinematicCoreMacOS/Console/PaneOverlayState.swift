//
//  PaneOverlayState.swift
//  CinematicCoreMacOS
//
//  Every state a Preview or Program pane can overlay on its picture, derived
//  from one ConsoleSnapshot. Copy is exact from the CONSOLE card; the show
//  standard and rate always come from the active ShowStandard.
//

import Foundation

nonisolated enum PaneOverlayState: Equatable, Sendable {
    case none
    /// Single running input: the Preview pane is empty, never a second shot
    /// of the Program channel.
    case noPreviewCamera
    /// Dimmed, non-blocking.
    case previewPreparing(ChannelID)
    case previewUnsupported(ChannelID, ShowStandard)
    case previewMissing(ChannelID)
    case programHold(standbyIn: Int?)
    case programStandby(program: ChannelID, alternate: ChannelID?, standard: ShowStandard)

    var title: String? {
        switch self {
        case .none:
            return nil
        case .noPreviewCamera:
            return "No Preview camera"
        case .previewPreparing(let channel):
            return "Preparing \(channel.cameraLabel) · Take unavailable"
        case .previewUnsupported(_, let standard):
            return "Unsupported at \(standard.title)"
        case .previewMissing(let channel):
            return "\(channel.cameraLabel) source missing"
        case .programHold(let seconds):
            guard let seconds else { return "Hold · last good frame" }
            return "Hold · last good frame · standby in \(seconds) s"
        case .programStandby:
            return "Standby · Program source missing"
        }
    }

    var detail: String? {
        switch self {
        case .previewUnsupported(_, let standard):
            return "This Mac could not keep this camera at \(Self.rateText(standard)) fps alongside Program. "
                + "Alfie will not lower the output rate. Program keeps running."
        case .previewMissing:
            return "Program is unaffected."
        case .programStandby(let program, let alternate, let standard):
            let lead = "\(program.cameraLabel) disconnected. Alfie is sending black at \(standard.title)"
            guard let alternate else { return lead + "." }
            return lead + " and will not switch to \(alternate.cameraLabel) on its own."
        default:
            return nil
        }
    }

    /// Channel the overlay's Reconnect button acts on, if it has one.
    var reconnectChannel: ChannelID? {
        switch self {
        case .previewMissing(let channel): return channel
        case .programStandby(let program, _, _): return program
        default: return nil
        }
    }

    var reconnectTitle: String? {
        reconnectChannel.map { "Reconnect \($0.cameraLabel)" }
    }

    /// Blocking overlays cover the picture with a scrim; Preparing only dims.
    var isBlocking: Bool {
        switch self {
        case .none, .previewPreparing, .programHold: return false
        default: return true
        }
    }

    static func preview(for snapshot: ConsoleSnapshot) -> PaneOverlayState {
        guard let preview = snapshot.previewChannel else { return .noPreviewCamera }
        switch TakeAvailability.evaluate(snapshot).reason {
        case .sourceMissing: return .previewMissing(preview)
        case .unsupported: return .previewUnsupported(preview, snapshot.showStandard)
        case .preparing: return .previewPreparing(preview)
        case .noPreviewCamera: return .noPreviewCamera
        case nil: return .none
        }
    }

    static func program(for snapshot: ConsoleSnapshot) -> PaneOverlayState {
        switch snapshot.programOutput {
        case .waiting, .routed:
            return .none
        case .holding(let seconds):
            return .programHold(standbyIn: seconds)
        case .standby, .reconnecting:
            return .programStandby(
                program: snapshot.programChannel,
                alternate: snapshot.previewChannel,
                standard: snapshot.showStandard)
        }
    }

    /// Program status, top-right of the Program pane. Never "On air": Alfie
    /// cannot know ATEM tally.
    static func programStatus(for output: ConsoleSnapshot.ProgramOutput) -> String {
        switch output {
        case .waiting: return "Waiting for first frame"
        case .routed: return "Routed"
        case .holding: return "Holding last good frame"
        case .standby: return "Standby · source missing"
        case .reconnecting: return "Reconnecting · standby"
        }
    }

    /// "50", "59.94", "60".
    static func rateText(_ standard: ShowStandard) -> String {
        let rate = standard.frameRate
        if rate.rounded() == rate { return String(Int(rate)) }
        return String(format: "%.2f", rate)
    }
}
