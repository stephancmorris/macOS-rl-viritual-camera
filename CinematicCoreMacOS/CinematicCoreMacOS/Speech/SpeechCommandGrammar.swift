import Foundation

nonisolated enum VoiceIntent: Equatable, Sendable {
    case detect, setMode(Mode), returnToWide, selectWaistUp, beginZoom(Zoom)
    enum Mode: Sendable { case autoTracking, manualCrop, autoPan }
    enum Zoom: Sendable { case pushIn, pullOut }
}
nonisolated enum SpeechRejection: Error, Equatable, Sendable {
    case noWakePrefix, unrecognized, subjectNotLocked, lowConfidence, duplicateUtterance
    case cancelledByManualCommand, targetUnavailable, missingUtteranceStart
    case invalidToken, muted, stopped, sessionChanged, roleChanged, targetRebound
    case sourceChanged, expired, cancelledByWide, cancelledByTake, cancelledByMute
    var message: String {
        switch self {
        case .subjectNotLocked: return "Pick a subject."
        case .noWakePrefix: return "Say Alfie first."
        case .unrecognized: return "Command not recognized."
        case .lowConfidence: return "Speech uncertain."
        case .duplicateUtterance: return "Already handled."
        case .cancelledByManualCommand: return "Cancelled by manual control."
        case .targetUnavailable: return "Camera unavailable."
        case .missingUtteranceStart: return "Utterance start missing."
        case .invalidToken: return "Voice context invalid."
        case .muted, .cancelledByMute: return "Voice is muted."
        case .stopped: return "Show stopped."
        case .sessionChanged: return "Show session changed."
        case .roleChanged: return "Camera roles changed."
        case .targetRebound: return "Control target changed."
        case .sourceChanged: return "Camera changed."
        case .expired: return "Voice command expired."
        case .cancelledByWide: return "Cancelled by Return to Wide."
        case .cancelledByTake: return "Cancelled by Take."
        }
    }
}
nonisolated struct ParsedVoiceCommand: Equatable, Sendable {
    let namedChannel: ChannelID?
    let intent: VoiceIntent
}

nonisolated enum SpeechCommandGrammar {
    static func parse(_ finalTranscript: String, subjectLocked: Bool) -> Result<ParsedVoiceCommand, SpeechRejection> {
        let normalized = finalTranscript.lowercased().unicodeScalars.map {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? String($0) : " "
        }.joined().split(whereSeparator: \.isWhitespace).map(String.init)
        guard normalized.first == "alfie" else { return .failure(.noWakePrefix) }
        var words = Array(normalized.dropFirst())
        var channel: ChannelID?
        if words.count >= 2, words[0] == "camera" {
            switch words[1] {
            case "one": channel = .a
            case "two": channel = .b
            case "three": channel = .c
            case "four": channel = .d
            default: return .failure(.unrecognized)
            }
            words.removeFirst(2)
        }
        let intent: VoiceIntent
        switch words {
        case ["detect"]: intent = .detect
        case ["track"]:
            guard subjectLocked else { return .failure(.subjectNotLocked) }
            intent = .setMode(.autoTracking)
        case ["manual"]: intent = .setMode(.manualCrop)
        case ["pan"]: intent = .setMode(.autoPan)
        case ["back", "to", "wide"]: intent = .returnToWide
        case ["waist", "up"]: intent = .selectWaistUp
        case ["push", "in"]: intent = .beginZoom(.pushIn)
        case ["pull", "out"]: intent = .beginZoom(.pullOut)
        default: return .failure(.unrecognized)
        }
        return .success(.init(namedChannel: channel, intent: intent))
    }
}
