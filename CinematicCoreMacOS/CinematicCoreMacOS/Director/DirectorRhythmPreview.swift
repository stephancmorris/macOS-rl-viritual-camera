//
//  DirectorRhythmPreview.swift
//  CinematicCoreMacOS
//
//  SU-06 (AD-STYLE-UX). Runs a fixed three-minute synthetic presenter
//  timeline through the real `DirectorShotPolicy` ranking and `CutPolicy`
//  timing for a style, and returns the cuts. Settings › Director draws it.
//  Pure: no camera effects, no shadow records, no clock.
//

import Foundation

nonisolated enum DirectorRhythmPreview {
    struct Shot: Equatable, Identifiable, Sendable {
        let id: Int
        let isWide: Bool
        let start: TimeInterval
        let length: TimeInterval
    }

    static let span: TimeInterval = 180
    static let step: TimeInterval = 1

    /// One presenter on a stage camera that Alfie may reframe. Closer shots
    /// carry more subject confidence, as a settled presenter would.
    private static let candidates: [(shot: DirectorShot, confidence: Double)] = [
        (DirectorShot(preset: .stage(.waistUp)), 0.9),
        (DirectorShot(preset: .stage(.fullBody)), 0.8),
        (DirectorShot(preset: .stage(.wide)), 0.6),
    ]

    static func shots(for style: DirectorStyle) -> [Shot] {
        guard (try? style.validated()) != nil else { return [] }
        let parameters = DirectorShotPolicy.Parameters(style)
        let preview = ChannelID.b
        var program = DirectorShot(preset: .stage(.waistUp))
        var programStartedAt: TimeInterval = 0
        var lastWideAt: TimeInterval = 0
        var history: [DirectorShotPolicy.History] = []
        var shots: [Shot] = []

        var now: TimeInterval = 0
        while now < span {
            let dwell = now - programStartedAt
            if dwell >= style.minimumShotDuration {
                let timeline = DirectorShotPolicy.Timeline(
                    programShot: program, programStartedAt: programStartedAt, lastWideAt: lastWideAt,
                    history: history,
                    candidates: candidates.map {
                        .init(channel: preview, shot: $0.shot, subjectConfidence: $0.confidence,
                              movement: 0, isWide: $0.shot.isWide)
                    },
                    now: now)
                if case .chosen(let next, _) = DirectorShotPolicy.choosePreparation(timeline, preview: preview, parameters: parameters),
                   CutPolicy.timingReason(dwell: dwell, sinceWide: now - lastWideAt, preparedIsWide: next.shot.isWide,
                                          programConfirmed: true, style: style) != nil {
                    shots.append(Shot(id: shots.count, isWide: program.isWide, start: programStartedAt, length: dwell))
                    history.append(.init(shot: program, endedAt: now))
                    program = next.shot
                    programStartedAt = now
                    if program.isWide { lastWideAt = now }
                }
            }
            now += step
        }
        shots.append(Shot(id: shots.count, isWide: program.isWide, start: programStartedAt, length: span - programStartedAt))
        return shots
    }
}
