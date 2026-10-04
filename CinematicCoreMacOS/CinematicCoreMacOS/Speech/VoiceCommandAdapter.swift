import Foundation

/// Minted only by the adapter at utterance start. A source echoes this value
/// on its final result; recognizer-local names cannot authorize a new start.
nonisolated struct VoiceUtteranceID: Hashable, Sendable {
    private let namespace: UUID
    private let sequence: UInt64

    fileprivate init(namespace: UUID, sequence: UInt64) {
        self.namespace = namespace
        self.sequence = sequence
    }
}

nonisolated protocol SpeechTranscriptSource {
    func finalTranscripts() -> [SpeechFinalTranscript]
}
nonisolated struct SpeechFinalTranscript: Equatable, Sendable {
    let id: VoiceUtteranceID
    let text: String
    let confidence: Double
}
nonisolated struct FakeSpeechTranscriptSource: SpeechTranscriptSource {
    var transcripts: [SpeechFinalTranscript]
    func finalTranscripts() -> [SpeechFinalTranscript] { transcripts }
}

/// Supplied by a future coordinator boundary at utterance start and again at
/// final text / dispatch. The running app does not yet provide this snapshot.
nonisolated struct VoiceWorldSnapshot: Equatable, Sendable {
    let now: TimeInterval
    let sessionGeneration: UInt64
    let muteGeneration: UInt64
    let running: Bool
    let muted: Bool
    let controlTargetRevision: UInt64
    let program: ChannelID
    let preview: ChannelID?
    let controlTarget: ChannelID
    let aRevisions: ChannelRevisions?
    let bRevisions: ChannelRevisions?
    let aSourceMissing: Bool
    let bSourceMissing: Bool
    let aSubjectLocked: Bool
    let bSubjectLocked: Bool

    func revisions(for channel: ChannelID) -> ChannelRevisions? {
        switch channel { case .a: aRevisions; case .b: bRevisions; default: nil }
    }
    func sourceMissing(_ channel: ChannelID) -> Bool {
        switch channel { case .a: aSourceMissing; case .b: bSourceMissing; default: true }
    }
    func subjectLocked(_ channel: ChannelID) -> Bool {
        switch channel { case .a: aSubjectLocked; case .b: bSubjectLocked; default: false }
    }
}

nonisolated struct VoiceUtteranceToken: Equatable, Sendable {
    let id: VoiceUtteranceID
    let start: VoiceWorldSnapshot
    let manualEpoch: UInt64
    let wideEpoch: UInt64
    let takeEpoch: UInt64
    let muteEpoch: UInt64
    let stopEpoch: UInt64
}

nonisolated struct BoundVoiceCommand: Sendable {
    let utteranceID: VoiceUtteranceID
    let target: ChannelID
    let action: OperatorCommand.Action
    let token: VoiceUtteranceToken
}

@MainActor final class VoiceCommandAdapter {
    enum Format { case stage, webcam }
    struct Pending: Equatable {
        let token: VoiceUtteranceToken
        let target: ChannelID
        let intent: VoiceIntent
        var utteranceID: VoiceUtteranceID { token.id }
    }
    let confidenceFloor: Double
    let maximumAge: TimeInterval
    let capacity: Int
    private(set) var manualEpoch: UInt64 = 0
    private var wideEpoch: UInt64 = 0
    private var takeEpoch: UInt64 = 0
    private var muteEpoch: UInt64 = 0
    private var stopEpoch: UInt64 = 0
    /// Replacing the adapter always creates a new namespace. Callers cannot
    /// inject one or reset this allocator to reuse an earlier identity.
    private let utteranceNamespace = UUID()
    private var nextUtteranceSequence: UInt64? = 0
    private var starts: [VoiceUtteranceID: VoiceUtteranceToken] = [:]
    private var startOrder: [VoiceUtteranceID] = []
    private var pending: [VoiceUtteranceID: Pending] = [:]
    private var pendingOrder: [VoiceUtteranceID] = []
    private var seenIDs: Set<VoiceUtteranceID> = []
    private var seenOrder: [VoiceUtteranceID] = []

    init(confidenceFloor: Double, maximumAge: TimeInterval = 2, capacity: Int = 128) {
        self.confidenceFloor = confidenceFloor
        self.maximumAge = maximumAge
        self.capacity = capacity
    }

    #if DEBUG
    /// Test-only exhaustion seam. The production namespace is still freshly
    /// minted; only the initial counter of this new adapter can be varied.
    convenience init(confidenceFloor: Double, maximumAge: TimeInterval = 2, capacity: Int = 128,
                     testingNextUtteranceSequence: UInt64) {
        self.init(confidenceFloor: confidenceFloor, maximumAge: maximumAge, capacity: capacity)
        nextUtteranceSequence = testingNextUtteranceSequence
    }
    #endif

    var retainedUtteranceCount: Int { starts.count + pending.count + seenIDs.count }

    /// Start must happen before recognition. The returned identity is the
    /// only correlation value a later final transcript may supply.
    func beginUtterance(world: VoiceWorldSnapshot) -> Result<VoiceUtteranceToken, SpeechRejection> {
        guard confidenceFloor.isFinite, (0...1).contains(confidenceFloor),
              maximumAge.isFinite, maximumAge > 0, capacity > 0,
              world.now.isFinite, world.now >= 0,
              world.program == .a || world.program == .b,
              world.preview == .a || world.preview == .b,
              world.preview != world.program else { return .failure(.invalidToken) }
        guard world.running else { return .failure(.stopped) }
        guard !world.muted else { return .failure(.muted) }
        guard let sequence = nextUtteranceSequence else { return .failure(.invalidToken) }
        // Admit UInt64.max once, then refuse further starts rather than wrap.
        nextUtteranceSequence = sequence == UInt64.max ? nil : sequence + 1
        let id = VoiceUtteranceID(namespace: utteranceNamespace, sequence: sequence)
        let token = VoiceUtteranceToken(id: id, start: world, manualEpoch: manualEpoch,
            wideEpoch: wideEpoch, takeEpoch: takeEpoch, muteEpoch: muteEpoch, stopEpoch: stopEpoch)
        if startOrder.count == capacity, let evicted = startOrder.first {
            startOrder.removeFirst(); starts.removeValue(forKey: evicted)
        }
        starts[id] = token; startOrder.append(id)
        return .success(token)
    }

