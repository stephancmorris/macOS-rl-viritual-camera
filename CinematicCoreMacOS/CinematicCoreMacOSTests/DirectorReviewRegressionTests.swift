import Foundation
import Testing
@testable import Alfie

/// Review repairs; all values and prerequisites are synthetic fixtures.
@MainActor struct DirectorReviewRegressionTests {
    @Test func qualifiedSelectionLeavesManualStatusAndRetainsFaultReasons() {
        let qualification = NextShotStatus.DirectorSection.Qualification(assist: true, auto: true, backup: true)
        let fake = FakeDirectorConsole(section: .atLaunch(qualified: qualification))
        #expect(fake.setLevel(.assist) == .accepted)
        #expect(fake.directorSection.statusLine == "Watching · Alfie is not changing shots")
        fake.takeOver()
        #expect(fake.setLevel(.auto) == .accepted)
        #expect(fake.directorSection.statusLine == "Watching · Alfie is not changing shots")
        #expect(fake.setLevel(.manual) == .accepted)
        #expect(fake.directorSection.statusLine == "Manual · Alfie is not directing")
        var section = NextShotStatus.DirectorSection.atLaunch(qualified: qualification)
        section.activity = .paused(.outputProblem)
        let fault = FakeDirectorConsole(section: section)
        #expect(fault.setLevel(.assist) == .accepted)
        #expect(fault.directorSection.activity == .paused(.outputProblem))
        #expect(fault.directorSection.prepared == nil && fault.directorSection.nextCut == nil)
    }

    @Test(arguments: [-1, Int.min, 0, 1, 2])
    func personCountsFailClosedWithoutChangingValidCases(count: Int) {
        func sample(_ phase: RecoveryState.Phase) -> ChannelEvidenceSample {
            .init(channel: .b, sampledAt: 10, lockPhase: phase, trackingOwnsControl: true,
                galleryReady: true, lockedTargetID: UUID(), observationAge: 0.01, subjectSpeed: 0,
                holdingSteady: true, cropConverged: true, operatorGestureInProgress: false,
                observedPersonCount: count)
        }
        let identity = IdentityEvidence.classify(sample(.tracking), maximumObservationAge: 1)
        let expected: IdentityEvidence = count < 0 ? .unavailable : count >= 2 ? .ambiguous : .confirmed
        #expect(identity == expected)
        let input = DirectorReadiness.Inputs(take: .init(program: .a, preview: .b, standard: .p50,
            reason: nil, takePending: false, editLive: false), identity: identity,
            framingSettledFor: 10, motion: 0, cropConverged: true)
        let parameters = DirectorReadiness.Parameters(minimumSettledTime: 1, maximumMotion: 1,
            cutOnMotionAllowed: false, minimumCutSettledTime: 2, maximumCutMotion: 0.5)
        #expect(DirectorReadiness.evaluate(input, parameters: parameters).isReady == (count == 0 || count == 1))
        #expect(DirectorReadiness.evaluate(input, parameters: parameters, bar: .cut).isReady == (count == 0 || count == 1))
        #expect(IdentityEvidence.classify(sample(.wideWaiting), maximumObservationAge: 1) == .lost)
    }

    private func style(_ minimum: Double, _ preferred: Double, _ maximum: Double) -> DirectorStyle {
        .init(minimumShotDuration: minimum, preferredShotDuration: preferred, softMaximumShotDuration: maximum,
            wideCadence: 90, repetitionWindow: 10, maximumMovement: 0.1, settleTime: 1,
            onAirMoveRate: 0.1, cutOnMotionAllowed: false)
    }

    @Test func oneSidedSegmentsRespectBothEffectiveProfilesInEitherOrder() throws {
        let fallback = style(20, 45, 90), segment = style(5, 10, 30)
        let a = DirectorPreferences(styles: [.liveEvent: fallback])
        let b = DirectorPreferences(styles: [.liveEvent: fallback, .performance: segment])
        let expected = try DirectorStyle.resolve(fallback, segment)
        let ab = try DirectorPreferences.resolve(a, b), ba = try DirectorPreferences.resolve(b, a)
        #expect(ab == ba)
        #expect(ab.style(for: .performance) == expected)
        #expect(ab.style(for: .panel) == fallback)
        #expect(ab.version == 2)
        let both = try DirectorPreferences.resolve(b, b)
        #expect(both.style(for: .performance) == segment)
        #expect(try DirectorPreferences.resolve(a, a) == a)
    }

    @Test func impossibleFallbackSegmentIntersectionRefusesInsteadOfDroppingConstraint() {
        let a = DirectorPreferences(styles: [.liveEvent: style(40, 45, 90)])
        let b = DirectorPreferences(styles: [.liveEvent: style(20, 45, 90), .performance: style(1, 5, 10)])
        #expect(throws: DirectorPreferences.ValidationError.conflictingConstraints) {
            try DirectorPreferences.resolve(a, b)
        }
        #expect(throws: DirectorPreferences.ValidationError.conflictingConstraints) {
            try DirectorPreferences.resolve(b, a)
        }
    }
    @Test func pythonReportFixtureUsesTheActualSwiftSchema() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = project.appendingPathComponent("scripts/fixtures/director-shadow-synthetic.jsonl")
        let data = try Data(contentsOf: fixture)
        let records = try data.split(separator: 10).map {
            try JSONDecoder().decode(DirectorShadowRecord.self, from: Data($0))
        }
        #expect(records.count == 7)
        #expect(records.allSatisfy { $0.evidenceClass == .synthetic && $0.schemaVersion == 1 })
    }

    @Test func negativeCountsImmediatelyInhibitPreviouslyConfirmedAdapter() {
        let subject = UUID()
        func sample(_ time: Double, _ count: Int) -> ChannelEvidenceSample {
            .init(channel: .b, sampledAt: time, lockPhase: .tracking, trackingOwnsControl: true,
                galleryReady: true, lockedTargetID: subject, observationAge: 0.01, subjectSpeed: 0,
                holdingSteady: true, cropConverged: true, operatorGestureInProgress: false,
                observedPersonCount: count)
        }
        var adapter = DirectorEvidenceAdapter(parameters: .init(maximumObservationAge: 1, debounce: 0.5, stillSpeed: 0.1))
        adapter.ingest(sample(1, 1)); adapter.ingest(sample(1.6, 1))
        #expect(adapter.state(for: .b)?.evidenceAvailable == true)
        #expect(adapter.ingest(sample(1.7, -1)) == [.evidenceAvailable(.b, false)])
        #expect(adapter.state(for: .b)?.identity == .unavailable)
        #expect(adapter.settledFor(.b, now: 1.8) == 0)
    }

}
