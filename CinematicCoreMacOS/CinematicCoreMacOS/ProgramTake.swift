//
//  ProgramTake.swift
//  CinematicCoreMacOS
//
//  Take eligibility and results (TAKE card; docs/ALFIE_MULTICAMERA_SPEC.md
//  "Message and time model"). A Take is a hard cut to the prepared Preview:
//  validated at the click, never armed for later.
//
//  Eligible only if Preview's latest rendered frame
//  - exists and came from the Preview channel,
//  - completed within `maxRenderAgePeriods` show-frame periods of the click,
//  - came from a source frame processed within `maxSourceAgePeriods`,
//  - matches the channel's current source generation and shot revision,
//  - has legal geometry, is not a held / repeated frame,
//  - and its source is present and admitted alongside Program.
//  Thresholds are provisional calibration gates, not measured performance.
//

import CoreGraphics
import Foundation

/// Who asked for a Take. Operator Takes keep today's path; Director and
/// fallback Takes will also need a one-shot permit (S3 B-07).
nonisolated enum TakeOrigin: Equatable, Sendable {
    case operatorUI, director, fallback
}

nonisolated enum TakeRules {
    static let maxRenderAgePeriods = 2.0
    static let maxSourceAgePeriods = 4.0
    /// Guard after a commit so a double-click cannot cut straight back.
    static let minimumInterval: TimeInterval = 0.5

    /// The TakeInputs the console shows, from the live Preview state.
    static func inputs(
        frame: RenderedChannelFrame?,
        previewChannel: ChannelID,
        current: ChannelRevisions,
        sourceMissing: Bool,
        admission: AdmissionDecision,
        now: TimeInterval,
        framePeriod: TimeInterval
    ) -> ConsoleSnapshot.TakeInputs {
        let supported: Bool
        if case .refused = admission { supported = false } else { supported = true }
        guard let frame, frame.channelID == previewChannel else {
            return ConsoleSnapshot.TakeInputs(
                sourcePresent: !sourceMissing, supportedAtStandard: supported, hasFreshRender: false,
                matchesSourceGeneration: false, matchesShotRevision: false, legalGeometry: false,
                isHeldFrame: false, takePending: false)
        }
        let renderFresh = now - frame.renderedAt <= framePeriod * maxRenderAgePeriods
        let sourceFresh = now - frame.processingStartedAt <= framePeriod * maxSourceAgePeriods
        return ConsoleSnapshot.TakeInputs(
            sourcePresent: !sourceMissing,
            supportedAtStandard: supported,
            hasFreshRender: renderFresh && sourceFresh,
            matchesSourceGeneration: frame.revisions.sourceGeneration == current.sourceGeneration,
            matchesShotRevision: frame.revisions.shotRevision == current.shotRevision,
            legalGeometry: isLegal(frame),
            isHeldFrame: frame.isRepeat,
            takePending: false)
    }

    static func isLegal(_ frame: RenderedChannelFrame) -> Bool {
        let c = frame.crop
        let inside = c.origin.x >= -0.0001 && c.origin.y >= -0.0001
            && c.origin.x + c.size.width <= 1.0001 && c.origin.y + c.size.height <= 1.0001
        return inside && c.size.width > 0 && c.size.height > 0
            && frame.outputSize.width > 0 && frame.outputSize.height > 0
    }
}

/// A Take bound at the click: the roles and route generation it expects.
nonisolated struct TakeRequest: Equatable, Sendable {
    let expectedProgram: ChannelID
    let expectedPreview: ChannelID
    let routeGeneration: UInt64
}

nonisolated enum TakeResult: Equatable, Sendable {
    case committed(newProgram: ChannelID)
    case rejected(TakeRejection)
}

nonisolated enum TakeRejection: Equatable, Sendable {
    case noPreview
    /// Roles or route changed since the click (e.g. a second click).
    case superseded
    /// Inside the post-commit guard interval.
    case tooSoon
    /// Preview not eligible; the reason matches TakeAvailability.
    case notEligible(TakeAvailability.Reason?)
    /// The output did not accept the frame (route missing / refused).
    case outputRefused
}
