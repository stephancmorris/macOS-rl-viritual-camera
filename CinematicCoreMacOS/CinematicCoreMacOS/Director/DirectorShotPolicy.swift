import Foundation

nonisolated struct DirectorShotPolicy {
    struct Parameters: Equatable, Sendable {
        let minimumShotDuration: TimeInterval
        let maximumShotDuration: TimeInterval
        let wideCadence: TimeInterval
        let repetitionWindow: TimeInterval
        let maximumMovement: Double
        let cutOnMotionAllowed: Bool

        // Historical unapproved fixture parameters. Study values must be explicitly supplied.
        static let proposed = Parameters(minimumShotDuration: 8, maximumShotDuration: 35,
            wideCadence: 90, repetitionWindow: 20, maximumMovement: 0.1,
            cutOnMotionAllowed: false)

        var isValid: Bool {
            minimumShotDuration.isFinite && maximumShotDuration.isFinite &&
            wideCadence.isFinite && repetitionWindow.isFinite && maximumMovement.isFinite &&
            minimumShotDuration >= 0 && maximumShotDuration >= minimumShotDuration &&
            wideCadence > 0 && repetitionWindow >= 0 && maximumMovement >= 0
        }
    }
    struct Candidate: Equatable, Sendable {
        let channel: ChannelID
        let shot: DirectorShot
        let subjectConfidence: Double
        let movement: Double
        let isWide: Bool
    }
    struct History: Equatable, Sendable {
        let shot: DirectorShot
        let endedAt: TimeInterval
    }
    struct Timeline: Sendable {
        let programShot: DirectorShot
        let programStartedAt: TimeInterval
        let lastWideAt: TimeInterval
        let history: [History]
        let candidates: [Candidate]
        let now: TimeInterval
    }
    enum Abstention: Equatable, Sendable {
        case invalidInput, minimumDuration, noEligibleCandidate, repetition, movement, noPreview
    }
    enum Decision: Equatable, Sendable {
        case chosen(Candidate, String), abstain(Abstention)
    }

    /// Future recommendation timing only. This grants no permission to Take.
    static func recommendationDue(_ timeline: Timeline, parameters: Parameters) -> Bool {
        parameters.isValid && timeline.now.isFinite && timeline.programStartedAt.isFinite &&
        timeline.now >= timeline.programStartedAt &&
        timeline.now - timeline.programStartedAt >= parameters.minimumShotDuration
    }

    static func choosePreparation(_ timeline: Timeline, preview: ChannelID,
                       parameters p: Parameters) -> Decision {
        guard p.isValid, timeline.now.isFinite, timeline.programStartedAt.isFinite,
              timeline.lastWideAt.isFinite, timeline.now >= timeline.programStartedAt,
              timeline.now >= timeline.lastWideAt,
              timeline.history.allSatisfy({ $0.endedAt.isFinite && $0.endedAt <= timeline.now }) else {
            return .abstain(.invalidInput)
        }
        let dueWide = timeline.now - timeline.lastWideAt >= p.wideCadence
        let eligible = timeline.candidates.filter { $0.channel == preview && $0.shot != timeline.programShot &&
            $0.subjectConfidence.isFinite && $0.subjectConfidence >= 0 && $0.subjectConfidence <= 1 &&
            $0.movement.isFinite && $0.movement >= 0 }
        guard !eligible.isEmpty else { return .abstain(.noPreview) }
        let noRepeat = eligible.filter { candidate in
            !timeline.history.contains { $0.shot == candidate.shot && timeline.now - $0.endedAt < p.repetitionWindow }
        }
        guard !noRepeat.isEmpty else { return .abstain(.repetition) }
        // A total order makes the selection independent of candidate input order.
        let sorted = noRepeat.sorted {
            if dueWide && $0.isWide != $1.isWide { return $0.isWide }
            if $0.subjectConfidence != $1.subjectConfidence { return $0.subjectConfidence > $1.subjectConfidence }
            if $0.shot.order != $1.shot.order { return $0.shot.order < $1.shot.order }
            if $0.isWide != $1.isWide { return $0.isWide }
            return $0.movement < $1.movement
        }
        guard let selected = sorted.first else { return .abstain(.noEligibleCandidate) }
        let reason = dueWide && selected.isWide ? "advisory wide reminder" :
            timeline.now - timeline.programStartedAt >= p.maximumShotDuration ? "advisory maximum dwell" : "subject evidence"
        return .chosen(selected, reason)
    }
}
