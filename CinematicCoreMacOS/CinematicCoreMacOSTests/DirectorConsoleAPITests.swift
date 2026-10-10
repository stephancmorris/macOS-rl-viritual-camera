import CoreGraphics
import Foundation
import Testing
@testable import Alfie

/// A-04: console status model and control API (U2, U1).
@MainActor struct DirectorConsoleAPITests {
    typealias Section = NextShotStatus.DirectorSection

    private let waistUp = DirectorShot(preset: .stage(.waistUp))

    private var everyActivity: [Section.Activity] {
        [.active(.watching), .active(.preparing(input: .b, shot: waistUp, settled: true)),
         .active(.preparing(input: .b, shot: waistUp, settled: false)),
         .active(.ready(input: .b, shot: waistUp)), .active(.holdingOperatorShot(input: .a)),
         .paused(.manualMode), .paused(.operatorTookOver), .paused(.editLive), .paused(.sourceLost(.b)),
         .paused(.outputProblem), .paused(.setupChanged), .paused(.subjectLost(.b)),
         .paused(.afterFallback), .paused(.styleChanged), .paused(.subjectChanged), .paused(.showStopped),
         .inhibited(.operatorAdjusting(.b)), .inhibited(.learningSubject(.b)),
         .inhibited(.recoveringSubject(.b)), .inhibited(.noFreshView(.b)), .inhibited(.cameraNotReady),
         .abstaining(.noPreview), .abstaining(.previewIsSafeWide), .abstaining(.moreThanOnePerson(.b)),
         .abstaining(.justUsed), .abstaining(.holdingCurrentShot), .abstaining(.subjectMoving),
         .abstaining(.nothingBetter), .abstaining(.cannotDecide), .abstaining(.notSureEnough)]
    }

    @Test func everyStateHasPlainWordsWithoutCodes() {
        let texts = everyActivity.map(\.text)
        #expect(Set(texts).count == texts.count)
        for text in texts {
            #expect(!text.isEmpty)
            // No revisions, epochs, raw enum names or ages leak to the operator.
            #expect(!text.contains("epoch") && !text.contains("revision") && !text.contains("_"))
            #expect(text.range(of: #"\d+\.\d+"#, options: .regularExpression) == nil)
        }
        #expect(Set(everyActivity.map(\.kind)) == Set(Section.Activity.Kind.allCases))
    }

    @Test func contractPhrasesMatch() {
        #expect(Section.Activity.active(.preparing(input: .b, shot: waistUp, settled: true)).text
                == "Preparing Cam B Waist Up · subject settled")
        #expect(Section.Activity.paused(.operatorTookOver).text == "Paused: you took over")
        #expect(Section.NextCut(input: .b, countdown: 2, cancellable: true).line == "Next: Cam B · 2 s · Esc to cancel")
        #expect(Section.NextCut(input: .b, countdown: nil, cancellable: false).line == "Next: Cam B")
        #expect(Section.NextCut(input: .a, countdown: 2.5, cancellable: false).line == "Next: Cam A · 2.5 s")
        #expect(Section.PreparedShot(input: .b, shot: waistUp).line == "Cam B · Waist Up")
    }

    @Test func launchStateIsManualWhateverIsQualified() {
        let everything = Section.Qualification(assist: true, auto: true, backup: true)
        let launch = Section.atLaunch(qualified: everything)
        #expect(launch.level == .manual && !launch.handedToAlfie)
        #expect(launch.prepared == nil && launch.nextCut == nil && launch.alfieSetShot.isEmpty)
        #expect(launch.statusLine == "Manual · Alfie is not directing")
        #expect(launch.preparedLine == "No shot prepared")
    }

    @Test func qualificationGatesSelectionButNeverManual() {
        let launch = Section.atLaunch(qualified: .init(assist: true, auto: false, backup: false))
        #expect(launch.canSelect(.manual) && launch.canSelect(.assist))
        #expect(!launch.canSelect(.auto) && !launch.canSelect(.backup))
        #expect(Section.atLaunch(qualified: .none).canSelect(.manual))
        #expect(Section.Level.allCases.map(\.title) == ["Manual", "Assist", "Auto", "Backup"])
    }

    @Test func autoBadgeOnlyWhereAlfieSetTheShot() {
        var section = Section.atLaunch(qualified: .none)
        section.alfieSetShot = [.b]
        #expect(section.showsAutoBadge(on: .b) && !section.showsAutoBadge(on: .a))
    }

    @Test func nextShotStatusStillDefaultsToNoDirector() {
        for scenario in FakeConsoleModel.Scenario.allCases {
            #expect(NextShotStatus.make(FakeConsoleModel.snapshot(for: scenario, standard: .p50)).director == nil)
        }
    }

    // MARK: Control protocol

    private final class FakeController: DirectorConsoleControlling {
        var directorSection = Section.atLaunch(qualified: .init(assist: true, auto: false, backup: false))
        var calls: [String] = []
        func setLevel(_ level: Section.Level) -> DirectorControlResult {
            calls.append("level \(level.rawValue)")
            guard directorSection.canSelect(level) else { return .refused(Section.notQualifiedCaption) }
            directorSection.level = level
            return .accepted
        }
        func handToAlfie() -> DirectorControlResult { calls.append("hand"); directorSection.handedToAlfie = true; return .accepted }
        func takeOver() { calls.append("take over"); directorSection.handedToAlfie = false }
        func cancelNextCut() { calls.append("cancel"); directorSection.nextCut = nil }
        func advanceSegment() { calls.append("advance") }
        func overrideSubject(on channel: ChannelID, at point: CGPoint) { calls.append("subject \(channel.rawValue)") }
    }

    @Test func unqualifiedLevelIsRefusedNotSubstituted() {
        let controller = FakeController()
        #expect(controller.setLevel(.auto) == .refused("not qualified"))
        #expect(controller.directorSection.level == .manual)
        #expect(controller.setLevel(.assist) == .accepted)
        #expect(controller.directorSection.level == .assist)
        _ = controller.handToAlfie(); controller.takeOver()
        #expect(!controller.directorSection.handedToAlfie)
        #expect(controller.calls == ["level auto", "level assist", "hand", "take over"])
    }
}
