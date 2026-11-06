//
//  OperatorPillCommands.swift
//  CinematicCoreMacOS
//
//  Track A (UX J3, J4, J12): what the single-camera pill publishes to the
//  Session and Shot menus, why a pill control is unavailable, and what the
//  pill's Stop says it stops. The rules are plain values so tests can pin
//  them without a camera.
//

import AppKit
import SwiftUI

/// What the pill can do right now, read from the channel it was drawn for.
nonisolated struct PillCommandState: Equatable, Sendable {
    var isRunning: Bool
    var isWebcam: Bool
    var isDiscovering: Bool
    var detectEnabled: Bool
    var canPushIn: Bool
    var canPullOut: Bool

    /// The commands the live Single Cam or Webcam view publishes. Anything
    /// missing is withdrawn, so its menu item is disabled and its bare key
    /// passes through. Escape is Cancel Detect only while Detect is waiting
    /// for a click; Webcam has no Full Body or Waist Up.
    var published: Set<AlfieCommandCatalog.ID> {
        guard isRunning else { return [] }
        var ids: Set<AlfieCommandCatalog.ID> = [.stopSession, .wide]
        if isDiscovering { ids.insert(.cancel) } else if detectEnabled { ids.insert(.detect) }
        if !isWebcam { ids.formUnion([.fullBody, .waistUp]) }
        if canPushIn { ids.insert(.pushIn) }
        if canPullOut { ids.insert(.pullOut) }
        return ids
    }
}

/// Why a pill control is unavailable. The pill shows each as a help tag and
/// VoiceOver hint (`alfieUnavailableReason`); the disabled floor and the
/// words carry the state, never opacity.
enum PillUnavailableReason {
    static let notRunning = "Start the session first."

    static func detect(isRunning: Bool, operatorGeometry: Bool, isLocked: Bool,
                       canReacquire: Bool, isAcquiring: Bool) -> String? {
        if !isRunning { return notRunning }
        if operatorGeometry { return "Turn off Manual or Auto Pan to detect." }
        if isAcquiring { return "Alfie is learning the subject." }
        if isLocked && !canReacquire { return "Unlock the subject first." }
        return nil
    }

    static func crop(isRunning: Bool, isOn: Bool, hasLock: Bool) -> String? {
        if !isRunning { return notRunning }
        if isOn { return "Crop is on. Choose Manual, Auto Pan or Return to Wide to leave it." }
        if !hasLock { return "Lock a subject first." }
        return nil
    }

    static func mode(_ title: String, isRunning: Bool, isOn: Bool) -> String? {
        if !isRunning { return notRunning }
        if isOn { return "\(title) is on. Choose another mode to leave it." }
        return nil
    }

    static func zoom(_ direction: OperatorCommand.ZoomDirection, isRunning: Bool, canBegin: Bool,
                     movingDirection: OperatorCommand.ZoomDirection?, isZoomLimited: Bool) -> String? {
        if !isRunning { return notRunning }
        if canBegin { return nil }
        if movingDirection == direction {
            return direction == .pushIn ? "Already pushing in." : "Already pulling out."
        }
        if direction == .pushIn && isZoomLimited { return "Zoom limited by the source." }
        return direction == .pushIn ? "Already at the tightest shot." : "Already at the widest shot."
    }
}

/// `stop.md`'s route table: what Stop says it stops. Track A uses the
/// confirmation; Track B's Multi Cam header can use the helper line too.
nonisolated enum StopRouteCopy {
    static func confirmation(for route: ProgramOutputManager.Route?) -> String {
        switch route {
        case .virtualCamera: return "This stops the cameras and Program output to Alfie camera."
        // A Direct destination's identity is never inferred from the cable.
        case .display: return "This stops the cameras and Direct Program output."
        case .rehearsal: return "This stops the rehearsal cameras. No external output is active."
        case nil: return "This stops the cameras and Program output."
        }
    }

    static func helper(for route: ProgramOutputManager.Route?) -> String {
        switch route {
        case .virtualCamera: return "Stops Program output to Alfie camera."
        case .display: return "Stops Program on Direct output."
        case .rehearsal: return "Stops the rehearsal cameras."
        case nil: return "Stops the cameras and Program output."
        }
    }
}

/// The accessible result of a menu or key command (keyboard-map.md). A
/// refused command announces its reason once and never claims success.
@MainActor
enum PillCommandAnnouncement {
    static func say(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    static func report(_ result: CommandResult, success: String) {
        switch result {
        case .accepted, .completed: say(success)
        case .rejected(let reason): say(reason)
        }
    }
}

/// Applies the publisher only to the single-camera pill.
struct SingleCameraCommands: ViewModifier {
    let isPublishing: Bool
    let state: PillCommandState
    let sink: PillCommandSink

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPublishing {
            content.modifier(OperatorPillCommandPublisher(state: state, sink: sink))
        } else {
            content
        }
    }
}

/// Publishes the pill's commands to the active scene. Only the single-camera
/// pill does this; in the Multiview console the pill's channel can change
/// under it, and that console's commands belong to Track B.
struct OperatorPillCommandPublisher: ViewModifier {
    let state: PillCommandState
    let sink: PillCommandSink

    func body(content: Content) -> some View {
        let ids = state.published
        let wide: OperatorCommand.Preset = state.isWebcam ? .webcam(.wide) : .stage(.wide)
        let detect = action(.detect, in: ids, "Detecting people.", .detect)
        // The menu Stop stays immediate (stop.md); only the on-screen
        // control asks for a hold or a confirmation.
        let stop = action(.stopSession, in: ids, "Stopping session.", .stopSession)
        let cancel = action(.cancel, in: ids, "Detection cancelled.", .cancelDetect, title: "Cancel Detect")
        let wideShot = action(.wide, in: ids, "Wide selected.", .selectPreset(wide))
        let fullBody = action(.fullBody, in: ids, "Full Body selected.", .selectPreset(.stage(.fullBody)))
        let waistUp = action(.waistUp, in: ids, "Waist Up selected.", .selectPreset(.stage(.waistUp)))
        let pushIn = action(.pushIn, in: ids, "Push In applied.", .beginZoom(.pushIn))
        let pullOut = action(.pullOut, in: ids, "Pull Out applied.", .beginZoom(.pullOut))
        return content
            .focusedSceneValue(\.alfieDetect, detect)
            .focusedSceneValue(\.alfieCancel, cancel)
            .focusedSceneValue(\.alfieStopSession, stop)
            .focusedSceneValue(\.alfieWide, wideShot)
            .focusedSceneValue(\.alfieFullBody, fullBody)
            .focusedSceneValue(\.alfieWaistUp, waistUp)
            .focusedSceneValue(\.alfiePushIn, pushIn)
            .focusedSceneValue(\.alfiePullOut, pullOut)
    }

    /// The command when it's published, otherwise nil so it's withdrawn.
    private func action(_ id: AlfieCommandCatalog.ID, in ids: Set<AlfieCommandCatalog.ID>, _ success: String,
                        _ command: OperatorCommand.Action, title: String? = nil) -> AlfieCommandAction? {
        guard ids.contains(id) else { return nil }
        let sink = self.sink
        return AlfieCommandAction(title: title) {
            PillCommandAnnouncement.report(sink.send(command), success: success)
        }
    }
}
