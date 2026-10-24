import Foundation
import Testing
@testable import Alfie

@MainActor struct DirectorRunSheetControllerTests {
    private final class Ticker: DirectorTicker {
        func start(every interval: TimeInterval, _ tick: @escaping @MainActor () -> Bool) {}
        func stop() {}
    }
    private func style(wide: Double, minimum: Double = 2) -> DirectorStyle {
        .init(minimumShotDuration: minimum, preferredShotDuration: max(minimum, 5),
              softMaximumShotDuration: max(minimum, 12), wideCadence: wide, repetitionWindow: 0,
              maximumMovement: 1, settleTime: 1, onAirMoveRate: 1, cutOnMotionAllowed: false)
    }
    private func show() -> ShowCoordinator {
        ShowCoordinator(programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "b11-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
    }
    private func controller(_ show: ShowCoordinator, sheet: RunSheet? = nil) -> DirectorController {
        DirectorController(show: show, ticker: Ticker(), clock: { 100 },
            qualifiedLevels: { [.assist, .auto, .backup] }, runSheet: sheet, log: { _ in })
    }
    private var ready: DirectorAuthority.Prerequisites {
        .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
              outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist, .auto, .backup])
    }

    @Test(arguments: [NextShotStatus.DirectorSection.Level.manual, .assist, .auto, .backup])
    func advanceChangesStyleWithoutAuthorityOrCameraEffects(level: NextShotStatus.DirectorSection.Level) throws {
        let show = show()
        let sheet = try RunSheet(segments: [.init(type: .presenter, name: "Opening"), .init(type: .panel, name: "Discussion")])
        let controller = controller(show, sheet: sheet)
        #expect(controller.directorSection.runSheet?.current == "Presenter · Opening")
        controller.preferencesChanged(.init(styles: [.liveEvent: style(wide: 60), .presenter: style(wide: 10), .panel: style(wide: 30)]))
        controller.prerequisitesOverride = { ready }
        #expect(controller.setLevel(level) == .accepted)
        let before = controller.authority
        let events = controller.appliedEvents
        let revision = controller.policyRevision
        let cameraRevisions = show.channelA.revisions
        #expect(controller.effectiveStyle?.wideCadence == 10)
        controller.advanceSegment()
        #expect(controller.effectiveStyle?.wideCadence == 30)
        #expect(controller.authority == before)
        #expect(controller.appliedEvents == events)
        #expect(controller.policyRevision == revision + 1)
        #expect(controller.lastStyleEvent == .policyChanged(segmentID: sheet.next?.id))
        #expect(show.channelA.revisions == cameraRevisions)
        #expect(show.programChannel == .a)
        #expect(controller.directorSection.runSheet?.current == "Panel · Discussion")
        #expect(controller.directorSection.runSheet?.next == nil)
        let endRevision = controller.policyRevision
        controller.advanceSegment()
        #expect(controller.policyRevision == endRevision)
        #expect(controller.authority == before)
    }

    @Test func nextPureDecisionUsesCurrentSegmentStyleImmediately() throws {
        let show = show()
        let sheet = try RunSheet(segments: [.init(type: .presenter), .init(type: .panel)])
        let controller = controller(show, sheet: sheet)
        controller.preferencesChanged(.init(styles: [.liveEvent: style(wide: 60), .presenter: style(wide: 10), .panel: style(wide: 100)]))
        let close = DirectorShotPolicy.Candidate(channel: .b, shot: .init(preset: .stage(.waistUp)), subjectConfidence: 0.9, movement: 0, isWide: false)
        let wide = DirectorShotPolicy.Candidate(channel: .b, shot: .init(preset: .stage(.wide)), subjectConfidence: 0.5, movement: 0, isWide: true)
        let timeline = DirectorShotPolicy.Timeline(programShot: .init(preset: .stage(.fullBody)), programStartedAt: 0,
            lastWideAt: 0, history: [], candidates: [close, wide], now: 20)
        guard case .chosen(let first, _) = controller.choosePreparation(timeline, preview: .b) else {
            Issue.record("Expected first style to rank a shot"); return
        }
        #expect(first == wide)
        controller.advanceSegment()
        guard case .chosen(let second, _) = controller.choosePreparation(timeline, preview: .b) else {
            Issue.record("Expected next style to rank a shot"); return
        }
        #expect(second == close)
        #expect(controller.authority.level == .off)
    }

    @Test func emptyMissingAndInvalidStylesFailClosedWithoutDefaults() throws {
        let show = show(), controller = controller(show)
        #expect(controller.effectiveStyle == nil)
        controller.preferencesChanged(.init(styles: [.liveEvent: style(wide: 60)]))
        #expect(controller.effectiveStyle?.wideCadence == 60)
        #expect(controller.setRunSheet(try RunSheet(segments: [.init(type: .performance)])))
        #expect(controller.effectiveStyle?.wideCadence == 60)
        controller.preferencesChanged(.init(styles: [.panel: style(wide: 30)]))
        #expect(controller.effectiveStyle == nil)
        #expect(controller.setRunSheet(try RunSheet(segments: [])))
        #expect(controller.directorSection.runSheet == nil)
        #expect(controller.authority.level == .off)
    }

    @Test func replacingSheetPreservesPausedAuthorityAndSameSheetIsIdempotent() throws {
        let show = show(), controller = controller(show)
        controller.prerequisitesOverride = { ready }
        #expect(controller.setLevel(.auto) == .accepted)
        controller.takeOver()
        let authority = controller.authority
        let sheet = try RunSheet(segments: [.init(type: .videoBreak)])
        #expect(controller.setRunSheet(sheet))
        let revision = controller.policyRevision
        #expect(controller.setRunSheet(sheet))
        #expect(controller.policyRevision == revision)
        #expect(controller.authority == authority)
        #expect(controller.directorSection.activity == .paused(.operatorTookOver))
        #expect(controller.setRunSheet(nil))
        #expect(controller.authority == authority)
    }
}
