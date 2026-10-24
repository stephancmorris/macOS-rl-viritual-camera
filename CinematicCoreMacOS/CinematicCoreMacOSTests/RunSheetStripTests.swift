//
//  RunSheetStripTests.swift
//  CinematicCoreMacOSTests
//
//  C-07: displayed current/next context and explicit, non-wrapping boundaries.
//

import SwiftUI
import Testing
@testable import Alfie

struct RunSheetStripTests {
    @Test func anEmptySheetNamesTheLiveEventFallbackAndHasNoNextSegment() throws {
        let presentation = RunSheetStripPresentation(sheet: try RunSheet(segments: []))
        #expect(presentation.current == "Live event · No run sheet")
        #expect(presentation.next == "No segments")
        #expect(presentation.boundary == "Add a segment to use a run sheet.")
    }

    @Test func currentAndNextIncludeOnlySuppliedSegmentMetadata() throws {
        let sheet = try RunSheet(segments: [
            .init(type: .presenter, name: "Opening", positionHint: .lectern),
            .init(type: .panel, name: nil, positionHint: .centre)
        ])
        let presentation = RunSheetStripPresentation(sheet: sheet)
        #expect(presentation.current == "Presenter · Opening · Lectern")
        #expect(presentation.next == "Panel · Centre")
        #expect(presentation.boundary == nil)
    }

    @Test func advancingToTheLastSegmentShowsTheBoundaryWithoutWrapping() throws {
        var sheet = try RunSheet(segments: [
            .init(type: .performance, name: "Finale"),
            .init(type: .videoBreak)
        ])
        let advanced = sheet.advance()
        #expect(advanced)
        let final = RunSheetStripPresentation(sheet: sheet)
        #expect(final.current == "Video break")
        #expect(final.next == "End of run sheet")
        #expect(final.boundary == "Last segment. Advance does not wrap.")
        let advancedPastEnd = sheet.advance()
        #expect(!advancedPastEnd)
        #expect(RunSheetStripPresentation(sheet: sheet) == final)
    }

    @Test @MainActor func advanceUsesItsOwnShortcutChord() {
        #expect(RunSheetAdvanceShortcut.key == .return)
        #expect(RunSheetAdvanceShortcut.modifiers == [.command, .shift])
        #expect(RunSheetAdvanceShortcut.title == "Command Shift Return")
        #expect(RunSheetAdvanceShortcut.key != DirectorHandShortcut.key)
        #expect(RunSheetAdvanceShortcut.key != .escape)
    }
}
