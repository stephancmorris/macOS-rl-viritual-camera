import Combine
import CoreGraphics
import Foundation

/// Decision core, stage 5: typed commands for Preview. The operator types
/// what they want; Alfie does it, asks which person, or says why not.
///
/// A command is the operator acting. It goes through the show's ordinary
/// command path with the operator's origin, like a click, so it works at
/// every Director level and in a shadow-only build, and a command on Preview
/// pauses a directing Alfie as any manual command does. It never reaches
/// Program and never Takes.
///
/// Each command is bound to the roles and revisions at entry. A pending
/// "which one?" is cancelled by any change of roles, route, control target or
/// the input's revisions, and never acts on the old answer.
final class TypedCommandController: ObservableObject {
    enum Outcome: Equatable {
        /// The commands were sent, in order (their actions' names).
        case sent([String])
        /// Waiting for "1" or "2".
        case clarify(DirectorReason)
        case refused(DirectorReason)
        /// The camera refused a command; its own words.
        case cameraRefused(String)
        case ignored
    }

    /// The roles and revisions a command was entered under.
    private struct Bound: Equatable {
        let program: ChannelID
        let preview: ChannelID?
        let controlTargetRevision: UInt64
        let routeGeneration: UInt64
        let input: ChannelID
        let revisions: ChannelRevisions?
        let sourceMissing: Bool
    }
    private struct Clarification {
        let bound: Bound
        /// Left to right: choice 1 is the left one.
        let tracks: [UUID]
        let preset: OperatorCommand.Preset?
        let reason: DirectorReason
    }

    /// The one status line the console shows under the field.
    @Published private(set) var status: String?
    private var pending: Clarification?
    var hasPendingClarification: Bool { pending != nil }

    private weak var show: ShowCoordinator?
    /// A fresh builder per entry: grounding needs roles, inputs and the world
    /// model, not the Director's timing facts.
    private lazy var sceneBuilder = DirectorSceneBuilder(show: show)
    #if DEBUG
    /// Every command this controller sent, in order. Tests only.
    private(set) var sentForTesting: [OperatorCommand] = []
    #endif

    init(show: ShowCoordinator?) { self.show = show }

