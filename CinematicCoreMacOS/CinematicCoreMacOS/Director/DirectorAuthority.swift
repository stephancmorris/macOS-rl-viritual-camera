import Foundation

/// Authority for proposals; it has no reference to routing or the camera pipeline.
nonisolated struct DirectorAuthority: Equatable, Sendable {
    enum Level: Equatable, Sendable { case off, suggest, autoPrepare, autoDirect }
    enum Event: Equatable, Sendable {
        case enable(Level), disable, pause, resume, pin(ChannelID), unpin
        case manualCommand, editLive(Bool), operatorTake, sourceLoss(ChannelID), stopShow
    }
    enum Cancellation: Hashable, Sendable { case proposal, prepare, take }
    struct Transition: Equatable, Sendable {
        let state: DirectorAuthority
        let cancellations: Set<Cancellation>
    }

    /// Auto Take requires a separate qualification and is deliberately unavailable.
    static let autoTakeQualified = false
    private(set) var level: Level = .off
    private(set) var paused = false
    private(set) var pinnedShot: ChannelID?
    private(set) var editLive = false
    private(set) var epoch: UInt64 = 0

    var mayPropose: Bool { level != .off && !paused && !editLive && pinnedShot == nil }
    var mayPrepare: Bool { mayPropose && (level == .autoPrepare || level == .autoDirect) }
    var mayTake: Bool { mayPropose && level == .autoDirect && Self.autoTakeQualified }

    func admits(_ token: UInt64, forTake: Bool = false) -> Bool {
        token == epoch && (forTake ? mayTake : mayPropose)
    }

    mutating func apply(_ event: Event) -> Transition {
        let all: Set<Cancellation> = [.proposal, .prepare, .take]
        var cancellations: Set<Cancellation> = []
        switch event {
        case .enable(let requested):
            let next: Level = requested == .autoDirect && !Self.autoTakeQualified ? .autoPrepare : requested
            if next != level { level = next; paused = false; epoch &+= 1; cancellations = all }
        case .disable, .stopShow:
            level = .off; paused = false; pinnedShot = nil; editLive = false
            epoch &+= 1; cancellations = all
        case .pause:
            if !paused { paused = true; epoch &+= 1; cancellations = all }
        case .resume:
            if paused { paused = false; epoch &+= 1; cancellations = all }
        case .pin(let shot):
            pinnedShot = shot; epoch &+= 1; cancellations = all
        case .unpin:
            if pinnedShot != nil { pinnedShot = nil; epoch &+= 1; cancellations = all }
        case .manualCommand, .operatorTake:
            // Revoke before the operator action can be delivered.
            epoch &+= 1; cancellations = all
        case .editLive(let enabled):
            if editLive != enabled { editLive = enabled; epoch &+= 1; cancellations = all }
        case .sourceLoss:
            epoch &+= 1; cancellations = all
        }
        return Transition(state: self, cancellations: cancellations)
    }

    func section(proposal: ChannelID? = nil, reason: String? = nil) -> NextShotStatus.DirectorSection {
        let mode: NextShotStatus.DirectorSection.Mode = level == .off ? .off :
            level == .suggest ? .suggest : .auto
        let authority: NextShotStatus.DirectorSection.Authority = mayTake ? .directorMayTake :
            mayPrepare ? .directorMayCue : .operatorOnly
        return .init(mode: mode, proposal: mayPropose ? proposal : nil,
                     reason: reason, countdown: nil, authority: authority)
    }
}
