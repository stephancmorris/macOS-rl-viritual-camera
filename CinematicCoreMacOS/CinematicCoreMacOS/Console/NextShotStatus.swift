//
//  NextShotStatus.swift
//  CinematicCoreMacOS
//
//  What the next cut will be and whether it is ready, for the panel under the
//  Preview pane. Built from TakeAvailability so the panel's reason is always
//  the Take button's reason for the same state (NEXT-PANEL card).
//
//  R3 seam: `director` carries the Auto Director's status (S3 A-04). R2 builds
//  leave it nil; the model and its plain-words text live in
//  Director/DirectorConsoleAPI.swift.
//

import Foundation

nonisolated struct NextShotStatus: Equatable, Sendable {

    enum Readiness: Equatable, Sendable {
        /// Take sends exactly this shot.
        case ready
        /// Take would be refused; `reasonText` says why.
        case notReady
        /// Controls target Program; Preview is untouched.
        case editingLive
        /// Single running input.
        case noPreviewCamera
    }

    static let label = "NEXT"

    let preview: ChannelID?
    /// Line 1, e.g. "Cam B · Band side · Waist Up".
    let shotLine: String
    let readiness: Readiness
    /// Line 2 in plain words.
    let statusText: String
    /// Identical to the Take bar's reason for the same snapshot (nil if ready).
    let reasonText: String?
    /// nil unless the Auto Director is wired in (S3 B-03).
    let director: DirectorSection?

    var accessibilityLabel: String {
        "Next: \(shotLine.replacingOccurrences(of: " · ", with: ", ")). \(statusText)"
    }

    static func make(_ snapshot: ConsoleSnapshot) -> NextShotStatus {
        make(snapshot, availability: .evaluate(snapshot))
    }

    static func make(_ snapshot: ConsoleSnapshot, availability: TakeAvailability) -> NextShotStatus {
        guard let preview = snapshot.previewChannel else {
            return NextShotStatus(
                preview: nil,
                shotLine: "No Preview camera",
                readiness: .noPreviewCamera,
                statusText: "Take unavailable",
                reasonText: availability.reasonText,
                director: nil)
        }

        var shotLine = preview.cameraLabel
        if let input = snapshot.input(preview) {
            shotLine += " · \(input.name) · \(input.shot)"
        }

        let readiness: Readiness
        let statusText: String
        if snapshot.editLive {
            readiness = .editingLive
            statusText = "Editing Program live · Preview \(preview.cameraLabel) is unchanged"
        } else if let reason = availability.reasonText {
            readiness = .notReady
            statusText = reason
        } else {
            readiness = .ready
            statusText = "Ready · Take sends exactly this shot"
        }

        return NextShotStatus(
            preview: preview,
            shotLine: shotLine,
            readiness: readiness,
            statusText: statusText,
            reasonText: availability.reasonText,
            director: nil)
    }
}
