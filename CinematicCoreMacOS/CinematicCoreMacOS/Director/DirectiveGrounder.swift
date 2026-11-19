import CoreGraphics
import Foundation

/// What a typed command points at, once grounded: an input, optionally a
/// person, a preset, or one of the existing voice commands.
nonisolated struct ShotTarget: Equatable, Sendable {
    struct Person: Equatable, Sendable {
        /// Local to this camera and source generation.
        let track: UUID
        /// Vision coordinates, as the world model holds them.
        let box: CGRect
        /// Where a click on this person would land: the centre of the box.
        var point: CGPoint { .init(x: box.midX, y: box.midY) }
    }
    let input: ChannelID
    let person: Person?
    let preset: OperatorCommand.Preset?
    let verb: VoiceIntent?
}

/// Decision core, stage 5: grounds a typed directive against one scene and
/// the world model. Pure: it reads values and answers; it sends nothing.
nonisolated enum DirectiveGrounder {
    enum Grounding: Equatable, Sendable {
        case target(ShotTarget)
        /// More than one person matched; ask which, left to right.
        case clarify([UUID], DirectorReason)
        /// The camera's view is partial, not yet looked at, or out of date.
        /// One census of that camera could answer it. The reason says which.
        case needsCensus(ChannelID, DirectorReason)
        case refuse(DirectorReason)
    }

    /// The oldest world-model scan a typed command acts on.
    static let maximumAge: TimeInterval = 0.5

    /// - lecternZone: a calibrated lectern zone for the input, in Vision
    ///   coordinates. The app has none yet, so "at the lectern" refuses
    ///   rather than guess a place.
    static func ground(_ directive: Directive, scene: DirectorScene, world: WorldModel, now: TimeInterval,
                       lecternZone: SubjectSelector.Zone? = nil) -> Grounding {
        guard now.isFinite, now >= 0 else { return .refuse(.init(.policy, .invalidInput)) }
        // Preview only. Naming no camera means Preview.
        guard let channel = directive.input ?? scene.preview else { return .refuse(.init(.policy, .noPreview)) }
        guard let input = scene.input(channel) else { return .refuse(.init(.worldModel, .notAssigned)) }
        if input.sourceMissing { return .refuse(.init(.worldModel, .sourceMissing)) }
        guard input.running else { return .refuse(.init(.speech, .targetUnavailable)) }
        if channel == scene.program { return .refuse(.init(.proposalStale, .targetBecameProgram)) }
        guard channel == scene.preview else { return .refuse(.init(.speech, .targetUnavailable)) }

        if case .setMode(.autoTracking)? = directive.verb, input.sample.lockedTargetID == nil {
            return .refuse(.init(.speech, .subjectNotLocked))
        }
        var preset: OperatorCommand.Preset?
        if let framing = directive.framing {
            guard let value = framing.preset(for: input.format) else { return .refuse(.init(.policy, .presetUnavailable)) }
            preset = value
        }

        var person: ShotTarget.Person?
        switch directive.subject {
        case nil: break
        case .left?, .right?:
            let answer = directive.subject == .left
                ? world.leftmost(on: channel, now: now, maximumAge: maximumAge)
                : world.rightmost(on: channel, now: now, maximumAge: maximumAge)
            switch answer {
            case .person(_, let found): person = .init(track: found.track, box: found.box)
            case .nobody: return .refuse(.init(.worldModel, .nobody))
            case .unknown(let unknown): return grounding(for: unknown, on: channel, world: world)
            }
        case .lectern?:
            guard let zone = lecternZone, zone.isValid else { return .refuse(.init(.worldModel, .noLecternZone)) }
            switch freshPeople(on: channel, world: world, now: now) {
            case .unknown(let unknown): return grounding(for: unknown, on: channel, world: world)
            case .people(let people):
                let inside = people.filter {
                    (zone.minX...zone.maxX).contains(Double($0.box.midX)) && (zone.minY...zone.maxY).contains(Double($0.box.midY))
                }
                switch inside.count {
                case 0: return .refuse(.init(.worldModel, .nobody))
                case 1: person = .init(track: inside[0].track, box: inside[0].box)
                default:
                    return .clarify(inside.sorted { $0.box.midX < $1.box.midX }.map(\.track),
                                    DirectorReason(WorldModel.Unknown.ambiguous([])))
                }
            }
        }
        return .target(.init(input: channel, person: person, preset: preset, verb: directive.verb))
    }

    /// Every world-model "unknown" has one answer: ask which, look again, or refuse.
    static func grounding(for unknown: WorldModel.Unknown, on channel: ChannelID, world: WorldModel) -> Grounding {
        switch unknown {
        case .partialView, .notObserved, .stale: return .needsCensus(channel, DirectorReason(unknown))
        case .ambiguous(let tracks):
            // Left to right, so "1" is always the left one.
            let people = world.camera(channel)?.people ?? []
            let ordered = tracks.sorted { a, b in
                (people.first { $0.track == a }?.box.midX ?? 0) < (people.first { $0.track == b }?.box.midX ?? 0)
            }
            return .clarify(ordered, DirectorReason(unknown))
        case .notAssigned, .sourceMissing: return .refuse(DirectorReason(unknown))
        }
    }

    /// The people on a camera whose newest scan covered the whole picture and
    /// is fresh enough to act on, or why not. The same checks `outermost` makes.
    enum FreshPeople: Equatable, Sendable { case people([WorldModel.Person]), unknown(WorldModel.Unknown) }
    static func freshPeople(on channel: ChannelID, world: WorldModel, now: TimeInterval) -> FreshPeople {
        guard let camera = world.camera(channel) else { return .unknown(.notAssigned) }
        if camera.sourceMissing { return .unknown(.sourceMissing) }
        guard camera.isRunning else { return .unknown(.notObserved) }
        switch camera.coverage {
        case .none: return .unknown(.notObserved)
        case .region(let region): return .unknown(.partialView(region))
        case .fullFrame: break
        }
        guard let observedAt = camera.observedAt else { return .unknown(.notObserved) }
        let age = now - observedAt
        guard age.isFinite, age >= 0, age <= maximumAge else { return .unknown(.stale(age: age)) }
        return .people(camera.people)
    }
}
