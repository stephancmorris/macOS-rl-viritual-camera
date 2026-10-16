import Foundation

/// Isolated review candidate. No runtime grant is restored from preferences.
nonisolated struct DirectorAuthority: Equatable, Sendable {
    enum ReviewPolicy: Sendable { case conservative }
    /// Off (Manual), Suggest (shadow: proposes, never acts), Assist (prepares
    /// Preview), Auto and Backup (may issue one-shot Take permits when qualified).
    enum Level: Equatable, Hashable, Sendable { case off, suggest, assist, auto, backup }
    enum Action: Sendable { case propose, prepare, take }
    struct Prerequisites: Equatable, Sendable {
        let nominationsCurrent: Bool
        let previewAvailable: Bool
        let sourcesHealthy: Bool
        let outputHealthy: Bool
        let admissionCurrent: Bool
        /// Levels with a current sign-off on this rig (C16 / B-06). Empty by
        /// default: nothing beyond Suggest can be enabled without a record.
        var qualifiedLevels: Set<Level> = []
        var satisfied: Bool {
            nominationsCurrent && previewAvailable && sourcesHealthy && outputHealthy && admissionCurrent
        }
    }
    enum Event: Equatable, Sendable {
        case enable(Level), disable, pause, resume, pin(ChannelID), unpin
        case manualCommand, editLive(Bool), operatorTake, sourceLoss(ChannelID), stopShow, restart
        /// The operator gives control back (A1). Same contract as `resume`.
        case handToAlfie
        case navigation, cosmeticEdit, evidenceAvailable(Bool), identityLost(ChannelID)
        case sourceRebound(ChannelID), outputFault, admissionLost, healthRestored
        case policyChanged, nominationChanged
    }
    /// Retires future Director effects only, never already admitted R2 tracking.
    enum Cancellation: Hashable, Sendable { case proposal, prepare, take }
    enum Refusal: Equatable, Sendable { case notQualified, prerequisites, paused, exhausted }
    struct Transition: Equatable, Sendable {
        let state: DirectorAuthority
        let cancellations: Set<Cancellation>
        let refusal: Refusal?
    }
    struct TakeTiming: Equatable, Sendable {
        let now: TimeInterval
        let minimumShotDuration: TimeInterval
    }
    enum NudgeHold: Equatable, Sendable { case none, until(TimeInterval), unavailable }
    private(set) var nudgeHold: NudgeHold = .none
    private(set) var lastTakeTime: TimeInterval?
    private var qualifiedGrant = false
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
    var mayPrepare: Bool { mayPropose && evidenceAvailable && Self.prepares(level) }
    /// Capability to issue a permit, not permission to dispatch a Take.
    var mayTake: Bool { mayPrepare && qualifiedGrant && Self.cuts(level) && nudgeHold == .none }
    static func cuts(_ level: Level) -> Bool { level == .auto || level == .backup }
    func mayIssueTake(at now: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, lastTakeTime.map({ now >= $0 }) ?? true,
              mayPrepare, qualifiedGrant, Self.cuts(level) else { return false }
        switch nudgeHold {
        case .none: return true
        case .until(let deadline): return now >= deadline
        case .unavailable: return false
        }
    }
    static func prepares(_ level: Level) -> Bool { level == .assist || level == .auto || level == .backup }
    static func needsQualification(_ level: Level) -> Bool { prepares(level) }

    func authorizes(_ token: UInt64, action: Action) -> Bool {
        guard token == epoch else { return false }
        switch action {
        case .propose: return mayPropose
        case .prepare: return mayPrepare
        case .take: return false // Bare epochs never authorize a cut; consume a TakePermit.
        }
    }
    private mutating func retire() {
        guard epoch < UInt64.max else { exhausted = true; level = .off; paused = true; return }
        epoch += 1
    }
    @discardableResult mutating func apply(_ event: Event, prerequisites: Prerequisites? = nil, takeTiming: TakeTiming? = nil) -> Transition {
        let all: Set<Cancellation> = [.proposal, .prepare, .take]
        var cancellations: Set<Cancellation> = []
        var refusal: Refusal?
        switch event {
        case .enable(let requested) where Self.needsQualification(requested) && prerequisites != nil
                && prerequisites?.qualifiedLevels.contains(requested) != true:
            // Refused, never substituted: level and epoch are unchanged.
            refusal = exhausted ? .exhausted : .notQualified
        case .enable(.off), .disable, .stopShow:
            retire(); cancellations = all
            level = .off; paused = false; pinnedShot = nil; editLive = false
            qualifiedGrant = false; nudgeHold = .none
            if event == .stopShow { running = false }
        case .enable, .resume, .handToAlfie:
            if exhausted { refusal = .exhausted }
            else if !running || !healthy || editLive || pinnedShot != nil || prerequisites?.satisfied != true {
                refusal = .prerequisites
            } else if case .enable = event, paused { refusal = .paused }
            else if (event == .resume || event == .handToAlfie) && level == .off { refusal = .prerequisites }
            else if (event == .resume || event == .handToAlfie) && Self.needsQualification(level)
                        && prerequisites?.qualifiedLevels.contains(level) != true {
                // The rig's sign-off lapsed (e.g. setup changed): never resume unqualified.
                refusal = .notQualified
            }
            else {
                retire(); cancellations = all
                if !exhausted {
                    if case .enable(let requested) = event { level = requested }
                    paused = false; nudgeHold = .none
                    qualifiedGrant = prerequisites?.qualifiedLevels.contains(level) == true
                }
            }
        case .restart:
            retire(); cancellations = all; running = true; level = .off
            paused = false; pinnedShot = nil; editLive = false
            qualifiedGrant = false; nudgeHold = .none; lastTakeTime = nil
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
        case .operatorTake where Self.cuts(level):
            // N1: the operator cut is never blocked. Retire all prior work,
            // keep authority active and inhibit Director cuts for the full dwell.
            retire(); cancellations = all
            guard let timing = takeTiming, timing.now.isFinite, timing.now >= 0,
                  timing.minimumShotDuration.isFinite, timing.minimumShotDuration >= 0,
                  lastTakeTime.map({ timing.now >= $0 }) ?? true,
                  (timing.now + timing.minimumShotDuration).isFinite else {
                nudgeHold = .unavailable
                return Transition(state: self, cancellations: cancellations, refusal: nil)
            }
            lastTakeTime = timing.now
            nudgeHold = .until(timing.now + timing.minimumShotDuration)
        case .operatorTake where level == .suggest || level == .assist:
            // N1: in Assist (and shadow) a Take is the expected rhythm, not an
            // override. Retire all work and start fresh on the new Preview.
            retire(); cancellations = all
        case .pause, .manualCommand, .operatorTake, .identityLost, .policyChanged, .nominationChanged:
            retire(); cancellations = all; paused = true
        }
        return Transition(state: self, cancellations: cancellations, refusal: refusal)
    }
}
