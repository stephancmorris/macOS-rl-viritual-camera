import Foundation

nonisolated protocol SpeechTranscriptSource {
    func finalTranscripts() -> [SpeechFinalTranscript]
}
nonisolated struct SpeechFinalTranscript: Equatable, Sendable {
    let id: String
    let text: String
    let confidence: Double
}
nonisolated struct FakeSpeechTranscriptSource: SpeechTranscriptSource {
    var transcripts: [SpeechFinalTranscript]
    func finalTranscripts() -> [SpeechFinalTranscript] { transcripts }
}

@MainActor final class VoiceCommandAdapter {
    enum Format { case stage, webcam }
    struct Pending {
        let utteranceID: String
        let target: ChannelID
        let intent: VoiceIntent
        let manualEpoch: UInt64
    }
    let confidenceFloor: Double
    private(set) var manualEpoch: UInt64 = 0
    private var seenIDs: Set<String> = []
    private var dispatchedIDs: Set<String> = []

    init(confidenceFloor: Double) { self.confidenceFloor = confidenceFloor }

    func accept(_ transcript: SpeechFinalTranscript, controlTarget: ChannelID,
                subjectLocked: Bool) -> Result<Pending, SpeechRejection> {
        guard transcript.confidence.isFinite, transcript.confidence >= confidenceFloor else {
            return .failure(.lowConfidence)
        }
        guard seenIDs.insert(transcript.id).inserted else { return .failure(.duplicateUtterance) }
        switch SpeechCommandGrammar.parse(transcript.text, subjectLocked: subjectLocked) {
        case .failure(let rejection): return .failure(rejection)
        case .success(let parsed):
            return .success(Pending(utteranceID: transcript.id,
                target: parsed.namedChannel ?? controlTarget, intent: parsed.intent,
                manualEpoch: manualEpoch))
        }
    }

    /// Call synchronously before every manual action, including Return to Wide.
    func manualCommandOccurred() { manualEpoch &+= 1 }

    func dispatch(_ pending: Pending, through show: ShowCoordinator,
                  format: Format) -> Result<CommandResult, SpeechRejection> {
        guard pending.manualEpoch == manualEpoch else { return .failure(.cancelledByManualCommand) }
        guard dispatchedIDs.insert(pending.utteranceID).inserted else { return .failure(.duplicateUtterance) }
        guard let channel = show.channel(pending.target) else { return .failure(.targetUnavailable) }
        let action: OperatorCommand.Action
        switch pending.intent {
        case .detect: action = .detect
        case .setMode(.autoTracking): action = .setMode(.autoTracking)
        case .setMode(.manualCrop): action = .setMode(.manualCrop)
        case .setMode(.autoPan): action = .setMode(.autoPan)
        case .returnToWide: action = .returnToWide
        case .selectWaistUp:
            action = format == .stage ? .selectPreset(.stage(.waistUp)) : .selectPreset(.webcam(.tight))
        case .beginZoom(.pushIn): action = .beginZoom(.pushIn)
        case .beginZoom(.pullOut): action = .beginZoom(.pullOut)
        }
        // Current control target uses the normal binding. An explicitly named camera
        // uses its public channel command factory and the same target revision gate.
        let bound = pending.target == show.controlTarget ? show.makeCommand(action) :
            ShowCoordinator.ShowCommand(command: channel.makeCommand(action),
                                        controlTargetRevision: show.controlTargetRevision)
        return .success(show.dispatch(bound))
    }
}
