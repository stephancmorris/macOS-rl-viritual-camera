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
        #expect(DirectorShotPolicy.choose(early, preview: .b, parameters: .proposed) == .abstain(.minimumDuration))
        let repeated = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [.init(shot: b, endedAt: 5)], candidates: [candidate], now: 10)
        #expect(DirectorShotPolicy.choose(repeated, preview: .b, parameters: .proposed) == .abstain(.repetition))
        let clear = DirectorShotPolicy.Timeline(programShot: a, programStartedAt: 0,
            lastWideAt: 0, history: [.init(shot: b, endedAt: 5)], candidates: [candidate], now: 26)
        guard case .chosen(let selected, _) = DirectorShotPolicy.choose(clear, preview: .b, parameters: .proposed) else {
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
}