    func accept(_ transcript: SpeechFinalTranscript,
                world: VoiceWorldSnapshot) -> Result<Pending, SpeechRejection> {
        if seenIDs.contains(transcript.id) { return .failure(.duplicateUtterance) }
        guard let token = starts.removeValue(forKey: transcript.id) else {
            return .failure(.missingUtteranceStart)
        }
        startOrder.removeAll { $0 == transcript.id }
        remember(transcript.id)
        guard transcript.confidence.isFinite, transcript.confidence >= confidenceFloor,
              transcript.confidence <= 1 else { return .failure(.lowConfidence) }
        if let rejection = validate(token, world: world) { return .failure(rejection) }
        let parsed: ParsedVoiceCommand
        switch SpeechCommandGrammar.parse(transcript.text, subjectLocked: true) {
        case .failure(let reason): return .failure(reason)
        case .success(let value): parsed = value
        }
        // A spoken camera name resolves against the roles captured at start.
        // Both implicit and explicit targets are Preview only.
        let target = parsed.namedChannel ?? token.start.controlTarget
        guard target == token.start.preview, target == world.preview,
              target == .a || target == .b else { return .failure(.targetUnavailable) }
        guard token.start.revisions(for: target) != nil, world.revisions(for: target) != nil,
              !token.start.sourceMissing(target), !world.sourceMissing(target) else {
            return .failure(.sourceChanged)
        }
        if case .setMode(.autoTracking) = parsed.intent, !world.subjectLocked(target) {
            return .failure(.subjectNotLocked)
        }
        let bound = Pending(token: token, target: target, intent: parsed.intent)
        if pendingOrder.count == capacity, let evicted = pendingOrder.first {
            pendingOrder.removeFirst(); pending.removeValue(forKey: evicted)
        }
        pending[transcript.id] = bound; pendingOrder.append(transcript.id)
        return .success(bound)
    }

    /// A later coordinator hook must call this in the same MainActor turn as
    /// the final effect gate. The result is a bound value, not an app dispatch.
    func prepareDispatch(_ value: Pending, world: VoiceWorldSnapshot,
                         format: Format) -> Result<BoundVoiceCommand, SpeechRejection> {
        guard let stored = pending.removeValue(forKey: value.utteranceID), stored == value else {
            return .failure(.duplicateUtterance)
        }
        pendingOrder.removeAll { $0 == value.utteranceID }
        if let rejection = validate(value.token, world: world) { return .failure(rejection) }
        guard value.target == world.preview, value.target == value.token.start.preview,
              !world.sourceMissing(value.target) else { return .failure(.roleChanged) }
        if case .setMode(.autoTracking) = value.intent, !world.subjectLocked(value.target) {
            return .failure(.subjectNotLocked)
        }
        let action: OperatorCommand.Action
        switch value.intent {
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
        return .success(.init(utteranceID: value.utteranceID, target: value.target,
            action: action, token: value.token))
    }

    func manualCommandOccurred() { manualEpoch &+= 1 }
    func returnToWideOccurred() { wideEpoch &+= 1; manualEpoch &+= 1 }
    func operatorTakeOccurred() { takeEpoch &+= 1; manualEpoch &+= 1 }
    func muteChanged() { muteEpoch &+= 1 }
    func stopOccurred() { stopEpoch &+= 1 }

    private func validate(_ token: VoiceUtteranceToken,
                          world: VoiceWorldSnapshot) -> SpeechRejection? {
        guard world.now.isFinite, token.start.now.isFinite, world.now >= 0,
              token.start.now >= 0, maximumAge.isFinite,
              maximumAge > 0, world.now >= token.start.now,
              world.now - token.start.now <= maximumAge else { return .expired }
        if token.stopEpoch != stopEpoch || !world.running { return .stopped }
        if token.wideEpoch != wideEpoch { return .cancelledByWide }
        if token.takeEpoch != takeEpoch { return .cancelledByTake }
        if token.muteEpoch != muteEpoch || token.start.muteGeneration != world.muteGeneration || world.muted {
            return .cancelledByMute
        }
        if token.manualEpoch != manualEpoch { return .cancelledByManualCommand }
        if token.start.sessionGeneration != world.sessionGeneration { return .sessionChanged }
        if token.start.program != world.program || token.start.preview != world.preview {
            return .roleChanged
        }
        if token.start.controlTargetRevision != world.controlTargetRevision ||
           token.start.controlTarget != world.controlTarget { return .targetRebound }
        if token.start.aRevisions != world.aRevisions || token.start.bRevisions != world.bRevisions ||
           token.start.aSourceMissing != world.aSourceMissing ||
           token.start.bSourceMissing != world.bSourceMissing { return .sourceChanged }
        return nil
    }

    private func remember(_ id: VoiceUtteranceID) {
        if seenOrder.count == capacity, let evicted = seenOrder.first {
            seenOrder.removeFirst(); seenIDs.remove(evicted)
        }
        seenIDs.insert(id); seenOrder.append(id)
    }
}
