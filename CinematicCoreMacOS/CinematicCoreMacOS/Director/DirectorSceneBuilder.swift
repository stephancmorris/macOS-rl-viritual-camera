import Foundation

/// Decision core, stage 2: builds one `DirectorScene` per Director tick.
/// Owned by `DirectorController`; runs on the main thread four times a second
/// and reads plain values only. It never touches the frame path, a camera
/// command or Program.
///
/// The timing facts come from what the builder itself observes on Program,
/// never from a guess:
/// - `programStartedAt` restarts whenever Program's (input, shot) pair changes,
///   for any reason. It starts when the builder begins (attach time).
/// - `lastWideAt` is the tick time of any tick where Program's shot is wide.
///   It also starts at attach time.
/// - `history` gains (previous shot, ended now) each time the pair changes.
///
/// A change is seen at the tick after it happens, so these times are late by
/// at most one tick interval.
final class DirectorSceneBuilder {
    static let historyLimit = 32

    private struct ProgramPair: Equatable {
        let channel: ChannelID
        let shot: DirectorShot
    }

    private weak var show: ShowCoordinator?
    private var startedAt: TimeInterval?
    private var pair: ProgramPair?
    private var programStartedAt: TimeInterval?
    private var lastWideAt: TimeInterval?
    private var history: [DirectorShotPolicy.History] = []

    init(show: ShowCoordinator?) { self.show = show }

    /// Restart the timing facts from `now`. Called on attach. A bad clock
    /// leaves them unset; the first good build starts them instead.
    func begin(at now: TimeInterval) {
        pair = nil; programStartedAt = nil; lastWideAt = nil; history = []
        startedAt = now.isFinite && now >= 0 ? now : nil
    }

    /// One scene, or nil when there is no show, no Program camera or the clock
    /// is bad. The world model is refreshed first, so its rows are as fresh as
    /// this tick even when the console is not drawing.
    func build(now: TimeInterval, evidenceRevision: UInt64, samples: [ChannelID: ChannelEvidenceSample],
               adapter: DirectorEvidenceAdapter?, segmentType: SegmentType, style: DirectorStyle?) -> DirectorScene? {
        guard let show, now.isFinite, now >= 0 else { return nil }
        let program = show.programChannel
        guard let programCamera = show.channel(program) else { return nil }
        // A clock that ran backwards cannot place this tick after the facts kept so far.
        guard programStartedAt.map({ now >= $0 }) ?? true, lastWideAt.map({ now >= $0 }) ?? true,
              history.last.map({ now >= $0.endedAt }) ?? true else { return nil }

        let current = ProgramPair(channel: program, shot: programCamera.directorShot)
        if let previous = pair {
            if previous != current {
                history.append(.init(shot: previous.shot, endedAt: now))
                if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
                programStartedAt = now
            }
        } else {
            let start = startedAt.map { min($0, now) } ?? now
            programStartedAt = start
            lastWideAt = start
        }
        pair = current
        if current.shot.isWide { lastWideAt = now }
        guard let programStartedAt, let lastWideAt else { return nil }

        show.refreshWorldModel()
        let inputs = ChannelID.allCases.compactMap { id -> DirectorScene.Input? in
            guard let camera = show.channel(id), let sample = samples[id] else { return nil }
            let shot = camera.directorShot
            let revisions = camera.revisions
            return .init(channel: id, running: camera.isRunning, sourceMissing: camera.sourceMissing,
                revisions: revisions, sourceGeneration: revisions.sourceGeneration, shot: shot,
                format: .init(shot.preset), sample: sample, state: adapter?.state(for: id),
                settledFor: adapter?.settledFor(id, now: now) ?? 0,
                people: DirectorScene.People(show.worldModel.camera(id)))
        }
        let preview = show.previewChannel
        let previewTake = preview.flatMap { preview in
            show.takeInputs().map { TakeAvailability.evaluate(take: $0, program: program, preview: preview,
                standard: ShowStandard.activeOrCurrent, editLive: show.editLive) }
        }
        return .init(now: now, evidenceRevision: evidenceRevision, program: program, preview: preview,
            previewTake: previewTake, routeGeneration: show.router.routeGeneration, inputs: inputs, programStartedAt: programStartedAt,
            lastWideAt: lastWideAt, history: history, segmentType: segmentType, style: style)
    }
}
