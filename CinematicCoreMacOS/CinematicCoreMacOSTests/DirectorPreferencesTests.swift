import Foundation
import Testing
@testable import Alfie

/// A-05: one versioned parameter source, a style per segment type, no defaults.
struct DirectorPreferencesTests {
    /// Test fixture values only.
    private func style(min: TimeInterval = 20, preferred: TimeInterval = 45, softMax: TimeInterval = 90,
                       wide: TimeInterval = 120, repetition: TimeInterval = 20, movement: Double = 0.1,
                       settle: TimeInterval = 1, moveRate: Double = 0.5, cutOnMotion: Bool = false) -> DirectorStyle {
        DirectorStyle(minimumShotDuration: min, preferredShotDuration: preferred, softMaximumShotDuration: softMax,
            wideCadence: wide, repetitionWindow: repetition, maximumMovement: movement,
            settleTime: settle, onAirMoveRate: moveRate, cutOnMotionAllowed: cutOnMotion)
    }

    private func preferences(_ styles: [SegmentType: DirectorStyle]) -> DirectorPreferences {
        DirectorPreferences(styles: styles)
    }

    @Test func roundTripsThroughMigrationAsADictionaryKeyedBySegment() throws {
        let prefs = preferences([.liveEvent: style(), .panel: style(min: 10, preferred: 20, softMax: 40)])
        let data = try JSONEncoder().encode(prefs)
        #expect(try DirectorPreferences.migrate(data) == prefs)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"liveEvent\"") && json.contains("\"panel\""))
    }

    @Test func segmentsWithoutAStyleUseLiveEvent() throws {
        let live = style()
        let panel = style(min: 10, preferred: 20, softMax: 40)
        let prefs = try preferences([.liveEvent: live, .panel: panel]).validated()
        #expect(prefs.style(for: .panel) == panel)
        #expect(prefs.style(for: .presenter) == live)
        #expect(prefs.style(for: .videoBreak) == live)
    }

    @Test func liveEventStyleIsRequired() {
        #expect(throws: DirectorPreferences.ValidationError.missingLiveEventStyle) {
            try preferences([.presenter: style()]).validated()
        }
    }

    @Test func oldAndFutureSchemasFailClosed() throws {
        let v1 = #"{"version":1,"minimumShotDuration":8,"maximumShotDuration":35,"wideCadence":90,"repetitionWindow":20,"maximumMovement":0.1,"cutOnMotionAllowed":false}"#
        #expect(throws: DirectorPreferences.ValidationError.unsupportedVersion) {
            try DirectorPreferences.migrate(Data(v1.utf8))
        }
        var future = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences([.liveEvent: style()]))) as! [String: Any]
        future["version"] = 3
        #expect(throws: DirectorPreferences.ValidationError.unsupportedVersion) {
            try DirectorPreferences.migrate(JSONSerialization.data(withJSONObject: future))
        }
        #expect(throws: DirectorPreferences.ValidationError.unsupportedVersion) {
            try DirectorPreferences.migrate(Data("not json".utf8))
        }
    }

    @Test func invalidStylesAreRejected() {
        #expect(throws: DirectorPreferences.ValidationError.invalidDuration) {
            try style(min: 40, preferred: 30).validated()
        }
        #expect(throws: DirectorPreferences.ValidationError.invalidDuration) {
            try style(preferred: 100, softMax: 90).validated()
        }
        #expect(throws: DirectorPreferences.ValidationError.invalidDuration) { try style(wide: 0).validated() }
        #expect(throws: DirectorPreferences.ValidationError.invalidDuration) { try style(settle: .nan).validated() }
        #expect(throws: DirectorPreferences.ValidationError.invalidMovement) { try style(movement: -1).validated() }
        #expect(throws: DirectorPreferences.ValidationError.invalidMovement) { try style(moveRate: 0).validated() }
    }

    @Test func mergeIsConservativePerField() throws {
        let a = style(min: 20, preferred: 45, softMax: 90, wide: 120, repetition: 20, movement: 0.1,
                      settle: 1, moveRate: 0.5, cutOnMotion: true)
        let b = style(min: 15, preferred: 60, softMax: 80, wide: 100, repetition: 30, movement: 0.05,
                      settle: 2, moveRate: 0.25, cutOnMotion: false)
        let merged = try DirectorStyle.resolve(a, b)
        #expect(merged == style(min: 20, preferred: 60, softMax: 80, wide: 100, repetition: 30,
                                movement: 0.05, settle: 2, moveRate: 0.25, cutOnMotion: false))
    }

    @Test func impossibleIntersectionIsRejected() {
        let long = style(min: 20, preferred: 25, softMax: 30)
        let short = style(min: 1, preferred: 5, softMax: 10)
        #expect(throws: DirectorPreferences.ValidationError.conflictingConstraints) {
            try DirectorPreferences.resolve(preferences([.liveEvent: long]), preferences([.liveEvent: short]))
        }
    }

    @Test func mergeKeepsOneSidedSegments() throws {
        let merged = try DirectorPreferences.resolve(preferences([.liveEvent: style()]),
            preferences([.liveEvent: style(), .performance: style(min: 5, preferred: 10, softMax: 20)]))
        #expect(merged.styles.keys.sorted { $0.rawValue < $1.rawValue } == [.liveEvent, .performance])
    }

    @Test func policyReadsItsPacingFromTheStyle() {
        let parameters = DirectorShotPolicy.Parameters(style(min: 12, softMax: 70, wide: 110,
            repetition: 25, movement: 0.2, cutOnMotion: true))
        #expect(parameters == DirectorShotPolicy.Parameters(minimumShotDuration: 12, maximumShotDuration: 70,
            wideCadence: 110, repetitionWindow: 25, maximumMovement: 0.2, cutOnMotionAllowed: true))
    }
}
