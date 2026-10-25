//
//  DirectorRhythmPreviewTests.swift
//  CinematicCoreMacOSTests
//
//  SU-06: the Settings preview runs the real Director ranking and cut timing
//  on a fixed synthetic timeline, so it is deterministic and follows the feel.
//

import Foundation
import Testing
@testable import Alfie

struct DirectorRhythmPreviewTests {
    private func shots(_ pace: DirectorFeel.Pace, _ wide: DirectorFeel.WideShots) -> [DirectorRhythmPreview.Shot] {
        DirectorRhythmPreview.shots(for: DirectorFeelTable.v1.style(
            for: DirectorFeel(pace: pace, wideShots: wide, movement: .waitUntilSettled)))
    }

    @Test func theSameStyleGivesTheSameCuts() {
        #expect(shots(.balanced, .sometimes) == shots(.balanced, .sometimes))
    }

    @Test func shotsCoverThreeMinutesWithoutGaps() {
        for feel in DirectorFeel.all {
            let result = DirectorRhythmPreview.shots(for: DirectorFeelTable.v1.style(for: feel))
            #expect(result.first?.start == 0)
            #expect(abs(result.reduce(0) { $0 + $1.length } - DirectorRhythmPreview.span) < 0.001)
            for (earlier, later) in zip(result, result.dropFirst()) {
                #expect(abs(earlier.start + earlier.length - later.start) < 0.001)
            }
        }
    }

    @Test func livelyCutsMoreThanCalm() {
        #expect(shots(.lively, .sometimes).count > shots(.calm, .sometimes).count)
    }

    @Test func oftenNeverShowsFewerWidesThanRarely() {
        // With one camera and three shots, the repetition window (2 ×
        // preferred) already forces a wide every third shot, so the wide
        // cadence rarely changes the result here. Reported on SU-06.
        for pace in DirectorFeel.Pace.allCases {
            let often = shots(pace, .often).filter(\.isWide).count
            let rarely = shots(pace, .rarely).filter(\.isWide).count
            #expect(often >= rarely)
        }
    }

    @Test func noFinishedShotIsShorterThanTheMinimum() {
        for feel in DirectorFeel.all {
            let style = DirectorFeelTable.v1.style(for: feel)
            for shot in DirectorRhythmPreview.shots(for: style).dropLast() {
                #expect(shot.length >= style.minimumShotDuration)
            }
        }
    }

    @Test func cutTimingMatchesTheLiveRule() {
        let style = DirectorFeelTable.v1.style(for: .liveEventDefault)
        #expect(CutPolicy.timingReason(dwell: 10, sinceWide: 10, preparedIsWide: false, programConfirmed: true, style: style) == nil)
        #expect(CutPolicy.timingReason(dwell: 20, sinceWide: 10, preparedIsWide: false, programConfirmed: true, style: style) == .preferredLength)
        #expect(CutPolicy.timingReason(dwell: 10, sinceWide: 75, preparedIsWide: true, programConfirmed: true, style: style) == .wideDue)
        #expect(CutPolicy.timingReason(dwell: 10, sinceWide: 0, preparedIsWide: false, programConfirmed: false, style: style) == .programUncertain)
    }
}
