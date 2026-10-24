import Foundation
import Testing
@testable import Alfie

nonisolated struct DirectorSubjectSelectorTests {
    private let centre = SubjectSelector.Zone(minX: 0.3, minY: 0.1, maxX: 0.7, maxY: 0.9)
    private let left = SubjectSelector.Zone(minX: 0, minY: 0, maxX: 0.2, maxY: 1)
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private func person(_ id: UUID, x: Double = 0.5, y: Double = 0.5,
                        stable: Double = 3, age: Double = 0) -> SubjectSelector.Observation {
        .init(id: id, x: x, y: y, stableFor: stable, observationAge: age)
    }
    private func decide(_ people: [SubjectSelector.Observation], nomination: UUID? = nil,
                        hint: SubjectSelector.Zone? = nil, now: Double = 10, sampled: Double = 10,
                        minimumStable: Double = 2, maximumAge: Double = 1) -> SubjectSelector.Decision {
        SubjectSelector.select(.init(channel: .b, sourceGeneration: 3, sampledAt: sampled, observations: people),
            nomination: nomination, positionHint: hint, now: now,
            parameters: .init(lecternZone: centre, maximumCentreDistance: 0.15,
                minimumStableDuration: minimumStable, maximumObservationAge: maximumAge, maximumSampleAge: 2))
    }
    private func chosen(_ id: UUID, reason: SubjectSelector.Reason) -> SubjectSelector.Decision {
        .selected(.init(channel: .b, sourceGeneration: 3, subject: id, reason: reason, sampledAt: 10))
    }
    @Test func nominationBeatsHintAndCentralityEvenBeforeStability() {
        let people = [person(a), person(b, x: 0.1, stable: 0)]
        #expect(decide(people, nomination: b, hint: centre) == chosen(b, reason: .operatorNomination))
        #expect(decide(people, nomination: a, hint: left) == chosen(a, reason: .operatorNomination))
    }
    @Test func absentOrStaleNominationNeverSubstitutesAnotherPerson() {
        #expect(decide([person(a)], nomination: b) == .awaitingNomination(b))
        #expect(decide([person(a), person(b, age: 2)], nomination: b) == .awaitingNomination(b))
        #expect(decide([], nomination: b) == .awaitingNomination(b))
    }
    @Test func hintBeatsLecternAndFallsBackOnlyWhenEmpty() {
        #expect(decide([person(a), person(b, x: 0.1)], hint: left) == chosen(b, reason: .positionHint))
        #expect(decide([person(a)], hint: left) == chosen(a, reason: .centralPresenter))
        #expect(decide([person(a)]) == chosen(a, reason: .centralPresenter))
    }
    @Test func crossingAndPanelNeverGuessATightSubject() {
        let panel = [person(b, x: 0.55), person(a)]
        #expect(decide(panel) == .ambiguous([a, b]))
        #expect(decide(Array(panel.reversed())) == .ambiguous([a, b]))
        #expect(decide(panel, hint: centre) == .ambiguous([a, b]))
        #expect(decide(panel, nomination: b) == chosen(b, reason: .operatorNomination))
        let hintedPanel = [person(a, x: 0.1), person(b, x: 0.15)]
        #expect(decide(hintedPanel, hint: left) == .ambiguous([a, b]))
    }
    @Test func automaticChoiceRequiresFreshStableEvidenceInTheCalibratedZone() {
        #expect(decide([person(a, stable: 1.999)]) == .abstain(.noPlausibleSubject))
        #expect(decide([person(a, x: 0.8)]) == .abstain(.noPlausibleSubject))
        #expect(decide([person(a, y: 0.95)]) == .abstain(.noPlausibleSubject))
        #expect(decide([person(a, x: 0.69)]) == .abstain(.noPlausibleSubject))
        #expect(decide([person(a, stable: 2, age: 1)]) == chosen(a, reason: .centralPresenter))
        #expect(decide([person(a, age: 0.5)], now: 10.5) == chosen(a, reason: .centralPresenter))
        #expect(decide([person(a, age: 0.5)], now: 10.501) == .abstain(.evidenceUnavailable))
        #expect(decide([person(a)], now: 12.001) == .abstain(.evidenceUnavailable))
        #expect(decide([person(a)], now: 9) == .abstain(.evidenceUnavailable))
    }
    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidEvidenceAndThresholdsFailClosed(value: Double) {
        #expect(decide([person(a)], now: value) == .abstain(.invalidInput))
        #expect(decide([person(a)], sampled: value) == .abstain(.invalidInput))
        #expect(decide([person(a)], minimumStable: value) == .abstain(.invalidInput))
        #expect(decide([person(a)], maximumAge: value) == .abstain(.invalidInput))
        for invalid in [person(a, x: value), person(a, y: value), person(a, stable: value), person(a, age: value)] {
            #expect(decide([invalid]) == .abstain(.invalidInput))
        }
        let invalidZone = SubjectSelector.Zone(minX: value, minY: 0, maxX: 1, maxY: 1)
        #expect(decide([person(a)], hint: invalidZone) == .abstain(.invalidInput))
    }
    @Test func duplicateIDsAndMalformedCoordinatesCannotHideAmbiguity() {
        #expect(decide([person(a), person(a, x: 0.6)]) == .abstain(.invalidInput))
        #expect(decide([person(a, x: 1.1)]) == .abstain(.invalidInput))
        #expect(decide([person(a)], hint: .init(minX: 0.5, minY: 0, maxX: 0.5, maxY: 1)) == .abstain(.invalidInput))
    }
    @Test func staleBystandersDoNotCreateFalseAmbiguityAndHintsDoNotBypassStability() {
        #expect(decide([person(a), person(b, age: 2)]) == chosen(a, reason: .centralPresenter))
        #expect(decide([person(a), person(b, x: 0.1, stable: 1)], hint: left) == chosen(a, reason: .centralPresenter))
        #expect(decide([]) == .abstain(.evidenceUnavailable))
    }
}
