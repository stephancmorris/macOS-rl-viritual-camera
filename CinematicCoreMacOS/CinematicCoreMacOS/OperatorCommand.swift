import Foundation
import CoreGraphics
import QuartzCore

/// An address, not a Channel implementation. Camera commands name a stable
/// ChannelID bound when the gesture starts; delayed continuations keep that
/// target and never look up "the currently selected camera" (CHANNEL-CMD).
struct OperatorCommand {
    enum Target: Equatable {
        case channel(ChannelID)
        case session

        /// The single-camera app's only channel.
        static let cameraA = Target.channel(.a)
    }
    enum Origin: Equatable { case operatorUI, safety, automaticRecovery }
    /// Shared with the nonisolated Director logic (Stage 3), so it is a
    /// plain value: hashable, sendable, no actor isolation.
    nonisolated enum Preset: Hashable, Sendable {
        case stage(ShotComposer.Config.ShotPreset), webcam(ShotComposer.Config.WebcamPreset)
    }
    enum ZoomDirection: CGFloat { case pullOut = -1, pushIn = 1 }
    enum Action {
        case detect, cancelDetect
        case selectSubject(CGPoint, retarget: Bool = false)
        case unlock, resumeTracking, setMode(CameraManager.OperationMode), selectPreset(Preset)
        case beginZoom(ZoomDirection)
        case endZoom
        case moveManualCenter(CGPoint)
        case returnToWide, startSession, stopSession
    }

    let target: Target
    let origin: Origin
    let id: UUID
    let epoch: UInt64
    let expiry: TimeInterval
    let action: Action

    init(target: Target = .cameraA, origin: Origin = .operatorUI,
         id: UUID = UUID(), epoch: UInt64, expiry: TimeInterval,
         action: Action) {
        self.target = target
        self.origin = origin
        self.id = id
        self.epoch = epoch
        self.expiry = expiry
        self.action = action
    }
}

enum CommandResult: Equatable {
    case accepted, completed, rejected(String)
    var wasAccepted: Bool {
        if case .rejected = self { return false }
        return true
    }
}

/// Synchronous admission and ownership, shared by pill and recovery. The
/// manager performs the effects; no second camera pipeline lives here.
@MainActor
final class CommandDispatcher {
    /// The channel this dispatcher admits camera commands for.
    let channelID: ChannelID
    private(set) var epoch: UInt64 = 0
    private(set) var trackingOwnsControl = false
    private var recentIDs: [UUID] = []

    init(channelID: ChannelID = .a) {
        self.channelID = channelID
    }

    func rejection(for command: OperatorCommand, now: TimeInterval) -> String? {
        guard command.epoch == epoch else { return "Superseded command" }
        guard command.expiry.isFinite, now <= command.expiry else { return "Expired command" }
        guard !recentIDs.contains(command.id) else { return "Duplicate command" }
        switch command.action {
        case .startSession, .stopSession:
            guard command.target == .session else { return "Wrong command target" }
        default:
            guard command.target == .channel(channelID) else { return "Wrong command target" }
        }
        if command.origin == .automaticRecovery { return "Recovery must retain tracking ownership" }
        return nil
    }

    func accept(_ command: OperatorCommand) {
        recentIDs.append(command.id)
        if recentIDs.count > 64 { recentIDs.removeFirst() }
        epoch &+= 1
    }

    func setTrackingOwnership(_ owns: Bool) { trackingOwnsControl = owns }

    func invalidateMotion() {
        epoch &+= 1
    }

    /// Recovery is admitted only under the authority granted by subject
    /// selection / Track. Manual, Pan and explicit Wide revoke that grant.
    func admitRecovery(_ outcome: ShotComposer.TickOutcome) -> Bool {
        guard trackingOwnsControl else { return false }
        if case .noChange = outcome { return false }
        invalidateMotion()
        return true
    }
}
