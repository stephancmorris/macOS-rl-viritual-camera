import CoreGraphics
import Foundation

/// C-08 projects current source facts, sampled by the console rather than the
/// frame path. Bindings change on discrete selection/role/control changes;
/// ordinary movement of the same box does not invalidate every UI click.
final class DirectorSubjectConsole {
    private struct Binding: Equatable {
        let revisions: ChannelRevisions
        let route: UInt64
        let target: UInt64
        let phase: DirectorSubjectPick.Phase
        let selected: UUID?
        let candidates: [UUID]
        let discovery: UInt64
        let provenance: DirectorSubjectPick.Provenance?
    }
    private struct Version { let binding: Binding; let revision: UInt64 }
    private var versions: [ChannelID: Version] = [:]
    private var exhausted: Set<ChannelID> = []
    private weak var show: ShowCoordinator?

    init(show: ShowCoordinator?) { self.show = show }

    func picks(now: TimeInterval) -> [ChannelID: DirectorSubjectPick] {
        guard let show, now.isFinite, now >= 0 else { return [:] }
        var result: [ChannelID: DirectorSubjectPick] = [:]
        for id in ChannelID.allCases {
            guard let channel = show.channel(id), channel.isRunning, !channel.sourceMissing,
                  channel.currentFrameBuffer != nil || channel.latestRenderedFrame != nil else { continue }
            let discovery = channel.subjectDiscoverySnapshot(at: now)
            let persons = channel.personDetector.detectedPersons.filter {
                $0.timestamp.isFinite && now >= $0.timestamp && now - $0.timestamp <= DetectionFrameStore.maximumAge
            }
            var candidates = persons.map { DirectorSubjectPick.Candidate(id: $0.id, bounds: $0.boundingBox) }
            var selected = channel.shotComposer.manualLockedTargetID
            var provenance: DirectorSubjectPick.Provenance?
            var phase: DirectorSubjectPick.Phase
            switch channel.recoveryState.phase {
            case .inactive: phase = .unavailable
            case .acquiring: phase = .acquiring
            case .tracking: phase = .tracking
            case .hold: phase = .recovering
            case .wideWaiting: phase = .lost
            }
            if let selectedID = selected {
                if let automatic = channel.directorDiscoveredSubject,
                   automatic.sourceGeneration == channel.revisions.sourceGeneration,
                   automatic.subject == selectedID {
                    switch automatic.reason {
                    case .operatorNomination: provenance = .operatorNomination
                    case .positionHint: provenance = .alfie(.positionHint)
                    case .centralPresenter: provenance = .alfie(.centralPresenter)
                    }
                } else { provenance = .operatorNomination }
                if !candidates.contains(where: { $0.id == selectedID }) {
                    selected = nil
                    if phase == .tracking || phase == .acquiring { phase = .unavailable }
                }
            } else if discovery.sourceGeneration == channel.revisions.sourceGeneration,
                      let decision = discovery.decision {
                candidates = discovery.candidates.map { .init(id: $0.id, bounds: $0.bounds) }
                switch decision {
                case .selected(let choice):
                    // A selector choice is not a confirmed lock or readiness.
                    selected = choice.subject; phase = .suggested
                    switch choice.reason {
                    case .operatorNomination: provenance = .operatorNomination
                    case .positionHint: provenance = .alfie(.positionHint)
                    case .centralPresenter: provenance = .alfie(.centralPresenter)
                    }
                case .ambiguous: phase = .ambiguous
                case .awaitingNomination: phase = .lost
                case .abstain: phase = .unavailable
                }
            }
            if phase == .lost || phase == .unavailable || phase == .ambiguous { selected = nil }
            // Never truncate a candidate set into an apparently unambiguous
            // choice. Invalid or excessive geometry is unavailable as a whole.
            if candidates.count > DirectorSubjectPick.maximumCandidates || !candidates.allSatisfy(\.isValid) ||
                Set(candidates.map(\.id)).count != candidates.count {
                candidates = []; selected = nil; phase = .unavailable; provenance = nil
            }
            let binding = Binding(revisions: channel.revisions, route: show.router.routeGeneration,
                target: show.controlTargetRevision, phase: phase, selected: selected,
                candidates: candidates.map(\.id).sorted { $0.uuidString < $1.uuidString },
                discovery: discovery.selectionRevision, provenance: provenance)
            let old = versions[id]
            let revision: UInt64
            if old?.binding == binding { revision = old!.revision }
            else {
                guard !exhausted.contains(id), old?.revision != UInt64.max else { exhausted.insert(id); continue }
                revision = (old?.revision ?? 0) + 1
                versions[id] = .init(binding: binding, revision: revision)
            }
            let modeAllows = channel.activeMode != .manualCrop && channel.activeMode != .autoPan
            let roleAllows = id != show.programChannel || show.previewChannel == nil || show.editLive
            let pick = DirectorSubjectPick(channel: id, sourceGeneration: channel.revisions.sourceGeneration,
                selectionRevision: revision, routeGeneration: show.router.routeGeneration, phase: phase,
                selectedCandidateID: selected, candidates: candidates, provenance: provenance,
                canOverride: modeAllows && roleAllows && show.controlTarget == id &&
                    (channel.zoomMoveDirection == nil || !channel.operatorGestureInProgress))
            if pick.isValid { result[id] = pick }
        }
        return result
    }
}
