//
//  TakeAvailability.swift
//  CinematicCoreMacOS
//
//  Pure mapping from the router's committed Take inputs to what the Take bar
//  and the next-shot panel say. One source of truth for the refusal reason so
//  the two surfaces can never disagree (TAKE-BAR / NEXT-PANEL cards).
//
//  Reasons, in priority order:
//    1. "Cam B source missing"
//    2. "Cam B unsupported alongside Cam A at <standard>"
//    3. "Preparing Cam B · waiting for a fresh frame"
//  <standard> is always the active ShowStandard title, never a literal.
//

import Foundation

nonisolated struct TakeAvailability: Equatable, Sendable {

    enum Reason: Equatable, Sendable {
        case sourceMissing
        case unsupported
        case preparing
        /// Single running input; there is nothing to take.
        case noPreviewCamera
    }

    let program: ChannelID
    let preview: ChannelID?
    let standard: ShowStandard
    /// nil when Preview passes every check.
    let reason: Reason?
    /// A Take click is admitted and not yet committed. The bar keeps showing
    /// the old roles (the router's committed state) and refuses further clicks.
    let takePending: Bool
    let editLive: Bool

    /// True only when a click right now would be admitted.
    var isEligible: Bool { reason == nil && !takePending }

    /// Plain-words refusal reason, shared word-for-word with the next-shot panel.
    var reasonText: String? {
        guard let reason else { return nil }
        let previewLabel = preview?.cameraLabel ?? "Preview"
        switch reason {
        case .sourceMissing:
            return "\(previewLabel) source missing"
        case .unsupported:
            return "\(previewLabel) unsupported alongside \(program.cameraLabel) at \(standard.title)"
        case .preparing:
            return "Preparing \(previewLabel) · waiting for a fresh frame"
        case .noPreviewCamera:
            return "No Preview camera"
        }
    }

    /// Subtitle under TAKE: always the route or the current reason.
    var subtitle: String {
        if let reasonText { return reasonText }
        return "\(preview?.cameraLabel ?? "Preview") → Program"
    }

    var takeAccessibilityLabel: String {
        "Take \(preview?.cameraLabel ?? "Preview") to Program"
    }

    var editLiveTitle: String {
        editLive ? "Done editing \(program.cameraLabel)" : "Edit Live · \(program.cameraLabel)"
    }

    var editLiveAccessibilityLabel: String {
        "Edit Program \(program.cameraLabel) live"
    }

    static func evaluate(_ snapshot: ConsoleSnapshot) -> TakeAvailability {
        evaluate(
            take: snapshot.take,
            program: snapshot.programChannel,
            preview: snapshot.previewChannel,
            standard: snapshot.showStandard,
            editLive: snapshot.editLive)
    }

    static func evaluate(
        take: ConsoleSnapshot.TakeInputs,
        program: ChannelID,
        preview: ChannelID?,
        standard: ShowStandard,
        editLive: Bool
    ) -> TakeAvailability {
        TakeAvailability(
            program: program,
            preview: preview,
            standard: standard,
            reason: reason(for: take, hasPreview: preview != nil),
            takePending: take.takePending,
            editLive: editLive)
    }

    private static func reason(for take: ConsoleSnapshot.TakeInputs, hasPreview: Bool) -> Reason? {
        guard hasPreview else { return .noPreviewCamera }
        if !take.sourcePresent { return .sourceMissing }
        if !take.supportedAtStandard { return .unsupported }
        let qualifyingRender = take.hasFreshRender
            && take.matchesSourceGeneration
            && take.matchesShotRevision
            && take.legalGeometry
            && !take.isHeldFrame
        return qualifyingRender ? nil : .preparing
    }
}
