#if DEBUG
import Combine
import Foundation
import SwiftUI

private final class DirectorRunSheetControllerGallery: ObservableObject {
    let show: ShowCoordinator
    let controller: DirectorController
    @Published private(set) var result = "No synthetic decision evaluated."
    private let sheet: RunSheet

    init() {
        sheet = try! RunSheet(segments: [.init(type: .presenter, name: "Opening"), .init(type: .panel, name: "Discussion")])
        show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
        controller = DirectorController(show: show, runSheet: sheet, log: { _ in })
        func fixtureStyle(cadence: Double) -> DirectorStyle {
            .init(minimumShotDuration: 2, preferredShotDuration: 5, softMaximumShotDuration: 30,
                wideCadence: cadence, repetitionWindow: 0, maximumMovement: 1, settleTime: 1,
                onAirMoveRate: 1, cutOnMotionAllowed: false)
        }
        controller.preferencesChanged(.init(styles: [.liveEvent: fixtureStyle(cadence: 60),
            .presenter: fixtureStyle(cadence: 10), .panel: fixtureStyle(cadence: 100)]))
    }

    func evaluate() {
        let close = DirectorShotPolicy.Candidate(channel: .b, shot: .init(preset: .stage(.waistUp)),
            subjectConfidence: 0.9, movement: 0, isWide: false)
        let wide = DirectorShotPolicy.Candidate(channel: .b, shot: .init(preset: .stage(.wide)),
            subjectConfidence: 0.5, movement: 0, isWide: true)
        let timeline = DirectorShotPolicy.Timeline(programShot: .init(preset: .stage(.fullBody)),
            programStartedAt: 0, lastWideAt: 0, history: [], candidates: [close, wide], now: 20)
        switch controller.choosePreparation(timeline, preview: .b) {
        case .chosen(let candidate, let reason): result = "Pure choice: \(candidate.shot.title) · \(reason). No effect dispatched."
        case .abstain: result = "Pure choice abstained. No effect dispatched."
        }
    }
    func reset() {
        _ = controller.setRunSheet(sheet)
        result = "Reset to the first synthetic segment."
    }
}

struct DirectorRunSheetControllerDemo: View {
    @StateObject private var gallery = DirectorRunSheetControllerGallery()

    var body: some View {
        DirectorRunSheetControllerPanel(gallery: gallery, controller: gallery.controller)
    }
}

private struct DirectorRunSheetControllerPanel: View {
    @ObservedObject var gallery: DirectorRunSheetControllerGallery
    @ObservedObject var controller: DirectorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synthetic style-context rehearsal. Manual authority; no cameras or qualification. The fixture parameters apply only to this example.")
                .font(.caption).foregroundStyle(.secondary)
            if let sheet = controller.directorSection.runSheet {
                Text("Current: \(sheet.current)")
                Text(sheet.next.map { "Next: \($0)" } ?? "End of run sheet").foregroundStyle(.secondary)
                HStack {
                    Button("Advance synthetic controller segment") { controller.advanceSegment() }
                        .disabled(sheet.next == nil)
                        .accessibilityLabel("Advance synthetic controller segment")
                    Button("Reset synthetic controller sheet") { gallery.reset() }
                        .accessibilityLabel("Reset synthetic controller sheet")
                }
            }
            Text("Authority: \(controller.directorSection.level.title) · Epoch: \(controller.authority.epoch) · Policy revision: \(controller.policyRevision)")
                .font(.system(.caption, design: .monospaced))
            Button("Evaluate synthetic preparation choice") { gallery.evaluate() }
                .accessibilityLabel("Evaluate synthetic preparation choice")
            Text(gallery.result).font(.callout)
        }
    }
}
#endif
