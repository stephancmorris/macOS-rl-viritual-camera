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
        let start = world(now: 1)
        guard case .success = adapter.beginUtterance(id: "u1", world: start),
              case .success(let pending) = adapter.accept(transcript, world: world(now: 1.2)) else {
            Issue.record("expected pending"); return
        }
        #expect(pending.target == .b)
        if case .success = adapter.accept(transcript, world: world(now: 1.2)) {
            Issue.record("duplicate accepted")
        }
        adapter.manualCommandOccurred()
        if case .failure(let reason) = adapter.prepareDispatch(pending, world: world(now: 1.3), format: .stage) {
            #expect(reason == .cancelledByManualCommand)
        } else { Issue.record("manual override admitted") }
        let low = SpeechFinalTranscript(id: "u2", text: "Alfie, detect", confidence: 0.2)
        _ = adapter.beginUtterance(id: "u2", world: world(now: 2))
        if case .success = adapter.accept(low, world: world(now: 2.1)) {
            Issue.record("low confidence accepted")
        }
    }

    private func world(now: Double, session: UInt64 = 1, mute: UInt64 = 1,
                       running: Bool = true, muted: Bool = false, targetRevision: UInt64 = 1,
                       program: ChannelID = .a, preview: ChannelID = .b,
                       control: ChannelID = .b, sourceGeneration: UInt64 = 1,
                       locked: Bool = true) -> VoiceWorldSnapshot {
        VoiceWorldSnapshot(now: now, sessionGeneration: session, muteGeneration: mute,
            running: running, muted: muted, controlTargetRevision: targetRevision,
            program: program, preview: preview, controlTarget: control,
            aRevisions: .init(sourceGeneration: 1, controlEpoch: 1, shotRevision: 1),
            bRevisions: .init(sourceGeneration: sourceGeneration, controlEpoch: 1, shotRevision: 1),
            aSourceMissing: false, bSourceMissing: false,
            aSubjectLocked: true, bSubjectLocked: locked)
    }

    private func pending(_ adapter: VoiceCommandAdapter, id: String = "u",
                         text: String = "Alfie, pan") -> VoiceCommandAdapter.Pending? {
        guard case .success = adapter.beginUtterance(id: id, world: world(now: 1)),
              case .success(let value) = adapter.accept(.init(id: id, text: text, confidence: 0.95),
                world: world(now: 1.1)) else { return nil }
        return value
    }

    @Test func startSnapshotBindsPreviewAndNamedCamera() {
        let named = VoiceCommandAdapter(confidenceFloor: 0.8)
        guard let command = pending(named, text: "Alfie, camera two, pan") else {
            Issue.record("named camera rejected"); return
        }
        guard case .success(let bound) = named.prepareDispatch(command, world: world(now: 1.2), format: .stage) else {
            Issue.record("bound command rejected"); return
        }
        #expect(bound.target == .b)
        if case .success = named.prepareDispatch(command, world: world(now: 1.2), format: .stage) {
            Issue.record("utterance dispatched twice")
        }
        let program = VoiceCommandAdapter(confidenceFloor: 0.8)
        _ = program.beginUtterance(id: "program", world: world(now: 1))
        #expect(program.accept(.init(id: "program", text: "Alfie, camera one, pan", confidence: 0.95),
            world: world(now: 1.1)) == .failure(.targetUnavailable))
        let implicit = VoiceCommandAdapter(confidenceFloor: 0.8)
        _ = implicit.beginUtterance(id: "implicit", world: world(now: 1, control: .a))
        #expect(implicit.accept(.init(id: "implicit", text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.1, control: .a)) == .failure(.targetUnavailable))
        let extra = VoiceCommandAdapter(confidenceFloor: 0.8)
        _ = extra.beginUtterance(id: "extra", world: world(now: 1))
        #expect(extra.accept(.init(id: "extra", text: "Alfie, camera three, pan", confidence: 0.95),
            world: world(now: 1.1)) == .failure(.targetUnavailable))
    }

    @Test func interveningActionsRevokeAtFinalAndDispatch() {
        let cases: [(String, (VoiceCommandAdapter) -> Void, SpeechRejection)] = [
            ("manual", { $0.manualCommandOccurred() }, .cancelledByManualCommand),
            ("wide", { $0.returnToWideOccurred() }, .cancelledByWide),
            ("take", { $0.operatorTakeOccurred() }, .cancelledByTake),
            ("mute", { $0.muteChanged() }, .cancelledByMute),
            ("stop", { $0.stopOccurred() }, .stopped)]
        for (id, intervene, expected) in cases {
            let beforeFinal = VoiceCommandAdapter(confidenceFloor: 0.8)
            _ = beforeFinal.beginUtterance(id: id, world: world(now: 1))
            intervene(beforeFinal)
            #expect(beforeFinal.accept(.init(id: id, text: "Alfie, pan", confidence: 0.9),
                world: world(now: 1.1)) == .failure(expected))
            let beforeDispatch = VoiceCommandAdapter(confidenceFloor: 0.8)
            guard let value = pending(beforeDispatch, id: id) else { Issue.record("missing pending"); continue }
            intervene(beforeDispatch)
            if case .failure(let reason) = beforeDispatch.prepareDispatch(value,
                world: world(now: 1.2), format: .stage) {
                #expect(reason == expected)
            } else { Issue.record("intervening action admitted") }
        }
    }

    @Test func liveChangesExpiryAndBoundedDedupe() {
        let changed: [(VoiceWorldSnapshot, SpeechRejection)] = [
            (world(now: 1.2, session: 2), .sessionChanged),
            (world(now: 1.2, mute: 2), .cancelledByMute),
            (world(now: 1.2, targetRevision: 2), .targetRebound),
            (world(now: 1.2, program: .b, preview: .a), .roleChanged),
            (world(now: 1.2, sourceGeneration: 2), .sourceChanged),
            (world(now: 4), .expired)]
        for (index, item) in changed.enumerated() {
            let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, maximumAge: 2)
            guard let value = pending(adapter, id: "c\(index)") else { Issue.record("missing pending"); continue }
            if case .failure(let reason) = adapter.prepareDispatch(value, world: item.0, format: .stage) {
                #expect(reason == item.1)
            } else { Issue.record("stale token admitted") }
            let finalAdapter = VoiceCommandAdapter(confidenceFloor: 0.8, maximumAge: 2)
            let finalID = "f\(index)"
            _ = finalAdapter.beginUtterance(id: finalID, world: world(now: 1))
            #expect(finalAdapter.accept(.init(id: finalID, text: "Alfie, pan", confidence: 0.9),
                world: item.0) == .failure(item.1))
        }
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: 2)
        for index in 0..<10 {
            let id = "bounded-\(index)"
            _ = adapter.beginUtterance(id: id, world: world(now: 1))
            _ = adapter.accept(.init(id: id, text: "Alfie, detect", confidence: 0.9), world: world(now: 1.1))
            #expect(adapter.retainedUtteranceCount <= 4)
        }
        #expect(adapter.accept(.init(id: "orphan", text: "Alfie, detect", confidence: 0.9),
            world: world(now: 1.1)) == .failure(.missingUtteranceStart))
    }
}