    /// Return in the field. Empty text is ignored.
    @discardableResult
    func submit(_ text: String) -> Outcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ignored }
        guard let show else { return refuse(.init(.speech, .stopped)) }
        if let pending {
            if let choice = SpeechCommandGrammar.parseChoice(text) { return answer(choice, to: pending, show: show) }
            // Anything else is a new command; the question is dropped.
            self.pending = nil
        }
        let directive: Directive
        switch SpeechCommandGrammar.parseTyped(text) {
        case .failure(let rejection): return refuse(DirectorReason(rejection))
        case .success(let value): directive = value
        }
        let now = show.clock()
        guard let scene = scene(show: show, now: now) else { return refuse(.init(.policy, .invalidInput)) }
        switch DirectiveGrounder.ground(directive, scene: scene, world: show.worldModel, now: now) {
        case .refuse(let reason): return refuse(reason)
        case .needsCensus(_, let reason):
            // The census (#142) is not in this build, so Alfie cannot look again.
            return refuse(reason)
        case .clarify(let tracks, let reason):
            guard tracks.count >= 2, let channel = directive.input ?? scene.preview else { return refuse(reason) }
            let preset = directive.framing.flatMap { framing in scene.input(channel).flatMap { framing.preset(for: $0.format) } }
            pending = .init(bound: bound(channel, show: show), tracks: Array(tracks.prefix(2)), preset: preset, reason: reason)
            status = "\(reason.words) Type 1 for the left one or 2 for the right one."
            return .clarify(reason)
        case .target(let target):
            return execute(target, bound: bound(target.input, show: show), show: show)
        }
    }

    /// Called with the console's refresh: a pending question whose roles or
    /// revisions changed is cancelled and says why.
    func refresh() {
        guard let pending, let show else { return }
        if let reason = changed(pending.bound, show: show) {
            self.pending = nil
            status = reason.words
        }
    }

    // MARK: Private

    private func answer(_ choice: Int, to question: Clarification, show: ShowCoordinator) -> Outcome {
        pending = nil
        if let reason = changed(question.bound, show: show) { return refuse(reason) }
        guard question.tracks.indices.contains(choice - 1) else { return refuse(.init(.speech, .unrecognized)) }
        let track = question.tracks[choice - 1]
        show.refreshWorldModel()
        guard case .people(let people) = DirectiveGrounder.freshPeople(on: question.bound.input, world: show.worldModel,
                                                                       now: show.clock()),
              let person = people.first(where: { $0.track == track }) else {
            return refuse(.init(.worldModel, .stale))
        }
        return execute(.init(input: question.bound.input, person: .init(track: person.track, box: person.box),
                             preset: question.preset, verb: nil), bound: question.bound, show: show)
    }

    private func execute(_ target: ShotTarget, bound: Bound, show: ShowCoordinator) -> Outcome {
        guard let camera = show.channel(target.input) else { return refuse(.init(.worldModel, .notAssigned)) }
        var sent: [String] = []
        var expected = bound
        func send(_ action: OperatorCommand.Action) -> CommandResult {
            // Still the world the command was entered under, apart from this
            // command's own revisions; still Preview, never Program.
            guard changed(expected, show: show) == nil, target.input == show.previewChannel,
                  target.input != show.programChannel else { return .rejected(DirectorReason(.speech, .roleChanged).words) }
            let command = camera.makeCommand(action)
            let result = show.dispatch(.init(command: command, controlTargetRevision: show.controlTargetRevision))
            if result.wasAccepted {
                #if DEBUG
                sentForTesting.append(command)
                #endif
                sent.append(String(String(describing: action).prefix { $0 != "(" }))
                expected = self.bound(target.input, show: show)
            }
            return result
        }
        func refused(_ result: CommandResult) -> Outcome {
            if case .rejected(let words) = result { status = words; return .cameraRefused(words) }
            return refuse(.init(.speech, .targetUnavailable))
        }

        if let person = target.person {
            // The same steps a click on the person takes.
            let retarget = camera.manualLockedTargetID != nil
            if !retarget && !camera.detectionDiscoveryActive && !camera.canDirectlyReacquire {
                let armed = send(.detect)
                guard armed.wasAccepted else { return refused(armed) }
            }
            let selected = send(.selectSubject(person.point, retarget: retarget))
            guard selected.wasAccepted else { return refused(selected) }
        }
        if let verb = target.verb {
            let action: OperatorCommand.Action
            switch verb {
            case .detect: action = .detect
            case .setMode(.autoTracking): action = .setMode(.autoTracking)
            case .setMode(.manualCrop): action = .setMode(.manualCrop)
            case .setMode(.autoPan): action = .setMode(.autoPan)
            case .returnToWide: action = .returnToWide
            case .selectWaistUp:
                action = .selectPreset(DirectorShotPolicy.InputFormat(camera.directorShot.preset) == .stage
                    ? .stage(.waistUp) : .webcam(.tight))
            case .beginZoom(.pushIn): action = .beginZoom(.pushIn)
            case .beginZoom(.pullOut): action = .beginZoom(.pullOut)
            }
            let result = send(action)
            guard result.wasAccepted else { return refused(result) }
        }
        if let preset = target.preset {
            let result = send(.selectPreset(preset))
            guard result.wasAccepted else { return refused(result) }
        }
        var parts: [String] = []
        if target.person != nil { parts.append("subject selected") }
        if let verb = target.verb { parts.append(Self.title(verb)) }
        if let preset = target.preset { parts.append(DirectorShot(preset: preset).title) }
        status = "\(target.input.cameraLabel): " + parts.joined(separator: " · ")
        return .sent(sent)
    }

    private func refuse(_ reason: DirectorReason) -> Outcome {
        status = reason.words
        return .refused(reason)
    }

    private func scene(show: ShowCoordinator, now: TimeInterval) -> DirectorScene? {
        var samples: [ChannelID: ChannelEvidenceSample] = [:]
        for id in ChannelID.allCases {
            guard let channel = show.channel(id) else { continue }
            samples[id] = DirectorController.sample(channel.evidenceReadings(now: now))
        }
        sceneBuilder.begin(at: now)
        return sceneBuilder.build(now: now, evidenceRevision: 0, samples: samples, adapter: nil,
                                  segmentType: .liveEvent, style: nil)
    }

    private func bound(_ input: ChannelID, show: ShowCoordinator) -> Bound {
        let camera = show.channel(input)
        return .init(program: show.programChannel, preview: show.previewChannel,
                     controlTargetRevision: show.controlTargetRevision, routeGeneration: show.router.routeGeneration,
                     input: input, revisions: camera?.revisions, sourceMissing: camera?.sourceMissing ?? true)
    }

    /// Why the world is no longer the one a command was bound to, or nil.
    private func changed(_ bound: Bound, show: ShowCoordinator) -> DirectorReason? {
        let now = self.bound(bound.input, show: show)
        if now.program != bound.program || now.preview != bound.preview || now.routeGeneration != bound.routeGeneration {
            return .init(.speech, .roleChanged)
        }
        if now.controlTargetRevision != bound.controlTargetRevision { return .init(.speech, .targetRebound) }
        if now.revisions != bound.revisions || now.sourceMissing != bound.sourceMissing { return .init(.speech, .sourceChanged) }
        return nil
    }

    private static func title(_ verb: VoiceIntent) -> String {
        switch verb {
        case .detect: "Detect"
        case .setMode(.autoTracking): "Track"
        case .setMode(.manualCrop): "Manual"
        case .setMode(.autoPan): "Pan"
        case .returnToWide: "Back to Wide"
        case .selectWaistUp: "Waist Up"
        case .beginZoom(.pushIn): "Push In"
        case .beginZoom(.pullOut): "Pull Out"
        }
    }
}
