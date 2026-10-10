import Foundation

/// Isolated review candidate. No runtime grant is restored from preferences.
nonisolated struct DirectorAuthority: Equatable, Sendable {
    enum ReviewPolicy: Sendable { case conservative }
    enum Level: Equatable, Sendable { case off, suggest, autoPrepare, autoDirect }
    enum Action: Sendable { case propose, prepare, take }
    struct Prerequisites: Equatable, Sendable {
        let nominationsCurrent: Bool
        let previewAvailable: Bool
        let sourcesHealthy: Bool
        let outputHealthy: Bool
        let admissionCurrent: Bool
        var satisfied: Bool {
            nominationsCurrent && previewAvailable && sourcesHealthy && outputHealthy && admissionCurrent
        }
    }
    enum Event: Equatable, Sendable {
        case enable(Level), disable, pause, resume, pin(ChannelID), unpin
        case manualCommand, editLive(Bool), operatorTake, sourceLoss(ChannelID), stopShow, restart
        case navigation, cosmeticEdit, evidenceAvailable(Bool), identityLost(ChannelID)
        case sourceRebound(ChannelID), outputFault, admissionLost, healthRestored
        case policyChanged, nominationChanged
    }
    /// Retires future Director effects only, never already admitted R2 tracking.
    enum Cancellation: Hashable, Sendable { case proposal, prepare, take }
    enum Refusal: Equatable, Sendable { case autoDirectUnqualified, prerequisites, paused, exhausted }
    struct Transition: Equatable, Sendable {
        let state: DirectorAuthority
        let cancellations: Set<Cancellation>
        let refusal: Refusal?
    }
    static let autoTakeQualified = false
    private(set) var level: Level = .off
    private(set) var paused = false
    private(set) var pinnedShot: ChannelID?
    private(set) var editLive = false
    private(set) var epoch: UInt64
    private(set) var exhausted = false
    private(set) var running = true
    private(set) var healthy = true
    private(set) var evidenceAvailable = true

    // No default policy. initialEpoch enables the exhaustion boundary test.
    init(reviewPolicy: ReviewPolicy, initialEpoch: UInt64 = 0) { epoch = initialEpoch }
    var mayPropose: Bool { !exhausted && running && healthy && level != .off && !paused && !editLive && pinnedShot == nil }
    var mayPrepare: Bool { mayPropose && evidenceAvailable && level == .autoPrepare }
    var mayTake: Bool { false }
    func authorizes(_ token: UInt64, action: Action) -> Bool {
        guard token == epoch else { return false }
        switch action {
        case .propose: return mayPropose
        case .prepare: return mayPrepare
        case .take: return mayTake
        }
    }
    private mutating func retire() {
        guard epoch < UInt64.max else { exhausted = true; level = .off; paused = true; return }
        epoch += 1
    }
    @discardableResult mutating func apply(_ event: Event, prerequisites: Prerequisites? = nil) -> Transition {
        let all: Set<Cancellation> = [.proposal, .prepare, .take]
        var cancellations: Set<Cancellation> = []
        var refusal: Refusal?
        switch event {
        case .enable(.autoDirect): refusal = .autoDirectUnqualified
        case .enable(.off), .disable, .stopShow:
            retire(); cancellations = all
            level = .off; paused = false; pinnedShot = nil; editLive = false
            if event == .stopShow { running = false }
        case .enable, .resume:
            if exhausted { refusal = .exhausted }
            else if !running || !healthy || editLive || pinnedShot != nil || prerequisites?.satisfied != true {
                refusal = .prerequisites
            } else if case .enable = event, paused { refusal = .paused }
            else if event == .resume && level == .off { refusal = .prerequisites }
            else {
                retire(); cancellations = all
                if !exhausted {
                    if case .enable(let requested) = event { level = requested }
                    paused = false
                }
            }
        case .restart:
            retire(); cancellations = all; running = true; level = .off
            paused = false; pinnedShot = nil; editLive = false
        case .navigation, .cosmeticEdit: break
        case .evidenceAvailable(let available): evidenceAvailable = available
        case .healthRestored: healthy = true // Never clears Pause.
        case .editLive(false): editLive = false
        case .unpin: pinnedShot = nil // Never clears Pause.
        case .pin(let shot):
            retire(); cancellations = all; pinnedShot = shot; paused = true
        case .editLive(true):
            retire(); cancellations = all; editLive = true; paused = true
        case .sourceLoss, .sourceRebound, .outputFault, .admissionLost:
            retire(); cancellations = all; healthy = false; paused = true
        case .pause, .manualCommand, .operatorTake, .identityLost, .policyChanged, .nominationChanged:
            retire(); cancellations = all; paused = true
        }
        return Transition(state: self, cancellations: cancellations, refusal: refusal)
    }
}
