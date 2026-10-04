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

    @Test func bindingDeduplicationAndManualCancellation() throws {
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8)
        let token = try adapter.beginUtterance(world: world(now: 1)).get()
        let transcript = SpeechFinalTranscript(id: token.id, text: "Alfie, camera two, pan", confidence: 0.9)
        guard case .success(let pending) = adapter.accept(transcript, world: world(now: 1.2)) else {
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
        let lowToken = try adapter.beginUtterance(world: world(now: 2)).get()
        let low = SpeechFinalTranscript(id: lowToken.id, text: "Alfie, detect", confidence: 0.2)
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

    private func pending(_ adapter: VoiceCommandAdapter,
                         text: String = "Alfie, pan") -> VoiceCommandAdapter.Pending? {
        guard case .success(let token) = adapter.beginUtterance(world: world(now: 1)),
              case .success(let value) = adapter.accept(.init(id: token.id, text: text, confidence: 0.95),
                world: world(now: 1.1)) else { return nil }
        return value
    }

    @Test func startSnapshotBindsPreviewAndNamedCamera() throws {
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
        let programToken = try program.beginUtterance(world: world(now: 1)).get()
        #expect(program.accept(.init(id: programToken.id, text: "Alfie, camera one, pan", confidence: 0.95),
            world: world(now: 1.1)) == .failure(.targetUnavailable))
        let implicit = VoiceCommandAdapter(confidenceFloor: 0.8)
        let implicitToken = try implicit.beginUtterance(world: world(now: 1, control: .a)).get()
        #expect(implicit.accept(.init(id: implicitToken.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.1, control: .a)) == .failure(.targetUnavailable))
        let extra = VoiceCommandAdapter(confidenceFloor: 0.8)
        let extraToken = try extra.beginUtterance(world: world(now: 1)).get()
        #expect(extra.accept(.init(id: extraToken.id, text: "Alfie, camera three, pan", confidence: 0.95),
            world: world(now: 1.1)) == .failure(.targetUnavailable))
    }

    @Test func interveningActionsRevokeAtFinalAndDispatch() throws {
        let cases: [(String, (VoiceCommandAdapter) -> Void, SpeechRejection)] = [
            ("manual", { $0.manualCommandOccurred() }, .cancelledByManualCommand),
            ("wide", { $0.returnToWideOccurred() }, .cancelledByWide),
            ("take", { $0.operatorTakeOccurred() }, .cancelledByTake),
            ("mute", { $0.muteChanged() }, .cancelledByMute),
            ("stop", { $0.stopOccurred() }, .stopped)]
        for (_, intervene, expected) in cases {
            let beforeFinal = VoiceCommandAdapter(confidenceFloor: 0.8)
            let token = try beforeFinal.beginUtterance(world: world(now: 1)).get()
            intervene(beforeFinal)
            #expect(beforeFinal.accept(.init(id: token.id, text: "Alfie, pan", confidence: 0.9),
                world: world(now: 1.1)) == .failure(expected))
            let beforeDispatch = VoiceCommandAdapter(confidenceFloor: 0.8)
            guard let value = pending(beforeDispatch) else { Issue.record("missing pending"); continue }
            intervene(beforeDispatch)
            if case .failure(let reason) = beforeDispatch.prepareDispatch(value,
                world: world(now: 1.2), format: .stage) {
                #expect(reason == expected)
            } else { Issue.record("intervening action admitted") }
        }
    }

    @Test func liveChangesExpiryAndBoundedDedupe() throws {
        let changed: [(VoiceWorldSnapshot, SpeechRejection)] = [
            (world(now: 1.2, session: 2), .sessionChanged),
            (world(now: 1.2, mute: 2), .cancelledByMute),
            (world(now: 1.2, targetRevision: 2), .targetRebound),
            (world(now: 1.2, program: .b, preview: .a), .roleChanged),
            (world(now: 1.2, sourceGeneration: 2), .sourceChanged),
            (world(now: 4), .expired)]
        for item in changed {
            let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, maximumAge: 2)
            guard let value = pending(adapter) else { Issue.record("missing pending"); continue }
            if case .failure(let reason) = adapter.prepareDispatch(value, world: item.0, format: .stage) {
                #expect(reason == item.1)
            } else { Issue.record("stale token admitted") }
            let finalAdapter = VoiceCommandAdapter(confidenceFloor: 0.8, maximumAge: 2)
            let token = try finalAdapter.beginUtterance(world: world(now: 1)).get()
            #expect(finalAdapter.accept(.init(id: token.id, text: "Alfie, pan", confidence: 0.9),
                world: item.0) == .failure(item.1))
        }
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: 2)
        for _ in 0..<10 {
            let token = try adapter.beginUtterance(world: world(now: 1)).get()
            _ = adapter.accept(.init(id: token.id, text: "Alfie, detect", confidence: 0.9), world: world(now: 1.1))
            #expect(adapter.retainedUtteranceCount <= 4)
        }
        let otherAdapter = VoiceCommandAdapter(confidenceFloor: 0.8)
        let orphan = try otherAdapter.beginUtterance(world: world(now: 1)).get()
        #expect(adapter.accept(.init(id: orphan.id, text: "Alfie, detect", confidence: 0.9),
            world: world(now: 1.1)) == .failure(.missingUtteranceStart))
    }


    @Test func lateFinalCannotAliasAFreshStartAfterRecentIdentityEviction() throws {
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: 1)
        let first = try adapter.beginUtterance(world: world(now: 1)).get()
        let oldFinal = SpeechFinalTranscript(id: first.id, text: "Alfie, pan", confidence: 0.95)
        let firstPending = try adapter.accept(oldFinal, world: world(now: 1.1)).get()
        let firstBound = try adapter.prepareDispatch(firstPending, world: world(now: 1.2), format: .stage).get()
        #expect(firstBound.utteranceID == first.id)

        let middle = try adapter.beginUtterance(world: world(now: 1.3)).get()
        _ = try adapter.accept(.init(id: middle.id, text: "Alfie, detect", confidence: 0.95),
            world: world(now: 1.4)).get() // capacity=1 evicts first from recent IDs.
        let fresh = try adapter.beginUtterance(world: world(now: 1.5)).get()
        #expect(Set([first.id, middle.id, fresh.id]).count == 3)
        #expect(adapter.accept(oldFinal, world: world(now: 1.6)) == .failure(.missingUtteranceStart))
        let freshPending = try adapter.accept(.init(id: fresh.id, text: "Alfie, manual", confidence: 0.95),
            world: world(now: 1.6)).get()
        let freshBound = try adapter.prepareDispatch(freshPending, world: world(now: 1.7), format: .stage).get()
        #expect(freshBound.utteranceID == fresh.id)
        guard case .setMode(.manualCrop) = freshBound.action else {
            Issue.record("old final replaced the fresh command"); return
        }
        #expect(adapter.accept(oldFinal, world: world(now: 1.7)) == .failure(.missingUtteranceStart))
        if case .success = adapter.prepareDispatch(freshPending, world: world(now: 1.7), format: .stage) {
            Issue.record("fresh identity dispatched twice")
        }
    }

    @Test(arguments: [false, true])
    func oldSessionFinalCannotConsumeANewSessionStart(stopBeforeRestart: Bool) throws {
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: 1)
        let old = try adapter.beginUtterance(world: world(now: 1, session: 1)).get()
        if stopBeforeRestart { adapter.stopOccurred() }
        let fresh = try adapter.beginUtterance(world: world(now: 1.2, session: 2)).get()
        #expect(old.id != fresh.id)
        #expect(old.start.sessionGeneration == 1)
        #expect(fresh.start.sessionGeneration == 2)
        #expect(adapter.accept(.init(id: old.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.3, session: 2)) == .failure(.missingUtteranceStart))
        let command = try adapter.accept(.init(id: fresh.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.3, session: 2)).get()
        let bound = try adapter.prepareDispatch(command, world: world(now: 1.4, session: 2), format: .stage).get()
        #expect(bound.utteranceID == fresh.id)
    }

    @Test func replacingAdapterCannotReuseIdentityOrConsumeItsCurrentPendingCommand() throws {
        let oldAdapter = VoiceCommandAdapter(confidenceFloor: 0.8)
        let old = try oldAdapter.beginUtterance(world: world(now: 1)).get()
        let oldFinal = SpeechFinalTranscript(id: old.id, text: "Alfie, pan", confidence: 0.95)
        let oldPending = try oldAdapter.accept(oldFinal, world: world(now: 1.1)).get()
        // Same show generation, clock and initial counter; the adapter namespace differs.
        let freshAdapter = VoiceCommandAdapter(confidenceFloor: 0.8)
        let fresh = try freshAdapter.beginUtterance(world: world(now: 1)).get()
        #expect(old.id != fresh.id)
        #expect(freshAdapter.accept(oldFinal, world: world(now: 1.1)) == .failure(.missingUtteranceStart))
        let freshPending = try freshAdapter.accept(.init(id: fresh.id, text: "Alfie, manual", confidence: 0.95),
            world: world(now: 1.1)).get()
        if case .failure(let reason) = freshAdapter.prepareDispatch(oldPending, world: world(now: 1.2), format: .stage) {
            #expect(reason == .duplicateUtterance)
        } else { Issue.record("another adapter's pending command admitted") }
        let bound = try freshAdapter.prepareDispatch(freshPending, world: world(now: 1.2), format: .stage).get()
        #expect(bound.utteranceID == fresh.id)
        guard case .setMode(.manualCrop) = bound.action else {
            Issue.record("another adapter consumed the fresh command"); return
        }
    }

    @Test(arguments: ["confidence", "grammar"])
    func refusedFinalStaysConsumedAfterItsRecentIdentityIsEvicted(refusal: String) throws {
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: 1)
        let refused = try adapter.beginUtterance(world: world(now: 1)).get()
        let expected: SpeechRejection = refusal == "confidence" ? .lowConfidence : .unrecognized
        let transcript = SpeechFinalTranscript(id: refused.id,
            text: refusal == "grammar" ? "Alfie, stop" : "Alfie, pan",
            confidence: refusal == "confidence" ? 0.2 : 0.95)
        #expect(adapter.accept(transcript, world: world(now: 1.1)) == .failure(expected))
        let retry = SpeechFinalTranscript(id: refused.id, text: "Alfie, pan", confidence: 0.95)
        #expect(adapter.accept(retry, world: world(now: 1.1)) == .failure(.duplicateUtterance))
        let middle = try adapter.beginUtterance(world: world(now: 1.2)).get()
        _ = try adapter.accept(.init(id: middle.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.3)).get()
        let fresh = try adapter.beginUtterance(world: world(now: 1.4)).get()
        #expect(adapter.accept(retry, world: world(now: 1.5)) == .failure(.missingUtteranceStart))
        let command = try adapter.accept(.init(id: fresh.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.5)).get()
        #expect(try adapter.prepareDispatch(command, world: world(now: 1.6), format: .stage).get().utteranceID == fresh.id)
    }

    #if DEBUG
    @Test func identitySequenceExhaustionRefusesRatherThanWraps() throws {
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: 2,
            testingNextUtteranceSequence: UInt64.max - 1)
        let penultimate = try adapter.beginUtterance(world: world(now: 1)).get()
        let last = try adapter.beginUtterance(world: world(now: 1)).get()
        #expect(penultimate.id != last.id)
        #expect(adapter.beginUtterance(world: world(now: 1)) == .failure(.invalidToken))
        #expect(adapter.beginUtterance(world: world(now: 1.1)) == .failure(.invalidToken))
        let command = try adapter.accept(.init(id: last.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 1.1)).get()
        #expect(try adapter.prepareDispatch(command, world: world(now: 1.2), format: .stage).get().utteranceID == last.id)
    }
    #endif

    @Test func identityUniquenessDoesNotRequireUnboundedRetainedState() throws {
        let capacity = 2
        let adapter = VoiceCommandAdapter(confidenceFloor: 0.8, capacity: capacity)
        var issued = Set<VoiceUtteranceID>()
        var first: VoiceUtteranceToken?
        for index in 0..<64 {
            let time = Double(index) / 100
            let token = try adapter.beginUtterance(world: world(now: time)).get()
            if first == nil { first = token }
            #expect(issued.insert(token.id).inserted)
            #expect(adapter.retainedUtteranceCount <= 3 * capacity)
            guard index % 3 != 0 else { continue } // Leave some starts to exercise their eviction.
            let command = try adapter.accept(.init(id: token.id, text: "Alfie, pan", confidence: 0.95),
                world: world(now: time)).get()
            #expect(adapter.retainedUtteranceCount <= 3 * capacity)
            if index % 3 == 1 {
                _ = try adapter.prepareDispatch(command, world: world(now: time), format: .stage).get()
                #expect(adapter.retainedUtteranceCount <= 3 * capacity)
            }
        }
        #expect(issued.count == 64)
        let evicted = try #require(first)
        #expect(adapter.accept(.init(id: evicted.id, text: "Alfie, pan", confidence: 0.95),
            world: world(now: 0.7)) == .failure(.missingUtteranceStart))
    }
}
