import Foundation

/// Decision core, stage 5: what a typed command asks for, before it is
/// grounded against the show. Values only; no camera, show or world access.
nonisolated struct Directive: Equatable, Sendable {
    /// Which person, by description.
    enum SubjectPhrase: Equatable, Sendable { case left, right, lectern }
    /// The framing words. They become a preset only once the input's format
    /// is known ("tight" on a Stage camera is its tightest shot, Waist Up).
    enum Framing: Equatable, Sendable { case wide, fullBody, waistUp, tight }

    /// nil: the Preview input.
    let input: ChannelID?
    let subject: SubjectPhrase?
    let framing: Framing?
    /// One of the existing voice commands. A verb is never combined with a
    /// subject or a framing.
    let verb: VoiceIntent?

    init(input: ChannelID? = nil, subject: SubjectPhrase? = nil, framing: Framing? = nil, verb: VoiceIntent? = nil) {
        self.input = input; self.subject = subject; self.framing = framing; self.verb = verb
    }
}

nonisolated extension Directive.Framing {
    /// The preset this framing means on an input of `format`, or nil when that
    /// format has no such shot (Full Body on a webcam).
    func preset(for format: DirectorShotPolicy.InputFormat) -> OperatorCommand.Preset? {
        switch (self, format) {
        case (.wide, .stage): .stage(.wide)
        case (.fullBody, .stage): .stage(.fullBody)
        case (.waistUp, .stage), (.tight, .stage): .stage(.waistUp)
        case (.wide, .webcam): .webcam(.wide)
        // As the voice grammar does: Waist Up on a webcam is its Tight.
        case (.waistUp, .webcam), (.tight, .webcam): .webcam(.tight)
        case (.fullBody, .webcam): nil
        }
    }
}

nonisolated extension SpeechCommandGrammar {
    /// Grammar two, for typed commands. No wake word is needed ("alfie" is
    /// allowed and ignored). In any order: "camera one|two|three|four" or
    /// "camera 1-4"; "the person|one on the left|right"; "the person|one at
    /// the lectern"; "wide", "full body", "waist up" or "tight". Or one of the
    /// eight existing commands, with an optional camera. Anything else, or a
    /// part given twice, is not recognized. The existing `parse` is unchanged.
    static func parseTyped(_ text: String) -> Result<Directive, SpeechRejection> {
        var words = normalizedWords(text)
        if words.first == "alfie" { words.removeFirst() }
        guard !words.isEmpty else { return .failure(.unrecognized) }

        var input: ChannelID?, subject: Directive.SubjectPhrase?, framing: Directive.Framing?, verb: VoiceIntent?
        var index = 0
        func take(_ phrase: [String]) -> Bool {
            guard index + phrase.count <= words.count, Array(words[index..<index + phrase.count]) == phrase else { return false }
            index += phrase.count
            return true
        }
        func skip(_ word: String) { if index < words.count, words[index] == word { index += 1 } }

        while index < words.count {
            let start = index
            if take(["camera"]) {
                guard input == nil, index < words.count,
                      let number = ["one": 1, "two": 2, "three": 3, "four": 4, "1": 1, "2": 2, "3": 3, "4": 4][words[index]],
                      let channel = ChannelID(cameraNumber: number) else { return .failure(.unrecognized) }
                index += 1
                input = channel
                continue
            }
            // [the] person|one on [the] left|right · [the] person|one at [the] lectern
            skip("the")
            if take(["person"]) || take(["one"]) {
                guard subject == nil else { return .failure(.unrecognized) }
                if take(["on"]) {
                    skip("the")
                    if take(["left"]) { subject = .left } else if take(["right"]) { subject = .right }
                    else { return .failure(.unrecognized) }
                } else if take(["at"]) {
                    skip("the")
                    guard take(["lectern"]) else { return .failure(.unrecognized) }
                    subject = .lectern
                } else { return .failure(.unrecognized) }
                continue
            }
            if take(["at"]) {
                skip("the")
                guard subject == nil, take(["lectern"]) else { return .failure(.unrecognized) }
                subject = .lectern
                continue
            }
            index = start
            let framings: [([String], Directive.Framing)] = [(["wide"], .wide), (["full", "body"], .fullBody),
                                                            (["waist", "up"], .waistUp), (["tight"], .tight)]
            if let match = framings.first(where: { take($0.0) }) {
                guard framing == nil else { return .failure(.unrecognized) }
                framing = match.1
                continue
            }
            let verbs: [([String], VoiceIntent)] = [(["detect"], .detect), (["track"], .setMode(.autoTracking)),
                (["manual"], .setMode(.manualCrop)), (["pan"], .setMode(.autoPan)), (["back", "to", "wide"], .returnToWide),
                (["push", "in"], .beginZoom(.pushIn)), (["pull", "out"], .beginZoom(.pullOut))]
            if let match = verbs.first(where: { take($0.0) }) {
                guard verb == nil else { return .failure(.unrecognized) }
                verb = match.1
                continue
            }
            return .failure(.unrecognized)
        }
        // Something must be asked for. A verb stands alone.
        guard subject != nil || framing != nil || verb != nil else { return .failure(.unrecognized) }
        guard verb == nil || (subject == nil && framing == nil) else { return .failure(.unrecognized) }
        return .success(.init(input: input, subject: subject, framing: framing, verb: verb))
    }

    /// The answer to "which one?": 1 or 2, "first" or "second". nil otherwise.
    static func parseChoice(_ text: String) -> Int? {
        switch normalizedWords(text) {
        case ["1"], ["one"], ["first"], ["the", "first"], ["the", "first", "one"]: 1
        case ["2"], ["two"], ["second"], ["the", "second"], ["the", "second", "one"]: 2
        default: nil
        }
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased().unicodeScalars.map {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? String($0) : " "
        }.joined().split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
