import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorShotPolicyTests {
    let a = DirectorShot(preset: .waistUp, mode: .autoTracking, zoomRung: 1)
    let b = DirectorShot(preset: .medium, mode: .manualCrop, zoomRung: 0)

    @Test func minimumAndRepetition() {
        let candidate = DirectorShotPolicy.Candidate(channel: .b, shot: b, subjectConfidence: 0.9,
                                                       movement: 0, isWide: false)
        let early = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [], candidates: [candidate], now: 7)
        #expect(DirectorShotPolicy.choosePreparation(early, preview: .b, parameters: .proposed) == .chosen(candidate, "subject evidence"))
        #expect(!DirectorShotPolicy.recommendationDue(early, parameters: .proposed))
        let repeated = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [.init(shot: b, endedAt: 5)], candidates: [candidate], now: 10)
        #expect(DirectorShotPolicy.choosePreparation(repeated, preview: .b, parameters: .proposed) == .abstain(.repetition))
        let clear = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [.init(shot: b, endedAt: 5)], candidates: [candidate], now: 26)
        guard case .chosen(let selected, _) = DirectorShotPolicy.choosePreparation(clear, preview: .b, parameters: .proposed) else {
            Issue.record("expected candidate"); return
        }
        #expect(selected.shot == b)
    }

    @Test func preferencesValidationAndRoundTrip() throws {
        let defaults = DirectorPreferences.safeDefaults
        let encoded = try JSONEncoder().encode(defaults)
        #expect(try DirectorPreferences.migrate(encoded) == defaults)
        let bad = DirectorPreferences(version: 1, minimumShotDuration: 40,
            maximumShotDuration: 8, wideCadence: 90, repetitionWindow: 20,
            maximumMovement: 0.1, cutOnMotionAllowed: false)
        #expect(throws: DirectorPreferences.ValidationError.invalidDuration) { try bad.validated() }
        let resolved = try DirectorPreferences.resolve(defaults, defaults)
        #expect(resolved == defaults)
    }

    @Test func invalidPolicyAndClockAbstain() {
        let candidate = DirectorShotPolicy.Candidate(channel: .b, shot: b, subjectConfidence: 0.9,
            movement: 0, isWide: false)
        let timeline = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [], candidates: [candidate], now: 10)
        let invalid = DirectorShotPolicy.Parameters(minimumShotDuration: .nan,
            maximumShotDuration: 35, wideCadence: 90, repetitionWindow: 20,
            maximumMovement: 0.1, cutOnMotionAllowed: false)
        #expect(DirectorShotPolicy.choosePreparation(timeline, preview: .b, parameters: invalid) == .abstain(.invalidInput))
        let badClock = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [], candidates: [candidate], now: .infinity)
        #expect(DirectorShotPolicy.choosePreparation(badClock, preview: .b, parameters: .proposed) == .abstain(.invalidInput))
        let badMovement = DirectorShotPolicy.Candidate(channel: .b, shot: b, subjectConfidence: 0.9,
            movement: .nan, isWide: false)
        let badCandidate = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [], candidates: [badMovement], now: 10)
        #expect(DirectorShotPolicy.choosePreparation(badCandidate, preview: .b, parameters: .proposed) == .abstain(.noPreview))
    }

    @Test func tiesResolveIndependentOfCandidateOrder() {
        let shots = [DirectorShot(preset: .medium, mode: .autoPan, zoomRung: 2),
            DirectorShot(preset: .medium, mode: .autoTracking, zoomRung: 1),
            DirectorShot(preset: .medium, mode: .autoTracking, zoomRung: 0)]
        let candidates = shots.map { DirectorShotPolicy.Candidate(channel: .b, shot: $0,
            subjectConfidence: 0.9, movement: 0, isWide: false) }
        func selected(_ values: [DirectorShotPolicy.Candidate]) -> DirectorShotPolicy.Decision {
            DirectorShotPolicy.choosePreparation(.init(programShot: a, programStartedAt: 0,
                lastWideAt: 0, history: [], candidates: values, now: 10),
                preview: .b, parameters: .proposed)
        }
        #expect(selected(candidates) == selected(candidates.reversed()))
    }

    @Test func impossiblePreferenceIntersectionIsRejected() throws {
        let a = DirectorPreferences(version: 1, minimumShotDuration: 20, maximumShotDuration: 30,
            wideCadence: 90, repetitionWindow: 20, maximumMovement: 0.1, cutOnMotionAllowed: false)
        let b = DirectorPreferences(version: 1, minimumShotDuration: 1, maximumShotDuration: 10,
            wideCadence: 90, repetitionWindow: 20, maximumMovement: 0.1, cutOnMotionAllowed: false)
        #expect(throws: DirectorPreferences.ValidationError.conflictingConstraints) {
            try DirectorPreferences.resolve(a, b)
        }
    }
}
