/// A frame-independent description of the current lock and its available
/// operator action. The composer supplies evidence; this type makes no
/// changes to tracking, identity, or program geometry.
nonisolated struct RecoveryState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case inactive, acquiring, tracking, hold, wideWaiting
    }

    enum Action: Equatable, Sendable {
        case none, unlock, resume, pickSubject
    }

    let phase: Phase
    let galleryReady: Bool
    let trackingOwnsControl: Bool

    var canResume: Bool {
        galleryReady && (phase == .tracking || phase == .hold || phase == .wideWaiting)
    }

    var isRecovering: Bool { phase == .hold || phase == .wideWaiting }
    var allowsDirectSelection: Bool { isRecovering }

    var statusLabel: String {
        switch phase {
        case .inactive: "Pick subject"
        case .acquiring: "Acquiring…"
        case .tracking: trackingOwnsControl ? "Locked" : (canResume ? "Resume" : "Pick subject")
        case .hold: trackingOwnsControl ? "Recovering" : (canResume ? "Resume" : "Pick subject")
        case .wideWaiting: trackingOwnsControl ? "Searching" : (canResume ? "Resume" : "Pick subject")
        }
    }

    var action: Action {
        if canResume && !trackingOwnsControl { return .resume }
        switch phase {
        case .inactive, .acquiring: return .none
        case .tracking: return trackingOwnsControl ? .unlock : .pickSubject
        case .hold, .wideWaiting:
            if trackingOwnsControl && canResume { return .none }
            return canResume ? .resume : .pickSubject
        }
    }
}
