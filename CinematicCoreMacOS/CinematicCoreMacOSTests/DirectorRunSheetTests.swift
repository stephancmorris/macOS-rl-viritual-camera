import Foundation
import Testing
@testable import Alfie

nonisolated struct DirectorRunSheetTests {
    private func segments() -> [RunSheet.Segment] {
        [.init(type: .presenter, name: "Welcome", positionHint: .lectern),
         .init(type: .panel, name: "Questions", positionHint: .centre),
         .init(type: .performance, positionHint: .left),
         .init(type: .videoBreak, positionHint: .right)]
    }
    private func style(_ preferred: Double) -> DirectorStyle {
        .init(minimumShotDuration: 5, preferredShotDuration: preferred, softMaximumShotDuration: 30,
              wideCadence: 20, repetitionWindow: 4, maximumMovement: 0.2,
              settleTime: 1, onAirMoveRate: 0.1, cutOnMotionAllowed: false)
    }
    private func encodedObject(_ sheet: RunSheet) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sheet)) as? [String: Any])
    }
    private func decoded(_ object: [String: Any]) throws -> RunSheet {
        try JSONDecoder().decode(RunSheet.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func suggestion(_ sheet: RunSheet, previous: RunSheet.Evidence = .init(personCount: 1, sampledAt: 10, stableFor: 5),
                            current: RunSheet.Evidence = .init(personCount: 3, sampledAt: 13, stableFor: 2),
                            now: Double = 14, maximumAge: Double = 5, minimumStable: Double = 2) -> RunSheet.ChangeSuggestion? {
        sheet.segmentChangeSuggestion(previous: previous, current: current, now: now,
            parameters: .init(maximumEvidenceAge: maximumAge, minimumStableDuration: minimumStable))
    }

    @Test func allTypedSegmentsAndOperatorPositionRoundTrip() throws {
        let authored = segments()
        var sheet = try RunSheet(segments: authored)
        let advanced = sheet.advance()
        #expect(advanced && sheet.current == authored[1] && sheet.next == authored[2])
        let restored = try JSONDecoder().decode(RunSheet.self, from: JSONEncoder().encode(sheet))
        #expect(restored == sheet)
        #expect(restored.segments.map(\.type) == [.presenter, .panel, .performance, .videoBreak])
        #expect(restored.segments.map(\.positionHint) == [.lectern, .centre, .left, .right])
        #expect(restored.segments[2].name == nil && restored.segments[0].name == "Welcome")
    }

    @Test func advanceAndBackAreOperatorDrivenAndNeverWrap() throws {
        let authored = segments()
        var sheet = try RunSheet(segments: authored)
        #expect(!sheet.back() && sheet.current == authored[0])
        for index in 1..<authored.count {
            let advanced = sheet.advance()
            #expect(advanced && sheet.currentIndex == index && sheet.current == authored[index])
        }
        #expect(sheet.next == nil && !sheet.advance())
        #expect(sheet.current == authored.last)
        for index in (0..<(authored.count - 1)).reversed() {
            let movedBack = sheet.back()
            #expect(movedBack && sheet.currentIndex == index)
        }
        #expect(!sheet.back() && sheet.current == authored[0])
    }

    @Test func emptySheetUsesLiveEventAndSingleSegmentStaysSelected() throws {
        var empty = try RunSheet(segments: [])
        #expect(empty.current == nil && empty.next == nil && empty.currentIndex == nil)
        #expect(!empty.advance() && !empty.back())
        #expect(suggestion(empty) == nil)
        let preferences = DirectorPreferences(styles: [.liveEvent: style(10)])
        #expect(empty.style(in: preferences) == style(10))
        #expect(try JSONDecoder().decode(RunSheet.self, from: JSONEncoder().encode(empty)) == empty)
        var single = try RunSheet(segments: [.init(type: .presenter)])
        let first = single.current
        #expect(!single.advance() && !single.back() && single.current == first)
    }

    @Test func stableIDsPreserveSelectionWhenTheEditorReordersSegments() throws {
        let authored = segments()
        let original = try RunSheet(segments: authored, currentSegmentID: authored[1].id)
        let reordered = try RunSheet(segments: [authored[2], authored[1], authored[3], authored[0]],
                                     currentSegmentID: original.currentSegmentID)
        #expect(reordered.current == original.current && reordered.next == authored[3])
        #expect(throws: RunSheet.ValidationError.invalidCurrentSegment) {
            try RunSheet(segments: [authored[0]], currentSegmentID: authored[1].id)
        }
    }

    @Test func authoringRejectsDuplicateIdentityInvalidSelectionAndFallbackAsASegment() throws {
        let segment = RunSheet.Segment(type: .presenter)
        #expect(throws: RunSheet.ValidationError.duplicateSegmentID) {
            try RunSheet(segments: [segment, segment])
        }
        #expect(throws: RunSheet.ValidationError.invalidSegmentType) {
            try RunSheet(segments: [.init(type: .liveEvent)])
        }
        #expect(throws: RunSheet.ValidationError.invalidCurrentSegment) {
            try RunSheet(segments: [], currentSegmentID: segment.id)
        }
    }

    @Test(arguments: ["version", "selection", "missingSelection", "duplicate", "type", "fallback"])
    func invalidPersistedSheetsFailClosed(field: String) throws {
        let sheet = try RunSheet(segments: segments())
        var object = try encodedObject(sheet)
        switch field {
        case "version": object["version"] = 99
        case "selection": object["currentSegmentID"] = UUID().uuidString
        case "missingSelection": object.removeValue(forKey: "currentSegmentID")
        default:
            var items = try #require(object["segments"] as? [[String: Any]])
            if field == "duplicate" { items.append(items[0]) }
            else { items[0]["type"] = field == "type" ? "future-segment" : "liveEvent" }
            object["segments"] = items
        }
        #expect(throws: (any Error).self) { try decoded(object) }
    }

    @Test func segmentSelectsTheExistingStyleSourceAndMissingStylesFallBack() throws {
        var sheet = try RunSheet(segments: segments())
        let preferences = DirectorPreferences(styles: [.liveEvent: style(10), .presenter: style(15), .panel: style(8)])
        #expect(sheet.style(in: preferences) == style(15))
        sheet.advance()
        #expect(sheet.style(in: preferences) == style(8))
        sheet.advance()
        #expect(sheet.style(in: preferences) == style(10))
        #expect(sheet.style(in: .init(styles: [.presenter: style(15)])) == nil)
        #expect(sheet.style(in: .init(version: 99, styles: [.liveEvent: style(10)])) == nil)
        #expect(sheet.style(in: .init(styles: [.liveEvent: style(.nan)])) == nil)
    }

    @Test func persistenceHasNoAuthorityOrPacingOverrides() throws {
        let sheet = try RunSheet(segments: segments())
        var object = try encodedObject(sheet)
        #expect(Set(object.keys) == ["version", "segments", "currentSegmentID"])
        // Even an added grant in a tampered document cannot become authority.
        object["authority"] = ["level": "auto", "qualified": true]
        object["style"] = ["minimumShotDuration": 0]
        let restored = try decoded(object)
        #expect(restored == sheet)
        let clean = try encodedObject(restored)
        #expect(clean["authority"] == nil && clean["style"] == nil)
    }

    @Test func evidenceOnlySuggestsAndNeverAdvancesOrChangesStyle() throws {
        let sheet = try RunSheet(segments: segments())
        let before = sheet
        let preferences = DirectorPreferences(styles: [.liveEvent: style(10), .presenter: style(15), .panel: style(8)])
        let result = try #require(suggestion(sheet))
        #expect(result.segmentID == sheet.currentSegmentID && result.previousPersonCount == 1)
        #expect(result.currentPersonCount == 3 && result.observedAt == 13 && result.text == "Segment changed?")
        #expect(sheet == before && sheet.style(in: preferences) == style(15))
        #expect(suggestion(sheet) == result)
    }

    @Test(arguments: [0, 1, 2, 5])
    func countChangesInEitherDirectionAreAdvisoryOnly(count: Int) throws {
        let sheet = try RunSheet(segments: segments())
        let result = suggestion(sheet, current: .init(personCount: count, sampledAt: 13, stableFor: 2))
        #expect((result != nil) == (count != 1))
        #expect(sheet.currentIndex == 0)
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidClocksDurationsAndThresholdsNeverSuggest(value: Double) throws {
        let sheet = try RunSheet(segments: segments())
        #expect(suggestion(sheet, now: value) == nil)
        #expect(suggestion(sheet, maximumAge: value) == nil)
        #expect(suggestion(sheet, minimumStable: value) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: value, stableFor: 2)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 13, stableFor: value)) == nil)
        #expect(suggestion(sheet, previous: .init(personCount: 1, sampledAt: value, stableFor: 0)) == nil)
    }

    @Test func staleUnstableUnorderedAndContradictoryObservationsNeverSuggest() throws {
        let sheet = try RunSheet(segments: segments())
        #expect(suggestion(sheet, now: 16) == nil) // old baseline
        #expect(suggestion(sheet, now: 12) == nil) // future sample
        #expect(suggestion(sheet, current: .init(personCount: -1, sampledAt: 13, stableFor: 2)) == nil)
        #expect(suggestion(sheet, previous: .init(personCount: -1, sampledAt: 10, stableFor: 0)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 13, stableFor: 1.999)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 10, stableFor: 2)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 9, stableFor: 2)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 13, stableFor: 4)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 13, stableFor: 14)) == nil)
        #expect(suggestion(sheet, current: .init(personCount: 3, sampledAt: 13, stableFor: 3)) != nil)
    }
}
