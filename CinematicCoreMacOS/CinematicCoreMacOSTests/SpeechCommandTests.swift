import Foundation
import Testing
@testable import Alfie

@MainActor struct SpeechCommandTests {
    @Test func completeGrammar() {
        let cases: [(String, VoiceIntent)] = [
            ("Alfie, detect", .detect), ("ALFIE! track.", .setMode(.autoTracking)),
            ("Alfie manual", .setMode(.manualCrop)), ("Alfie, pan", .setMode(.autoPan)),
            ("Alfie, back to wide", .returnToWide), ("Alfie, waist up", .selectWaistUp),
            ("Alfie, push in", .beginZoom(.pushIn)), ("Alfie, pull out", .beginZoom(.pullOut))]
        for (transcript, expected) in cases {
            guard case .success(let command) = SpeechCommandGrammar.parse(transcript, subjectLocked: true) else {
                Issue.record("Rejected \(transcript)"); continue
            }
            #expect(command.intent == expected)
        }
        #expect(SpeechCommandGrammar.parse("Alfie, track", subjectLocked: false) == .failure(.subjectNotLocked))
        #expect(SpeechRejection.subjectNotLocked.message == "Pick a subject.")
        #expect(SpeechCommandGrammar.parse("Alfie, wide", subjectLocked: true) == .failure(.unrecognized))
        #expect(SpeechCommandGrammar.parse("Alfie, stop", subjectLocked: true) == .failure(.unrecognized))
        #expect(SpeechCommandGrammar.parse("we said Alfie, detect", subjectLocked: true) == .failure(.noWakePrefix))
        #expect(SpeechCommandGrammar.parse("Alfie, detect now", subjectLocked: true) == .failure(.unrecognized))
        guard case .success(let named) = SpeechCommandGrammar.parse("Alfie, camera two, pan", subjectLocked: true) else {
            Issue.record("named camera failed"); return
        }
        #expect(named.namedChannel == .b)
    }

    @Test func falseActionCorpus() {
        let phrases = ["please detect the issue", "track number four", "manual page", "pan flute",
            "back to wide angle", "waist up in the hymn", "push in the chairs", "pull out the cable",
            "Alfie is here", "ask Alfie to detect", "Alfie detected", "Alfie track the sermon",
            "Alfie, stop", "Alfie, wide", "Alfie, camera two", "Alfie, push in now",
            "hallelujah", "amen", "let us pray", "our father", "sing together", "verse two",
            "the reading today", "please be seated", "peace be with you", "thanks be to God",
            "bring the lights up", "turn the page", "watch the stage", "camera crew ready",
            "the pastor is walking", "the choir is singing", "one two three", "check check",
            "could you pan later", "manual control is available", "we are back to wide",
            "this is a waist up shot", "push in after lunch", "pull out of the lot",
            "detective story", "tracking attendance", "panning for gold", "wide is a word",
            "Alfie and the band", "Alfie please", "Alfie, detect people please",
            "Alfie, camera five, pan", "Alfie, return wide", "Alfie, stop session",
            "music is louder", "the sermon continues", "conversation in the booth",
            "Alfie, track? no", "Alfie, manual please", "Alfie, pull out later"]
        #expect(phrases.count >= 50)
        for phrase in phrases {
            if case .success = SpeechCommandGrammar.parse(phrase, subjectLocked: true) {
                Issue.record("False action: \(phrase)")
            }
        }
    }

    @Test func bindingDeduplicationAndManualCancellation() {
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8)
        let transcript = SpeechFinalTranscript(id: "u1", text: "Alfie, camera two, pan", confidence: 0.9)
        guard case .success(let pending) = adapter.accept(transcript, controlTarget: .a, subjectLocked: true) else {
            Issue.record("expected pending"); return
        }
        #expect(pending.target == .b)
        if case .success = adapter.accept(transcript, controlTarget: .a, subjectLocked: true) {
            Issue.record("duplicate accepted")
        }
        adapter.manualCommandOccurred()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "Speech-\(UUID())")!))
        #expect(adapter.dispatch(pending, through: show, format: .stage) == .failure(.cancelledByManualCommand))
        let low = SpeechFinalTranscript(id: "u2", text: "Alfie, detect", confidence: 0.2)
        if case .success = adapter.accept(low, controlTarget: .a, subjectLocked: true) {
            Issue.record("low confidence accepted")
        }
    }
}
